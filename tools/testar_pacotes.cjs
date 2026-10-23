/* Retomada e integridade dos pacotes reais, sem carregar Flutter ou o SQL inteiro.
 * Usa um perfil normal descartável, Chrome e IndexedDB reais.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {chromium} = require('playwright-core');
(async () => {
  const root = path.resolve(__dirname, '..');
  const folder = path.resolve(process.env.PWA_TEST_DIRECTORY || path.join(root, 'build/web'));
  const manifest = JSON.parse(fs.readFileSync(path.join(folder, 'data/manifest.json')));
  const counts = Array(manifest.bundles.length).fill(0);
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cultivar-pacotes-'));
  let available = false;
  let context;
  const checks = [];
  const server = http.createServer((req, res) => {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const index = manifest.bundles.findIndex(b => '/' + b.download === pathname);
    if (index >= 0) {
      counts[index]++;
      if (index === 1 && !available) {res.writeHead(503);res.end('interrompido');return;}
    }
    res.setHeader('Cache-Control', 'no-store');
    if (pathname === '/sw.js') {res.setHeader('Content-Type', 'application/javascript'); res.end("self.addEventListener('install',e=>e.waitUntil(self.skipWaiting()));self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));");}
    else if (pathname === '/pwa.js' || pathname === '/region_packages.js') {res.setHeader('Content-Type', 'application/javascript');res.end(fs.readFileSync(path.join(root, 'web', pathname.slice(1))));}
    else if (index >= 0) {res.setHeader('Content-Type', 'application/octet-stream');fs.createReadStream(path.join(folder, manifest.bundles[index].download)).pipe(res);}
    else {res.setHeader('Content-Type', 'text/html');res.end('<!doctype html><html><head><base href="/"></head><body><script src="region_packages.js"></script><script src="pwa.js"></script></body></html>');}
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}/`;
  async function open() {
    context = await chromium.launchPersistentContext(profile, {executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
    await context.addInitScript(() => {
      delete window.DecompressionStream;
      if (navigator.storage) {
        Object.defineProperty(navigator.storage, 'estimate', {value: undefined});
        Object.defineProperty(navigator.storage, 'persist', {value: undefined});
      }
    });
    const page = context.pages()[0];
    await page.goto(base);
    return page;
  }
  try {
    let page = await open();
    await page.evaluate(async () => {
      localStorage.setItem('historico-preservado-teste', 'original');
      await new Promise((resolve, reject) => {
        const r = indexedDB.open('cultivar__dados_legado_preservado', 1);
        r.onupgradeneeded = () => r.result.createObjectStore('original');
        r.onsuccess = () => {r.result.close();resolve();};r.onerror = () => reject(r.error);
      });
    });
    const failure = await page.evaluate(async manifest => {
      try {await cultivarPlatform.preparePackages(JSON.stringify(manifest), () => {});return null;}
      catch (error) {return error.message;}
    }, manifest);
    assert.match(failure, /HTTP 503/);
    let stats = await page.evaluate(() => cultivarRegions.diagnostics);
    assert(stats.saved > 0 && stats.saved < stats.expected);
    assert.equal(counts[0], 1); assert.equal(counts[1], 3);
    checks.push('Lote interrompido recebe três tentativas; os anteriores permanecem gravados');
    await context.close();
    available = true;
    page = await open();
    assert.equal(await page.evaluate(async manifest => {await cultivarPlatform.preparePackages(JSON.stringify(manifest), () => {});return true;}, manifest), true);
    assert.equal(counts[0], 1, 'reabrir não deve baixar novamente o primeiro lote');
    stats = await page.evaluate(() => cultivarRegions.diagnostics);
    assert.equal(stats.saved, Object.keys(manifest.regions).length + 1);
    assert(stats.maxNetworkBufferBytes <= 2000000);
    checks.push('Após fechar e reabrir o navegador, baixa somente os lotes que faltam');
    assert.equal(await page.evaluate(() => localStorage.getItem('historico-preservado-teste')), 'original');
    assert(await page.evaluate(async () => (await indexedDB.databases()).some(db => db.name === 'cultivar__dados_legado_preservado')));
    checks.push('Banco antigo e preferências preservados');
    checks.push('Funciona sem DecompressionStream e sem StorageManager.estimate/persist');
    // Corrupção com tamanho correto: somente SHA detecta, e só o lote afetado volta a ser baixado.
    await page.evaluate(async descriptor => {
      const name = cultivarRegions.diagnostics.storage;
      await new Promise((resolve, reject) => {
        const r = indexedDB.open(name);
        r.onsuccess = () => {
          const db = r.result;const t = db.transaction('packages', 'readwrite');
          t.objectStore('packages').put({data: new Blob([new Uint8Array(descriptor.compressed_bytes)]), bytes: descriptor.compressed_bytes}, descriptor.compressed_sha256);
          t.oncomplete = () => {db.close();resolve();};t.onabort = () => reject(t.error);
        };
      });
    }, manifest.catalog);
    const beforeRepair = [...counts];
    const hash = await page.evaluate(async ({manifest, descriptor}) => {
      const bytes = await cultivarPlatform.loadPackage(JSON.stringify(manifest), JSON.stringify(descriptor));
      const digest = await crypto.subtle.digest('SHA-256', bytes);
      return [...new Uint8Array(digest)].map(n => n.toString(16).padStart(2,'0')).join('');
    }, {manifest, descriptor: manifest.catalog});
    assert.equal(hash, manifest.catalog.compressed_sha256);
    assert.equal(counts[0], beforeRepair[0] + 1);
    assert.deepEqual(counts.slice(1), beforeRepair.slice(1));
    checks.push('SHA detecta pacote corrompido e recupera apenas o lote afetado');
    const beforeOffline = [...counts];
    await context.setOffline(true);
    await page.evaluate(async manifest => {
      await cultivarPlatform.preparePackages(JSON.stringify(manifest), () => {});
      const biggest = Object.values(manifest.regions).sort((a,b) => b.database_bytes-a.database_bytes)[0];
      const packed = await cultivarPlatform.loadPackage(JSON.stringify(manifest), JSON.stringify(biggest));
      if (packed.length !== biggest.compressed_bytes) throw Error('Região incompleta');
    }, manifest);
    assert.deepEqual(counts, beforeOffline);
    checks.push('Todos os pacotes, inclusive o maior município, disponíveis sem rede');
    const report = {success: true, checks, stats, packages: stats.saved, bundleDownloads: counts, missingAPIsSimulated: true};
    const output = path.join(root, 'build/verificacao-pacotes-v6');fs.mkdirSync(output, {recursive: true});
    fs.writeFileSync(path.join(output, 'resultado.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
  } finally {if (context) await context.close();await new Promise(resolve => server.close(resolve));fs.rmSync(profile, {recursive: true, force: true});}
})().catch(error => {console.error(error);process.exitCode=1;});
