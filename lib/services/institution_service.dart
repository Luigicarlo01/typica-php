import 'dart:convert';

import 'package:flutter/services.dart';

import 'cultivar_info_service.dart';

/// Apenas metadados da planilha; os rankings e bancos científicos são preservados.
class InstitutionService {
  static final InstitutionService _instance = InstitutionService._();
  factory InstitutionService() => _instance;
  InstitutionService._();

  static const unknownLabel = 'Não informada';
  final Map<String, String> _institutions = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final text = await rootBundle.loadString('assets/instituicoes.json');
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final entries = decoded['cultivars'] as Map<String, dynamic>;
    final parsed = <String, String>{};
    for (final entry in entries.entries) {
      final institution = (entry.value as String).trim();
      if (institution.isEmpty) {
        throw const FormatException('Instituição da cultivar não informada.');
      }
      parsed[CultivarInfoService.chaveCultivar(entry.key)] = institution;
    }
    _institutions
      ..clear()
      ..addAll(parsed);
    _loaded = true;
  }

  String? institutionFor(String cultivar) =>
      _institutions[CultivarInfoService.chaveCultivar(cultivar)];

  List<String> get options => [
    ...(_institutions.values.toSet().toList()..sort()),
    unknownLabel,
  ];
}
