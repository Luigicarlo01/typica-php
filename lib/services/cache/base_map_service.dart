import 'package:flutter/foundation.dart';

/// Mantém a interface das telas; o mapa de fundo continua sendo online.
class BaseMapService extends ChangeNotifier {
  static final _instance = BaseMapService._();
  factory BaseMapService() => _instance;
  BaseMapService._();
  Future<void> refreshStatus() async {}
}
