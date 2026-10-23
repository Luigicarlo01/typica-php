import 'mg_shape_service.dart';
import 'cultivar_info_service.dart';
import 'app_mode.dart';
import 'cultivar_database.dart';
import 'pwa_platform.dart';

Future<void> bootstrapApp() async {
  await CultivarDatabase.instance.ready();
  await MgShapeService().load();
  await CultivarInfoService().load();
  await AppMode().init();
  if (!await PwaPlatform.offlineShellReady()) {
    throw StateError(
      'Não foi possível salvar os arquivos do aplicativo para uso offline. Mantenha a conexão e tente novamente.',
    );
  }
}
