/* Pacotes SQLite pequenos. IndexedDB guarda Blobs compactados; nunca abre o
 * SQLite monolítico. Um lote é verificado e gravado antes de baixar o próximo.
 */
(() => {
  'use strict';
  const base = new URL('.', document.baseURI);
  const name = `cultivar_packages_${base.pathname.replace(/[^a-zA-Z0-9_]/g, '_')}`;
  const stats = {format: 'cultivar-sqlite-regions-v2', expected: 0, saved: 0, maxNetworkBufferBytes: 0, maxDatabaseBytes: 0, openDatabaseBytes: 0};
  let opening;
  const allPackages = manifest => [manifest.catalog, ...Object.values(manifest.regions)];
  const hex = bytes => Array.from(new Uint8Array(bytes), n => n.toString(16).padStart(2, '0')).join('');
  const sha256 = async bytes => hex(await crypto.subtle.digest('SHA-256', bytes));
  function database() {
    return opening ||= new Promise((resolve, reject) => {
      if (!window.indexedDB) return reject(new Error('O navegador não permite salvar os dados offline. Abra uma aba normal e habilite o armazenamento do site.'));
      const request = indexedDB.open(name, 1);
      request.onupgradeneeded = () => request.result.createObjectStore('packages');
      request.onsuccess = () => {
        const db = request.result;
        db.onversionchange = () => {db.close(); opening = null;};
        resolve(db);
      };
      request.onblocked = () => reject(new Error('Feche outras janelas do Typica para preparar os dados.'));
      request.onerror = () => reject(request.error);
    }).catch(error => {opening = null; throw error;});
  }
  async function read(key) {
    const db = await database();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction('packages', 'readonly');
      const request = transaction.objectStore('packages').get(key);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }
  async function available(manifest) {
    const expected = new Map(allPackages(manifest).map(p => [p.compressed_sha256, p.compressed_bytes]));
    const saved = new Set();
    const db = await database();
    await new Promise((resolve, reject) => {
      const transaction = db.transaction('packages', 'readonly');
      const cursor = transaction.objectStore('packages').openCursor();
      cursor.onsuccess = () => {
        const row = cursor.result;
        if (!row) return;
        const entry = row.value;
        if (entry?.data instanceof Blob && entry.data.size === expected.get(row.key)) saved.add(row.key);
        row.continue();
      };
      transaction.oncomplete = resolve;
      transaction.onabort = () => reject(transaction.error);
      transaction.onerror = () => reject(transaction.error);
    });
    return saved;
  }
  async function downloadBundle(manifest, index, onProgress = () => {}) {
    const bundle = manifest.bundles[index];
    const url = new URL(bundle.download, base);
    if (url.origin !== base.origin || bundle.bytes > 2_000_000) throw new Error('Lote de dados incompatível.');
    let packed;
    for (let attempt = 0; ; attempt++) {
      try {
        const response = await fetch(url, {cache: 'no-store'});
        if (!response.ok || !response.body) throw new Error(`Não foi possível baixar os dados (HTTP ${response.status}).`);
        packed = new Uint8Array(bundle.bytes);
        stats.maxNetworkBufferBytes = Math.max(stats.maxNetworkBufferBytes, packed.byteLength);
        const reader = response.body.getReader();
        let received = 0;
        try {
          while (true) {
            const {done, value} = await reader.read();
            if (done) break;
            if (received + value.length > packed.length) throw new Error('O lote recebido tem tamanho inesperado.');
            packed.set(value, received);
            received += value.length;
            onProgress(received);
          }
        } finally {await reader.cancel().catch(() => {});}
        if (received !== bundle.bytes) throw new Error('O download do lote foi interrompido.');
        if (await sha256(packed) !== bundle.sha256) throw new Error('O lote baixado falhou na verificação de integridade.');
        break;
      } catch (error) {
        packed = null;
        if (attempt === 2) throw error;
        await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
      }
    }
    const members = allPackages(manifest).filter(p => p.bundle === index);
    const db = await database();
    await new Promise((resolve, reject) => {
      const transaction = db.transaction('packages', 'readwrite');
      const store = transaction.objectStore('packages');
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error || new Error('Não foi possível gravar o lote. Confira o espaço disponível.'));
      try {
        for (const p of members) {
          const bytes = packed.subarray(p.offset, p.offset + p.compressed_bytes);
          if (bytes.length !== p.compressed_bytes) throw new Error('O lote está incompleto.');
          store.put({data: new Blob([bytes]), bytes: p.compressed_bytes}, p.compressed_sha256);
        }
      } catch (error) {transaction.abort(); reject(error);}
    });
    packed = null;
  }
  window.cultivarRegions = Object.freeze({
    get diagnostics() {return {...stats, storage: name};},
    noteDatabaseBytes(bytes) {
      stats.openDatabaseBytes = bytes;
      stats.maxDatabaseBytes = Math.max(stats.maxDatabaseBytes, bytes);
    },
    async hasPackages(manifestJson) {
      const manifest = JSON.parse(manifestJson);
      if (manifest.format !== stats.format || manifest.schema_version !== 2) throw new Error('Versão dos dados incompatível.');
      // Apenas consulta os Blobs locais; não baixa nem abre bancos SQLite.
      return (await available(manifest)).size === allPackages(manifest).length;
    },
    async prepare(manifestJson, onProgress) {
      const run = () => prepare(manifestJson, onProgress);
      // A aba do navegador e o ícone podem abrir durante a instalação.
      // Só uma janela baixa por vez; a seguinte reaproveita os lotes salvos.
      return navigator.locks ? navigator.locks.request(`${name}:download`, run) : run();
    },
    async load(manifestJson, packageJson) {
      const manifest = JSON.parse(manifestJson);
      const p = JSON.parse(packageJson);
      // Mesmo sem rede, somente a partição solicitada é lida e verificada.
      for (let attempt = 0; attempt < 2; attempt++) {
        const record = await read(p.compressed_sha256);
        if (record?.data instanceof Blob && record.data.size === p.compressed_bytes) {
          const packed = new Uint8Array(await record.data.arrayBuffer());
          if (await sha256(packed) === p.compressed_sha256) return packed;
        }
        if (attempt === 0) await downloadBundle(manifest, p.bundle);
      }
      throw new Error('A cópia local desta região está incompleta. Conecte-se à internet e tente novamente.');
    },
  });

  async function prepare(manifestJson, onProgress) {
    const manifest = JSON.parse(manifestJson);
    if (manifest.format !== stats.format || manifest.schema_version !== 2) throw new Error('Versão dos dados incompatível.');
    const packages = allPackages(manifest);
    const saved = await available(manifest);
    stats.expected = packages.length;
    stats.saved = saved.size;
    let received = packages.filter(p => saved.has(p.compressed_sha256)).reduce((n, p) => n + p.compressed_bytes, 0);
    onProgress(received, manifest.compressed_bytes, 'download');
    if (saved.size < packages.length) await cultivarPlatform.prepareStorage(manifest.compressed_bytes - received);
    for (let index = 0; index < manifest.bundles.length; index++) {
      const members = packages.filter(p => p.bundle === index);
      if (members.every(p => saved.has(p.compressed_sha256))) continue;
      const previouslySaved = members.filter(p => saved.has(p.compressed_sha256)).reduce((n, p) => n + p.compressed_bytes, 0);
      const before = received - previouslySaved;
      await downloadBundle(manifest, index, value => onProgress(Math.min(manifest.compressed_bytes, before + value), manifest.compressed_bytes, 'download'));
      received = before + manifest.bundles[index].bytes;
      for (const p of members) saved.add(p.compressed_sha256);
      stats.saved = saved.size;
      onProgress(received, manifest.compressed_bytes, 'store');
    }
    if (saved.size !== packages.length) throw new Error('A preparação dos dados está incompleta. Tente novamente.');
    return true;
  }
})();
