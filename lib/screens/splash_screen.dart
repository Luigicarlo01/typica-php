import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/app_bootstrap.dart';
import '../services/cultivar_database.dart';
import '../services/pwa_platform.dart';
import '../utils/app_colors.dart';
import '../widgets/partner_logos.dart';
import '../widgets/pwa_actions.dart';
import 'map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _bootError;
  bool _prepared = false;
  bool _preparing = false;
  bool _entering = false;
  bool _brandingVisible = true;
  final _brandingReady = Completer<void>();
  Timer? _brandingTimer;
  late bool _wasInstalled;
  late final void Function() _stopListening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _brandingTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (!_entering) setState(() => _brandingVisible = false);
        _brandingReady.complete();
      });
    });
    _wasInstalled = PwaPlatform.isInstalled;
    _stopListening = PwaPlatform.listenInstallation((_) {
      if (!mounted) return;
      final justInstalled = !_wasInstalled && PwaPlatform.isInstalled;
      _wasInstalled = PwaPlatform.isInstalled;
      setState(() {});
      if (justInstalled && !_prepared) _abrir();
    });
    _restaurar();
  }

  @override
  void dispose() {
    _brandingTimer?.cancel();
    if (!_brandingReady.isCompleted) _brandingReady.complete();
    _stopListening();
    super.dispose();
  }

  Future<void> _restaurar() async {
    if (!PwaPlatform.isInstalled &&
        PwaPlatform.preference('app_entered') != '1') {
      return;
    }
    try {
      // A instalação inclui a preparação dos dados. Um ícone com armazenamento
      // próprio (como no iPhone) também conclui essa etapa sem outro botão.
      final available = await CultivarDatabase.instance.hasLocalData();
      if (!mounted || _preparing || _prepared || _entering) {
        return;
      }
      if (available || PwaPlatform.isInstalled) {
        await _abrir(enterWhenReady: true);
      }
    } catch (error) {
      debugPrint('Dados locais ainda indisponíveis: $error');
      if (PwaPlatform.isInstalled) await _abrir(enterWhenReady: true);
    }
  }

  Future<void> _abrir({bool enterWhenReady = false}) async {
    if (_preparing || _entering || !mounted) return;
    if (mounted) {
      setState(() {
        _bootError = null;
        _prepared = false;
        _preparing = true;
      });
    }
    PwaPlatform.setPrepared(false);
    try {
      await CultivarDatabase.instance.prepareLocalData();
      await PwaPlatform.offlineShellReady();
      if (!mounted) return;
      if (enterWhenReady) {
        PwaPlatform.setPrepared(true);
        await _entrar();
        return;
      }
      _prepared = true;
      PwaPlatform.setPrepared(true);
      setState(() {});
    } catch (error) {
      debugPrint('Falha ao preparar os dados locais: $error');
      if (mounted) {
        setState(
          () => _bootError =
              'Não foi possível preparar os dados do aplicativo. Motivo: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _entrar() async {
    if (_entering || !mounted) return;
    _entering = true;
    try {
      await bootstrapApp();
      await _brandingReady.future;
      PwaPlatform.savePreference('app_entered', '1');
    } catch (error) {
      _entering = false;
      if (mounted) {
        setState(() {
          _prepared = false;
          _brandingVisible = !_brandingReady.isCompleted;
          _bootError =
              'Não foi possível abrir os dados do aplicativo. Motivo: $error';
        });
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const MapScreen(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _copiarErro() async {
    final error = _bootError;
    if (error == null) return;
    try {
      await Clipboard.setData(
        ClipboardData(text: '$error\n\n${PwaPlatform.diagnostics}'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Detalhes do erro copiados.')),
        );
      }
    } catch (_) {
      // O texto também pode ser selecionado na tela.
    }
  }

  Widget _section(String title, List<Widget> children) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(top: 16),
    color: Colors.white.withValues(alpha: 0.75),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppColors.green.withValues(alpha: 0.2)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _preparation(DatabasePreparation state) {
    final error = _bootError;
    final message = switch (state.phase) {
      PreparationPhase.downloading =>
        'Baixando dados: ${((state.progress ?? 0) * 100).toStringAsFixed(0)}%',
      PreparationPhase.verifying => 'Conferindo os dados baixados…',
      PreparationPhase.installing => 'Salvando os dados no aparelho…',
      PreparationPhase.ready => 'Preparando o aplicativo para uso offline…',
      _ => 'Verificando os dados salvos…',
    };
    return _section(_prepared ? 'Typica pronto para usar' : 'Bem-vindo ao Typica', [
      Text(
        _prepared
            ? 'O banco de dados está salvo neste aparelho. Você já pode abrir o Typica e consultar as recomendações offline.'
            : 'Toque em Salvar como app para instalar e preparar os dados para usar no campo, mesmo sem internet.',
      ),
      const SizedBox(height: 16),
      PwaActions(showInstall: false, fullWidth: true, enabled: !_preparing),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _preparing || _prepared ? null : () => _abrir(),
        icon: Icon(
          _prepared ? Icons.check_circle_outline : Icons.download_outlined,
        ),
        label: Text(
          _prepared
              ? 'Banco de dados salvo'
              : _preparing
              ? 'Preparando banco de dados…'
              : error != null
              ? 'Tentar novamente'
              : 'Baixar banco de dados',
        ),
      ),
      const SizedBox(height: 12),
      PwaActions(showUpdates: false, fullWidth: true, enabled: !_preparing),
      if (_preparing) ...[
        const SizedBox(height: 20),
        Row(
          children: [
              _loadingIndicator(),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Estamos preparando tudo para você. Mantenha a internet conectada até terminar. Depois, o Typica estará pronto para usar no campo.',
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: 16),
        SelectableText(error),
        TextButton(
          onPressed: _copiarErro,
          child: const Text('Copiar detalhes do erro'),
        ),
      ],
      if (_prepared) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _entrar,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Abrir Typica'),
        ),
      ],
    ]);
  }

  Widget _loadingIndicator() => SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: AppColors.green,
      backgroundColor: AppColors.green.withValues(alpha: 0.12),
      semanticsLabel: 'Carregando Typica',
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bege,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, constraints.maxHeight - 48),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_brandingVisible) const SizedBox.shrink(),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: SvgPicture.asset(
                              'assets/typica_logo_sem_borda.svg',
                              width: 240,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Typica — recomendações para o campo',
                            textAlign: TextAlign.center,
                          ),
                          if (_brandingVisible) ...[
                            const SizedBox(height: 24),
                            Center(child: _loadingIndicator()),
                          ] else
                            ValueListenableBuilder<DatabasePreparation>(
                              valueListenable:
                                  CultivarDatabase.instance.preparation,
                              builder: (context, state, _) =>
                                  _preparation(state),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            'Versão ${PwaPlatform.version}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 32),
                    child: PartnerLogos(
                      altura: 48,
                      terceiraLogoAsset: 'assets/Logo embrapa cafe.png',
                      fatorTerceiraLogo: 0.75,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
