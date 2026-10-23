import 'package:flutter/material.dart';

import '../services/pwa_platform.dart';

class PwaActions extends StatefulWidget {
  const PwaActions({
    super.key,
    this.showUpdates = true,
    this.showInstall = true,
    this.fullWidth = false,
    this.enabled = true,
  });

  final bool showUpdates;
  final bool showInstall;
  final bool fullWidth;
  final bool enabled;

  @override
  State<PwaActions> createState() => _PwaActionsState();
}

class _PwaActionsState extends State<PwaActions> {
  bool _checking = false;
  String _installationState = PwaPlatform.installationState;
  late final void Function() _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = PwaPlatform.listenInstallation((state) {
      if (mounted && state != _installationState) {
        setState(() => _installationState = state);
      }
    });
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  Future<void> _message(String title, String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );

  Future<void> _install() async {
    final hasPrompt = PwaPlatform.installationState == 'ready';
    try {
      if (await PwaPlatform.install()) return;
      if (hasPrompt) return;
    } catch (error) {
      if (mounted) {
        await _message(
          'Instalar o Typica',
          'O navegador não concluiu a instalação. Detalhes: $error',
        );
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Instalar o Typica'),
        content: Text(PwaPlatform.installationHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  Future<void> _update() async {
    setState(() => _checking = true);
    try {
      final available = await PwaPlatform.checkUpdate();
      if (!mounted) return;
      if (available) {
        final apply = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Nova versão disponível'),
            content: const Text(
              'Atualizar vai reabrir o aplicativo. Se houver uma nova versão dos dados, será necessário baixá-la antes de voltar ao uso offline.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Depois'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Atualizar'),
              ),
            ],
          ),
        );
        if (apply == true) await PwaPlatform.applyUpdate();
      } else {
        await _message(
          'Aplicativo atualizado',
          'Você está usando a versão disponível nesta hospedagem.',
        );
      }
    } catch (_) {
      if (mounted) {
        await _message(
          'Verificar atualização',
          'Conecte-se à internet para verificar atualizações.',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (widget.showInstall)
        OutlinedButton.icon(
          onPressed: !widget.enabled || _installationState == 'installed'
              ? null
              : _install,
          icon: const Icon(Icons.install_mobile),
          label: Text(switch (_installationState) {
            'installed' => 'Aplicativo instalado',
            _ => 'Salvar como app',
          }),
        ),
      if (widget.showUpdates)
        OutlinedButton.icon(
          onPressed: !widget.enabled || _checking ? null : _update,
          icon: const Icon(Icons.system_update_alt),
          label: Text(_checking ? 'Verificando…' : 'Verificar atualização'),
        ),
    ];
    if (widget.fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: actions,
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: actions,
    );
  }
}
