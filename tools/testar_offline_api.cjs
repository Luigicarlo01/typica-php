/* Testa o manifesto PHP fixado no cache e os endpoints que exigem rede.
 * Funciona na raiz ou em subpasta, sem baixar o banco científico completo.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright-core');

const base = process.env.PWA_TEST_URL || 'http://localhost:8081/';
const output = path.resolve(__dirname, '../build/verificacao-offline-api');
let browser;
(async () => {
  fs.mkdirSync(output, {recursive: true});
  browser = await chromium.launch({executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
    headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
  const context = await browser.newContext({viewport: {width: 320, height: 568}});
  const page = await context.newPage();
  const errors = [];
  let downloads = 0;
  page.on('pageerror', error => errors.push(error.message));
  context.on('request', request => {if (new URL(request.url()).pathname.endsWith('/api/lote.php')) downloads++;});
  async function open() {
    await page.goto(base, {waitUntil: 'domcontentloaded'});
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor({timeout: 30000});
    await semantics.evaluate(node => node.click());
    await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).waitFor();
  }
  await open();
  await page.getByRole('button', {name: 'Salvar como app', exact: true}).waitFor();
  assert.equal(await page.title(), 'Typica');
  assert.equal(await page.evaluate(() => cultivarPlatform.offlineShellReady()), true);
  await page.waitForFunction(() => !!navigator.serviceWorker.controller);
  const latest = await page.evaluate(async () => (await fetch(new URL('api/versao.php', document.baseURI), {cache: 'no-store'})).json());
  assert.equal(latest.backend, 'php');
  const manifestUrl = new URL(latest.manifest_url, base).href;
  const keys = await page.evaluate(async () => {
    const keys = [];
    for (const name of await caches.keys()) {
      if (name.startsWith('typica-php-shell-')) keys.push(...(await (await caches.open(name)).keys()).map(request => request.url));
    }
    return keys;
  });
  assert(keys.includes(manifestUrl), 'O manifesto PHP da versão instalada deve estar salvo para reabertura offline');
  assert(!keys.some(url => /\/api\/(versao|lote|saude)\.php/.test(url)), 'O cache da interface não deve guardar verificações nem downloads');
  assert(!keys.some(url => /\/api\/_/.test(url)), 'O cache não deve pedir arquivos PHP internos');
  await page.screenshot({path: path.join(output, '01-inicial-subpasta.png')});
  await context.setOffline(true);
  await open();
  const offline = await page.evaluate(async url => {
    const response = await fetch(url);
    return {status: response.status, manifest: await response.json()};
  }, manifestUrl);
  assert.equal(offline.status, 200);
  assert.equal(offline.manifest.manifest_version, latest.manifest_version);
  assert.equal(offline.manifest.backend.type, 'php');
  assert.equal(offline.manifest.bundles.length, latest.bundles);
  const staleVersion = await page.evaluate(async () => {
    try {await fetch(new URL('api/versao.php', document.baseURI), {cache: 'no-store'}); return true;} catch (_) {return false;}
  });
  assert.equal(staleVersion, false, 'A verificação de nova versão não pode usar uma resposta antiga do cache');
  assert.equal(downloads, 0);
  assert.deepEqual(errors, []);
  await page.screenshot({path: path.join(output, '02-inicial-offline.png')});
  const report = {success: true, url: base, phpBackend: true, pinnedManifestOffline: true,
    versionCheckNeedsNetwork: true, noDatabaseDownloaded: true, noInternalPhpPrecached: true,
    viewport: {width: 320, height: 568}};
  fs.writeFileSync(path.join(output, 'resultado.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
})().catch(error => {console.error(error); process.exitCode = 1;})
  .finally(async () => {if (browser) await browser.close();});
