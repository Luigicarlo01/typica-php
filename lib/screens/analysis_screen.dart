import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/analysis_controller.dart';

import '../services/analysis_service.dart';
import '../services/onboarding_service.dart';

import '../widgets/cycle_selection_picker.dart';
import '../widgets/institution_filter_picker.dart';
import '../widgets/genotype_plot.dart';
import '../widgets/genotypes_list.dart';
import '../widgets/onboarding_overlay.dart';
import '../widgets/opacity_slider.dart';
import '../widgets/resistance_filter_picker.dart';

class AnalysisScreen extends StatefulWidget {
  final LatLng selectedPoint;

  final String selectedCrop;

  const AnalysisScreen({
    super.key,
    required this.selectedPoint,
    required this.selectedCrop,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final AnalysisController _controller = AnalysisController();

  // ============================================================
  // MAPA
  // ============================================================

  double _opacity = 0.7;

  /// O mapa começa oculto.
  bool _showMap = false;

  bool _isMapFullscreen = false;

  // ============================================================
  // KEYS
  // ============================================================

  final GlobalKey _mapToggleKey = GlobalKey();

  final GlobalKey _mapKey = GlobalKey();

  final GlobalKey _fullscreenKey = GlobalKey();

  final GlobalKey _sliderKey = GlobalKey();

  final GlobalKey _cycleKey = GlobalKey();

  final GlobalKey _institutionKey = GlobalKey();

  final GlobalKey _resistanceKey = GlobalKey();

  final GlobalKey _cultivaresKey = GlobalKey();

  bool _onboardingChecked = false;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _controller.addListener(_onControllerChanged);

    _controller.load(position: widget.selectedPoint);
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);

    _controller.dispose();

    super.dispose();
  }

  // ============================================================
  // CONTROLLER
  // ============================================================

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});

    if (_onboardingChecked) {
      return;
    }

    if (_controller.isLoading) {
      return;
    }

    if (_controller.errorMessage != null) {
      return;
    }

    _onboardingChecked = true;

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowOnboarding());
  }

  // ============================================================
  // MOSTRAR / OCULTAR MAPA
  // ============================================================

  void _toggleMap() {
    setState(() {
      _showMap = !_showMap;
    });
  }

  // ============================================================
  // ONBOARDING
  // ============================================================

  Future<void> _maybeShowOnboarding() async {
    final visto = await OnboardingService().seenVersion(
      OnboardingFlow.analysis,
    );

    if (visto >= OnboardingFlow.analysis.version) {
      return;
    }

    if (!mounted || _isMapFullscreen) {
      return;
    }

    _startOnboarding(sinceVersion: visto);
  }

  void _startOnboarding({int sinceVersion = 0}) {
    showOnboarding(
      context,

      steps: _onboardingSteps(),

      sinceVersion: sinceVersion,

      onFinish: () => OnboardingService().markSeen(OnboardingFlow.analysis),
    );
  }

  List<OnboardingStep> _onboardingSteps() {
    return [
      const OnboardingStep(
        title: 'Sua análise está pronta',

        description:
            'Aqui você encontra as cultivares recomendadas '
            'para a região escolhida.',
      ),

      OnboardingStep(
        targetKey: _mapToggleKey,

        padding: 6,

        title: 'Mapa da análise',

        description:
            'O mapa começa oculto. Use este botão para '
            'visualizar o mapa e ajustar a opacidade.',
      ),

      OnboardingStep(
        targetKey: _cycleKey,

        padding: 6,

        introducedIn: 2,
        title: 'Ciclo de maturação',

        description:
            'Escolha o ciclo ou use Todos para considerar qualquer maturação.',
      ),

      OnboardingStep(
        targetKey: _institutionKey,
        padding: 6,
        introducedIn: 2,
        title: 'Instituição da cultivar',
        description:
            'Filtre pela instituição responsável ou use Todos para considerar qualquer instituição.',
      ),

      OnboardingStep(
        targetKey: _resistanceKey,

        padding: 6,

        title: 'Filtros de resistência',

        description: 'Filtre pela resistência à ferrugem e ao nematóide.',
      ),

      OnboardingStep(
        targetKey: _cultivaresKey,

        padding: 6,

        title: 'Cultivares recomendadas',

        description:
            'Toque em uma cultivar para visualizar '
            'suas informações.',
      ),
    ];
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final municipio = AnalysisService().municipio;

    final displayName = AnalysisService().displayName;

    final titleText =
        displayName ?? (municipio != null ? _toTitleCase(municipio) : null);

    // ==========================================================
    // MAPA EM TELA CHEIA
    // ==========================================================

    if (_isMapFullscreen) {
      return PopScope(
        canPop: false,

        onPopInvokedWithResult: (didPop, _) {
          if (didPop) {
            return;
          }

          setState(() {
            _isMapFullscreen = false;
          });
        },

        child: Scaffold(
          body: Stack(
            children: [
              // ================================================
              // MAPA
              // ================================================

              Positioned.fill(
                child: GenotypePlot(
                  key: _mapKey,

                  isLoading: _controller.isLoading,

                  selectedPoint: widget.selectedPoint,

                  opacity: _opacity,

                  onMarkerMoved: (geoOffset) {
                    _controller.updateSelectedGenotypeFromPosition(geoOffset);
                  },
                ),
              ),

              // ================================================
              // VOLTAR
              // ================================================
              Positioned(
                top: 0,
                left: 0,
                right: 0,

                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),

                    child: Align(
                      alignment: Alignment.centerLeft,

                      child: Material(
                        color: Colors.white.withValues(alpha: 0.88),

                        shape: const CircleBorder(),

                        child: IconButton(
                          tooltip: 'Voltar',

                          onPressed: () {
                            setState(() {
                              _isMapFullscreen = false;
                            });
                          },

                          icon: const Icon(
                            Icons.arrow_back,

                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ================================================
              // OPACIDADE
              // ================================================
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,

                child: SafeArea(
                  top: false,

                  child: OpacitySlider(
                    value: _opacity,

                    showLabel: false,

                    onChanged: (value) {
                      setState(() {
                        _opacity = value;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ==========================================================
    // CULTIVARES FILTRADAS
    // ==========================================================

    final ranking = _controller.selectedRanking;

    // ==========================================================
    // TELA PRINCIPAL
    // ==========================================================

    return Scaffold(
      // ========================================================
      // APP BAR
      // ========================================================

      appBar: AppBar(
        centerTitle: true,

        toolbarHeight: 70,

        titleSpacing: 0,

        title: titleText != null
            ? Column(
                mainAxisSize: MainAxisSize.min,

                children: [
                  const Text(
                    'Análise de',

                    style: TextStyle(
                      fontSize: 13,

                      fontWeight: FontWeight.w400,

                      height: 1,
                    ),
                  ),

                  const SizedBox(height: 3),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),

                    child: FittedBox(
                      fit: BoxFit.scaleDown,

                      child: Text(
                        titleText,

                        maxLines: 1,

                        textAlign: TextAlign.center,

                        style: const TextStyle(
                          fontSize: 19,

                          fontWeight: FontWeight.w600,

                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const SizedBox(
                width: 20,
                height: 20,

                child: CircularProgressIndicator(
                  strokeWidth: 2,

                  color: Colors.white,
                ),
              ),

        actions: [
          IconButton(
            onPressed: _startOnboarding,

            tooltip: 'Rever tutorial',

            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: SafeArea(
        top: false,

        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              // =================================================
              // ERRO
              // =================================================

              if (_controller.errorMessage != null)
                MaterialBanner(
                  content: Text(_controller.errorMessage!),

                  backgroundColor: Colors.red.shade100,

                  actions: [
                    TextButton(
                      onPressed: () {
                        _controller.load(position: widget.selectedPoint);
                      },

                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),

              // =================================================
              // BOTÃO DO MAPA
              // =================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),

                child: OutlinedButton(
                  key: _mapToggleKey,

                  onPressed: _toggleMap,

                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,

                      vertical: 11,
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),

                  child: Row(
                    mainAxisSize: MainAxisSize.min,

                    mainAxisAlignment: MainAxisAlignment.center,

                    children: [
                      const Icon(Icons.map_outlined, size: 19),

                      const SizedBox(width: 7),

                      Text(
                        _showMap
                            ? 'Ocultar mapa e opacidade'
                            : 'Mostrar mapa e opacidade',
                      ),

                      const SizedBox(width: 5),

                      Icon(
                        _showMap
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,

                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // =================================================
              // MAPA
              // =================================================
              if (_showMap) ...[
                const SizedBox(height: 12),

                SizedBox(
                  height: 300,

                  child: Stack(
                    children: [
                      // =========================================
                      // MAPA CAPTURADO NO PDF
                      // =========================================

                      Positioned.fill(
                        child: RepaintBoundary(
                          child: GenotypePlot(
                            key: _mapKey,

                            isLoading: _controller.isLoading,

                            selectedPoint: widget.selectedPoint,

                            opacity: _opacity,

                            onMarkerMoved: (geoOffset) {
                              _controller.updateSelectedGenotypeFromPosition(
                                geoOffset,
                              );
                            },
                          ),
                        ),
                      ),

                      // =========================================
                      // TELA CHEIA
                      // =========================================
                      Align(
                        alignment: Alignment.bottomRight,

                        child: Padding(
                          padding: const EdgeInsets.all(8),

                          child: Material(
                            color: Colors.white.withValues(alpha: 0.82),

                            shape: const CircleBorder(),

                            child: IconButton(
                              key: _fullscreenKey,

                              tooltip: 'Tela cheia',

                              onPressed: () {
                                setState(() {
                                  _isMapFullscreen = true;
                                });
                              },

                              icon: const Icon(
                                Icons.zoom_out_map,

                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ===============================================
                // OPACIDADE
                // ===============================================
                OpacitySlider(
                  key: _sliderKey,

                  value: _opacity,

                  onChanged: (value) {
                    setState(() {
                      _opacity = value;
                    });
                  },
                ),
              ],

              // =================================================
              // CICLO E INSTITUIÇÃO
              // =================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: CycleSelectionPicker(
                          key: _cycleKey,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InstitutionFilterPicker(
                          key: _institutionKey,
                          compact: true,
                          value: _controller.institutionFilter,
                          institutions: _controller.institutions,
                          onChanged: _controller.setInstitutionFilter,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // =================================================
              // RESISTÊNCIA
              // =================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),

                child: ResistanceFilterPicker(
                  key: _resistanceKey,

                  ferrugem: _controller.ferrugemFilter,

                  nematoide: _controller.nematoideFilter,

                  onFerrugemChanged: _controller.setFerrugemFilter,

                  onNematoideChanged: _controller.setNematoideFilter,
                ),
              ),

              // =================================================
              // CULTIVARES E FILTROS
              // =================================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 8, 3),

                child: Row(
                  children: [
                    // ===========================================
                    // TÍTULO
                    // ===========================================

                    Expanded(
                      child: Text(
                        'Cultivares recomendadas',

                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),

                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _controller.hasActiveFilters
                          ? _controller.clearFilters
                          : null,
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Limpar filtros'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // ESPAÇO ENTRE TÍTULO E LISTA
              // =================================================
              const SizedBox(height: 8),

              // =================================================
              // CULTIVARES
              // =================================================
              if (ranking.isNotEmpty)
                GenotypeList(
                  key: _cultivaresKey,

                  cultivares: ranking,

                  selectedGenotype: _controller.selectedGenotype,

                  municipio: AnalysisService().municipio,

                  onSelect: _controller.selectGenotype,
                )
              // =================================================
              // SEM CULTIVARES
              // =================================================
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,

                    vertical: 24,
                  ),

                  child: Column(
                    children: [
                      Icon(
                        Icons.filter_alt_off_outlined,

                        size: 32,

                        color: Colors.black.withValues(alpha: 0.30),
                      ),

                      const SizedBox(height: 9),

                      Text(
                        'Nenhuma cultivar atende aos filtros selecionados.',

                        textAlign: TextAlign.center,

                        style: TextStyle(
                          fontSize: 14,

                          fontWeight: FontWeight.w500,

                          color: Colors.black.withValues(alpha: 0.60),
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Tente alterar o ciclo, a instituição, a ferrugem '
                        'ou o nematóide.',

                        textAlign: TextAlign.center,

                        style: TextStyle(
                          fontSize: 12.5,

                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FORMATAR MUNICÍPIO
  // ============================================================

  String _toTitleCase(String text) {
    final semAno = text.replaceAll(RegExp(r'_\d{4}$'), '');

    return semAno
        .split('_')
        .map(
          (word) => word.isEmpty
              ? ''
              : '${word[0].toUpperCase()}'
                    '${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
