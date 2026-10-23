/* Fluxo real de dados e navegação em três tamanhos de tela no Chrome do PC.
 * O convite nativo e o modo standalone são simulados; não cria ícone no Android.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {chromium} = require('playwright-core');
const base = process.env.PWA_TEST_URL || 'http://localhost:8081/';
const output = path.resolve(__dirname, '../build/verificacao-tela-inicial');
fs.mkdirSync(output, {recursive: true});

async function semantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({state: 'attached', timeout: 30000});
  await placeholder.evaluate(node => node.click());
}

async function mapReady(page) {
  const skip = page.getByText('Não desejo fazer o tutorial', {exact: true});
  await Promise.race([skip.waitFor({timeout: 120000}), page.getByRole('textbox').first().waitFor({timeout: 120000})]);
  await page.waitForTimeout(500);
  if (await skip.count()) await skip.click();
  await page.getByRole('textbox').first().waitFor({timeout: 120000});
  assert.equal(await page.getByRole('button', {name: 'Salvar como app', exact: true}).count(), 0);
  assert.equal(await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).count(), 0);
  assert.equal(await page.getByRole('button', {name: 'Abrir Typica', exact: true}).count(), 0);
}

async function completeMapTutorial(page) {
  const titles = ['Bem-vindo ao Typica', 'Busque uma cidade', 'Escolha o ponto no mapa', 'Usar minha localização', 'Dados para usar sem internet', 'Pronto para começar'];
  for (let index = 0; index < titles.length; index++) {
    await page.getByText(`${index + 1} de ${titles.length}`, {exact: true}).waitFor({timeout: 120000});
    await page.getByText(titles[index], {exact: true}).waitFor();
    await page.waitForTimeout(750);
    if (index === 0) await page.screenshot({path: path.join(output, `${page.viewportSize().width}x${page.viewportSize().height}-tutorial-mapa.png`)});
    await page.getByText(index === titles.length - 1 ? 'Começar a usar' : 'Próximo', {exact: true}).last().click();
  }
  await page.getByText('Pronto para começar', {exact: true}).waitFor({state: 'hidden'});
  assert.equal(await page.evaluate(() => cultivarPlatform.getPreference('onboarding_installed_done')), '1');
  assert.equal(await page.evaluate(() => cultivarPlatform.getPreference('onboarding_done')), '1');
  assert.equal(await page.evaluate(() => cultivarPlatform.getPreference('onboarding_analysis')), '1');
}

(async () => {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'cultivar-telas-'));
  let context;
  const results = [];
  try {
    const viewports = process.env.PWA_TEST_VIEWPORTS ? process.env.PWA_TEST_VIEWPORTS.split(',').map(value => {const [width, height] = value.split('x').map(Number); return {width, height};}) : [{width: 320, height: 568}, {width: 390, height: 844}, {width: 844, height: 390}];
    for (const viewport of viewports) {
      context = await chromium.launchPersistentContext(path.join(profile, `${viewport.width}`), {executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'], viewport});
      const page = context.pages()[0] || await context.newPage();
      const errors = [];
      let downloads = 0;
      context.on('request', request => {const p = new URL(request.url()).pathname; if (p.endsWith('/api/lote.php')) downloads++;});
      page.on('console', message => {if (/overflowed|RenderFlex/.test(message.text())) errors.push(message.text());});
      await page.goto(base, {waitUntil: 'domcontentloaded'});
      await semantics(page);
      const spinner = page.getByLabel('Carregando Typica', {exact: true});
      await spinner.waitFor();
      const brandingStarted = Date.now();
      const spinnerBox = await spinner.boundingBox();
      assert(Math.abs(spinnerBox.width - 20) < 1 && Math.abs(spinnerBox.height - 20) < 1, JSON.stringify(spinnerBox));
      await page.screenshot({path: path.join(output, `${viewport.width}x${viewport.height}-abertura.png`)});
      await page.waitForTimeout(1000);
      assert.equal(await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).count(), 0, 'os logotipos devem permanecer visíveis antes das ações');
      await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).waitFor();
      const brandingVisibleMs = Date.now() - brandingStarted;
      assert(brandingVisibleMs >= 2000, `Abertura curta: ${brandingVisibleMs} ms`);
      assert.equal(await page.title(), 'Typica');
      const appManifest = await page.evaluate(async () => (await (await fetch('manifest.json')).json()));
      assert.equal(appManifest.name, 'Typica');
      assert.equal(appManifest.short_name, 'Typica');
      await page.evaluate(() => {
        cultivarPlatform.setPreference('onboarding_done', '1');
        cultivarPlatform.setPreference('onboarding_analysis', '1');
      });
      const expectedBundles = await page.evaluate(async () => (await (await fetch((await (await fetch('api/versao.php')).json()).manifest_url)).json()).bundles.length);
      await page.getByRole('button', {name: 'Baixar banco de dados', exact: true}).waitFor();
      await page.getByRole('button', {name: 'Salvar como app', exact: true}).waitFor();
      assert.equal(await page.getByRole('button', {name: 'Salvar como app', exact: true}).isEnabled(), true);
      await page.getByRole('button', {name: 'Verificar atualização', exact: true}).click();
      await page.getByText('Aplicativo atualizado', {exact: true}).waitFor({timeout: 120000});
      await page.getByRole('button', {name: 'Entendi', exact: true}).click();
      assert.equal(downloads, 0, 'abrir a tela e verificar atualizações não deve baixar o banco');
      assert.equal(await page.evaluate(() => JSON.parse(cultivarPlatform.diagnostics).dataReady), false);
      await page.screenshot({path: path.join(output, `${viewport.width}x${viewport.height}-inicial.png`)});
      await page.evaluate(() => {
        const event = new Event('beforeinstallprompt', {cancelable: true});
        event.prompt = async () => {};
        event.userChoice = Promise.resolve({outcome: 'dismissed'});
        window.dispatchEvent(event);
      });
      await page.getByRole('button', {name: 'Salvar como app', exact: true}).click();
      assert.equal(await page.evaluate(() => cultivarPlatform.isInstalled), false);
      assert.equal(downloads, 0, 'cancelar a instalação não deve baixar dados');

      let releaseFirstBundle;
      let bundlePaused = false;
      await context.route(/\/api\/lote\.php\?/, async route => {
        if (!bundlePaused) {
          bundlePaused = true;
          await new Promise(resolve => {releaseFirstBundle = resolve;});
        }
        await route.continue();
      });
      await page.evaluate(() => {
        const event = new Event('beforeinstallprompt', {cancelable: true});
        event.prompt = async () => { window.__installationPrompted = true; };
        event.userChoice = Promise.resolve({outcome: 'accepted'});
        window.dispatchEvent(event);
      });
      assert.equal(await page.evaluate(() => cultivarPlatform.installationState), 'ready');
      await page.getByRole('button', {name: 'Salvar como app', exact: true}).click();
      await page.waitForFunction(() => cultivarPlatform.isInstalled);
      assert.equal(await page.evaluate(() => window.__installationPrompted), true);
      await page.getByRole('button', {name: 'Aplicativo instalado', exact: true}).waitFor();
      await page.getByRole('button', {name: 'Preparando banco de dados…', exact: true}).waitFor();
      await page.screenshot({path: path.join(output, `${viewport.width}x${viewport.height}-baixando.png`)});

      // Abrir o ícone durante o primeiro lote não pode disputar nem repetir o download.
      const installed = await context.newPage();
      await installed.addInitScript(() => Object.defineProperty(navigator, 'standalone', {value: true}));
      await installed.goto(base, {waitUntil: 'domcontentloaded'});
      await semantics(installed);
      await installed.getByRole('button', {name: 'Preparando banco de dados…', exact: true}).waitFor();
      await installed.waitForFunction(async () => (await navigator.locks.query()).pending.some(lock => lock.name.endsWith(':download')));
      assert.equal(downloads, 1, 'a janela instalada deve aguardar o lote em andamento');
      assert.equal(typeof releaseFirstBundle, 'function');
      releaseFirstBundle();
      await page.waitForFunction(() => JSON.parse(cultivarPlatform.diagnostics).dataReady, {}, {timeout: 180000});
      await page.getByRole('button', {name: 'Abrir Typica', exact: true}).waitFor();
      console.log('PREPARADO JUNTO COM A INSTALAÇÃO:', viewport.width, 'x', viewport.height);
      await page.screenshot({path: path.join(output, `${viewport.width}x${viewport.height}-pronto.png`)});
      await completeMapTutorial(installed);
      await mapReady(installed);
      assert.equal(downloads, expectedBundles, 'abrir o ícone deve reaproveitar o banco já salvo pela aba original');
      const diagnostics = await installed.evaluate(() => JSON.parse(cultivarPlatform.diagnostics));
      assert.equal(diagnostics.standalone, true);
      assert.equal(diagnostics.dataReady, true);
      await installed.screenshot({path: path.join(output, `${viewport.width}x${viewport.height}-instalado.png`)});
      await installed.close();
      await context.setOffline(true);
      const reopened = await context.newPage();
      await reopened.goto(base, {waitUntil: 'domcontentloaded'});
      await semantics(reopened);
      await mapReady(reopened);
      assert.equal(await reopened.getByText('1 de 6', {exact: true}).count(), 0, 'tutorial concluído não deve reaparecer');
      if (viewport.width === 390) {
        await reopened.getByRole('button', {name: 'Mais opções', exact: true}).click();
        await reopened.getByRole('menuitem', {name: /Rever tutorial/}).click();
        await reopened.getByText('1 de 6', {exact: true}).waitFor();
        await reopened.getByText('Bem-vindo ao Typica', {exact: true}).waitFor();
        await reopened.getByRole('button', {name: 'Não desejo fazer o tutorial', exact: true}).click();
      }
      assert.equal(downloads, expectedBundles);
      assert.deepEqual(errors, []);
      results.push({viewport, version: diagnostics.version, brand: 'Typica', brandingVisibleMs, indicatorSize: {width: spinnerBox.width, height: spinnerBox.height}, mapTutorialAfterInstallDespiteBrowserTutorialSeen: true, fullMapTutorialCompleted: true, completedTutorialNotRepeatedOffline: true, firstAccessShowsThreeActions: true, siteVisitWithoutDataDownload: true, updateWithoutDataDownload: true, cancelInstallWithoutDataDownload: true, simulatedInstallationIncludesData: true, iconOpenedDuringDownloadCompletesAutomatically: true, noDuplicateDownloadBetweenWindows: true, installedLaunchDirectMapWithOriginalTabOpen: true, installationRememberedOffline: true, snapshotDownloads: downloads, overflowErrors: errors});
      console.log('OK:', viewport.width, 'x', viewport.height);
      await context.close();
    }
    // Simula o armazenamento separado do Safari: nenhum pacote nem preferência copiados.
    context = await chromium.launchPersistentContext(path.join(profile, 'isolated-installed'), {executablePath: process.env.CHROME_PATH || '/usr/bin/google-chrome', headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage'], viewport: {width: 390, height: 844}});
    await context.addInitScript(() => Object.defineProperty(navigator, 'standalone', {value: true}));
    let isolatedDownloads = 0;
    context.on('request', request => {const p = new URL(request.url()).pathname; if (p.endsWith('/api/lote.php')) isolatedDownloads++;});
    const isolated = context.pages()[0];
    await isolated.goto(base, {waitUntil: 'domcontentloaded'});
    await semantics(isolated);
    await mapReady(isolated);
    const expected = await isolated.evaluate(() => JSON.parse(cultivarPlatform.diagnostics).packages.expected);
    const isolatedBundles = await isolated.evaluate(async () => (await (await fetch((await (await fetch('api/versao.php')).json()).manifest_url)).json()).bundles.length);
    assert.equal(isolatedDownloads, isolatedBundles);
    assert.equal(expected, 854);
    await context.setOffline(true);
    await isolated.reload({waitUntil: 'domcontentloaded'});
    await semantics(isolated);
    await mapReady(isolated);
    assert.equal(isolatedDownloads, isolatedBundles);
    const report = {success: true, nativePromptSimulated: true, standaloneModeSimulated: true, isolatedInstalledStorageSimulated: {automaticPreparationAndMap: true, offlineReopen: true, bundlesDownloaded: isolatedDownloads}, results};
    fs.writeFileSync(path.join(output, 'resultado.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report));
  } catch (error) {
    if (context) {
      for (const [index, page] of context.pages().entries()) {
        const details = await page.locator('body').innerText().catch(() => '');
        const labels = await page.locator('[aria-label]').evaluateAll(nodes => nodes.map(node => ({role: node.getAttribute('role'), label: node.getAttribute('aria-label')}))).catch(() => []);
        fs.writeFileSync(path.join(output, `falha-${index}.json`), JSON.stringify({details, labels}, null, 2));
        await page.screenshot({path: path.join(output, `falha-${index}.png`)}).catch(() => {});
      }
    }
    throw error;
  } finally {if (context) await context.close(); fs.rmSync(profile, {recursive: true, force: true});}
})().catch(error => {console.error(error); process.exitCode = 1;});
