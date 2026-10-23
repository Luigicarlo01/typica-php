import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

import 'pwa_platform.dart';

String webDatabaseName(String name) =>
    'cultivar${PwaPlatform.storageNamespace}_$name';

Future<bool> webDatabaseExists(String name) async {
  await _acquireSession();
  final fullName = webDatabaseName(name);
  final probe = await WasmDatabase.probe(
    databaseName: fullName,
    sqlite3Uri: PwaPlatform.baseUri.resolve('sqlite3.wasm'),
    driftWorkerUri: PwaPlatform.baseUri.resolve('drift_worker.dart.js'),
  );
  return probe.existingDatabases.any((database) => database.$2 == fullName);
}

Future<void> _acquireSession() async {
  if (!await PwaPlatform.acquireSession()) {
    throw StateError(
      'O Typica já está aberto em outra aba. Feche a outra janela e recarregue esta página.',
    );
  }
}

Future<WasmDatabaseResult> openWebDatabase({
  required String name,
  Future<Uint8List?> Function()? initializeDatabase,
  bool enableMigrations = true,
}) async {
  await _acquireSession();
  final result = await WasmDatabase.open(
    databaseName: webDatabaseName(name),
    sqlite3Uri: PwaPlatform.baseUri.resolve('sqlite3.wasm'),
    driftWorkerUri: PwaPlatform.baseUri.resolve('drift_worker.dart.js'),
    initializeDatabase: initializeDatabase,
    enableMigrations: enableMigrations,
  );
  if (result.chosenImplementation == WasmStorageImplementation.inMemory ||
      (result.chosenImplementation ==
              WasmStorageImplementation.unsafeIndexedDb &&
          !PwaPlatform.hasSessionLocks)) {
    await result.resolvedExecutor.close();
    throw StateError(
      'O navegador não permite salvar os dados. Use uma janela normal e habilite o armazenamento do site.',
    );
  }
  return result;
}
