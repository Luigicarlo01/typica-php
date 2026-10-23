{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href},
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    document.getElementById('loading')?.remove();
    await appRunner.runApp();
  },
});
