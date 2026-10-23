import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../controllers/map_controller_logic.dart';
import '../controllers/search_controller.dart';

import '../services/analysis_service.dart';
import '../services/app_mode.dart';
import '../services/cache/base_map_service.dart';
import '../widgets/pwa_actions.dart';
import '../services/onboarding_service.dart';

import '../utils/app_colors.dart';

import '../widgets/map_widget.dart';
import '../widgets/onboarding_overlay.dart';

import 'about_screen.dart';
import 'analysis_screen.dart';

enum _MenuAppBar { tutorial, sobre }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapControllerLogic _logic = MapControllerLogic();

  final CitySearchController _search = CitySearchController();

  final BaseMapService _baseMap = BaseMapService();

  final AppMode _mode = AppMode();

  final TextEditingController _searchTextCtrl = TextEditingController();

  // ============================================================
  // CHAVES DO TUTORIAL
  // ============================================================

  final GlobalKey _searchKey = GlobalKey();

  final GlobalKey _mapKey = GlobalKey();

  final GlobalKey _gpsKey = GlobalKey();

  final GlobalKey _downloadKey = GlobalKey();

  bool _onboardingScheduled = false;
  bool _onboardingShowing = false;
  Animation<double>? _entryAnimation;

  // ============================================================
  // LISTENERS
  // ============================================================

  late final VoidCallback _logicListener;

  late final VoidCallback _searchListener;

  late final VoidCallback _baseMapListener;

  late final VoidCallback _modeListener;

  @override
  void initState() {
    super.initState();

    _logicListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    _searchListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    _baseMapListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    _modeListener = () {
      if (mounted) {
        setState(() {});
      }
    };

    _logic.addListener(_logicListener);

    _search.addListener(_searchListener);

    _baseMap.addListener(_baseMapListener);

    _mode.addListener(_modeListener);

    _searchTextCtrl.addListener(_onSearchTextChanged);

    _baseMap.refreshStatus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_onboardingScheduled) return;
    _onboardingScheduled = true;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _scheduleOnboarding();
    } else {
      _entryAnimation = animation;
      animation.addStatusListener(_onEntryStatus);
    }
  }

  void _onEntryStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _entryAnimation?.removeStatusListener(_onEntryStatus);
    _entryAnimation = null;
    _scheduleOnboarding();
  }

  void _scheduleOnboarding() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowOnboarding();
    });
  }

  void _onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // TUTORIAL
  // ============================================================

  Future<void> _maybeShowOnboarding() async {
    final visto = await OnboardingService().seenVersion(OnboardingFlow.map);

    if (visto >= OnboardingFlow.map.version) {
      return;
    }

    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }

    _startOnboarding(sinceVersion: visto);
  }

  Future<void> _startOnboarding({int sinceVersion = 0}) async {
    if (_onboardingShowing) return;
    _onboardingShowing = true;
    try {
      await showOnboarding(
        context,

        steps: _onboardingSteps(),

        sinceVersion: sinceVersion,

        onFinish: () => OnboardingService().markSeen(OnboardingFlow.map),
      );
    } finally {
      _onboardingShowing = false;
    }
  }

  List<OnboardingStep> _onboardingSteps() {
    return [
      const OnboardingStep(
        title: 'Bem-vindo ao Typica',

        description:
            'Em poucos passos você descobre qual cultivar de café é '
            'recomendada para um ponto específico de Minas Gerais.',
      ),

      OnboardingStep(
        targetKey: _searchKey,

        title: 'Busque uma cidade',

        description:
            'Digite o nome do município para levar o mapa direto até '
            'ele, sem precisar arrastar a tela.',
      ),

      // ========================================================
      // CICLO DE MATURAÇÃO FOI REMOVIDO DESTA TELA
      // ========================================================
      OnboardingStep(
        targetKey: _mapKey,

        circular: true,

        maxSize: 160,

        title: 'Escolha o ponto no mapa',

        description:
            'Toque em qualquer lugar dentro de Minas Gerais para '
            'selecionar a localização. Depois é só confirmar no botão '
            'que aparece embaixo.',
      ),

      OnboardingStep(
        targetKey: _gpsKey,

        circular: true,

        title: 'Usar minha localização',

        description:
            'Este botão centraliza o mapa onde você está agora, usando '
            'o GPS do aparelho.',
      ),

      OnboardingStep(
        targetKey: _downloadKey,

        title: 'Dados para usar sem internet',

        description:
            'As recomendações e a pesquisa de municípios ficam salvas '
            'no aparelho para usar no campo. O mapa de fundo precisa '
            'de internet. Este botão mostra as informações do uso offline.',
      ),

      const OnboardingStep(
        title: 'Pronto para começar',

        description:
            'Você pode rever este tutorial quando quiser no menu "?" '
            'no topo da tela.',
      ),
    ];
  }

  // ============================================================
  // MAPA BASE
  // ============================================================

  Future<void> _onBaseMapTap() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Uso offline'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Os dados de recomendação e a pesquisa de municípios estão salvos neste navegador. O mapa de fundo do OpenStreetMap precisa de internet. Não limpe os dados do site se precisar consultar no campo.',
            ),
            SizedBox(height: 20),
            PwaActions(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );

  Widget _buildBaseMapAction() => IconButton(
    onPressed: _onBaseMapTap,
    tooltip: 'Dados offline e instalação',
    icon: const Icon(Icons.offline_pin_outlined),
  );

  // ============================================================
  // LOCALIZAÇÃO INVÁLIDA
  // ============================================================

  void _showInvalidLocationMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Selecione um ponto dentro de Minas Gerais'),

        backgroundColor: Colors.red,

        duration: Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  // CONFIRMAR LOCALIZAÇÃO
  // ============================================================

  Future<void> _confirmLocation() async {
    if (_logic.selectedPoint == null) {
      return;
    }

    final point = _logic.selectedPoint!;

    showDialog<void>(
      context: context,

      barrierDismissible: false,

      builder: (_) => const _PreflightLoadingDialog(),
    );

    try {
      await AnalysisService().load(lat: point.latitude, lng: point.longitude);

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      Navigator.push(
        context,

        MaterialPageRoute(
          builder: (_) =>
              AnalysisScreen(selectedPoint: point, selectedCrop: ''),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      await _showAnalysisErrorDialog(e);
    }
  }

  Future<void> _showAnalysisErrorDialog(Object error) {
    final noData = error is NoDataException;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          noData ? Icons.info_outline : Icons.error_outline,
          color: noData ? Colors.orange.shade700 : Colors.red.shade700,
          size: 48,
        ),
        title: Text(
          noData ? 'Sem dados para esta região' : 'Erro ao carregar dados',
        ),
        content: Text(
          noData
              ? error.message
              : 'Não foi possível abrir os dados desta região. Tente novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TELA PRINCIPAL
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        titleSpacing: 16,

        title: SvgPicture.asset('assets/typica_logo_sem_borda.svg', width: 100),

        actions: [
          KeyedSubtree(key: _downloadKey, child: _buildBaseMapAction()),

          PopupMenuButton<_MenuAppBar>(
            tooltip: 'Mais opções',

            icon: const Icon(Icons.help_outline),

            onSelected: (opcao) {
              switch (opcao) {
                case _MenuAppBar.tutorial:
                  _startOnboarding();
                  break;

                case _MenuAppBar.sobre:
                  Navigator.push(
                    context,

                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );

                  break;
              }
            },

            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _MenuAppBar.tutorial,

                child: ListTile(
                  contentPadding: EdgeInsets.zero,

                  leading: Icon(Icons.school_outlined),

                  title: Text('Rever tutorial'),
                ),
              ),

              PopupMenuItem(
                value: _MenuAppBar.sobre,

                child: ListTile(
                  contentPadding: EdgeInsets.zero,

                  leading: Icon(Icons.info_outline),

                  title: Text('Sobre o app'),
                ),
              ),
            ],
          ),
        ],
      ),

      // ========================================================
      // MAPA
      // ========================================================
      body: Stack(
        children: [
          MapWidget(
            key: _mapKey,

            mapController: _logic.mapController,

            selectedPoint: _logic.selectedPoint,

            onTap: (point) =>
                _logic.onMapTap(point, onInvalid: _showInvalidLocationMessage),

            maxZoom: _mode.isOffline ? 10.0 : null,

            maxNativeZoom: _mode.isOffline ? 10 : null,
          ),

          // ====================================================
          // BUSCA
          // ====================================================
          _buildTopBar(),

          // ====================================================
          // MODO OFFLINE
          // ====================================================
          if (_mode.isOffline) _buildOfflineBadge(),
        ],
      ),

      // ========================================================
      // CONFIRMAR LOCALIZAÇÃO
      // ========================================================
      bottomNavigationBar: _logic.selectedPoint != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),

                child: ElevatedButton(
                  onPressed: _confirmLocation,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,

                    foregroundColor: Colors.white,

                    padding: const EdgeInsets.symmetric(vertical: 16),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: const Text(
                    'Confirmar localização',

                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            )
          : null,

      // ========================================================
      // GPS
      // ========================================================
      floatingActionButton: FloatingActionButton(
        key: _gpsKey,
        tooltip: 'Usar minha localização',

        onPressed: () =>
            _logic.goToCurrentLocation(onInvalid: _showInvalidLocationMessage),

        backgroundColor: AppColors.green,

        child: const Icon(Icons.my_location, color: AppColors.greenDark),
      ),
    );
  }

  // ============================================================
  // MODO OFFLINE
  // ============================================================

  Widget _buildOfflineBadge() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 80,
      child: IgnorePointer(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: AppColors.greenDark, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sem internet: pesquisa e recomendações locais disponíveis. '
                    'O mapa de fundo precisa de conexão.',
                    style: TextStyle(color: AppColors.greenDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BARRA DE PESQUISA DO MUNICÍPIO
  // ============================================================
  //
  // O filtro de ciclo NÃO aparece mais nesta tela.
  //
  // Agora esta área contém somente:
  //
  // [ Pesquisar cidade ]
  //
  // O ciclo é escolhido posteriormente na tela de análise.
  // ============================================================

  Widget _buildTopBar() {
    return Positioned(
      top: 20,

      left: 16,

      right: 16,

      child: Material(
        key: _searchKey,

        elevation: 6,

        borderRadius: BorderRadius.circular(16),

        color: Colors.white,

        clipBehavior: Clip.antiAlias,

        child: Column(
          mainAxisSize: MainAxisSize.min,

          children: [
            // ==================================================
            // CAMPO DE PESQUISA
            // ==================================================

            TextField(
              controller: _searchTextCtrl,

              decoration: InputDecoration(
                hintText: 'Pesquisar cidade de Minas Gerais',

                prefixIcon: const Icon(Icons.search),

                border: InputBorder.none,

                contentPadding: const EdgeInsets.symmetric(vertical: 16),

                suffixIcon: _searchTextCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),

                        tooltip: 'Limpar busca',

                        onPressed: () {
                          _searchTextCtrl.clear();

                          _search.clearSuggestions();

                          FocusScope.of(context).unfocus();
                        },
                      ),
              ),

              onTapOutside: (_) {
                FocusManager.instance.primaryFocus?.unfocus();
              },

              onChanged: _search.onSearchChanged,
            ),

            // ==================================================
            // SUGESTÕES
            // ==================================================
            if (_search.suggestions.isNotEmpty) const Divider(height: 1),

            if (_search.suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),

                child: ListView.separated(
                  shrinkWrap: true,

                  padding: EdgeInsets.zero,

                  itemCount: _search.suggestions.length,

                  separatorBuilder: (_, _) => const Divider(height: 1),

                  itemBuilder: (context, index) {
                    final city = _search.suggestions[index];

                    final cityName = city['name']?.toString() ?? '';

                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined),

                      title: Text(
                        cityName,

                        maxLines: 1,

                        overflow: TextOverflow.ellipsis,
                      ),

                      onTap: () async {
                        _searchTextCtrl.text = cityName;

                        _search.clearSuggestions();

                        FocusScope.of(context).unfocus();

                        // A sugestão local já contém um ponto dentro do município.
                        final resolved = await _search.resolveSuggestion(city);

                        if (!mounted || !context.mounted) {
                          return;
                        }

                        if (resolved == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Não foi possível obter as coordenadas '
                                'desta localização.',
                              ),

                              backgroundColor: Colors.red,
                            ),
                          );

                          return;
                        }

                        _logic.onCitySelected(
                          resolved,

                          onInvalid: _showInvalidLocationMessage,

                          onSuccess: () {},
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _entryAnimation?.removeStatusListener(_onEntryStatus);
    _searchTextCtrl.removeListener(_onSearchTextChanged);

    _searchTextCtrl.dispose();

    _logic.removeListener(_logicListener);

    _search.removeListener(_searchListener);

    _baseMap.removeListener(_baseMapListener);

    _mode.removeListener(_modeListener);

    _logic.dispose();
    _search.dispose();

    super.dispose();
  }
}

// =============================================================
// DIALOG DE CARREGAMENTO
// =============================================================

class _PreflightLoadingDialog extends StatelessWidget {
  const _PreflightLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,

      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),

      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),

        child: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            SizedBox(
              width: 28,

              height: 28,

              child: CircularProgressIndicator(
                strokeWidth: 3,

                color: AppColors.green,
              ),
            ),

            SizedBox(width: 20),

            Flexible(
              child: Text(
                'Buscando dados da região...',

                style: TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
