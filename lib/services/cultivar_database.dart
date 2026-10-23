import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/wasm.dart';

import 'pwa_platform.dart';

enum PreparationPhase {
  checking,
  awaitingDownload,
  downloading,
  verifying,
  installing,
  ready,
}

class DatabasePreparation {
  const DatabasePreparation(
    this.phase, {
    this.received = 0,
    this.total = 0,
    this.recovering = false,
  });
  final PreparationPhase phase;
  final int received;
  final int total;
  final bool recovering;
  double? get progress => total > 0 ? received / total : null;
}

/// Todos os municípios permanecem offline em Blobs compactados no IndexedDB.
/// O catálogo pequeno e apenas uma região por vez são abertos como SQLite.
class CultivarDatabase {
  static final instance = CultivarDatabase();
  static const dataVersion = String.fromEnvironment('TYPICA_DATA_VERSION');
  static const manifestAsset = 'api/manifesto.php?versao=$dataVersion';
  static const format = 'cultivar-sqlite-regions-v2';
  static Future<WasmSqlite3>? _sqlite;
  static int _sequence = 0;
  final preparation = ValueNotifier(
    const DatabasePreparation(PreparationPhase.checking),
  );
  CultivarDatabase();
  Future<_MemorySnapshot>? _opening;
  Future<void> _regionWork = Future.value();
  Map<int, Map<String, dynamic>>? _rankings;
  late Map<String, dynamic> _manifest;
  late String _manifestText;
  Future<void>? _manifestLoading;
  int _catalogBytes = 0;
  bool _closed = false;

  Future<void> ready() async {
    await _executor();
  }

  Future<bool> hasLocalData() async {
    await _loadManifest();
    return PwaPlatform.hasPackages(_manifestText);
  }

  /// Prepara e valida os dados sem ocupar a sessão de consulta/histórico.
  /// Assim, o ícone instalado pode concluir a abertura com o navegador aberto.
  Future<void> prepareLocalData() async {
    await _preparePackages();
    final snapshot = await _openCatalog();
    snapshot.close();
    preparation.value = const DatabasePreparation(PreparationPhase.ready);
  }

  Future<void> _loadManifest() async {
    final pending = _manifestLoading ??= _readManifest();
    try {
      await pending;
    } catch (_) {
      if (identical(_manifestLoading, pending)) _manifestLoading = null;
      rethrow;
    }
  }

  Future<void> _readManifest() async {
    final response = await http.get(PwaPlatform.baseUri.resolve(manifestAsset));
    if (response.statusCode != 200) {
      throw const FormatException(
        'O pacote de dados não está disponível na hospedagem.',
      );
    }
    _manifestText = utf8.decode(response.bodyBytes);
    _manifest = jsonDecode(_manifestText) as Map<String, dynamic>;
    _validateManifest();
  }

  Future<CommonDatabase> _executor() async {
    if (_closed) throw StateError('Banco local fechado.');
    final pending = _opening ??= _open();
    try {
      return (await pending).database;
    } catch (_) {
      if (identical(_opening, pending)) _opening = null;
      await PwaPlatform.releaseSession();
      rethrow;
    }
  }

  Future<_MemorySnapshot> _open() async {
    await _preparePackages();
    if (!await PwaPlatform.acquireSession()) {
      throw StateError(
        'O Typica já está aberto em outra janela. Feche a outra janela e tente novamente.',
      );
    }
    final snapshot = await _openCatalog();
    _catalogBytes = (_manifest['catalog'] as Map)['database_bytes'] as int;
    PwaPlatform.noteDatabaseBytes(_catalogBytes);
    preparation.value = const DatabasePreparation(PreparationPhase.ready);
    return snapshot;
  }

  Future<void> _preparePackages() async {
    preparation.value = const DatabasePreparation(PreparationPhase.checking);
    await _loadManifest();
    await PwaPlatform.preparePackages(_manifestText, (received, total, phase) {
      preparation.value = DatabasePreparation(
        PreparationPhase.downloading,
        received: received,
        total: total,
      );
    });
    preparation.value = const DatabasePreparation(PreparationPhase.verifying);
  }

  Future<_MemorySnapshot> _openCatalog() async {
    final descriptor = _manifest['catalog'] as Map<String, dynamic>;
    final snapshot = await _openPackage(descriptor);
    try {
      final count = snapshot.database
          .select('SELECT count(*) AS n FROM cultivar_municipios')
          .single['n'];
      if (count != _manifest['municipalities']) {
        throw const FormatException('Catálogo municipal incompleto.');
      }
      return snapshot;
    } catch (_) {
      snapshot.close();
      rethrow;
    }
  }

  void _validateManifest() {
    if (_manifest['format'] != format ||
        _manifest['schema_version'] != 2 ||
        _manifest['regions'] is! Map ||
        _manifest['catalog'] is! Map ||
        _manifest['bundles'] is! List ||
        _manifest['compressed_bytes'] is! int) {
      throw const FormatException(
        'Versão dos dados incompatível com este aplicativo.',
      );
    }
    final regions = _manifest['regions'] as Map;
    if (regions.length != _manifest['municipalities']) {
      throw const FormatException('Lista de municípios incompleta.');
    }
    for (final descriptor in [_manifest['catalog'], ...regions.values]) {
      if (descriptor is! Map ||
          descriptor['database_bytes'] is! int ||
          (descriptor['database_bytes'] as int) <= 0 ||
          (descriptor['database_bytes'] as int) > 4000000 ||
          descriptor['compressed_bytes'] is! int ||
          descriptor['bundle'] is! int ||
          descriptor['offset'] is! int ||
          !RegExp(
            r'^[0-9a-f]{64}$',
          ).hasMatch('${descriptor['database_sha256']}') ||
          !RegExp(
            r'^[0-9a-f]{64}$',
          ).hasMatch('${descriptor['compressed_sha256']}')) {
        throw const FormatException('Partição de dados incompatível.');
      }
    }
  }

  Future<_MemorySnapshot> _openPackage(Map<String, dynamic> descriptor) async {
    final packed = await PwaPlatform.loadPackage(
      _manifestText,
      jsonEncode(descriptor),
    );
    // Não depende de DecompressionStream, ausente em versões antigas do Safari.
    final bytes = const GZipDecoder().decodeBytes(
      packed,
      verify: true,
      maxOutputSize: descriptor['database_bytes'] as int,
    );
    if (bytes.length != descriptor['database_bytes'] ||
        sha256.convert(bytes).toString() != descriptor['database_sha256']) {
      throw const FormatException(
        'A região falhou na verificação de integridade.',
      );
    }
    WasmSqlite3 sqlite;
    try {
      sqlite = await (_sqlite ??= WasmSqlite3.loadFromUrl(
        PwaPlatform.baseUri.resolve('sqlite3.wasm'),
      ));
    } catch (_) {
      _sqlite = null;
      rethrow;
    }
    final vfs = InMemoryFileSystem(name: 'cultivar_part_${_sequence++}');
    sqlite.registerVirtualFileSystem(vfs);
    CommonDatabase? database;
    try {
      final (file: file, outFlags: _) = vfs.xOpen(
        Sqlite3Filename('/database'),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      );
      file.xWrite(bytes, 0);
      file.xClose();
      database = sqlite.open(
        '/database',
        vfs: vfs.name,
        mode: OpenMode.readOnly,
      );
      database.execute('PRAGMA query_only=ON');
      final metadata = {
        for (final row in database.select(
          'SELECT chave,valor FROM cultivar_metadata',
        ))
          row['chave']: row['valor'],
      };
      if (metadata['format'] != format ||
          metadata['kind'] != descriptor['kind'] ||
          metadata['key'] != descriptor['key'] ||
          metadata['source_database_sha256'] != _manifest['database_sha256'] ||
          metadata['source_sql_sha256'] != _manifest['source_sql_sha256']) {
        throw const FormatException(
          'Metadados da região incompatíveis com o catálogo.',
        );
      }
      return _MemorySnapshot(database, sqlite, vfs);
    } catch (_) {
      database?.close();
      sqlite.unregisterVirtualFileSystem(vfs);
      vfs.fileData.clear();
      rethrow;
    }
  }

  Future<T> _withRegion<T>(
    String assetPath,
    T Function(CommonDatabase) operation,
  ) async {
    await ready();
    final previous = _regionWork;
    final done = Completer<void>();
    _regionWork = done.future;
    await previous;
    _MemorySnapshot? snapshot;
    try {
      final descriptor =
          (_manifest['regions'] as Map)[p.basename(assetPath)]
              as Map<String, dynamic>?;
      if (descriptor == null) {
        throw const FormatException('Região ausente no catálogo offline.');
      }
      snapshot = await _openPackage(descriptor);
      PwaPlatform.noteDatabaseBytes(
        _catalogBytes + (descriptor['database_bytes'] as int),
      );
      final count = snapshot.database
          .select('SELECT count(*) AS n FROM cultivar_feicoes')
          .single['n'];
      if (count != descriptor['features']) {
        throw const FormatException('Dados da região incompletos.');
      }
      return operation(snapshot.database);
    } finally {
      snapshot?.close();
      PwaPlatform.noteDatabaseBytes(_catalogBytes);
      done.complete();
    }
  }

  Future<List<Map<String, dynamic>>> municipalities(int year) async {
    final rows = (await _executor()).select(
      '''
      SELECT m.codigo,m.nome,a.arquivo,a.min_lon,a.min_lat,a.max_lon,a.max_lat,
             a.centro_lon,a.centro_lat
      FROM cultivar_municipios m JOIN cultivar_arquivos a ON a.municipio_codigo=m.codigo
      WHERE a.ano=? ORDER BY m.nome
    ''',
      [year],
    );
    return rows
        .map(
          (row) => <String, dynamic>{
            'code': row['codigo'],
            'name': row['nome'],
            'asset': 'assets/${row['arquivo']}',
            'bbox': [
              row['min_lon'],
              row['min_lat'],
              row['max_lon'],
              row['max_lat'],
            ],
            'center': [row['centro_lon'], row['centro_lat']],
          },
        )
        .toList(growable: false);
  }

  Future<Uint8List> boundary(String assetPath) => _withRegion(assetPath, (db) {
    final rows = db.select(
      "SELECT geometria FROM cultivar_feicoes WHERE tipo='municipio'",
    );
    if (rows.length != 1) {
      throw const FormatException('Limite municipal ausente no banco.');
    }
    return rows.single['geometria'] as Uint8List;
  });

  Future<Map<String, Object>> region(String assetPath) async {
    final catalog = await _executor();
    _rankings ??= {
      for (final row in catalog.select(
        'SELECT id,propriedades_json FROM cultivar_rankings',
      ))
        row['id'] as int:
            jsonDecode(row['propriedades_json'] as String)
                as Map<String, dynamic>,
    };
    final rows = await _withRegion(
      assetPath,
      (db) => db
          .select(
            "SELECT geometria,ranking_id FROM cultivar_feicoes WHERE tipo='grid' ORDER BY indice",
          )
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false),
    );
    return {'features': rows, 'rankings': _rankings!};
  }

  Future<void> suspend() async {
    await _regionWork;
    final pending = _opening;
    _opening = null;
    _rankings = null;
    _catalogBytes = 0;
    if (pending != null) (await pending).close();
    PwaPlatform.noteDatabaseBytes(0);
    await PwaPlatform.releaseSession();
  }

  Future<void> close() async {
    if (_closed) return;
    await suspend();
    _closed = true;
  }
}

class _MemorySnapshot {
  _MemorySnapshot(this.database, this.sqlite, this.vfs);
  final CommonDatabase database;
  final WasmSqlite3 sqlite;
  final InMemoryFileSystem vfs;
  void close() {
    database.close();
    sqlite.unregisterVirtualFileSystem(vfs);
    vfs.fileData.clear();
  }
}
