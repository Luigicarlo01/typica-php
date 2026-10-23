import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/bounding_box.dart';
import '../models/genotype_point.dart';
import '../utils/app_colors.dart';
import '../utils/polygon_wkb.dart';
import 'local_municipality_service.dart';
import 'cultivar_database.dart';
import 'cache/region_database.dart';

class GridCell {
  final List<Offset> points;
  final List<List<Offset>> holes;
  final String? winner;
  final List<String> alternatives;

  GridCell({
    required this.points,
    this.holes = const [],
    this.winner,
    this.alternatives = const [],
  });

  Offset? _centroidCache;

  Offset get centroid {
    if (_centroidCache != null) {
      return _centroidCache!;
    }

    double sumLng = 0;
    double sumLat = 0;

    for (final p in points) {
      sumLng += p.dx;
      sumLat += p.dy;
    }

    _centroidCache = Offset(sumLng / points.length, sumLat / points.length);

    return _centroidCache!;
  }

  bool containsPoint(Offset point) {
    if (!_containsRing(points, point)) return false;
    return !holes.any((ring) => _containsRing(ring, point));
  }

  static bool _containsRing(List<Offset> points, Offset point) {
    int intersections = 0;

    final n = points.length;

    for (int i = 0; i < n; i++) {
      final a = points[i];
      final b = points[(i + 1) % n];

      if (((a.dy <= point.dy && point.dy < b.dy) ||
              (b.dy <= point.dy && point.dy < a.dy)) &&
          (point.dx >
              ((b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy)) + a.dx)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }
}

class NoDataException implements Exception {
  final String message;

  NoDataException(this.message);

  @override
  String toString() => message;
}

class _ParseResult {
  final List<GridCell> cells;
  final BoundingBox? bbox;

  _ParseResult(this.cells, this.bbox);
}

class AnalysisService {
  static final AnalysisService _instance = AnalysisService._internal();

  factory AnalysisService() => _instance;

  AnalysisService._internal()
    : _database = CultivarDatabase.instance,
      _municipalities = LocalMunicipalityService.instance;

  AnalysisService.forDatabase(CultivarDatabase database)
    : _database = database,
      _municipalities = LocalMunicipalityService(database: database);

  final CultivarDatabase _database;
  final LocalMunicipalityService _municipalities;

  // ============================================================
  // CONFIGURAÇÃO
  // ============================================================

  List<GenotypePoint> points = [];

  List<GridCell> cells = [];

  String? municipio;

  String? displayName;

  List<String> _winners = [];

  List<String> get winners => _winners;

  List<Polygon> _cachedPolygons = [];

  double _lastOpacity = -1;

  // ============================================================
  // POLÍGONOS DO MAPA
  // ============================================================

  List<Polygon> polygonsFor(double opacity) {
    if (_cachedPolygons.isNotEmpty && (_lastOpacity - opacity).abs() < 0.001) {
      return _cachedPolygons;
    }

    const base = AppColors.green;

    _cachedPolygons = cells.map((cell) {
      return Polygon(
        points: cell.points.map((o) => LatLng(o.dy, o.dx)).toList(),
        holePointsList: cell.holes
            .map((ring) => ring.map((o) => LatLng(o.dy, o.dx)).toList())
            .toList(),
        color: base.withValues(alpha: opacity),
        borderColor: base,
        borderStrokeWidth: 0.3,
      );
    }).toList();

    _lastOpacity = opacity;

    return _cachedPolygons;
  }

  // ============================================================
  // ÍNDICE ESPACIAL
  // ============================================================

  static const double _gridStep = 0.01;

  final Map<String, List<GridCell>> _spatialGrid = {};

  void _buildSpatialIndex() {
    _spatialGrid.clear();

    for (final cell in cells) {
      final key = _spatialKey(cell.centroid.dx, cell.centroid.dy);

      _spatialGrid.putIfAbsent(key, () => []).add(cell);
    }
  }

  String _spatialKey(double lng, double lat) {
    final col = (lng / _gridStep).floor();

    final row = (lat / _gridStep).floor();

    return '$col:$row';
  }

  GridCell? cellContaining(Offset point) {
    final baseCol = (point.dx / _gridStep).floor();

    final baseRow = (point.dy / _gridStep).floor();

    for (int dc = -1; dc <= 1; dc++) {
      for (int dr = -1; dr <= 1; dr++) {
        final key = '${baseCol + dc}:${baseRow + dr}';

        final bucket = _spatialGrid[key];

        if (bucket == null) {
          continue;
        }

        for (final cell in bucket) {
          if (cell.containsPoint(point)) {
            return cell;
          }
        }
      }
    }

    return null;
  }

  GridCell? nearestCell(Offset point, {bool requireWinner = false}) {
    GridCell? nearest;

    double minDist = double.infinity;

    for (final cell in cells) {
      if (requireWinner && cell.winner == null) {
        continue;
      }

      final c = cell.centroid;

      final d =
          (c.dx - point.dx) * (c.dx - point.dx) +
          (c.dy - point.dy) * (c.dy - point.dy);

      if (d < minDist) {
        minDist = d;
        nearest = cell;
      }
    }

    return nearest;
  }

  GridCell? resolveCell(Offset point) {
    if (cells.isEmpty) {
      return null;
    }

    return cellContaining(point) ??
        nearestCell(point, requireWinner: true) ??
        nearestCell(point);
  }

  Offset nearestCellCentroid(Offset point) {
    if (cells.isEmpty) {
      return point;
    }

    return nearestCell(point)?.centroid ?? point;
  }

  // ============================================================
  // RESET
  // ============================================================

  void _reset() {
    points = [];

    cells = [];

    _winners = [];

    municipio = null;

    displayName = null;

    _cachedPolygons = [];

    _lastOpacity = -1;

    _spatialGrid.clear();
  }

  // ============================================================
  // CARREGAMENTO PRINCIPAL
  // ============================================================

  Future<void> load({required double lat, required double lng}) async {
    _reset();
    try {
      await _loadLocalDatabase(lat: lat, lng: lng);
    } on NoDataException {
      rethrow;
    } catch (error) {
      debugPrint('Falha ao consultar banco local: $error');
      throw NoDataException(
        'Não foi possível consultar os dados locais. Verifique o armazenamento do navegador e abra o aplicativo novamente.',
      );
    }
  }

  Future<void> _loadLocalDatabase({
    required double lat,
    required double lng,
  }) async {
    // GPS, clique e pesquisa usam sempre as coordenadas atuais. O nome de
    // uma pesquisa anterior nunca deve selecionar os dados de outro município.
    final municipality = await _municipalities.findByCoordinates(
      lat: lat,
      lng: lng,
    );
    if (municipality == null) {
      throw NoDataException(
        'Não há dados locais para este ponto. '
        'Escolha uma cidade ou localização dentro de Minas Gerais.',
      );
    }
    final assetPath = municipality.assetPath;
    final fileName = assetPath.split('/').last;
    final selectedCity = municipality.name;

    try {
      final region = await _database.region(assetPath);
      final parsed = await compute(_parseSqlCellsIsolate, region);

      cells = parsed.cells;

      if (cells.isEmpty) {
        throw NoDataException(
          'Os dados de $selectedCity foram encontrados no banco, '
          'mas não contém células de análise.',
        );
      }

      municipio = fileName.replaceFirst(RegExp(r'\.geojson$'), '');

      displayName = selectedCity;

      _winners =
          cells
              .map((cell) => cell.winner)
              .whereType<String>()
              .where((winner) => winner.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      _buildSpatialIndex();

      try {
        await RegionDatabase.instance.recordVisit(
          municipio: municipio!,
          displayName: selectedCity,
          lat: lat,
          lng: lng,
          minLat: parsed.bbox?.minLat ?? lat,
          maxLat: parsed.bbox?.maxLat ?? lat,
          minLon: parsed.bbox?.minLon ?? lng,
          maxLon: parsed.bbox?.maxLon ?? lng,
        );
      } catch (error) {
        debugPrint('Não foi possível salvar o histórico: $error');
      }
      debugPrint('[analysis] Dados carregados do SQLite offline.');

      debugPrint('[analysis] Município: $municipio');

      debugPrint('[analysis] Células: ${cells.length}');

      debugPrint('[analysis] Cultivares vencedores: $_winners');
    } on NoDataException {
      rethrow;
    } catch (e) {
      debugPrint('[analysis] Erro ao consultar SQLite: $e');
      throw NoDataException(
        'Não foi possível abrir os dados locais de $selectedCity. '
        'Verifique o armazenamento do navegador e abra o aplicativo novamente.',
      );
    }
  }

  // ============================================================
  // PONTOS / GENÓTIPOS
  // ============================================================

  @Deprecated('Mapa monocromático não colore por genótipo.')
  void buildPoints(Map<String, Color> winnerColors) {
    if (cells.isEmpty) {
      return;
    }

    points = cells.map((cell) {
      final color = winnerColors[cell.winner] ?? Colors.grey.withOpacity(0.25);

      return GenotypePoint(
        position: cell.centroid,
        genotype: cell.winner ?? 'N/A',
        alternatives: cell.alternatives,
        color: color,
      );
    }).toList();
  }
}

// ============================================================
// PARSER DE ALTERNATIVAS
// ============================================================
//
// O script R grava `alternatives` como JSON.
// Dependendo de como o sf escreve o GeoJSON,
// podemos receber:
//
// ["A","B","C"]
//
// ou:
//
// "[\"A\",\"B\",\"C\"]"
//
// Esta função suporta as duas formas.
// ============================================================

List<String> _parseAlternatives(dynamic raw) {
  if (raw == null) {
    return <String>[];
  }

  if (raw is List) {
    return raw.where((e) => e != null).map((e) => e.toString()).toList();
  }

  if (raw is String) {
    final value = raw.trim();

    if (value.isEmpty || value == '[]') {
      return <String>[];
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is List) {
        return decoded
            .where((e) => e != null)
            .map((e) => e.toString())
            .toList();
      }
    } catch (_) {
      // Se não for JSON válido,
      // deixa cair no retorno abaixo.
    }

    return <String>[value];
  }

  return <String>[raw.toString()];
}

// ============================================================
// PARSER DO GEOJSON
// ============================================================

_ParseResult _parseSqlCellsIsolate(Map<String, Object> data) {
  final rankings = data['rankings'] as Map<int, Map<String, dynamic>>;
  final rows = data['features'] as List<Map<String, Object?>>;
  return _parseFeatureCells(
    rows
        .map(
          (row) => <String, dynamic>{
            'properties': rankings[row['ranking_id']],
            'geometry': polygonGeometryFromWkb(row['geometria'] as Uint8List),
          },
        )
        .toList(growable: false),
  );
}

_ParseResult _parseFeatureCells(dynamic features) {
  final result = <GridCell>[];

  if (features is! List) {
    return _ParseResult(result, null);
  }

  double? minLat;
  double? maxLat;

  double? minLon;
  double? maxLon;

  for (final feature in features) {
    if (feature is! Map<String, dynamic>) {
      continue;
    }

    final properties = feature['properties'];

    final geometry = feature['geometry'];

    if (properties is! Map<String, dynamic>) {
      continue;
    }

    if (geometry is! Map<String, dynamic>) {
      continue;
    }

    // Ignora o contorno do município.
    // Queremos apenas as células da grade.
    if (properties['type'] != 'grid') {
      continue;
    }

    final geometryType = geometry['type']?.toString();

    // O R normalmente gera Polygon.
    // Se aparecer MultiPolygon,
    // tratamos também.
    final coordinates = geometry['coordinates'];

    final polygons = <List<dynamic>>[];

    if (geometryType == 'Polygon' &&
        coordinates is List &&
        coordinates.isNotEmpty) {
      polygons.add(coordinates);
    } else if (geometryType == 'MultiPolygon' && coordinates is List) {
      for (final polygon in coordinates) {
        if (polygon is List && polygon.isNotEmpty && polygon.first is List) {
          polygons.add(polygon);
        }
      }
    } else {
      continue;
    }

    final winner = properties['winner']?.toString();

    final alternatives = _parseAlternatives(properties['alternatives']);

    for (final polygon in polygons) {
      final coords = polygon.first as List;
      if (coords.isEmpty) {
        continue;
      }

      final cellPoints = <Offset>[];

      for (final c in coords) {
        if (c is! List || c.length < 2) {
          continue;
        }

        final lngValue = c[0];

        final latValue = c[1];

        if (lngValue is! num || latValue is! num) {
          continue;
        }

        final lng = lngValue.toDouble();

        final lat = latValue.toDouble();

        cellPoints.add(Offset(lng, lat));

        minLat = (minLat == null || lat < minLat) ? lat : minLat;

        maxLat = (maxLat == null || lat > maxLat) ? lat : maxLat;

        minLon = (minLon == null || lng < minLon) ? lng : minLon;

        maxLon = (maxLon == null || lng > maxLon) ? lng : maxLon;
      }

      if (cellPoints.length < 3) {
        continue;
      }

      result.add(
        GridCell(
          points: cellPoints,
          holes: polygon
              .skip(1)
              .whereType<List>()
              .map(
                (ring) => ring
                    .whereType<List>()
                    .where((p) => p.length >= 2)
                    .map(
                      (p) => Offset(
                        (p[0] as num).toDouble(),
                        (p[1] as num).toDouble(),
                      ),
                    )
                    .toList(growable: false),
              )
              .toList(growable: false),
          winner: winner,
          alternatives: alternatives,
        ),
      );
    }
  }

  final bbox =
      minLat != null && maxLat != null && minLon != null && maxLon != null
      ? BoundingBox(
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
        )
      : null;

  return _ParseResult(result, bbox);
}
