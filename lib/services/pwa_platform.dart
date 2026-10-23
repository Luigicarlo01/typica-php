import 'dart:js_interop';
import 'dart:typed_data';

@JS('cultivarPlatform.baseUri')
external JSString get _baseUri;
@JS('cultivarPlatform.hasSessionLocks')
external JSBoolean get _hasSessionLocks;
@JS('cultivarPlatform.acquireSession')
external JSPromise<JSBoolean> _acquireSession();
@JS('cultivarPlatform.releaseSession')
external JSPromise<JSAny?> _releaseSession();
@JS('cultivarPlatform.getPreference')
external JSString? _getPreference(JSString name);
@JS('cultivarPlatform.setPreference')
external void _setPreference(JSString name, JSString value);
@JS('cultivarPlatform.removePreference')
external void _removePreference(JSString name);
@JS('cultivarPlatform.prepareStorage')
external JSPromise<JSBoolean> _prepareStorage(JSNumber bytes);
@JS('cultivarPlatform.preparePackages')
external JSPromise<JSBoolean> _preparePackages(
  JSString manifest,
  JSFunction callback,
);
@JS('cultivarPlatform.loadPackage')
external JSPromise<JSUint8Array> _loadPackage(
  JSString manifest,
  JSString descriptor,
);
@JS('cultivarPlatform.hasPackages')
external JSPromise<JSBoolean> _hasPackages(JSString manifest);
@JS('cultivarPlatform.noteDatabaseBytes')
external void _noteDatabaseBytes(JSNumber bytes);
@JS('cultivarPlatform.installationState')
external JSString get _installationState;
@JS('cultivarPlatform.isInstalled')
external JSBoolean get _isInstalled;
@JS('cultivarPlatform.isStandalone')
external JSBoolean get _isStandalone;
@JS('cultivarPlatform.setPrepared')
external void _setPrepared(JSBoolean value);
@JS('cultivarPlatform.setClientVersion')
external void _setClientVersion(JSString value);
@JS('cultivarPlatform.diagnostics')
external JSString get _diagnostics;
@JS('cultivarPlatform.listenInstallation')
external JSFunction _listenInstallation(JSFunction listener);
@JS('cultivarPlatform.install')
external JSPromise<JSBoolean> _install();
@JS('cultivarPlatform.installationHelp')
external JSString get _installationHelp;
@JS('cultivarPlatform.checkUpdate')
external JSPromise<JSBoolean> _checkUpdate();
@JS('cultivarPlatform.applyUpdate')
external JSPromise<JSAny?> _applyUpdate();
@JS('cultivarPlatform.offlineShellReady')
external JSPromise<JSBoolean> _offlineShellReady();

/// Contratos do navegador mantidos separados das telas e regras de ranking.
abstract final class PwaPlatform {
  static const version = String.fromEnvironment(
    'CULTIVAR_VERSION',
    defaultValue: 'desenvolvimento',
  );
  static void initialize() => _setClientVersion(version.toJS);
  static bool get isInstalled => _isInstalled.toDart;
  static bool get isStandalone => _isStandalone.toDart;
  static void setPrepared(bool value) => _setPrepared(value.toJS);
  static String get diagnostics => _diagnostics.toDart;
  static Uri get baseUri => Uri.parse(_baseUri.toDart);
  static bool get hasSessionLocks => _hasSessionLocks.toDart;
  static Future<bool> acquireSession() async =>
      (await _acquireSession().toDart).toDart;
  static Future<void> releaseSession() async {
    await _releaseSession().toDart;
  }

  static String get storageNamespace =>
      baseUri.path.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  static String? preference(String name) => _getPreference(name.toJS)?.toDart;
  static void savePreference(String name, String value) =>
      _setPreference(name.toJS, value.toJS);
  static void removePreference(String name) => _removePreference(name.toJS);
  static Future<bool> prepareStorage(int bytes) async =>
      (await _prepareStorage(bytes.toJS).toDart).toDart;
  static Future<void> preparePackages(
    String manifest,
    void Function(int, int, String) progress,
  ) async {
    final callback = ((JSNumber received, JSNumber total, JSString phase) {
      progress(received.toDartInt, total.toDartInt, phase.toDart);
    }).toJS;
    await _preparePackages(manifest.toJS, callback).toDart;
  }

  static Future<bool> hasPackages(String manifest) async =>
      (await _hasPackages(manifest.toJS).toDart).toDart;

  static Future<Uint8List> loadPackage(
    String manifest,
    String descriptor,
  ) async => (await _loadPackage(manifest.toJS, descriptor.toJS).toDart).toDart;
  static void noteDatabaseBytes(int bytes) => _noteDatabaseBytes(bytes.toJS);
  static Future<bool> install() async => (await _install().toDart).toDart;
  static String get installationState => _installationState.toDart;
  static void Function() listenInstallation(void Function(String) listener) {
    final cancel = _listenInstallation(
      ((JSString state) => listener(state.toDart)).toJS,
    );
    return () => cancel.callAsFunction();
  }

  static String get installationHelp => _installationHelp.toDart;
  static Future<bool> checkUpdate() async =>
      (await _checkUpdate().toDart).toDart;
  static Future<void> applyUpdate() async {
    await _applyUpdate().toDart;
  }

  static Future<bool> offlineShellReady() async =>
      (await _offlineShellReady().toDart).toDart;
}
