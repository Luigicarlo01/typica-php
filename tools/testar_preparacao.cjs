/* Recuperação de cache offline interrompido, com o Chrome e o worker reais.
 * NODE_PATH=/tmp/cultivar-pwa-browser/node_modules node tools/testar_preparacao.cjs
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require('playwright-core');

(async () => {
  const root = path.resolve(__dirname, '..');
  const script = fs.readFileSync(path.join(root, 'web/pwa.js'));
  const worker = fs.readFileSync(path.join(root, 'tools/service_worker.template.js'), 'utf8')
    .replace('__MANIFEST_PATH__', 'api/manifesto.php?versao=fixture').replace('__BUILD_ID__', 'teste-recuperacao')
    .replace('__CORE_FILES__', JSON.stringify(['ok.txt', 'interrompido.txt', 'index.html', 'pwa.js', 'assets/AssetManifest.bin']));
  let available = false;
  const requests = {saved: 0, interrupted: 0};
  const server = http.createServer((request, response) => {
    const name = new URL(request.url, 'http://localhost').pathname;
    response.setHeader('Cache-Control', 'no-store');
    if (name === '/sw.js' || name === '/pwa.js') {
      response.setHeader('Content-Type', 'application/javascript');
      response.end(name === '/sw.js' ? worker : script);
    } else if (name === '/ok.txt') {
      requests.saved++;
      response.end('arquivo já salvo');
    } else if (name === '/interrompido.txt') {
      requests.interrupted++;
      response.statusCode = available ? 200 : 503;
      response.end(available ? 'conexão recuperada' : 'conexão indisponível');
    } else if (name === '/assets/AssetManifest.bin') {
      response.end('manifesto binário do aplicativo');
    } else {
      response.setHeader('Content-Type', 'text/html');
      response.end('<!doctype html><html><head><base href="/"></head><body><script src="pwa.js"></script></body></html>');
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    const failure = await page.evaluate(async () => {
      try { await cultivarPlatform.offlineShellReady(); return null; }
      catch (error) { return error.message; }
    });
    assert.match(failure, /Tentar novamente/);
    assert.doesNotMatch(failure, /localhost|HTTPS/);
    assert.equal(requests.saved, 1, 'o arquivo já salvo deve ser reaproveitado nas novas tentativas');
    assert(requests.interrupted >= 3, 'uma interrupção deve receber tentativas automáticas');
    available = true;
    assert.equal(await page.evaluate(() => cultivarPlatform.offlineShellReady()), true);
    assert.equal(requests.saved, 1, 'recuperar a instalação não deve baixar novamente o arquivo já salvo');
    const offlineResponse = await page.evaluate(async () => {
      const cache = await caches.open('cultivar-shell-teste-recuperacao');
      return (await cache.match(new URL('interrompido.txt', location.href))).text();
    });
    assert.equal(offlineResponse, 'conexão recuperada');
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    assert.equal(await page.evaluate(() => cultivarPlatform.acquireSession()), true);
    const other = await page.context().newPage();
    await other.goto(page.url());
    assert.equal(await other.evaluate(() => cultivarPlatform.acquireSession()), false);
    await page.evaluate(() => cultivarPlatform.releaseSession());
    assert.equal(await other.evaluate(() => cultivarPlatform.acquireSession()), true);
    await other.evaluate(() => cultivarPlatform.releaseSession());
    await other.close();
    await context.setOffline(true);
    assert.equal(await page.evaluate(async () => (await fetch('assets/AssetManifest.bin')).text()), 'manifesto binário do aplicativo');
    const report = {success: true, checks: ['Cache completo confirmado antes de liberar o uso offline', 'Falha de cache identificada sem atribuir o erro ao HTTPS', 'Novas tentativas automáticas após erro de rede', 'Recuperação do cache após interrupção', 'Arquivos já salvos reaproveitados', 'Troca de janela libera a sessão do banco', 'Janela bloqueada pode tentar obter a sessão novamente'], requests};
    const output = path.join(root, 'build/verificacao-preparacao');
    fs.mkdirSync(output, {recursive: true});
    fs.writeFileSync(path.join(output, 'verificacao.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
