/* Filtros reais por instituição/ciclo em dois pixels, com a ordem do SQLite
 * como referência independente. Inclui limpeza dos filtros, ausência de exportação e reabertura offline.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {execFileSync} = require('node:child_process');
const {chromium} = require('playwright-core');
const root = path.resolve(__dirname, '..');
const base = process.env.PWA_TEST_URL || 'http://localhost:8084/';
const directory = process.env.PWA_TEST_DIRECTORY || path.join(root, 'build/web');
const output = process.env.PWA_TEST_OUTPUT || path.join(root, 'build/verificacao-filtros');
const fixture = JSON.parse(execFileSync('python3', [path.join(__dirname, 'casos_filtros.py'), directory]));
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'typica-filtros-'));
fs.mkdirSync(output, {recursive: true});
const report = {success: false, checks: [], clearChecks: [], errors: [], url: base};
let context, page;
let downloads = 0;
let exportedFiles = 0;

async function open(offline = false) {
  context = await chromium.launchPersistentContext(profile, {
    executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', headless: true,
    args: ['--no-sandbox', '--disable-dev-shm-usage'], viewport: {width: 390, height: 844},
    acceptDownloads: true,
  });
  await context.grantPermissions(['geolocation'], {origin: new URL(base).origin});
  page = context.pages()[0];
  page.on('download', () => exportedFiles++);
  page.on('pageerror', error => report.errors.push(error.message));
  page.on('console', message => {if (/overflowed|RenderFlex/.test(message.text())) report.errors.push(message.text());});
  context.on('request', request => {if (new URL(request.url()).pathname.endsWith('/api/lote.php')) downloads++;});
  if (offline) await context.setOffline(true);
  await page.goto(base, {waitUntil: 'domcontentloaded'});
  const semantics = page.locator('flt-semantics-placeholder');
  await semantics.waitFor({state: 'attached', timeout: 30000});
  await semantics.evaluate(node => node.click());
}

async function tutorial() {
  await page.waitForTimeout(400);
  const skip = page.getByRole('button', {name: 'Não desejo fazer o tutorial', exact: true});
  if (await skip.count()) await skip.click();
}

async function mapReady() {
  await Promise.race([
    page.getByRole('textbox').first().waitFor({timeout: 120000}),
    page.getByText('Não desejo fazer o tutorial', {exact: true}).waitFor({timeout: 120000}),
  ]);
  await tutorial();
  await page.getByRole('textbox').first().waitFor();
}

async function atPixel(pixel) {
  await context.setGeolocation({latitude: pixel.latitude, longitude: pixel.longitude, accuracy: 1});
  await page.getByRole('button', {name: 'Usar minha localização', exact: true}).click();
  await page.waitForTimeout(1100);
  await page.getByRole('button', {name: 'Confirmar localização', exact: true}).click();
  await Promise.race([
    page.getByText('Análise de Viçosa', {exact: true}).waitFor({timeout: 30000}),
    page.getByText('Não desejo fazer o tutorial', {exact: true}).waitFor({timeout: 30000}),
  ]);
  await tutorial();
  await page.getByText('Análise de Viçosa', {exact: true}).waitFor();
}

const labels = {cycle: 'Filtrar por ciclo de maturação', institution: 'Filtrar por instituição', rust: 'Filtrar por Ferrugem', nematode: 'Filtrar por Nematóide'};
async function scroll(top) {
  await page.mouse.move(280, 450);
  await page.mouse.wheel(0, top ? -2500 : 1800);
  await page.waitForTimeout(200);
}

async function choose(type, value) {
  await scroll(true);
  await page.getByRole('button', {name: new RegExp(labels[type])}).first().click({timeout: 10000});
  await page.getByRole('menuitem', {name: value, exact: true}).click();
}

async function ranking(expected, pixel) {
  await scroll(false);
  await page.waitForFunction(names => names.every(name => document.body.innerText.includes(name)), expected, {timeout: 10000});
  const text = await page.locator('body').innerText();
  const actual = pixel.ranking.filter(name => text.includes(name)).sort((a, b) => text.indexOf(a) - text.indexOf(b));
  assert.deepEqual(actual, expected);
  if (!expected.length) await page.getByText('Nenhuma cultivar atende aos filtros selecionados.', {exact: true}).waitFor();
}

async function assertNoExport() {
  assert.equal(await page.getByRole('button', {name: /Compartilhar relatório|Exportar|Baixar relatório/}).count(), 0);
}

async function clearAndVerify(pixel, name) {
  await scroll(false);
  const clear = page.getByRole('button', {name: 'Limpar filtros', exact: true});
  assert.equal(await clear.isEnabled(), true);
  await clear.click();
  await ranking(pixel.cases[0].expected, pixel);
  assert.equal(await clear.isDisabled(), true);
  for (const type of Object.keys(labels)) {
    await scroll(true);
    await page.getByRole('button', {name: new RegExp(labels[type] + '[\\s\\S]*Todos')}).waitFor();
  }
  await assertNoExport();
  report.clearChecks.push(name);
  console.log('OK: limpar filtros —', name);
}

async function restricted(pixel) {
  await choose('cycle', 'Curto');
  await choose('institution', 'IAC');
  await choose('rust', 'Resistente');
  await choose('nematode', 'Resistente');
  await ranking(['IAC 125 RN'], pixel);
}

(async () => {
  await open();
  await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).click();
  await page.getByRole('button', {name: 'Abrir Typica', exact: true}).waitFor({timeout: 180000});
  await page.evaluate(() => {
    cultivarPlatform.setPreference('onboarding_done', '1');
    cultivarPlatform.setPreference('onboarding_analysis', '1');
  });
  await page.getByRole('button', {name: 'Abrir Typica', exact: true}).click();
  await mapReady();
  for (let p = 0; p < fixture.pixels.length; p++) {
    const pixel = fixture.pixels[p];
    await atPixel(pixel);
    await assertNoExport();
    await scroll(false);
    assert.equal(await page.getByRole('button', {name: 'Limpar filtros', exact: true}).isDisabled(), true);
    if (p === 0) {
      // Usuário que já viu o tutorial recebe apenas as duas novidades.
      // tutorial() pulou o fluxo; a versão deve avançar sem repetir na próxima análise.
      assert.equal(await page.evaluate(() => cultivarPlatform.getPreference('onboarding_analysis')), '2');
    }
    let current = {cycle: 'Todos', institution: 'Todos', rust: 'Todos', nematode: 'Todos'};
    for (let index = 0; index < pixel.cases.length; index++) {
      const item = pixel.cases[index];
      for (const type of Object.keys(labels)) {
        if (current[type] !== item[type]) {await choose(type, item[type]); current[type] = item[type];}
      }
      await ranking(item.expected, pixel);
      report.checks.push({pixel: p + 1, cycle: item.cycle, institution: item.institution, rust: item.rust, nematode: item.nematode, ranking: item.expected});
      console.log('OK:', p + 1, item.cycle, item.institution, item.expected.join(' / ') || 'lista vazia');
      if (p === 0 && index === 8) {
        await page.screenshot({path: path.join(output, '01-iac-curto.png')});
      }
    }
    await restricted(pixel);
    await clearAndVerify(pixel, `pixel ${p + 1}: quatro filtros ativos com resultados`);
    await choose('cycle', 'Longo');
    await choose('institution', 'IAC');
    await ranking([], pixel);
    await clearAndVerify(pixel, `pixel ${p + 1}: lista vazia e ciclo ativo`);
    await choose('institution', 'IDR Paraná');
    await ranking([], pixel);
    await clearAndVerify(pixel, `pixel ${p + 1}: somente instituição ativa`);
    await page.getByRole('button', {name: /^(Back|Voltar)$/}).click();
    await mapReady();
  }
  await context.close();
  await open(true);
  await mapReady();
  await atPixel(fixture.pixels[0]);
  await choose('institution', 'IAC');
  await choose('cycle', 'Curto');
  await ranking(fixture.pixels[0].cases[8].expected, fixture.pixels[0]);
  await page.screenshot({path: path.join(output, '02-iac-curto-offline.png')});
  await choose('rust', 'Resistente');
  await choose('nematode', 'Resistente');
  await ranking(['IAC 125 RN'], fixture.pixels[0]);
  await clearAndVerify(fixture.pixels[0], 'offline: quatro filtros ativos');
  await page.setViewportSize({width: 320, height: 568});
  await scroll(true);
  await page.screenshot({path: path.join(output, '05-filtros-lado-320.png')});
  await scroll(false);
  await page.screenshot({path: path.join(output, '03-limpar-320.png')});
  await choose('institution', 'Fundação Procafé');
  await ranking([], fixture.pixels[0]);
  await clearAndVerify(fixture.pixels[0], 'offline: tela de 320 px e lista vazia');
  await scroll(false);
  await page.screenshot({path: path.join(output, '04-limpar-offline.png')});
  assert.equal(exportedFiles, 0);
  report.noExportAction = true;
  assert.equal(downloads, 46);
  assert.deepEqual(report.errors, []);
  report.success = true;
  report.offlineFilters = true;
  report.noRepeatedDatabaseDownload = true;
  report.nativeDevicesTested = false;
})().catch(async error => {
  report.error = error.stack;
  console.error(error);
  if (page && !page.isClosed()) {
    report.lastScreen = await page.locator('body').innerText().catch(() => '');
    report.labels = await page.locator('[role]').evaluateAll(nodes => nodes.map(node => ({role: node.getAttribute('role'), label: node.getAttribute('aria-label'), text: node.innerText.slice(0, 160)}))).catch(() => []);
    await page.screenshot({path: path.join(output, 'falha.png')}).catch(() => {});
  }
  process.exitCode = 1;
}).finally(async () => {
  if (context) await context.close();
  fs.writeFileSync(path.join(output, 'resultado.json'), JSON.stringify(report, null, 2) + '\n');
  fs.rmSync(profile, {recursive: true, force: true});
});
