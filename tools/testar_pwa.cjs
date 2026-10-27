/* Teste real no Chrome, usando um perfil temporário e os dados de 2026.
 * Dependência de teste: playwright-core (não faz parte do app publicado).
 * NODE_PATH=/tmp/cultivar-pwa-browser/node_modules node tools/testar_pwa.cjs
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {chromium} = require('playwright-core');

const base = process.env.PWA_TEST_URL || 'http://localhost:8081/';
const output = process.env.PWA_TEST_OUTPUT || path.resolve(__dirname, '../build/verificacao');
fs.mkdirSync(output, {recursive: true});
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cultivar-pwa-teste-'));
const report = {url: base, viewport: {width: 390, height: 844}, checks: [], pageErrors: []};
let context;
let page;
const snapshotRequests = [];
const legacyRequests = [];
let expectedBundles = 0;
let progressTimer;
const mark = name => {report.checks.push(name); console.log('OK:', name);};
const options = {
  executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome',
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage', ...(process.env.PWA_TEST_LOW_MEMORY ? ['--js-flags=--max-old-space-size=256'] : [])],
  viewport: report.viewport,
  acceptDownloads: true,
};

async function launch(offline = false) {
  context = await chromium.launchPersistentContext(profile, options);
  if (process.env.PWA_TEST_LOW_MEMORY) await context.addInitScript(() => {
    delete window.DecompressionStream;
    delete window.SharedWorker;
    if (navigator.storage) {Object.defineProperty(navigator.storage, 'estimate', {value: undefined}); Object.defineProperty(navigator.storage, 'persist', {value: undefined});}
  });
  await context.grantPermissions(['geolocation'], {origin: new URL(base).origin});
  page = context.pages()[0] || await context.newPage();
  page.on('pageerror', error => report.pageErrors.push(error.message));
  page.on('console', message => {
    if (message.type() === 'error' && !message.text().includes('ERR_INTERNET_DISCONNECTED')) {
      console.log('BROWSER:', message.text().slice(0, 500));
    }
  });
  page.on('request', request => {
    const pathname = new URL(request.url()).pathname;
    if (pathname.endsWith('/api/lote.php')) snapshotRequests.push(request.url());
    if (pathname.endsWith('.sqlite.gz')) legacyRequests.push(request.url());
  });
  if (offline) {
    await context.setOffline(true);
  }
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  if (offline) {
    const cdp = await context.newCDPSession(page);
    await cdp.send('Network.enable');
    // Chrome recente separa a rede simulada do estado de navigator.onLine.
    await cdp.send('Network.overrideNetworkState', {
      offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1, connectionType: 'none',
    });
  }
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({state: 'attached', timeout: 30000});
  await placeholder.evaluate(node => node.click());
}

async function skipTutorial() {
  await page.waitForTimeout(500);
  const skip = page.getByText('Não desejo fazer o tutorial', {exact: true});
  if (await skip.count()) {
    await skip.click();
    await skip.waitFor({state: 'hidden'});
  }
}

async function mapReady() {
  await Promise.race([
    page.getByRole('textbox').first().waitFor({timeout: 120000}),
    page.getByText('Não desejo fazer o tutorial', {exact: true}).waitFor({timeout: 120000}),
  ]);
  await skipTutorial();
  await page.getByRole('textbox').first().waitFor({timeout: 120000});
}

async function search(name, suggestion) {
  const input = page.getByRole('textbox').first();
  const clear = page.getByRole('button', {name: 'Limpar busca', exact: true});
  if (await clear.count()) await clear.click();
  await input.click();
  await input.pressSequentially(name, {delay: 60});
  await page.getByText(suggestion, {exact: true}).click();
}

async function confirm(city = 'Viçosa') {
  await page.getByRole('button', {name: 'Confirmar localização', exact: true}).click();
  await Promise.race([
    page.getByText(`Análise de ${city}`, {exact: true}).waitFor({timeout: 30000}),
    page.getByText('Não desejo fazer o tutorial', {exact: true}).waitFor({timeout: 30000}),
  ]);
  await skipTutorial();
  await page.getByText(`Análise de ${city}`, {exact: true}).waitFor({timeout: 30000});
}

async function ranking(expected) {
  await page.mouse.move(280, 450);
  await page.mouse.wheel(0, 1800);
  await page.waitForTimeout(200);
  await page.waitForFunction(names => {
    const text = document.body.innerText;
    return names.every(name => text.includes(name));
  }, expected, {timeout: 15000});
  const text = await page.locator('body').innerText();
  const indices = expected.map(name => text.indexOf(name));
  for (let index = 1; index < indices.length; index++) {
    assert(indices[index] > indices[index - 1], `Ordem de ranking inesperada: ${text}`);
  }
}

async function back() {
  await page.getByRole('button', {name: /^(Back|Voltar)$/}).click();
  await mapReady();
}

async function gps(latitude, longitude) {
  await context.setGeolocation({latitude, longitude, accuracy: 1});
  await page.getByRole('button', {name: 'Usar minha localização', exact: true}).click();
  await page.waitForTimeout(1200);
  await confirm();
}

(async () => {
  await launch();
  expectedBundles = await page.evaluate(async () => (await (await fetch((await (await fetch('api/versao.php')).json()).manifest_url)).json()).bundles.length);
  const download = page.getByRole('button', {name: 'Baixar banco de dados', exact: true});
  await download.waitFor();
  assert.equal(snapshotRequests.length, 0);
  await download.click();
  const open = page.getByRole('button', {name: 'Abrir Typica', exact: true});
  await open.waitFor({timeout: 180000});
  assert.equal(await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).count(), 0);
  await page.screenshot({path: path.join(output, '01-pronto-para-instalar.png')});
  mark('Primeiro acesso apresenta ações e baixa o banco somente após o clique');
  await page.waitForFunction(() => !!navigator.serviceWorker.controller);
  const cdp = await context.newCDPSession(page);
  const installability = await cdp.send('Page.getInstallabilityErrors');
  report.installabilityErrors = installability.installabilityErrors;
  assert.deepEqual(report.installabilityErrors, []);
  assert.equal(snapshotRequests.length, expectedBundles);
  mark('Chrome aceita a instalação com o banco já salvo no aparelho');
  await open.click();
  await mapReady();
  clearInterval(progressTimer);
  assert.equal(snapshotRequests.length, expectedBundles);
  assert(await page.evaluate(() => !!navigator.serviceWorker.controller));
  assert.equal(legacyRequests.length, 0);
  mark('Todos os lotes salvos sem baixar ou abrir o SQLite monolítico');

  await search('Vicosa', 'Viçosa, Minas Gerais');
  await confirm();
  await page.mouse.move(280, 450);
  await page.mouse.wheel(0, -2500);
  await page.getByRole('button', {name: /Filtrar por ciclo de maturação/}).click();
  await page.getByRole('menuitem', {name: 'Médio', exact: true}).click();
  const names = ['MGS Epamig 1194', 'Topázio MG 1190', 'MGS Catiguá 3', 'Catiguá MG2', 'Catuaí Vermelho IAC 144'];
  await ranking(names);
  await page.screenshot({path: path.join(output, '02-analise-vicosa.png')});
  mark('Pesquisa municipal e ranking original de Viçosa');

  await back();
  await gps(-20.830307493566902, -42.85955821862572);
  await ranking(names);
  mark('GPS seleciona pixel cuja vencedora é MGS Epamig 1194');

  await back();
  await gps(-20.82459502172251, -42.87347917744958);
  await ranking([names[1], names[0], ...names.slice(2)]);
  await page.screenshot({path: path.join(output, '03-outro-pixel-vicosa.png')});
  mark('Outro pixel do mesmo município muda a ordem: Topázio em primeiro');

  await page.mouse.move(280, 450);
  await page.mouse.wheel(0, -2500);
  await page.getByRole('button', {name: /Filtrar por Ferrugem/}).click();
  await page.getByRole('menuitem', {name: 'Resistente', exact: true}).click();
  await ranking(['MGS Catiguá 3', 'Catiguá MG2', 'Pau Brasil MG1', 'Sarchimor MG 8840']);
  mark('Filtro de ferrugem preserva a ordem das alternativas do pixel');

  await page.getByRole('button', {name: /Filtrar por Nematóide/}).click();
  await page.getByRole('menuitem', {name: 'Resistente', exact: true}).click();
  await ranking(['MGS Catiguá 3']);
  assert(!(await page.locator('body').innerText()).includes('Topázio MG 1190'));
  mark('Filtro combinado de nematóide e ferrugem');

  assert.equal(await page.getByRole('button', {name: 'Compartilhar relatório', exact: true}).count(), 0);
  mark('Opção de exportação/compartilhamento ausente da interface');

  await back();
  await search('Joao Pinheiro', 'João Pinheiro, Minas Gerais');
  await confirm('João Pinheiro');
  mark('Maior partição municipal abre e gera análise sem carregar o banco estadual');
  report.onlinePackageDiagnostics = await page.evaluate(() => JSON.parse(cultivarPlatform.diagnostics).packages);
  assert(report.onlinePackageDiagnostics.maxNetworkBufferBytes > 0 && report.onlinePackageDiagnostics.maxNetworkBufferBytes <= 2000000);
  assert(report.onlinePackageDiagnostics.maxDatabaseBytes < 5000000);
  await context.close();
  await launch(true);
  await mapReady();
  assert.equal(await page.evaluate(() => navigator.onLine), false);
  await page.getByText(/Sem internet: pesquisa e recomendações locais disponíveis/).waitFor();
  assert.equal(snapshotRequests.length, expectedBundles);
  mark('Navegador fechado e reaberto offline, sem repetir download do banco');
  await search('Vicosa', 'Viçosa, Minas Gerais');
  await confirm();
  await page.mouse.move(280, 450);
  await page.mouse.wheel(0, -2500);
  await page.getByRole('button', {name: /Filtrar por ciclo de maturação/}).click();
  await page.getByRole('menuitem', {name: 'Médio', exact: true}).click();
  await ranking(names);
  await page.screenshot({path: path.join(output, '04-analise-offline.png')});
  mark('Pesquisa e recomendações funcionam após reabertura totalmente offline');
  const diagnostics = await page.evaluate(() => JSON.parse(cultivarPlatform.diagnostics));
  assert.equal(diagnostics.packages.saved, diagnostics.packages.expected);
  assert(diagnostics.packages.maxNetworkBufferBytes <= 2000000);
  assert(diagnostics.packages.maxDatabaseBytes < 5000000);
  report.packageDiagnostics = diagnostics.packages;
  report.legacySnapshotRequests = legacyRequests.length;
  report.simulatedMissingBrowserAPIs = !!process.env.PWA_TEST_LOW_MEMORY;
  report.v8OldHeapLimitMB = process.env.PWA_TEST_LOW_MEMORY ? 256 : null;
  mark('Somente catálogo e município consultado abertos; bancos somados abaixo de 5 MB');
  assert.deepEqual(report.pageErrors, []);
  report.success = true;
  report.browser = await context.browser().version();
  report.snapshotDownloads = snapshotRequests.length;
  console.log('PWA validado. Relatório e capturas em', output);
})().catch(async error => {
  report.success = false;
  report.error = error.stack;
  console.error(error);
  if (page && !page.isClosed()) {
    report.lastScreen = await page.locator('body').innerText().catch(() => '');
    console.log('ÚLTIMA TELA:', report.lastScreen);
    await page.screenshot({path: path.join(output, 'falha.png')}).catch(() => {});
  }
  process.exitCode = 1;
}).finally(async () => {
  clearInterval(progressTimer);
  if (context) await context.close();
  if (report.success) fs.rmSync(path.join(output, 'falha.png'), {force: true});
  fs.writeFileSync(path.join(output, 'resultado.json'), JSON.stringify(report, null, 2) + '\n');
  fs.rmSync(profile, {recursive: true, force: true});
});
