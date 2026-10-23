'use strict';
const CACHE = 'typica-php-shell-__BUILD_ID__';
const PREFIX = 'typica-php-shell-';
const CORE = __CORE_FILES__;
const scope = self.registration.scope;
// O Flutter pode gerar nomes contendo %20 literalmente. Codificar cada parte
// conserva esses nomes e também atende arquivos com espaços e acentos.
const local = path => {
  const [pathname, query] = path.split('?', 2);
  const url = new URL(pathname.split('/').map(encodeURIComponent).join('/'), scope);
  if (query) url.search = query;
  return url.href;
};
const manifestUrl = local('__MANIFEST_PATH__');
const coreUrls = new Set(CORE.map(local));
const migrationMarker = new URL('__upgrade_ready__', scope).href;

async function saveFiles(paths) {
  const cache = await caches.open(CACHE);
  for (const path of paths) {
    const url = local(path);
    if (await cache.match(url)) continue;
    await cache.put(url, await downloadCore(url));
  }
}

async function downloadCore(url) {
  for (let attempt = 0; ; attempt++) {
    try {
      const response = await fetch(new Request(url, {cache: 'reload'}));
      if (!response.ok) throw new Error(`Não foi possível preparar ${url} (HTTP ${response.status})`);
      return response;
    } catch (error) {
      if (attempt === 2) throw error;
      await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
    }
  }
}

self.addEventListener('install', event => {
  const upgrading = !!self.registration.active;
  // Uma atualização automática só substitui a versão antiga quando todos os
  // recursos novos estão salvos. O banco SQLite continua no armazenamento local.
  event.waitUntil((async () => {
    await saveFiles(CORE);
    if (upgrading) {
      const cache = await caches.open(CACHE);
      await cache.put(migrationMarker, new Response('ready'));
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  // Mantém versões anteriores para abas já abertas. Nunca apaga o IndexedDB.
  event.waitUntil((async () => {
    await self.clients.claim();
    const cache = await caches.open(CACHE);
    if (await cache.match(migrationMarker)) {
      const windows = await self.clients.matchAll({type: 'window'});
      // A navegação só termina depois da ativação. Aguardar essas promessas
      // aqui criaria uma espera circular e impediria a atualização de abrir.
      for (const client of windows) {
        if (client.frameType === 'top-level') client.navigate(client.url).catch(() => {});
      }
    }
  })());
});

self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
  if (event.data?.type === 'PREPARE_OFFLINE') {
    event.waitUntil(saveFiles(CORE).then(
      () => event.ports[0]?.postMessage({ok: true}),
      error => event.ports[0]?.postMessage({ok: false, message: `Não foi possível salvar os arquivos do aplicativo para uso offline. Toque em “Tentar novamente”. Detalhes: ${error.message}`}),
    ));
  }
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin || !url.href.startsWith(scope)) return;
  // Versões e downloads PHP sempre usam a rede. Só o manifesto fixado na
  // versão instalada entra no cache da interface para permitir reabrir offline.
  if (url.pathname.startsWith(new URL('api/', scope).pathname) && url.href !== manifestUrl) return;
  // O pacote científico é instalado no SQLite. Não duplicar 95 MB no cache HTTP.
  if (url.pathname.endsWith('.sqlite.gz') ||
      (url.href.startsWith(new URL('data/', scope).href) && url.pathname.endsWith('.bin'))) return;
  if (event.request.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE);
      return (await cache.match(local('index.html'))) || fetch(event.request);
    })());
    return;
  }
  const canonical = new URL(url);
  if (canonical.href !== manifestUrl) canonical.search = '';
  canonical.hash = '';
  if (!coreUrls.has(canonical.href)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const cached = await cache.match(canonical.href);
    if (cached) return cached;
    const response = await fetch(event.request);
    if (response.ok) await cache.put(canonical.href, response.clone());
    return response;
  })());
});
