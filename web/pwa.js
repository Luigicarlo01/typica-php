/* Integração do PWA com o navegador. Sem credenciais ou serviços externos. */
(() => {
  'use strict';
  const base = new URL('.', document.baseURI);
  const scopeKey = base.pathname;
  let installPrompt = null;
  let registration = null;
  let reloadRequested = false;
  let sessionOwnership = null;
  let releaseSessionLock = null;
  let sessionRequest = null;
  let registrationError = null;
  const displayMode = window.matchMedia('(display-mode: standalone), (display-mode: minimal-ui), (display-mode: fullscreen), (display-mode: window-controls-overlay)');
  const standalone = () => displayMode.matches || navigator.standalone === true;
  const installedKey = `${scopeKey}:installation-confirmed`;
  let installed = standalone();
  try { installed ||= localStorage.getItem(installedKey) === '1'; } catch (_) {}
  let offlinePrepared = false;
  let clientVersion = 'carregando';
  let lastInstallError = null;
  const installationListeners = new Set();
  const installationState = () => installed || standalone() ? 'installed' : installPrompt ? 'ready' : 'manual';
  const publishInstallation = () => {
    for (const listener of installationListeners) listener(installationState());
  };
  const confirmInstallation = () => {
    installed = true;
    try { localStorage.setItem(installedKey, '1'); } catch (_) {}
    publishInstallation();
  };
  displayMode.addEventListener('change', publishInstallation);
  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    installPrompt = event;
    publishInstallation();
  });
  window.addEventListener('appinstalled', () => {
    installPrompt = null;
    confirmInstallation();
  });

  const register = async () => {
    if (!window.isSecureContext) throw new Error('Abra o aplicativo por um endereço HTTPS válido.');
    if (!('serviceWorker' in navigator)) throw new Error('Este navegador não permite preparar o uso offline. Abra o link em uma aba normal do Chrome atualizado (Android) ou Safari (iPhone/iPad).');
    registration = await navigator.serviceWorker.register(new URL('sw.js', base), {
      scope: base.pathname, updateViaCache: 'none',
    });
    registrationError = null;
    registration.update().catch(() => {});
    return registration;
  };
  const registerSafely = () => register().catch(error => {
    registrationError = error;
    console.warn('PWA:', error);
    return null;
  });
  let registrationReady = registerSafely();
  navigator.serviceWorker?.addEventListener('controllerchange', () => {
    if (reloadRequested) location.reload();
  });
  const offlineFailure = () => new Error('Não foi possível salvar os arquivos do aplicativo para uso offline. Mantenha esta tela aberta com internet e toque em “Tentar novamente”. Os dados já salvos serão mantidos.');

  window.cultivarPlatform = Object.freeze({
    baseUri: base.href,
    get isInstalled() { return installed || standalone(); },
    get isStandalone() { return standalone(); },
    setClientVersion(version) { clientVersion = version; },
    setPrepared(value) { offlinePrepared = !!value; publishInstallation(); },
    get diagnostics() {
      return JSON.stringify({version: clientVersion, backend: 'php', origin: base.origin, installed: installed || standalone(), standalone: standalone(), dataReady: offlinePrepared, installPromptAvailable: !!installPrompt, lastInstallError, browser: navigator.userAgent, packages: window.cultivarRegions?.diagnostics}, null, 2);
    },
    hasSessionLocks: !!navigator.locks,
    async acquireSession() {
      if (!navigator.locks) return Promise.resolve(true);
      if (!sessionOwnership) {
        sessionOwnership = new Promise((resolve, reject) => {
          sessionRequest = navigator.locks.request(`cultivar:${scopeKey}`, {ifAvailable: true}, lock => {
            resolve(!!lock);
            if (lock) return new Promise(release => { releaseSessionLock = release; });
          }).catch(reject);
        });
      }
      const ownership = sessionOwnership;
      const acquired = await ownership;
      if (!acquired && sessionOwnership === ownership) sessionOwnership = null;
      return acquired;
    },
    async releaseSession() {
      releaseSessionLock?.();
      await sessionRequest;
      releaseSessionLock = null;
      sessionOwnership = null;
    },
    storageKey: name => `${scopeKey}:${name}`,
    getPreference(name) { return localStorage.getItem(`${scopeKey}:${name}`); },
    setPreference(name, value) { localStorage.setItem(`${scopeKey}:${name}`, value); },
    removePreference(name) { localStorage.removeItem(`${scopeKey}:${name}`); },
    get installationState() { return installationState(); },
    listenInstallation(listener) {
      installationListeners.add(listener);
      listener(installationState());
      return () => installationListeners.delete(listener);
    },
    get installationHelp() {
      const ua = navigator.userAgent;
      if (/\bwv\b|FBAN|FBAV|Instagram|Line\//i.test(ua)) {
        return 'Copie este link e abra diretamente no Chrome (Android) ou Safari (iPhone/iPad). O navegador dentro de outro aplicativo pode não permitir instalar o Typica ou manter os dados offline.';
      }
      if (/iPhone|iPad|iPod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) {
        return 'No Safari, toque em Compartilhar → Adicionar à Tela de Início → Adicionar. Depois, abra o Typica pelo ícone com internet. Ele preparará os dados automaticamente e estará pronto para usar no campo, mesmo sem internet.';
      }
      if (/Android/i.test(ua)) {
        return 'Abra este link no Chrome. No menu ⋮, escolha “Instalar aplicativo” ou “Adicionar à tela inicial”. Depois, abra o Typica pelo ícone com internet. Os dados serão preparados automaticamente. Se já instalou, abra pelo ícone existente.';
      }
      return 'No Chrome ou Edge, use a opção de instalar no menu ou na barra de endereços. Se já estiver instalado, abra pelo ícone do Typica.';
    },
    async prepareStorage(databaseBytes) {
      if (!window.isSecureContext) throw new Error('Abra o aplicativo por HTTPS para preparar os dados offline.');
      if (!('serviceWorker' in navigator) || !window.crypto?.subtle) {
        throw new Error('Atualize o navegador e abra este link diretamente no Chrome (Android) ou Safari (iPhone/iPad), em uma aba normal, antes de baixar os dados.');
      }
      const storage = navigator.storage;
      if (!storage) return false;
      const estimate = typeof storage.estimate === 'function' ? await storage.estimate().catch(() => ({})) : {};
      if (estimate.quota && estimate.quota - (estimate.usage || 0) < databaseBytes + 64 * 1024 * 1024) {
        throw new Error('Não há espaço suficiente no navegador. Libere espaço no aparelho e tente novamente.');
      }
      try { return typeof storage.persist === 'function' ? await storage.persist() : false; } catch (_) { return false; }
    },
    preparePackages(manifest, progress) {return cultivarRegions.prepare(manifest, progress);},
    hasPackages(manifest) {return cultivarRegions.hasPackages(manifest);},
    loadPackage(manifest, descriptor) {return cultivarRegions.load(manifest, descriptor);},
    noteDatabaseBytes(bytes) {cultivarRegions.noteDatabaseBytes(bytes);},
    async install() {
      if (installPrompt) {
        const prompt = installPrompt;
        installPrompt = null;
        publishInstallation();
        try {
          await prompt.prompt();
          const result = await prompt.userChoice;
          if (result.outcome === 'accepted') confirmInstallation();
          publishInstallation();
          return result.outcome === 'accepted';
        } catch (error) {
          lastInstallError = `${error.name || 'Erro'}: ${error.message || error}`;
          throw error;
        } finally { publishInstallation(); }
      }
      return false;
    },
    async checkUpdate() {
      await registrationReady;
      if (!registration) return false;
      const response = await fetch(new URL('api/versao.php', base), {cache: 'no-store'});
      if (!response.ok) throw new Error('Não foi possível verificar as atualizações no servidor. Confira a conexão e tente novamente.');
      const latest = await response.json();
      if (latest.backend !== 'php' || latest.api_version !== 1 || typeof latest.build !== 'string') {
        throw new Error('O servidor de atualizações está incompatível com este aplicativo.');
      }
      await registration.update();
      const installing = registration.installing;
      if (installing) {
        await new Promise(resolve => {
          installing.addEventListener('statechange', () => {
            if (['installed', 'redundant'].includes(installing.state)) resolve();
          });
          if (['installed', 'redundant'].includes(installing.state)) resolve();
        });
      }
      return !!registration.waiting;
    },
    async applyUpdate() {
      await registrationReady;
      if (!registration?.waiting) return;
      reloadRequested = true;
      registration.waiting.postMessage({type: 'SKIP_WAITING'});
    },
    async offlineShellReady() {
      await registrationReady;
      // Uma instalação interrompida pode deixar o registro sem nenhum worker.
      // Registrar novamente retoma essa etapa sem apagar o banco já instalado.
      if (!registration?.active && !registration?.installing && !registration?.waiting) {
        registrationReady = registerSafely();
        await registrationReady;
      }
      if (!registration) throw registrationError || offlineFailure();
      if (!registration.active) {
        const worker = registration.installing || registration.waiting;
        if (!worker) throw offlineFailure();
        await new Promise((resolve, reject) => {
        const finish = error => {
          clearTimeout(timer);
          worker.removeEventListener('statechange', changed);
          if (error) reject(error); else resolve(true);
        };
        const changed = () => {
          if (worker.state === 'activated') finish();
          if (worker.state === 'redundant') finish(offlineFailure());
        };
        const timer = setTimeout(() => finish(offlineFailure()), 300000);
        worker.addEventListener('statechange', changed);
        changed();
        });
      }
      // Confirma o cache da interface. A instalação do ícone é independente
      // do download dos dados científicos, iniciado pelo usuário.
      return new Promise((resolve, reject) => {
        const channel = new MessageChannel();
        const timer = setTimeout(() => finish(offlineFailure()), 300000);
        const finish = error => {
          clearTimeout(timer);
          channel.port1.close();
          if (error) reject(error); else resolve(true);
        };
        channel.port1.onmessage = event => {
          if (event.data?.ok) finish();
          else finish(new Error(event.data?.message || offlineFailure().message));
        };
        registration.active.postMessage({type: 'PREPARE_OFFLINE'}, [channel.port2]);
      });
    },
  });
})();
