/* Atualização automática: worker real, interrupção de rede e dados preservados.
 * A fixture usa arquivos pequenos para isolar o ciclo de atualização.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require('playwright-core');
(async () => {
  const root = path.resolve(__dirname, '..');
  const js = fs.readFileSync(path.join(root, 'web/pwa.js'));
  const template = fs.readFileSync(path.join(root, 'tools/service_worker.template.js'), 'utf8');
  let version = 1;
  let available = false;
  let reloads = 0;
  const worker = () => template.replace('__MANIFEST_PATH__', 'api/manifesto.php?versao=fixture').replace('__BUILD_ID__', `update-test-${version}`).replace('__CORE_FILES__', JSON.stringify(['index.html', 'pwa.js', 'ready.txt']));
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    res.setHeader('Cache-Control', 'no-store');
    if (url.pathname === '/sw.js' || url.pathname === '/pwa.js') {
      res.setHeader('Content-Type', 'application/javascript');
      res.end(url.pathname === '/sw.js' ? worker() : js);
    } else if (url.pathname === '/ready.txt') {
      res.statusCode = version === 2 && !available ? 503 : 200;
      res.end(`recursos-${version}`);
    } else {
      res.setHeader('Content-Type', 'text/html');
      res.end(`<!doctype html><html><head><base href="/"></head><body data-version="${version}"><script src="pwa.js"></script></body></html>`);
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    page.on('framenavigated', frame => {if (frame === page.mainFrame()) reloads++;});
    assert.equal(await page.evaluate(() => cultivarPlatform.offlineShellReady()), true);
    console.log('OK: primeiro cache completo');
    await page.waitForFunction(() => !!navigator.serviceWorker.controller);
    assert.equal(reloads, 0, 'a primeira instalação não deve interromper o download automático');
    await page.evaluate(async () => {
      localStorage.setItem('historico-preservado', 'original');
      await new Promise((resolve, reject) => {
        const r = indexedDB.open('dados-preservados', 1);
        r.onupgradeneeded = () => r.result.createObjectStore('snapshot');
        r.onerror = () => reject(r.error);
        r.onsuccess = () => {
          const db = r.result;
          const t = db.transaction('snapshot', 'readwrite');
          t.objectStore('snapshot').put('banco-original', 'conteudo');
          t.oncomplete = () => {db.close(); resolve();};
        };
      });
    });
    version = 2;
    console.log('OK: dados de teste preservados; interrompendo a atualização');
    await page.evaluate(async () => {
      const r = await navigator.serviceWorker.getRegistration();
      await r.update();
      const w = r.installing;
      if (w && !['activated', 'redundant'].includes(w.state)) await new Promise(resolve => w.addEventListener('statechange', () => {if (['activated', 'redundant'].includes(w.state)) resolve();}));
    });
    assert.equal(reloads, 0, 'uma atualização incompleta não deve substituir o aplicativo funcionando');
    console.log('OK: atualização incompleta manteve o aplicativo');
    assert.equal(await page.locator('body').getAttribute('data-version'), '1');
    available = true;
    await page.evaluate(async () => {const r = await navigator.serviceWorker.getRegistration(); r.update().catch(() => {});});
    await page.waitForFunction(() => document.body.dataset.version === '2', {}, {timeout: 30000});
    await page.waitForTimeout(500);
    assert.equal(reloads, 1, 'a atualização completa deve reabrir o app uma única vez');
    const data = await page.evaluate(async () => {
      const value = await new Promise((resolve, reject) => {
        const r = indexedDB.open('dados-preservados');
        r.onerror = () => reject(r.error);
        r.onsuccess = () => {const db = r.result; const q = db.transaction('snapshot').objectStore('snapshot').get('conteudo'); q.onsuccess = () => {db.close(); resolve(q.result);};};
      });
      return {value, history: localStorage.getItem('historico-preservado')};
    });
    assert.deepEqual(data, {value: 'banco-original', history: 'original'});
    await context.setOffline(true);
    await page.reload();
    assert.equal(await page.locator('body').getAttribute('data-version'), '2');
    const report = {success: true, checks: ['Primeira instalação não recarrega a página', 'Atualização interrompida mantém a versão funcional', 'Recursos completos provocam uma única reabertura automática', 'IndexedDB e histórico preservados', 'Nova versão reabre totalmente offline']};
    const output = path.join(root, 'build/verificacao-atualizacao');
    fs.mkdirSync(output, {recursive: true});
    fs.writeFileSync(path.join(output, 'resultado.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
  } finally {if (browser) await browser.close(); await new Promise(resolve => server.close(resolve));}
})().catch(error => {console.error(error); process.exitCode = 1;});
