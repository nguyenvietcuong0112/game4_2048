import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// Shared async sprite cache for extracted Flower Merge flower growth stages (`0..3`),
/// color-matched drifting petals, golden sunburst/burst effects, and animated butterfly parts.
class _GardenFlowerSpriteCache {
  _GardenFlowerSpriteCache._();
  static final _GardenFlowerSpriteCache instance = _GardenFlowerSpriteCache._();

  final ValueNotifier<int> version = ValueNotifier<int>(0);
  final Map<FlowerType, List<ui.Image?>> stages = {};
  final Map<FlowerType, ui.Image?> petals = {};
  final List<ui.Image?> burstFrames = List<ui.Image?>.filled(8, null);

  ui.Image? bloomRays;
  ui.Image? sparkleStar;
  ui.Image? glintDot;
  ui.Image? butterflyBody;
  ui.Image? butterflyWingL;
  ui.Image? butterflyWingR;

  final Set<String> _loadingKeys = <String>{};
  bool _sharedFxLoaded = false;

  static const Map<FlowerType, String> _flowerPrefix = {
    FlowerType.tulipPink: 'tulip',
    FlowerType.trioDaisy: 'daisy',
    FlowerType.sunflower: 'sunflower',
    FlowerType.scarletPoppy: 'poppy',
    FlowerType.crystalLotus: 'lotus',
  };

  List<ui.Image?>? stagesFor(FlowerType type) => stages[type];

  bool hasStages(FlowerType type) {
    final list = stages[type];
    return list != null && list[0] != null && list[3] != null;
  }

  Future<ui.Image?> _decodeAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  Future<void> preloadForFlowerType(FlowerType type) async {
    await Future.wait([
      _preloadFlower(type),
      _preloadSharedFx(),
    ]);
  }

  Future<void> _preloadFlower(FlowerType type) async {
    final prefix = _flowerPrefix[type];
    if (prefix == null) return;
    final lockKey = 'flower_$prefix';
    if (_loadingKeys.contains(lockKey) || hasStages(type)) return;
    _loadingKeys.add(lockKey);

    try {
      final results = await Future.wait([
        _decodeAsset('assets/images/flowers/${prefix}_stage_0.webp'),
        _decodeAsset('assets/images/flowers/${prefix}_stage_1.webp'),
        _decodeAsset('assets/images/flowers/${prefix}_stage_2.webp'),
        _decodeAsset('assets/images/flowers/${prefix}_stage_3.webp'),
        _decodeAsset('assets/images/flowers/petal_$prefix.webp'),
      ]);
      stages[type] = results.sublist(0, 4);
      petals[type] = results[4];
      version.value++;
    } finally {
      _loadingKeys.remove(lockKey);
    }
  }

  Future<void> _preloadSharedFx() async {
    if (_sharedFxLoaded || _loadingKeys.contains('shared_fx')) return;
    _loadingKeys.add('shared_fx');
    try {
      final fxFuture = Future.wait([
        _decodeAsset('assets/images/flowers/fx_bloom_rays.webp'),
        _decodeAsset('assets/images/flowers/fx_sparkle.webp'),
        _decodeAsset('assets/images/flowers/fx_glint.webp'),
        _decodeAsset('assets/images/flowers/fx_butterfly_body.webp'),
        _decodeAsset('assets/images/flowers/fx_butterfly_wing_l.webp'),
        _decodeAsset('assets/images/flowers/fx_butterfly_wing_r.webp'),
      ]);
      final burstFuture = Future.wait(
        List.generate(
          8,
          (i) => _decodeAsset('assets/images/flowers/fx_burst_$i.webp'),
        ),
      );

      final fx = await fxFuture;
      final bursts = await burstFuture;
      bloomRays = fx[0];
      sparkleStar = fx[1];
      glintDot = fx[2];
      butterflyBody = fx[3];
      butterflyWingL = fx[4];
      butterflyWingR = fx[5];
      for (int i = 0; i < 8; i++) {
        burstFrames[i] = bursts[i];
      }
      _sharedFxLoaded = true;
      version.value++;
    } finally {
      _loadingKeys.remove('shared_fx');
    }
  }
}

/// Preloads the sprite stages and shared bloom FX for [flowerType] ahead of Level Complete.
Future<void> precacheGardenFlowerAssets(FlowerType flowerType) {
  return _GardenFlowerSpriteCache.instance.preloadForFlowerType(flowerType);
}

/// Studio-grade Endgame Water Jar & Flower Garden Metagame View (`Panels 3 -> 4 -> 5 -> 6`)
/// harmonized 100% with the original royal-indigo & gold Unity UI theme:
/// - Royal-indigo dark backdrop scrim + magical warm-gold & cyan stage spotlight behind the crystal vase.
/// - Classic 2-line golden `PoetsenOne` `'Level' / 'Complete!'` wave header positioned strictly below `UnityCoinsWidget`.
/// - 5 sculpted 3D crystal/ceramic vase silhouettes (`fishbowl`, `ovalCeramic`, `flutedCrystal`, `royalTall`, `prismLotus`)
///   resting on a 3D royal stone pedestal with cyan water caustics.
/// - Physics-staged 60/120Hz fluid pouring: parabolic jar flight arc, progressive waterfall head/tail,
///   damped harmonic meniscus slosh, concentric ripples, parabolic crown splash, and 20 buoyant bubbles.
/// - Authentic botanicals: plump 3-petal cupped Pink Tulip Bud with two-tone curled 3D leaves
///   (Panels 3 & 6) seamlessly unfurling without hard cuts into lush 3/4-perspective bouquets (Panels 4 & 5).
/// - Native Old-Theme Monetization Buttons (`Button_Green.png` + `Inset_Button_CTA.png` & `Button_Yellow.png` + `Icon_Ads.png`)
///   and `popup_bg.png` + `Frame_Popup_Title.png` + `frame_content.png` `"New Mechanic!"` reward popup.
class WaterGardenView extends StatefulWidget {
  static const int rewardX2UnlockLevel = 7;

  final VaseStepAdvanceResult advanceResult;
  final int finalBlockNumber;
  final int rewardCoins;
  final int? levelNumber;
  final bool? showRewardX2;
  final VoidCallback onNextLevel;
  final VoidCallback? onRewardX2;
  final bool isActionBusy;
  final VoidCallback onClaimMilestone;
  final bool showGardenBackdrop;
  final bool playEntranceAnim;

  const WaterGardenView({
    super.key,
    required this.advanceResult,
    required this.finalBlockNumber,
    this.rewardCoins = 25,
    this.levelNumber,
    this.showRewardX2,
    required this.onNextLevel,
    this.onRewardX2,
    this.isActionBusy = false,
    required this.onClaimMilestone,
    this.showGardenBackdrop = true,
    this.playEntranceAnim = true,
  });

  @override
  State<WaterGardenView> createState() => _WaterGardenViewState();
}

class _WaterGardenViewState extends State<WaterGardenView>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _seqCtrl;
  late final AnimationController _ambientCtrl;
  late final AnimationController _claimCardCtrl;
  late final AnimationController _nextVaseCtrl;

  late final Animation<double> _jarEnterAnim;
  late final Animation<double> _pourAnim;
  late final Animation<double> _jarExitAnim;
  late final Animation<double> _waterRiseAnim;
  late final Animation<double> _bloomAnim;
  late final Animation<double> _raysAnim;

  Timer? _claimDelayTimer;
  bool _isSkipped = false;
  bool _showClaimModal = false;
  bool _showingNextVase = false;

  void _preloadActiveAndNextFlowers() {
    final cache = _GardenFlowerSpriteCache.instance;
    unawaited(cache.preloadForFlowerType(widget.advanceResult.config.flowerType));
    final nextCfg = VaseMilestoneConfig.getForVaseId(
      widget.advanceResult.vaseId + 1,
    );
    unawaited(cache.preloadForFlowerType(nextCfg.flowerType));
  }

  @override
  void initState() {
    super.initState();
    _preloadActiveAndNextFlowers();
    final is100 = widget.advanceResult.didReach100Percent;
    final totalDurationMs = is100 ? 2480 : 1580;

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: widget.playEntranceAnim ? 0.0 : 1.0,
    );
    if (widget.playEntranceAnim) {
      _entranceCtrl.forward();
    }

    _seqCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalDurationMs),
    );

    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5600),
    )..repeat();

    _claimCardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _nextVaseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );

    if (is100) {
      _jarEnterAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.06, 0.20, curve: Curves.easeOutCubic),
      );
      _pourAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.16, 0.52, curve: Curves.linear),
      );
      _waterRiseAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.19, 0.53, curve: Curves.easeInOutCubic),
      );
      _jarExitAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.49, 0.61, curve: Curves.easeInOutCubic),
      );
      _bloomAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.50, 0.93, curve: Curves.easeOutCubic),
      );
      _raysAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.48, 0.92, curve: Curves.easeOutCubic),
      );
    } else {
      _jarEnterAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.09, 0.28, curve: Curves.easeOutCubic),
      );
      _pourAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.24, 0.80, curve: Curves.linear),
      );
      _waterRiseAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.28, 0.82, curve: Curves.easeInOutCubic),
      );
      _jarExitAnim = CurvedAnimation(
        parent: _seqCtrl,
        curve: const Interval(0.76, 0.95, curve: Curves.easeInOutCubic),
      );
      _bloomAnim = const AlwaysStoppedAnimation<double>(0.0);
      _raysAnim = const AlwaysStoppedAnimation<double>(0.0);
    }

    _seqCtrl.forward().whenComplete(() {
      if (!mounted ||
          !widget.advanceResult.didReach100Percent ||
          _showingNextVase ||
          _showClaimModal) {
        return;
      }
      // Brief celebratory beat to admire the 100% Checkmark & full bouquet before sliding up the Reward Card
      _claimDelayTimer?.cancel();
      _claimDelayTimer = Timer(const Duration(milliseconds: 160), () {
        if (mounted && !_showingNextVase && !_showClaimModal) {
          setState(() {
            _showClaimModal = true;
          });
          _claimCardCtrl.forward(from: 0.0);
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant WaterGardenView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advanceResult.vaseId != widget.advanceResult.vaseId) {
      _preloadActiveAndNextFlowers();
    }
  }

  @override
  void dispose() {
    _claimDelayTimer?.cancel();
    _entranceCtrl.dispose();
    _seqCtrl.dispose();
    _ambientCtrl.dispose();
    _claimCardCtrl.dispose();
    _nextVaseCtrl.dispose();
    super.dispose();
  }

  void _fastForwardSequenceIfRunning() {
    _claimDelayTimer?.cancel();
    if (_entranceCtrl.value < 1.0) {
      _entranceCtrl.value = 1.0;
    }
    if (_seqCtrl.value < 1.0) {
      _seqCtrl.stop();
      _seqCtrl.value = 1.0;
    }
  }

  void _handleTapToSkip() {
    if (widget.isActionBusy || _showClaimModal || _showingNextVase) return;
    if (_isSkipped && _seqCtrl.value >= 1.0) return;
    _isSkipped = true;
    _fastForwardSequenceIfRunning();
    if (widget.advanceResult.didReach100Percent && !_showClaimModal) {
      setState(() {
        _showClaimModal = true;
      });
      _claimCardCtrl.forward(from: 0.0);
    } else {
      setState(() {});
    }
  }

  void _handleClaimTapped() {
    if (widget.isActionBusy) return;
    _fastForwardSequenceIfRunning();
    widget.onClaimMilestone();
    if (!mounted) return;
    setState(() {
      _showClaimModal = false;
      _showingNextVase = true;
    });
    _nextVaseCtrl.forward(from: 0.0);
  }

  void _handleNextLevelTapped() {
    if (widget.isActionBusy) return;
    _fastForwardSequenceIfRunning();
    widget.onNextLevel();
  }

  void _handleRewardX2Tapped() {
    if (widget.isActionBusy) return;
    _fastForwardSequenceIfRunning();
    if (widget.onRewardX2 != null) {
      widget.onRewardX2!();
    } else {
      widget.onNextLevel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final is100 = widget.advanceResult.didReach100Percent;
    final activeCfg = _showingNextVase
        ? VaseMilestoneConfig.getForVaseId(widget.advanceResult.vaseId + 1)
        : widget.advanceResult.config;

    final stageListenable = Listenable.merge([
      _entranceCtrl,
      _seqCtrl,
      _ambientCtrl,
      _nextVaseCtrl,
      _GardenFlowerSpriteCache.instance.version,
    ]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeH = constraints.maxHeight;
        final safeW = constraints.maxWidth;

        // Strictly clear the elevated top-left `UnityCoinsWidget` (`top: ux(21)`, `height: ux(108)` -> bottom `ux(129)`)
        final coinsBottomSafeY = ux(
          context,
          UnityCoinsWidget.hudTopUnity + UnityCoinsWidget.heightUnity + 14.0,
        );
        final ribbonTop = math.max(coinsBottomSafeY - 10.0, safeH * 0.038);
        final ribbonH = (safeH * 0.130).clamp(88.0, 120.0);
        final ribbonW = math.min(safeW - 12.0, 412.0);

        final bottomPad = math.max(12.0, safeH * 0.020);
        final bottomControlsEstimatedH = 104.0 + ux(context, 224.0);
        final stageTop = ribbonTop + ribbonH + 2.0;
        final maxControlsTop = math.max(
          stageTop + 176.0,
          safeH - bottomPad - bottomControlsEstimatedH,
        );
        final idealStageH = (safeH * 0.375).clamp(176.0, 320.0);
        final stageAvailH = math
            .min(maxControlsTop - stageTop + 4.0, idealStageH)
            .clamp(176.0, 320.0);
        final controlsTop = (stageTop + stageAvailH + 4.0).clamp(
          stageTop + 176.0,
          maxControlsTop,
        );

        return SizedBox.expand(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTapToSkip,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                // 0. Old-Theme Royal-Indigo Backdrop (when standalone) + Magical Golden/Cyan Stage Spotlight
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _ambientCtrl,
                        builder: (context, _) {
                          return SizedBox.expand(
                            child: CustomPaint(
                              painter: _OldThemeStageBackdropPainter(
                                drawSolidScrim: widget.showGardenBackdrop,
                                ambientPhase:
                                    _ambientCtrl.value * math.pi * 2.0,
                                stageCenterYFraction:
                                    ((stageTop + stageAvailH * 0.50) / safeH)
                                        .clamp(0.32, 0.62),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // 1. Central 3D Vase, Volumetric Water, Pouring Potion Jar & Bouquet Stage
                Positioned(
                  top: stageTop,
                  left: 6,
                  right: 6,
                  height: stageAvailH,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        key: const ValueKey('garden_vase_stage'),
                        width: 380,
                        height: 448,
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: stageListenable,
                            builder: (context, _) {
                              final enterT = Curves.easeOutCubic.transform(
                                _entranceCtrl.value.clamp(0.0, 1.0),
                              );
                              final ambientPhase =
                                  _ambientCtrl.value * math.pi * 2.0;

                              if (_showingNextVase) {
                                final rawNext =
                                    _nextVaseCtrl.value.clamp(0.0, 1.0);
                                final popT =
                                    Curves.easeOutBack.transform(rawNext);
                                final sparkleBurst =
                                    (1.0 - rawNext).clamp(0.0, 1.0);
                                return Transform.translate(
                                  offset: Offset(0, (1.0 - popT) * 18.0),
                                  child: Transform.scale(
                                    scale: (0.80 + 0.20 * popT).clamp(0.5, 1.2),
                                    child: CustomPaint(
                                      painter: _WaterGardenMasterPainter(
                                        config: activeCfg,
                                        oldWaterProgress: 0.0,
                                        waterProgress: 0.0,
                                        jarEnterProgress: 0.0,
                                        pourProgress: 0.0,
                                        jarExitProgress: 1.0,
                                        bloomProgress: 0.0,
                                        raysProgress: sparkleBurst * 0.70,
                                        finalBlockNumber:
                                            widget.finalBlockNumber,
                                        ambientPhase: ambientPhase,
                                        is100Percent: false,
                                        isNewVaseReveal: true,
                                        newVaseSparkleT: rawNext,
                                        spriteVersion: _GardenFlowerSpriteCache
                                            .instance.version.value,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final tWater = _waterRiseAnim.value;
                              final currentProgress = ui.lerpDouble(
                                widget.advanceResult.oldProgress,
                                widget.advanceResult.newProgress,
                                tWater,
                              )!;

                              return Transform.translate(
                                offset: Offset(0, (1.0 - enterT) * 20.0),
                                child: Transform.scale(
                                  scale: 0.90 + 0.10 * enterT,
                                  child: CustomPaint(
                                    painter: _WaterGardenMasterPainter(
                                      config: activeCfg,
                                      oldWaterProgress:
                                          widget.advanceResult.oldProgress,
                                      waterProgress: currentProgress,
                                      jarEnterProgress: _jarEnterAnim.value,
                                      pourProgress: _pourAnim.value,
                                      jarExitProgress: _jarExitAnim.value,
                                      bloomProgress:
                                          is100 ? _bloomAnim.value : 0.0,
                                      raysProgress:
                                          is100 ? _raysAnim.value : 0.0,
                                      finalBlockNumber: widget.finalBlockNumber,
                                      ambientPhase: ambientPhase,
                                      is100Percent: is100,
                                      isNewVaseReveal: false,
                                      newVaseSparkleT: 0.0,
                                      spriteVersion: _GardenFlowerSpriteCache
                                          .instance.version.value,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // 2. Classic Old-Theme 2-Line Golden `PoetsenOne` `'Level' / 'Complete!'` Wave Header
                //    (Positioned strictly below `UnityCoinsWidget` so coins never overlap!)
                Positioned(
                  top: ribbonTop,
                  width: ribbonW,
                  height: ribbonH,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _entranceCtrl,
                      builder: (context, ribbonChild) {
                        final rPop = Curves.easeOutBack.transform(
                          _entranceCtrl.value.clamp(0.0, 1.0),
                        );
                        return Transform.translate(
                          offset: Offset(0, -24.0 * (1.0 - rPop)),
                          child: Transform.scale(
                            scale: (0.86 + 0.14 * rPop).clamp(0.5, 1.15),
                            child: ribbonChild,
                          ),
                        );
                      },
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          key: const ValueKey<String>('Level Complete!'),
                          animation: _ambientCtrl,
                          builder: (context, _) {
                            return CustomPaint(
                              size: Size(ribbonW, ribbonH),
                              painter: _OldThemeLevelCompleteHeaderPainter(
                                ambientValue: _ambientCtrl.value,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

                // 3. Progress Card + CTA Buttons lifted right below the pedestal (never pinned down at screen bottom)
                if (!_showClaimModal)
                  Positioned(
                    top: controlsTop,
                    left: 16,
                    right: 16,
                    child: AnimatedBuilder(
                      animation: _entranceCtrl,
                      builder: (context, bottomChild) {
                        final bEase = Curves.easeOutCubic.transform(
                          _entranceCtrl.value.clamp(0.0, 1.0),
                        );
                        return Transform.translate(
                          offset: Offset(0, 36.0 * (1.0 - bEase)),
                          child: bottomChild,
                        );
                      },
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: ux(context, 984),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              RepaintBoundary(
                                child: AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _waterRiseAnim,
                                    _nextVaseCtrl,
                                  ]),
                                  builder: (context, _) {
                                    final double currentProgress;
                                    if (_showingNextVase) {
                                      currentProgress = 0.0;
                                    } else {
                                      currentProgress = ui.lerpDouble(
                                        widget.advanceResult.oldProgress,
                                        widget.advanceResult.newProgress,
                                        _waterRiseAnim.value,
                                      )!;
                                    }
                                    final isCompleteNow = !_showingNextVase &&
                                        is100 &&
                                        currentProgress >= 0.999;

                                    return _buildOldThemeProgressCard(
                                      cfg: activeCfg,
                                      progress: currentProgress,
                                      isComplete: isCompleteNow,
                                      isNewVaseMystery: _showingNextVase,
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (is100 && !_showingNextVase)
                                UnityCtaButton(
                                  key: const ValueKey('garden_claim_btn'),
                                  label: 'Claim',
                                  unityWidth: 499,
                                  unityHeight: 221,
                                  unityFontSize: 68,
                                  onTap: widget.isActionBusy
                                      ? null
                                      : _handleClaimTapped,
                                )
                              else
                                _buildDualNextAndRewardButtons(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // 4. Panel 5: Native Old-Theme `popup_bg.png` + `Frame_Popup_Title.png` + `frame_content.png`
                //    `"New Mechanic!"` Reward Card over lower half so the full blooming bouquet shines above!
                if (_showClaimModal)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: bottomPad,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _claimCardCtrl,
                        builder: (context, cardChild) {
                          final raw = _claimCardCtrl.value.clamp(0.0, 1.0);
                          final slideT = Curves.easeOutCubic.transform(raw);
                          final scaleT = Curves.easeOutBack.transform(raw);
                          return Transform.translate(
                            offset: Offset(0, (1.0 - slideT) * 48.0),
                            child: Transform.scale(
                              scale: (0.84 + 0.16 * scaleT).clamp(0.5, 1.12),
                              alignment: Alignment.bottomCenter,
                              child: cardChild,
                            ),
                          );
                        },
                        child: _buildNewMechanicCard(
                          context: context,
                          config: widget.advanceResult.config,
                          maxCardHeight: safeH * 0.50,
                          onClaim: _handleClaimTapped,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _effectiveShowRewardX2 {
    if (widget.showRewardX2 != null) return widget.showRewardX2!;
    if (widget.levelNumber != null) {
      return widget.levelNumber! >= WaterGardenView.rewardX2UnlockLevel;
    }
    return true;
  }

  /// Level Complete Action Buttons (100% 3-Slice `UnityNineSlice` — zero capsule distortion):
  /// - Levels 1..6 (`!_effectiveShowRewardX2`): Single centered `UnityStackedCoinCtaButton` (`500 x 221`).
  /// - Level 7+ (`_effectiveShowRewardX2`): Side-by-side `LevelCompleteDualActionRow`.
  Widget _buildDualNextAndRewardButtons() {
    if (!_effectiveShowRewardX2) {
      return Center(
        child: UnityStackedCoinCtaButton(
          key: const ValueKey('garden_next_level_btn'),
          label: 'Next Level',
          coinLabel: '+${math.max(1, widget.rewardCoins)}',
          sprite: 'Button_CTA.png',
          unityWidth: 500,
          unityHeight: 221,
          unityFontSize: 56,
          insetUnityWidth: 232,
          insetUnityHeight: 58,
          onTap: widget.isActionBusy ? null : _handleNextLevelTapped,
        ),
      );
    }

    return LevelCompleteDualActionRow(
      rewardCoins: widget.rewardCoins,
      shimmerAnimation: _ambientCtrl,
      enabled: !widget.isActionBusy,
      onNextLevel: _handleNextLevelTapped,
      onRewardX2: _handleRewardX2Tapped,
    );
  }

  /// Gold-Rimmed Royal-Indigo Unlock Progress Card matching `WidgetBase.png` & `WinOverlay` stats pill!
  Widget _buildOldThemeProgressCard({
    required VaseMilestoneConfig cfg,
    required double progress,
    required bool isComplete,
    required bool isNewVaseMystery,
  }) {
    final clampedP = progress.clamp(0.0, 1.0);
    final pctInt = (clampedP * 100).round();
    final remainingPercent = (100 - pctInt).clamp(0, 100);

    final statusLabel = isComplete
        ? '100%'
        : (remainingPercent > 0 ? '$remainingPercent% to unlock' : '100%');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xEE1D1454),
            Color(0xF4100B33),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFFFB915),
          width: 2.3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF9E5A00),
            offset: Offset(0, 3.5),
            blurRadius: 0,
          ),
          BoxShadow(
            color: Color(0x6602010D),
            offset: Offset(0, 9),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: Crisp White/Gold `Baloo2` Title + Recessed Navy Socket with Glowing Cyan Fill
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  height: 23,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      statusLabel,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontSize: isComplete ? 20.5 : 18.5,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                        color: isComplete
                            ? const Color(0xFFFFE082)
                            : Colors.white,
                        shadows: const [
                          Shadow(
                            color: Color(0xCC06031C),
                            offset: Offset(0, 1.8),
                            blurRadius: 2.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 22,
                  padding: const EdgeInsets.all(2.4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF08051F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0x526573C3),
                      width: 1.2,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: clampedP > 0.005
                        ? FractionallySizedBox(
                            widthFactor: clampedP.clamp(0.07, 1.0),
                            heightFactor: 1.0,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9.5),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF7AFBFF),
                                    Color(0xFF21D2EF),
                                    Color(0xFF0B95D6),
                                  ],
                                  stops: [0.0, 0.54, 1.0],
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x6623D2EB),
                                    blurRadius: 6,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  height: 4.5,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x88FFFFFF),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Right: Gold-Rimmed Royal-Blue / Emerald 3D Square Badge (Padlock / Checkmark / ?)
          _buildStatusSquareBadge(
            isComplete: isComplete,
            isMystery: isNewVaseMystery,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSquareBadge({
    required bool isComplete,
    required bool isMystery,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isComplete
              ? const [Color(0xFF43EE68), Color(0xFF0E9F2E)]
              : const [Color(0xFF429BFF), Color(0xFF0B4EC4)],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFFFCA28),
          width: 2.1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF965200),
            offset: Offset(0, 3.0),
            blurRadius: 0,
          ),
          BoxShadow(
            color: Color(0x5500041E),
            offset: Offset(0, 6),
            blurRadius: 6,
          ),
        ],
      ),
      child: (!isComplete && isMystery)
          ? const Center(
              child: Text(
                '?',
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  color: Color(0xFFFFF59D),
                  shadows: [
                    Shadow(
                      color: Color(0xCC041B5E),
                      offset: Offset(0, 1.8),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            )
          : (isComplete
              ? const CustomPaint(
                  painter: _BadgeGlyphPainter(mode: _BadgeGlyphMode.check),
                )
              : Padding(
                  padding: const EdgeInsets.all(7.5),
                  child: Image.asset(
                    'assets/images/Icon_Padlock_Silver.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const CustomPaint(
                      painter: _BadgeGlyphPainter(mode: _BadgeGlyphMode.lock),
                    ),
                  ),
                )),
    );
  }

  /// Panel 5 `"New Mechanic!"` Reward Popup Card reusing 100% `UnityNineSlice` & `UnityCtaButton`:
  /// - `popup_bg.png` 9-slice gold-rimmed royal-blue body
  /// - `Frame_Popup_Title.png` 3-slice top header ribbon (`"New Mechanic!"` / `"Bonus Reward!"`)
  /// - `frame_content.png` 9-slice warm cream inner well with 3D reward icon + coins + `#5A270B` title
  /// - `UnityCtaButton` (`Button_CTA.png`) `"Claim"` button!
  Widget _buildNewMechanicCard({
    required BuildContext context,
    required VaseMilestoneConfig config,
    required double maxCardHeight,
    required VoidCallback onClaim,
  }) {
    final modalHeaderTitle =
        config.unlockMechanicId != null ? 'New Mechanic!' : 'Bonus Reward!';
    final cardW = ux(context, 884);
    final cardH = ux(context, 856);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(cardW, 380.0),
        maxHeight: math.max(ux(context, 720), maxCardHeight),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: cardW,
          height: cardH,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              // 1. 9-Slice Gold-Rimmed Royal-Blue Popup Body (`popup_bg.png`, exact 884px width -> 1:1 arch continuity)
              Positioned(
                left: 0,
                right: 0,
                top: ux(context, 42),
                bottom: 0,
                child: const UnityNineSlice(
                  sprite: 'popup_bg.png',
                  pixelMultiplier: 1.0,
                ),
              ),

              // 2. 9-Slice Warm Cream Inner Content Well (`frame_content.png`, exact 784px width -> 1:1 corner continuity)
              Positioned(
                left: ux(context, 50),
                right: ux(context, 50),
                top: ux(context, 162),
                height: ux(context, 434),
                child: UnityNineSlice(
                  sprite: 'frame_content.png',
                  pixelMultiplier: 1.0,
                  padding: EdgeInsets.fromLTRB(
                    ux(context, 34),
                    ux(context, 16),
                    ux(context, 34),
                    ux(context, 22),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedBuilder(
                              animation: _ambientCtrl,
                              builder: (context, _) {
                                return _RewardShowcaseGraphic(
                                  mechanicId: config.unlockMechanicId,
                                  ambientPhase:
                                      _ambientCtrl.value * math.pi * 2.0,
                                );
                              },
                            ),
                            Positioned(
                              right: ux(context, 16),
                              bottom: ux(context, 6),
                              child: UnitySdfText(
                                '+${config.rewardCoins}',
                                unityFontSize: 54,
                                material: UnityTextMaterial.winCoinAmount,
                                singleTextNode: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: ux(context, 6)),
                      Text(
                        config.rewardTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: ux(context, 62),
                          fontWeight: FontWeight.w800,
                          fontVariations: const [FontVariation('wght', 800)],
                          height: 1.06,
                          color: const Color(0xFF5A270B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Bottom Shared `UnityCtaButton` (`Button_CTA.png`, `"Claim"`)
              Positioned(
                bottom: ux(context, 34),
                child: UnityCtaButton(
                  label: 'Claim',
                  unityWidth: 480,
                  unityHeight: 205,
                  unityFontSize: 64,
                  onTap: widget.isActionBusy ? null : onClaim,
                ),
              ),

              // 4. 3-Slice Top Overlapping Ribbon (`Frame_Popup_Title.png`)
              Positioned(
                top: 0,
                width: ux(context, 636),
                height: ux(context, 150),
                child: Container(
                  key: ValueKey<String>(modalHeaderTitle),
                  alignment: Alignment.center,
                  child: UnityNineSlice(
                    sprite: 'Frame_Popup_Title.png',
                    padding: EdgeInsets.fromLTRB(
                      ux(context, 52),
                      ux(context, 8),
                      ux(context, 52),
                      ux(context, 18),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: UnitySdfText(
                        modalHeaderTitle,
                        unityFontSize: 60,
                        material: UnityTextMaterial.popupTitle,
                        singleTextNode: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Old-Theme Royal-Indigo Backdrop & Magical Stage Spotlight Painter:
/// - When `drawSolidScrim == false` (inside `WinOverlay`), keeps edges transparent so gameplay's
///   `Background_Core.png` + `rgba(10, 8, 28, 0.90)` dark scrim shine through naturally!
/// - Casts a warm golden-violet & icy-cyan stage aura behind the central 3D crystal vase.
class _OldThemeStageBackdropPainter extends CustomPainter {
  final bool drawSolidScrim;
  final double ambientPhase;
  final double stageCenterYFraction;

  static final Paint _paint = Paint()..isAntiAlias = true;
  static final Path _conePath = Path();

  _OldThemeStageBackdropPainter({
    required this.drawSolidScrim,
    required this.ambientPhase,
    required this.stageCenterYFraction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    if (drawSolidScrim) {
      _paint
        ..style = PaintingStyle.fill
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(size.width * 0.5, 0),
          Offset(size.width * 0.5, size.height),
          const [
            Color(0xFF1D114D),
            Color(0xFF130B35),
            Color(0xFF09061E),
          ],
          const [0.0, 0.52, 1.0],
        );
      canvas.drawRect(rect, _paint);
      _paint.shader = null;
    }

    final breathe = 1.0 + 0.045 * math.sin(ambientPhase);
    final stageCenter = Offset(
      size.width * 0.5,
      size.height * stageCenterYFraction,
    );

    // 0. Soft overhead volumetric stage spotlight cone illuminating the 3D vase & pedestal
    _conePath
      ..reset()
      ..moveTo(size.width * 0.34, 0)
      ..lineTo(size.width * 0.66, 0)
      ..lineTo(size.width * 0.90, stageCenter.dy + 135)
      ..lineTo(size.width * 0.10, stageCenter.dy + 135)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(
        Offset(size.width * 0.5, 0),
        Offset(size.width * 0.5, stageCenter.dy + 135),
        const [
          Color(0x16FFF6C8),
          Color(0x186BEBFF),
          Color(0x001A1046),
        ],
        const [0.0, 0.56, 1.0],
      );
    canvas.drawPath(_conePath, _paint);

    // 1. Soft Magical Royal-Violet & Cyan Aura behind the 3D Crystal Vase
    final outerR = math.min(size.width, size.height) * 0.64 * breathe;
    _paint.shader = ui.Gradient.radial(
      stageCenter,
      outerR,
      const [
        Color(0x4C4CEBFF),
        Color(0x2E8458D6),
        Color(0x16FFD54F),
        Color(0x001A1046),
      ],
      const [0.0, 0.42, 0.72, 1.0],
    );
    canvas.drawCircle(stageCenter, outerR, _paint);

    // 2. Warm Golden Halo behind the Top `'Level / Complete!'` Wave Header
    final headerCenter = Offset(size.width * 0.5, size.height * 0.12);
    final headerR = math.min(size.width, size.height) * 0.38 * breathe;
    _paint.shader = ui.Gradient.radial(
      headerCenter,
      headerR,
      const [
        Color(0x46FFE082),
        Color(0x20FFB300),
        Color(0x00FFB300),
      ],
      const [0.0, 0.52, 1.0],
    );
    canvas.drawCircle(headerCenter, headerR, _paint);
    _paint.shader = null;

    // 3. Subtle Floating Golden & Cyan Starlight Bokeh Motes (additive glow)
    for (int i = 0; i < 16; i++) {
      final seed = i * 1.73;
      final fx = 0.08 +
          ((i * 0.193) % 0.84) +
          0.022 * math.sin(ambientPhase + seed);
      final rawY =
          ((i * 0.137) - (ambientPhase / (math.pi * 2.0)) * 0.16) % 1.0;
      final fy = rawY < 0 ? rawY + 1.0 : rawY;
      final radius = 2.6 + (i % 4) * 2.4;
      final alpha = (0.09 + 0.12 * math.sin(ambientPhase * 2.0 + seed))
          .clamp(0.02, 0.24);
      final baseColor =
          i.isEven ? const Color(0xFFFFE082) : const Color(0xFF80F8FF);
      final pos = Offset(fx * size.width, fy * size.height);
      _paint.shader = null;
      _paint.color = baseColor.withValues(alpha: alpha * 0.36);
      canvas.drawCircle(pos, radius * 2.0, _paint);
      _paint.color = baseColor.withValues(alpha: alpha * 0.85);
      canvas.drawCircle(pos, radius * 0.92, _paint);
    }
    _paint.shader = null;
    _paint.blendMode = BlendMode.srcOver;
  }

  @override
  bool shouldRepaint(covariant _OldThemeStageBackdropPainter oldDelegate) =>
      oldDelegate.ambientPhase != ambientPhase ||
      oldDelegate.drawSolidScrim != drawSolidScrim ||
      oldDelegate.stageCenterYFraction != stageCenterYFraction;
}

class _CachedWaveLineMetrics {
  final double totalW;
  final double lineH;
  final List<double> charXs;

  const _CachedWaveLineMetrics({
    required this.totalW,
    required this.lineH,
    required this.charXs,
  });
}

class _CachedWaveCharSprite {
  final ui.Image? backImage;
  final ui.Image? faceImage;
  final Rect srcRect;
  final double pad;
  final double logicalW;
  final double logicalH;
  final TextPainter? glowShadowTp;
  final TextPainter? underlayTp;
  final TextPainter? outerStrokeTp;
  final TextPainter? innerStrokeTp;
  final TextPainter? faceTp;
  final double dropY;

  const _CachedWaveCharSprite({
    required this.backImage,
    required this.faceImage,
    required this.srcRect,
    required this.pad,
    required this.logicalW,
    required this.logicalH,
    required this.glowShadowTp,
    required this.underlayTp,
    required this.outerStrokeTp,
    required this.innerStrokeTp,
    required this.faceTp,
    required this.dropY,
  });
}

/// Classic Old-Theme 2-Line `'Level' / 'Complete!'` Golden Wave Header Painter
/// matching `WinOverlay._buildTwoLineWaveLevelComplete` (`PoetsenOne` + `UnityTextMaterial.levelCompleteWave`):
/// - Pre-bakes each unique character's stroke underlay & gold gradient face once so the
///   60/120Hz sine wave runs with ZERO per-frame `TextPainter.layout()` or `MaskFilter.blur`.
class _OldThemeLevelCompleteHeaderPainter extends CustomPainter {
  final double ambientValue;

  static final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);
  static final Paint _sparkPaint = Paint()..isAntiAlias = true;
  static final Paint _glyphPaint = Paint()..filterQuality = FilterQuality.medium;
  static final Path _sparkPath = Path();
  static final Map<String, _CachedWaveLineMetrics> _lineMetricsCache =
      <String, _CachedWaveLineMetrics>{};
  static final Map<String, _CachedWaveCharSprite> _charGlyphCache =
      <String, _CachedWaveCharSprite>{};

  _OldThemeLevelCompleteHeaderPainter({required this.ambientValue});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final fs1 = (h * 0.46).clamp(34.0, 56.0);
    final fs2 = (h * 0.42).clamp(31.0, 51.0);
    final waveAmp = (h * 0.028).clamp(2.2, 4.0);

    _drawWaveLine(
      canvas: canvas,
      centerX: size.width * 0.5,
      baselineCenterY: h * 0.27,
      text: 'Level',
      fontSize: fs1,
      phaseOffset: 1.4,
      waveAmp: waveAmp,
      maxWidth: size.width * 0.94,
    );
    _drawWaveLine(
      canvas: canvas,
      centerX: size.width * 0.5,
      baselineCenterY: h * 0.72,
      text: 'Complete!',
      fontSize: fs2,
      phaseOffset: 0.0,
      waveAmp: waveAmp,
      maxWidth: size.width * 0.96,
    );

    _drawHeaderSparkles(canvas, size);
  }

  void _drawHeaderSparkles(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const spots = [
      (0.16, 0.24, 6.2, 0.0),
      (0.84, 0.22, 5.4, 1.7),
      (0.10, 0.74, 5.0, 3.1),
      (0.90, 0.70, 6.6, 4.4),
    ];
    for (final (fx, fy, r, phase) in spots) {
      final twinkle =
          (0.45 + 0.55 * math.sin(ambientValue * math.pi * 4.0 + phase))
              .clamp(0.15, 1.0);
      final c = Offset(w * fx, h * fy);
      final rad = r * (0.72 + 0.28 * twinkle);
      _sparkPath
        ..reset()
        ..moveTo(c.dx, c.dy - rad)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + rad * 0.85, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + rad)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - rad * 0.85, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - rad)
        ..close();
      _sparkPaint
        ..style = PaintingStyle.fill
        ..maskFilter = null
        ..color = Color.lerp(
          const Color(0xFFFFE57F),
          Colors.white,
          twinkle,
        )!.withValues(alpha: 0.88 * twinkle);
      canvas.drawPath(_sparkPath, _sparkPaint);
    }
  }

  static _CachedWaveLineMetrics _getLineMetrics(String text, double fontSize) {
    final fsKey = (fontSize * 4.0).round();
    final key = '$text|$fsKey';
    final cached = _lineMetricsCache[key];
    if (cached != null) return cached;

    const mat = UnityTextMaterial.levelCompleteWave;
    final measureStyle = TextStyle(
      fontFamily: mat.fontFamily,
      fontSize: fontSize,
      fontWeight: mat.fontWeight,
      height: 1.05,
      letterSpacing: fontSize * 0.012,
      color: Colors.white,
    );
    _tp.text = TextSpan(text: text, style: measureStyle);
    _tp.layout();
    final metrics = _CachedWaveLineMetrics(
      totalW: _tp.width,
      lineH: _tp.height,
      charXs: List<double>.generate(
        text.length,
        (i) => _tp.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx,
        growable: false,
      ),
    );
    if (_lineMetricsCache.length >= 24) {
      _lineMetricsCache.clear();
    }
    _lineMetricsCache[key] = metrics;
    return metrics;
  }

  static _CachedWaveCharSprite _getCharSprite(
    String ch,
    double fontSize,
    double lineH,
  ) {
    final fsKey = (fontSize * 4.0).round();
    final key = '$ch|$fsKey';
    final cached = _charGlyphCache[key];
    if (cached != null) return cached;

    const mat = UnityTextMaterial.levelCompleteWave;
    final innerSw = (fontSize * 0.095).clamp(2.0, 7.5);
    final outerSw = (fontSize * 0.148).clamp(innerSw + 1.0, 11.2);
    final dropY = fontSize * 0.092;

    TextStyle styleWith(Paint foreground) => TextStyle(
          fontFamily: mat.fontFamily,
          fontSize: fontSize,
          fontWeight: mat.fontWeight,
          height: 1.05,
          letterSpacing: fontSize * 0.012,
          foreground: foreground,
        );

    final glowShadowStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerSw * 1.18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          (fontSize * 0.075).clamp(2.0, 5.0),
        )
        ..color = const Color(0x9E2C0600),
    );
    final underlayStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerSw
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xE84B0D00),
    );
    final outerStrokeStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerSw
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF8C1800),
    );
    final innerStrokeStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = innerSw
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFE96D24),
    );
    final faceStyle = styleWith(
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fontSize * 0.14),
          Offset(0, fontSize * 0.94),
          const [
            Color(0xFFFFFFFF),
            Color(0xFFFFF8D0),
            Color(0xFFFFDF6A),
            Color(0xFFFFB528),
          ],
          const [0.0, 0.34, 0.70, 1.0],
        ),
    );

    final glowTp = TextPainter(
      text: TextSpan(text: ch, style: glowShadowStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final underlayTp = TextPainter(
      text: TextSpan(text: ch, style: underlayStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final outerTp = TextPainter(
      text: TextSpan(text: ch, style: outerStrokeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final innerTp = TextPainter(
      text: TextSpan(text: ch, style: innerStrokeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final faceTp = TextPainter(
      text: TextSpan(text: ch, style: faceStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = (outerSw * 1.45 + 6.0).ceilToDouble();
    final bottomExtra = (dropY * 1.3).ceilToDouble();
    final logicalW = math.max(faceTp.width, 8.0) + pad * 2.0;
    final logicalH = math.max(lineH, faceTp.height) + pad * 2.0 + bottomExtra;
    const ss = 2.0;
    final imgW = (logicalW * ss).ceil().clamp(4, 512);
    final imgH = (logicalH * ss).ceil().clamp(4, 512);

    ui.Image? backImg;
    ui.Image? faceImg;
    try {
      final backRec = ui.PictureRecorder();
      final backCanvas = Canvas(backRec);
      backCanvas.scale(imgW / logicalW, imgH / logicalH);
      glowTp.paint(backCanvas, Offset(pad, pad + dropY * 1.15));
      underlayTp.paint(backCanvas, Offset(pad, pad + dropY));
      outerTp.paint(backCanvas, Offset(pad, pad));
      innerTp.paint(backCanvas, Offset(pad, pad));
      final backPic = backRec.endRecording();
      backImg = backPic.toImageSync(imgW, imgH);
      backPic.dispose();

      final faceRec = ui.PictureRecorder();
      final faceCanvas = Canvas(faceRec);
      faceCanvas.scale(imgW / logicalW, imgH / logicalH);
      faceTp.paint(faceCanvas, Offset(pad, pad));
      final facePic = faceRec.endRecording();
      faceImg = facePic.toImageSync(imgW, imgH);
      facePic.dispose();
    } catch (_) {
      backImg = null;
      faceImg = null;
    }

    final sprite = _CachedWaveCharSprite(
      backImage: backImg,
      faceImage: faceImg,
      srcRect: Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
      pad: pad,
      logicalW: logicalW,
      logicalH: logicalH,
      glowShadowTp: glowTp,
      underlayTp: underlayTp,
      outerStrokeTp: outerTp,
      innerStrokeTp: innerTp,
      faceTp: faceTp,
      dropY: dropY,
    );
    if (_charGlyphCache.length >= 64) {
      _charGlyphCache.clear();
    }
    _charGlyphCache[key] = sprite;
    return sprite;
  }

  void _drawWaveLine({
    required Canvas canvas,
    required double centerX,
    required double baselineCenterY,
    required String text,
    required double fontSize,
    required double phaseOffset,
    required double waveAmp,
    required double maxWidth,
  }) {
    final metrics = _getLineMetrics(text, fontSize);
    final totalW = metrics.totalW;
    final lineH = metrics.lineH;
    final charXs = metrics.charXs;
    final scale = totalW > maxWidth ? (maxWidth / totalW) : 1.0;

    canvas.save();
    canvas.translate(centerX, baselineCenterY);
    if (scale < 0.999) {
      canvas.scale(scale, scale);
    }

    final startX = -totalW * 0.5;
    final baseWaveRad = ambientValue * math.pi * 4.0;
    final glyphs = List<_CachedWaveCharSprite>.generate(
      text.length,
      (i) => _getCharSprite(text[i], fontSize, lineH),
      growable: false,
    );

    // Pass 1: Pre-composited 3D drop shadows & beveled outlines
    for (int i = 0; i < text.length; i++) {
      final g = glyphs[i];
      final x = startX + charXs[i];
      final waveAngle = baseWaveRad - (i + phaseOffset) * 0.42;
      final topY = -lineH * 0.5 + math.sin(waveAngle) * waveAmp;
      final backImg = g.backImage;
      if (backImg != null) {
        canvas.drawImageRect(
          backImg,
          g.srcRect,
          Rect.fromLTWH(x - g.pad, topY - g.pad, g.logicalW, g.logicalH),
          _glyphPaint,
        );
      } else {
        g.underlayTp?.paint(canvas, Offset(x, topY + g.dropY));
        g.outerStrokeTp?.paint(canvas, Offset(x, topY));
        g.innerStrokeTp?.paint(canvas, Offset(x, topY));
      }
    }

    // Pass 2: Smooth Ivory-to-Honey-Gold Gradient Faces
    for (int i = 0; i < text.length; i++) {
      final g = glyphs[i];
      final x = startX + charXs[i];
      final waveAngle = baseWaveRad - (i + phaseOffset) * 0.42;
      final topY = -lineH * 0.5 + math.sin(waveAngle) * waveAmp;
      final faceImg = g.faceImage;
      if (faceImg != null) {
        canvas.drawImageRect(
          faceImg,
          g.srcRect,
          Rect.fromLTWH(x - g.pad, topY - g.pad, g.logicalW, g.logicalH),
          _glyphPaint,
        );
      } else {
        g.faceTp?.paint(canvas, Offset(x, topY));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _OldThemeLevelCompleteHeaderPainter oldDelegate,
  ) =>
      oldDelegate.ambientValue != ambientValue;
}

enum _BadgeGlyphMode { lock, check, question }

/// Crisp 3D vector Padlock, Checkmark (`✓`), and Mystery (`?`) painter for the Progress Card square badge.
class _BadgeGlyphPainter extends CustomPainter {
  final _BadgeGlyphMode mode;

  const _BadgeGlyphPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.5;
    final paint = Paint()..isAntiAlias = true;

    switch (mode) {
      case _BadgeGlyphMode.lock:
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x3808396B);
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, cy - 3.5), width: 13, height: 13),
          math.pi,
          math.pi,
          false,
          paint,
        );
        paint.color = Colors.white;
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, cy - 5), width: 13, height: 13),
          math.pi,
          math.pi,
          false,
          paint,
        );
        paint
          ..style = PaintingStyle.fill
          ..color = const Color(0x3808396B);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy + 4.5),
              width: 19,
              height: 15,
            ),
            const Radius.circular(4),
          ),
          paint,
        );
        paint.color = Colors.white;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy + 3), width: 19, height: 15),
            const Radius.circular(4),
          ),
          paint,
        );
        paint.color = const Color(0xFF2D84D8);
        canvas.drawCircle(Offset(cx, cy + 2), 2.1, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy + 5.2),
              width: 2.4,
              height: 4.5,
            ),
            const Radius.circular(1.2),
          ),
          paint,
        );
        break;

      case _BadgeGlyphMode.check:
        final path = Path()
          ..moveTo(cx - 9.5, cy + 0.5)
          ..lineTo(cx - 2.5, cy + 7.5)
          ..lineTo(cx + 10.5, cy - 6.5);
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x3D073868);
        canvas.drawPath(path.shift(const Offset(0, 1.8)), paint);

        paint.color = Colors.white;
        canvas.drawPath(path, paint);
        break;

      case _BadgeGlyphMode.question:
        final tp = TextPainter(
          text: const TextSpan(
            text: '?',
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.0,
              color: Color(0xFF172763),
              shadows: [
                Shadow(
                  color: Color(0xAAFFFFFF),
                  offset: Offset(0, 1),
                  blurRadius: 0,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width * 0.5, cy - tp.height * 0.5));
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _BadgeGlyphPainter oldDelegate) =>
      oldDelegate.mode != mode;
}

/// 3D Reward Showcase inside the `"New Mechanic!"` Card (Panel 5):
/// Combines golden comic sun-ticks, custom 3D crystal Ice Cube / Booster pedestal, and stacked 3D Gold Coins.
class _RewardShowcaseGraphic extends StatelessWidget {
  final String? mechanicId;
  final double ambientPhase;

  const _RewardShowcaseGraphic({
    required this.mechanicId,
    required this.ambientPhase,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: const Size(224, 128),
          painter: _RewardShowcasePainter(
            drawCustomIceCube: mechanicId == 'ice',
            drawCoinTreasureOnly: mechanicId == null,
            ambientPhase: ambientPhase,
          ),
        ),
        if (mechanicId == 'pu_level_up')
          Transform.translate(
            offset: const Offset(-18, 2),
            child: Image.asset(
              'assets/images/PowerUp_LevelUp.png',
              width: 78,
              height: 78,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        if (mechanicId == 'pu_time_freeze')
          Transform.translate(
            offset: const Offset(-18, 2),
            child: Image.asset(
              'assets/images/PowerUp_TimeFreeze.png',
              width: 78,
              height: 78,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }
}

class _RewardShowcasePainter extends CustomPainter {
  final bool drawCustomIceCube;
  final bool drawCoinTreasureOnly;
  final double ambientPhase;

  const _RewardShowcasePainter({
    required this.drawCustomIceCube,
    required this.drawCoinTreasureOnly,
    required this.ambientPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.54;
    final paint = Paint()..isAntiAlias = true;

    // 1. Soft sky-gold radial glow behind the reward
    paint
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        66,
        const [
          Color(0x88FFF8E1),
          Color(0x44B3E5FC),
          Color(0x00B3E5FC),
        ],
        const [0.0, 0.58, 1.0],
      );
    canvas.drawCircle(Offset(cx, cy), 66, paint);
    paint.shader = null;

    // 2. Golden Comic Celebration Ticks (Left & Right arcs like Panel 5!)
    final pulse = 1.0 + 0.07 * math.sin(ambientPhase * 2.0);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFCA28);

    const rayAngles = <double>[
      -2.62,
      -2.25,
      -1.88,
      -1.26,
      -0.89,
      -0.52,
    ];
    for (final a in rayAngles) {
      final r1 = 55.0 * pulse;
      final r2 = 69.0 * pulse;
      canvas.drawLine(
        Offset(cx + r1 * math.cos(a), cy - 4 + r1 * math.sin(a) * 0.82),
        Offset(cx + r2 * math.cos(a), cy - 4 + r2 * math.sin(a) * 0.82),
        paint,
      );
    }

    // Ground soft shadow
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x241B2B65);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 40), width: 136, height: 18),
      paint,
    );

    // 3. Isometric 3D Translucent Faceted Ice Cube Block (Matches Panel 5 1:1!)
    if (drawCustomIceCube) {
      _draw3DIceBlock(canvas, Offset(cx - 18, cy + 2));
    }

    // 4. Gleaming 3D Stacked Gold Coins beside the mechanic (or center treasure pile)
    if (drawCoinTreasureOnly) {
      _drawCoinStack(canvas, Offset(cx - 22, cy + 20), count: 3, radius: 17);
      _drawCoinStack(canvas, Offset(cx + 18, cy + 16), count: 4, radius: 18);
      _drawCoinStack(canvas, Offset(cx - 2, cy + 28), count: 2, radius: 17);
    } else {
      _drawCoinStack(canvas, Offset(cx + 40, cy + 18), count: 3, radius: 16.0);
      _drawCoinStack(canvas, Offset(cx + 17, cy + 28), count: 2, radius: 15.5);
    }
  }

  void _draw3DIceBlock(Canvas canvas, Offset c) {
    final p = Paint()..isAntiAlias = true;
    final path = Path();

    final top = Offset(c.dx, c.dy - 36);
    final midL = Offset(c.dx - 34, c.dy - 19);
    final midR = Offset(c.dx + 34, c.dy - 19);
    final midF = Offset(c.dx, c.dy - 2);
    final botL = Offset(c.dx - 33, c.dy + 21);
    final botR = Offset(c.dx + 33, c.dy + 21);
    final botF = Offset(c.dx, c.dy + 38);

    // Top diamond facet
    path
      ..reset()
      ..moveTo(top.dx, top.dy)
      ..lineTo(midR.dx, midR.dy)
      ..lineTo(midF.dx, midF.dy)
      ..lineTo(midL.dx, midL.dy)
      ..close();
    p
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        top,
        midF,
        const [Color(0xFFEFFCFF), Color(0xFF8BE8FF)],
      );
    canvas.drawPath(path, p);

    // Left facet
    path
      ..reset()
      ..moveTo(midL.dx, midL.dy)
      ..lineTo(midF.dx, midF.dy)
      ..lineTo(botF.dx, botF.dy)
      ..lineTo(botL.dx, botL.dy)
      ..close();
    p
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        midL,
        botF,
        const [Color(0xFF72E2FF), Color(0xFF28AAE8)],
      );
    canvas.drawPath(path, p);

    // Right facet
    path
      ..reset()
      ..moveTo(midF.dx, midF.dy)
      ..lineTo(midR.dx, midR.dy)
      ..lineTo(botR.dx, botR.dy)
      ..lineTo(botF.dx, botF.dy)
      ..close();
    p
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        midR,
        botF,
        const [Color(0xFF47C8F5), Color(0xFF1380C9)],
      );
    canvas.drawPath(path, p);
    p.shader = null;

    // Diagonal frost shine streaks
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x8CFFFFFF);
    canvas.drawLine(
      Offset(c.dx - 24, c.dy - 6),
      Offset(c.dx - 11, c.dy + 16),
      p,
    );
    canvas.drawLine(
      Offset(c.dx + 12, c.dy - 2),
      Offset(c.dx + 23, c.dy + 14),
      p,
    );

    // Specular crystal bevel edges
    p
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xEEFFFFFF);
    canvas.drawLine(midL, midF, p);
    canvas.drawLine(midF, midR, p);
    canvas.drawLine(midF, botF, p);

    path
      ..reset()
      ..moveTo(top.dx, top.dy)
      ..lineTo(midR.dx, midR.dy)
      ..lineTo(botR.dx, botR.dy)
      ..lineTo(botF.dx, botF.dy)
      ..lineTo(botL.dx, botL.dy)
      ..lineTo(midL.dx, midL.dy)
      ..close();
    p
      ..strokeWidth = 2.2
      ..color = const Color(0xCC58C8F2);
    canvas.drawPath(path, p);
  }

  void _drawCoinStack(
    Canvas canvas,
    Offset baseCenter, {
    required int count,
    required double radius,
  }) {
    final p = Paint()..isAntiAlias = true;
    final hOval = radius * 0.56;
    const stepY = 5.5;

    for (int i = 0; i < count; i++) {
      final cy = baseCenter.dy - i * stepY;
      final sideRect = Rect.fromCenter(
        center: Offset(baseCenter.dx, cy + 2.6),
        width: radius * 2,
        height: hOval * 2,
      );
      p
        ..style = PaintingStyle.fill
        ..shader = null
        ..color = const Color(0xFFD97706);
      canvas.drawOval(sideRect, p);

      final topRect = Rect.fromCenter(
        center: Offset(baseCenter.dx, cy),
        width: radius * 2,
        height: hOval * 2,
      );
      p
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(baseCenter.dx - radius, cy - hOval),
          Offset(baseCenter.dx + radius, cy + hOval),
          const [
            Color(0xFFFFF59D),
            Color(0xFFFFCA28),
            Color(0xFFF59E0B),
          ],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawOval(topRect, p);
      p.shader = null;

      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xCCFFFDE7);
      canvas.drawOval(topRect.deflate(2.5), p);
    }
  }

  @override
  bool shouldRepaint(covariant _RewardShowcasePainter oldDelegate) =>
      oldDelegate.ambientPhase != ambientPhase ||
      oldDelegate.drawCustomIceCube != drawCustomIceCube;
}

/// Parametric 3D silhouette metrics for the 5 sculpted vase shapes.
class _VaseMetrics {
  final double topRimY;
  final double neckY;
  final double baseY;
  final double mouthHalfW;
  final double neckHalfW;
  final double bellyHalfW;
  final double baseHalfW;
  final double bellyYFrac;
  final double wallThickness;
  final double baseCushionH;

  const _VaseMetrics({
    required this.topRimY,
    required this.neckY,
    required this.baseY,
    required this.mouthHalfW,
    required this.neckHalfW,
    required this.bellyHalfW,
    required this.baseHalfW,
    required this.bellyYFrac,
    required this.wallThickness,
    required this.baseCushionH,
  });

  double get innerBaseY => baseY - baseCushionH;

  static _VaseMetrics forShape(VaseShapeType type, double centerY) {
    return switch (type) {
      // Plump spherical blown-glass fishbowl orb
      VaseShapeType.fishbowl => _VaseMetrics(
          topRimY: centerY - 76,
          neckY: centerY - 52,
          baseY: centerY + 112,
          mouthHalfW: 64,
          neckHalfW: 54,
          bellyHalfW: 112,
          baseHalfW: 60,
          bellyYFrac: 0.50,
          wallThickness: 5.8,
          baseCushionH: 13.5,
        ),
      // Graceful pearl-azure translucent teardrop amphora-urn
      VaseShapeType.ovalCeramic => _VaseMetrics(
          topRimY: centerY - 74,
          neckY: centerY - 48,
          baseY: centerY + 116,
          mouthHalfW: 54,
          neckHalfW: 41,
          bellyHalfW: 98,
          baseHalfW: 53,
          bellyYFrac: 0.54,
          wallThickness: 6.0,
          baseCushionH: 15.0,
        ),
      // Baroque melon-ribbed fluted crystal carafe
      VaseShapeType.flutedCrystal => _VaseMetrics(
          topRimY: centerY - 78,
          neckY: centerY - 50,
          baseY: centerY + 116,
          mouthHalfW: 58,
          neckHalfW: 43,
          bellyHalfW: 108,
          baseHalfW: 56,
          bellyYFrac: 0.50,
          wallThickness: 5.8,
          baseCushionH: 14.5,
        ),
      // Regal high-shouldered slender amphora with flared base foot
      VaseShapeType.royalTall => _VaseMetrics(
          topRimY: centerY - 92,
          neckY: centerY - 62,
          baseY: centerY + 118,
          mouthHalfW: 49,
          neckHalfW: 31,
          bellyHalfW: 86,
          baseHalfW: 48,
          bellyYFrac: 0.28,
          wallThickness: 6.0,
          baseCushionH: 17.0,
        ),
      // Geometric faceted lotus-cut crystal chalice
      VaseShapeType.prismLotus => _VaseMetrics(
          topRimY: centerY - 75,
          neckY: centerY - 49,
          baseY: centerY + 116,
          mouthHalfW: 58,
          neckHalfW: 41,
          bellyHalfW: 104,
          baseHalfW: 52,
          bellyYFrac: 0.44,
          wallThickness: 6.5,
          baseCushionH: 16.0,
        ),
    };
  }

  /// Single geometric source of truth for the outer radius of any vase cross-section at `y`.
  double outerHalfWidthAt(double y, VaseShapeType type) {
    if (y <= neckY) {
      final tNeck = ((y - topRimY) / math.max(1.0, neckY - topRimY)).clamp(
        0.0,
        1.0,
      );
      final flare = 0.5 + 0.5 * math.cos(tNeck * math.pi);
      return ui.lerpDouble(neckHalfW, mouthHalfW, flare)!;
    }

    final t = ((y - neckY) / math.max(1.0, baseY - neckY)).clamp(0.0, 1.0);

    if (type == VaseShapeType.prismLotus) {
      if (t < 0.28) {
        return ui.lerpDouble(neckHalfW, bellyHalfW * 0.90, t / 0.28)!;
      } else if (t < 0.48) {
        return ui.lerpDouble(
          bellyHalfW * 0.90,
          bellyHalfW,
          (t - 0.28) / 0.20,
        )!;
      } else if (t < 0.74) {
        return ui.lerpDouble(
          bellyHalfW,
          bellyHalfW * 0.80,
          (t - 0.48) / 0.26,
        )!;
      } else {
        return ui.lerpDouble(
          bellyHalfW * 0.80,
          baseHalfW,
          (t - 0.74) / 0.26,
        )!;
      }
    }

    if (type == VaseShapeType.fishbowl) {
      // True spherical arc `sqrt(1 - u^2)` between truncated top (`-0.875`) and bottom (`+0.845`)
      // with a gentle C1 collar blend in the top 5% so the mouth meets the orb without pinching.
      final p = bellyYFrac;
      final u = t <= p
          ? -0.875 * (1.0 - (t / p).clamp(0.0, 1.0))
          : 0.845 * ((t - p) / math.max(0.01, 1.0 - p)).clamp(0.0, 1.0);
      final orbW = bellyHalfW * math.sqrt((1.0 - u * u).clamp(0.0, 1.0));
      if (t < 0.055) {
        final k = Curves.easeInOutSine.transform((t / 0.055).clamp(0.0, 1.0));
        return ui.lerpDouble(neckHalfW, orbW, k)!;
      }
      return orbW;
    }

    final p = bellyYFrac;
    if (type == VaseShapeType.ovalCeramic || type == VaseShapeType.flutedCrystal) {
      final normU = t <= p
          ? 0.5 * (t / p).clamp(0.0, 1.0)
          : 0.5 + 0.5 * ((t - p) / math.max(0.01, 1.0 - p)).clamp(0.0, 1.0);
      final bulge = math.pow(
        math.sin(normU * math.pi).clamp(0.0, 1.0),
        0.74,
      ).toDouble();
      final edgeW = ui.lerpDouble(neckHalfW, baseHalfW, t)!;
      final rawW = ui.lerpDouble(edgeW, bellyHalfW, bulge)!;
      if (t < 0.05) {
        final k = Curves.easeInOutSine.transform((t / 0.05).clamp(0.0, 1.0));
        return ui.lerpDouble(neckHalfW, rawW, k)!;
      }
      return rawW;
    }

    final easedT = t <= p
        ? 0.5 * Curves.easeInOutSine.transform((t / p).clamp(0.0, 1.0))
        : 0.5 +
              0.5 *
                  Curves.easeInOutSine.transform(
                    ((t - p) / math.max(0.01, 1.0 - p)).clamp(0.0, 1.0),
                  );
    final bulge = math.sin(easedT * math.pi);

    final edgeW = ui.lerpDouble(neckHalfW, baseHalfW, t)!;
    final rawW = ui.lerpDouble(edgeW, bellyHalfW, bulge)!;

    if (type == VaseShapeType.royalTall && t > 0.86) {
      final footT = ((t - 0.86) / 0.14).clamp(0.0, 1.0);
      return rawW + 5.5 * Curves.easeOutCubic.transform(footT);
    }
    return rawW;
  }

  /// Half-width of the interior chamber at height `y`, matching the exact wall thickness.
  double innerHalfWidthAt(double y, VaseShapeType type) {
    return math.max(15.0, outerHalfWidthAt(y, type) - wallThickness);
  }

  /// Perspective vertical radius (semi-minor axis) for horizontal 3D ellipses inside the vase.
  double ellipseHalfHeight(double halfW) => (halfW * 0.23).clamp(8.5, 25.0);
}

class _GlassPalette {
  final Color edgeDark;
  final Color edgeMid;
  final Color coreTint;
  final Color innerTint;
  final Color rimHighlight;
  final Color accentTint;

  const _GlassPalette({
    required this.edgeDark,
    required this.edgeMid,
    required this.coreTint,
    required this.innerTint,
    required this.rimHighlight,
    required this.accentTint,
  });

  static _GlassPalette forShape(VaseShapeType type) {
    return switch (type) {
      VaseShapeType.fishbowl => const _GlassPalette(
          edgeDark: Color(0xCC0D5A88),
          edgeMid: Color(0x883CC4EC),
          coreTint: Color(0x28D6FBFF),
          innerTint: Color(0x6494ECFF),
          rimHighlight: Color(0xEEECFEFF),
          accentTint: Color(0xFF80EEFF),
        ),
      VaseShapeType.ovalCeramic => const _GlassPalette(
          edgeDark: Color(0xDE0B6478),
          edgeMid: Color(0xA63ED4CA),
          coreTint: Color(0x3CDDFDFB),
          innerTint: Color(0x7AA6F9EE),
          rimHighlight: Color(0xF0FFF8E6),
          accentTint: Color(0xFF7AF2DD),
        ),
      VaseShapeType.flutedCrystal => const _GlassPalette(
          edgeDark: Color(0xCC284B9E),
          edgeMid: Color(0x8E56B4F9),
          coreTint: Color(0x2CEEF8FF),
          innerTint: Color(0x6CBBE8FF),
          rimHighlight: Color(0xF2F4FBFF),
          accentTint: Color(0xFF9ED5FF),
        ),
      VaseShapeType.royalTall => const _GlassPalette(
          edgeDark: Color(0xCC13548E),
          edgeMid: Color(0x8C42C8E8),
          coreTint: Color(0x2CFFF9E8),
          innerTint: Color(0x6CA4EFFF),
          rimHighlight: Color(0xF4FFF2CE),
          accentTint: Color(0xFFFFE08A),
        ),
      VaseShapeType.prismLotus => const _GlassPalette(
          edgeDark: Color(0xCC3B3B98),
          edgeMid: Color(0x9050D6FF),
          coreTint: Color(0x2CF0ECFF),
          innerTint: Color(0x6AC6D8FF),
          rimHighlight: Color(0xF2F7F0FF),
          accentTint: Color(0xFFD0A8FF),
        ),
    };
  }
}

/// Zero-Allocation Master 3D Painter for the Garden Stage (`380 x 448` virtual canvas):
/// Renders in strict physical back-to-front 3D order for authentic glass/water/stem refraction.
class _WaterGardenMasterPainter extends CustomPainter {
  final VaseMilestoneConfig config;
  final double oldWaterProgress;
  final double waterProgress;
  final double jarEnterProgress;
  final double pourProgress;
  final double jarExitProgress;
  final double bloomProgress;
  final double raysProgress;
  final int finalBlockNumber;
  final double ambientPhase;
  final bool is100Percent;
  final bool isNewVaseReveal;
  final double newVaseSparkleT;
  final int spriteVersion;

  static final Path _vaseOuterPath = Path();
  static final Path _vaseInnerPath = Path();
  static final Path _scratchPath = Path();
  static final Path _petalPath = Path();
  static final Map<String, ({Path softboxBand, Path leftGlint, Path rightBounce})>
      _frontGlassPathsCache =
      <String, ({Path softboxBand, Path leftGlint, Path rightBounce})>{};
  static final Paint _paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium;
  static final Paint _fxPaint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.medium;
  static final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  _WaterGardenMasterPainter({
    required this.config,
    required this.oldWaterProgress,
    required this.waterProgress,
    required this.jarEnterProgress,
    required this.pourProgress,
    required this.jarExitProgress,
    required this.bloomProgress,
    required this.raysProgress,
    required this.finalBlockNumber,
    required this.ambientPhase,
    required this.is100Percent,
    required this.isNewVaseReveal,
    required this.newVaseSparkleT,
    required this.spriteVersion,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paint
      ..color = Colors.white
      ..shader = null
      ..maskFilter = null
      ..filterQuality = FilterQuality.medium
      ..blendMode = BlendMode.srcOver
      ..style = PaintingStyle.fill;
    _fxPaint
      ..color = Colors.white
      ..shader = null
      ..maskFilter = null
      ..filterQuality = FilterQuality.medium
      ..blendMode = BlendMode.srcOver
      ..style = PaintingStyle.fill;

    final cx = size.width * 0.5;
    final cy = size.height * 0.630;
    final metrics = _VaseMetrics.forShape(config.shapeType, cy);

    // 0. Celebration Sunburst God-Rays & Shockwave behind the vase
    if (raysProgress > 0.01) {
      _drawCelebrationSunburst(
        canvas,
        Offset(cx, metrics.topRimY - 34),
        raysProgress,
      );
    }

    // 1. Multi-Tier 3D Cream-Marble & Gold Plinth + Refracted Cyan Water Caustics
    _drawPedestal(
      canvas,
      cx: cx,
      topSurfaceY: metrics.baseY + 2,
      baseHalfW: metrics.baseHalfW,
      causticIntensity: waterProgress.clamp(0.0, 1.0),
    );

    // Build synchronized outer & inner 3D sculpted vase contours
    _buildVaseSilhouettePath(
      _vaseOuterPath,
      cx: cx,
      m: metrics,
      type: config.shapeType,
      isInner: false,
    );
    _buildVaseSilhouettePath(
      _vaseInnerPath,
      cx: cx,
      m: metrics,
      type: config.shapeType,
      isInner: true,
    );

    // Compute live rising water surface Y inside the inner chamber
    final clampedFill = waterProgress.clamp(0.0, 1.0);
    final maxFillTopY = metrics.neckY + 11.0;
    final minFillBottomY = metrics.innerBaseY - 4.0;
    final waterTopY =
        ui.lerpDouble(minFillBottomY, maxFillTopY, clampedFill)!;

    // 2. Back Fresnel Crystal Glass Wall, Recessed Throat Bowl & Heavy Crystal Base Cushion
    _drawBackGlassWall(canvas, cx, metrics, config.shapeType);

    // 3. Underwater Refracted Stem Segment (drawn behind the water volume)
    _drawUnderwaterStems(
      canvas: canvas,
      cx: cx,
      metrics: metrics,
      waterTopY: waterTopY,
      hasWater: clampedFill > 0.02,
      bloomFraction: bloomProgress,
    );

    // Progressive waterfall stream envelope (`headT` drops first, `tailT` detaches at finish)
    final isStreamActive = pourProgress > 0.005 && pourProgress < 0.995;
    final streamHeadT = (pourProgress / 0.14).clamp(0.0, 1.0);
    final streamTailT = ((pourProgress - 0.86) / 0.14).clamp(0.0, 1.0);
    final isStreamTouchingWater =
        isStreamActive && streamHeadT >= 0.92 && streamTailT < 0.95;

    // 4. Zero-Seam Volumetric 3D Water Body + Perspective Elliptical Meniscus + Caustics + Bubbles
    _drawVolumetricWater(
      canvas: canvas,
      cx: cx,
      metrics: metrics,
      type: config.shapeType,
      fillFraction: clampedFill,
      waterTopY: waterTopY,
      isStreamImpacting: isStreamTouchingWater,
      pourT: pourProgress,
    );

    // 5. Above-Water Botanical Stems, Curled Two-Tone Leaves & 3D Buds / Blossoms
    _drawAboveWaterBotanicals(
      canvas: canvas,
      cx: cx,
      metrics: metrics,
      waterTopY: waterTopY,
      hasWater: clampedFill > 0.02,
      waterFraction: clampedFill,
      bloomFraction: bloomProgress,
      flowerType: config.flowerType,
    );

    // 6. Parabolic Trajectory of 3D Mini Potion Jar & Progressive Waterfall Stream
    final enterT = jarEnterProgress.clamp(0.0, 1.0);
    final exitT = jarExitProgress.clamp(0.0, 1.0);
    final jarVisibility = (enterT * (1.0 - exitT)).clamp(0.0, 1.0);

    final targetJarPos = Offset(cx - 93, metrics.topRimY - 47);
    final startJarPos = Offset(cx - 156, metrics.topRimY - 94);
    final enterArcLift = -22.0 * math.sin(enterT * math.pi);
    final hoverBob = 2.4 * math.sin(ambientPhase * 2.0);
    final baseJarPos = Offset(
      ui.lerpDouble(startJarPos.dx, targetJarPos.dx, enterT)! - exitT * 42.0,
      ui.lerpDouble(startJarPos.dy, targetJarPos.dy, enterT)! +
          enterArcLift +
          hoverBob -
          exitT * 34.0,
    );

    final pourTiltWeight =
        (Curves.easeInOutCubic.transform((enterT - 0.25).clamp(0.0, 0.75) / 0.75) *
                (1.0 - Curves.easeInCubic.transform(exitT)))
            .clamp(0.0, 1.0);
    final jarTiltRad = ui.lerpDouble(0.22, 1.02, pourTiltWeight)!;

    if (isStreamActive && jarVisibility > 0.12) {
      _drawProgressiveWaterfallAndSplash(
        canvas: canvas,
        jarCenter: baseJarPos,
        jarTiltRad: jarTiltRad,
        vaseMouthCenter: Offset(cx - 4, metrics.topRimY + 3),
        waterImpactPt: Offset(
          cx + 2,
          clampedFill > 0.03 ? waterTopY : (metrics.innerBaseY - 8),
        ),
        headT: streamHeadT,
        tailT: streamTailT,
        pourT: pourProgress,
      );
    }

    // 7. Front Crystal Glass Wall, Flutes/Facets, Gold Rim Band & Specular Highlights
    _drawFrontGlassOverlay(
      canvas,
      cx,
      metrics,
      config.shapeType,
      hasWater: clampedFill > 0.02,
    );

    // 8. Tilted 3D Mini Crystal Potion Jar + Gravity-Level Liquid + Golden Rope + Tag
    if (jarVisibility > 0.02) {
      _drawTiltedMiniPotionJar(
        canvas: canvas,
        jarCenter: baseJarPos,
        tiltRad: jarTiltRad,
        visibility: jarVisibility,
        pourT: pourProgress,
        enterT: enterT,
        numberText: '$finalBlockNumber',
      );
    }

    // 9. Magic Bloom Burst FX, Tumbling Real Petals, Butterflies & Starlight Sparkles
    if (bloomProgress > 0.14) {
      _drawFloatingPetalsAndSparkles(
        canvas: canvas,
        cx: cx,
        topY: metrics.topRimY - 24,
        intensity: ((bloomProgress - 0.14) / 0.86).clamp(0.0, 1.0),
        bloomProgress: bloomProgress,
        flowerType: config.flowerType,
      );
    } else if (isNewVaseReveal && newVaseSparkleT < 0.98) {
      _drawNewVaseRevealSparkles(
        canvas: canvas,
        cx: cx,
        cy: cy,
        t: newVaseSparkleT,
      );
    }
  }

  void _drawCelebrationSunburst(
    Canvas canvas,
    Offset center,
    double progress,
  ) {
    final p = progress.clamp(0.0, 1.0);
    const maxR = 205.0;
    final raysImg = _GardenFlowerSpriteCache.instance.bloomRays;

    _fxPaint
      ..blendMode = BlendMode.plus
      ..maskFilter = null
      ..shader = ui.Gradient.radial(
        center,
        maxR,
        [
          const Color(0xFFFFF8C4).withValues(alpha: 0.44 * p),
          const Color(0xFFFFD86B).withValues(alpha: 0.18 * p),
          const Color(0xFF4FF6FF).withValues(alpha: 0.08 * p),
          const Color(0x004FF6FF),
        ],
        const [0.0, 0.36, 0.72, 1.0],
      );
    canvas.drawCircle(center, maxR, _fxPaint);

    if (raysImg != null) {
      final pulse = 0.96 + 0.06 * math.sin(ambientPhase * 1.5);
      final dstHalf = 195.0 * Curves.easeOutCubic.transform(p) * pulse;
      _fxPaint
        ..shader = null
        ..color = Colors.white.withValues(alpha: (0.82 * p).clamp(0.0, 1.0))
        ..blendMode = BlendMode.plus;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(ambientPhase * 0.20);
      canvas.drawImageRect(
        raysImg,
        Rect.fromLTWH(0, 0, raysImg.width.toDouble(), raysImg.height.toDouble()),
        Rect.fromCenter(
          center: Offset.zero,
          width: dstHalf * 2.0,
          height: dstHalf * 2.0,
        ),
        _fxPaint,
      );
      canvas.restore();
    } else {
      const rayCount = 14;
      final rot = ambientPhase * 0.22;
      _fxPaint.maskFilter = null;
      for (int i = 0; i < rayCount; i++) {
        final a = (i * math.pi * 2.0) / rayCount + rot;
        final isMajor = i.isEven;
        final halfSpan = isMajor ? 0.088 : 0.042;
        final rayR = isMajor ? maxR : maxR * 0.82;
        _scratchPath
          ..reset()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + rayR * math.cos(a - halfSpan),
            center.dy + rayR * math.sin(a - halfSpan),
          )
          ..lineTo(
            center.dx + rayR * math.cos(a + halfSpan),
            center.dy + rayR * math.sin(a + halfSpan),
          )
          ..close();

        _fxPaint.shader = ui.Gradient.radial(
          center,
          rayR,
          [
            (isMajor ? const Color(0xFFFFF8D2) : const Color(0xFF9DF8FF))
                .withValues(alpha: (isMajor ? 0.34 : 0.22) * p),
            const Color(0x00FFFDE7),
          ],
        );
        canvas.drawPath(_scratchPath, _fxPaint);
      }
    }

    if (p > 0.05 && p < 0.88) {
      final ringT = Curves.easeOutCubic.transform((p / 0.88).clamp(0.0, 1.0));
      final ringR = ui.lerpDouble(42.0, 188.0, ringT)!;
      final baseRingAlpha = (0.48 * (1.0 - ringT)).clamp(0.0, 1.0);
      _fxPaint
        ..style = PaintingStyle.stroke
        ..shader = null
        ..maskFilter = null
        ..strokeWidth = 9.0 * (1.0 - ringT)
        ..color = const Color(0xFFFFF4B8).withValues(alpha: baseRingAlpha * 0.38);
      canvas.drawCircle(center, ringR, _fxPaint);
      _fxPaint
        ..strokeWidth = 4.5 * (1.0 - ringT)
        ..color = const Color(0xFFFFF4B8).withValues(alpha: baseRingAlpha);
      canvas.drawCircle(center, ringR, _fxPaint);
    }

    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..blendMode = BlendMode.srcOver;
  }

  void _drawPedestal(
    Canvas canvas, {
    required double cx,
    required double topSurfaceY,
    required double baseHalfW,
    required double causticIntensity,
  }) {
    const deckW = 224.0;
    const deckH = 36.0;
    const upperWallH = 11.0;
    const goldBandH = 4.5;
    const footW = 248.0;
    const footH = 40.0;
    const footWallH = 9.0;

    final deckTopY = topSurfaceY;
    final goldTopY = deckTopY + upperWallH;
    final footTopY = goldTopY + goldBandH;

    // 1. Soft Stage Floor Drop Shadow (feathered concentric ovals, zero MaskFilter.blur!)
    final floorShadowCenter = Offset(cx, footTopY + footWallH + 6);
    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = const Color(0x34030114);
    canvas.drawOval(
      Rect.fromCenter(
        center: floorShadowCenter,
        width: footW + 36,
        height: footH + 18,
      ),
      _fxPaint,
    );
    _fxPaint.color = const Color(0x6C030114);
    canvas.drawOval(
      Rect.fromCenter(
        center: floorShadowCenter,
        width: footW + 18,
        height: footH + 8,
      ),
      _fxPaint,
    );

    // 2. Lower Marble Base Foot Tier (3D shaded cylinder)
    final footBottomRect = Rect.fromCenter(
      center: Offset(cx, footTopY + footWallH),
      width: footW,
      height: footH,
    );
    final footTopRect = Rect.fromCenter(
      center: Offset(cx, footTopY),
      width: footW,
      height: footH,
    );
    final footSideRect = Rect.fromLTRB(
      cx - footW * 0.5,
      footTopY,
      cx + footW * 0.5,
      footTopY + footWallH,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - footW * 0.5, footTopY),
        Offset(cx + footW * 0.5, footTopY),
        const [
          Color(0xFF9A866A),
          Color(0xFFE7DBC5),
          Color(0xFFD0C0A4),
          Color(0xFF7D694D),
        ],
        const [0.0, 0.30, 0.68, 1.0],
      );
    canvas.drawOval(footBottomRect, _paint);
    canvas.drawRect(footSideRect, _paint);
    canvas.drawOval(footTopRect, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x704E3B20);
    canvas.drawArc(footBottomRect, 0.08, math.pi - 0.16, false, _paint);

    // 3. Beveled Antique Brushed-Gold Waist Band
    final goldBottomRect = Rect.fromCenter(
      center: Offset(cx, goldTopY + goldBandH),
      width: deckW + 6,
      height: deckH + 2,
    );
    final goldSideRect = Rect.fromLTRB(
      cx - (deckW + 6) * 0.5,
      goldTopY,
      cx + (deckW + 6) * 0.5,
      goldTopY + goldBandH,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - (deckW + 6) * 0.5, goldTopY),
        Offset(cx + (deckW + 6) * 0.5, goldTopY),
        const [
          Color(0xFF8C6214),
          Color(0xFFF6D978),
          Color(0xFFFFF6C9),
          Color(0xFFD1962E),
          Color(0xFF754E0C),
        ],
        const [0.0, 0.28, 0.44, 0.72, 1.0],
      );
    canvas.drawOval(goldBottomRect, _paint);
    canvas.drawRect(goldSideRect, _paint);
    _paint.shader = null;

    // 4. Upper Sunlit Ivory-Marble Drum & Top Deck
    final deckBottomRect = Rect.fromCenter(
      center: Offset(cx, goldTopY),
      width: deckW,
      height: deckH,
    );
    final deckSideRect = Rect.fromLTRB(
      cx - deckW * 0.5,
      deckTopY,
      cx + deckW * 0.5,
      goldTopY,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - deckW * 0.5, deckTopY),
        Offset(cx + deckW * 0.5, deckTopY),
        const [
          Color(0xFFBBA98E),
          Color(0xFFF6EFE0),
          Color(0xFFE0D4BD),
          Color(0xFF9F8B6D),
        ],
        const [0.0, 0.30, 0.68, 1.0],
      );
    canvas.drawOval(deckBottomRect, _paint);
    canvas.drawRect(deckSideRect, _paint);

    final topRect = Rect.fromCenter(
      center: Offset(cx, deckTopY),
      width: deckW,
      height: deckH,
    );
    _paint.shader = ui.Gradient.radial(
      Offset(cx - 22, deckTopY - 4),
      deckW * 0.62,
      const [
        Color(0xFFFFFEFA),
        Color(0xFFF5EAD6),
        Color(0xFFE3D3B7),
      ],
      const [0.0, 0.60, 1.0],
    );
    canvas.drawOval(topRect, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - deckW * 0.45, deckTopY - deckH * 0.4),
        Offset(cx + deckW * 0.45, deckTopY + deckH * 0.4),
        const [
          Color(0xEEFFFFFF),
          Color(0xAAFFF5DD),
          Color(0x55B89E7C),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawOval(topRect.deflate(1.2), _paint);
    _paint.shader = null;

    // 5. Soft Vase Contact AO + Dual-Lobe Refracted Cyan Caustic Glow
    final footBaseW = baseHalfW * 2.15;
    final contactCenter = Offset(cx, deckTopY + 1.5);
    _fxPaint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..color = const Color(0x2806283D);
    canvas.drawOval(
      Rect.fromCenter(
        center: contactCenter,
        width: footBaseW + 24,
        height: 25,
      ),
      _fxPaint,
    );
    _fxPaint.color = const Color(0x4E06283D);
    canvas.drawOval(
      Rect.fromCenter(
        center: contactCenter,
        width: footBaseW + 12,
        height: 17,
      ),
      _fxPaint,
    );

    if (causticIntensity > 0.02) {
      final shimmer = 0.88 + 0.12 * math.sin(ambientPhase * 2.4);
      final caustAlpha = causticIntensity * shimmer;
      _paint
        ..style = PaintingStyle.fill
        ..color = Colors.white
        ..shader = ui.Gradient.radial(
          Offset(cx + 8, deckTopY + 2.5),
          68,
          [
            const Color(0xFF72FAFF).withValues(alpha: 0.56 * caustAlpha),
            const Color(0xFF1EC8EE).withValues(alpha: 0.24 * caustAlpha),
            const Color(0x001EC8EE),
          ],
          const [0.0, 0.55, 1.0],
        );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 8, deckTopY + 2.5),
          width: footBaseW + 28,
          height: 21,
        ),
        _paint,
      );

      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..shader = null
        ..color = const Color(0xFFB4FFFF).withValues(alpha: 0.42 * caustAlpha);
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(cx + 10, deckTopY + 3),
          width: footBaseW + 6,
          height: 15,
        ),
        0.2,
        math.pi * 0.72,
        false,
        _paint,
      );
    }
  }

  /// Builds exact closed outer or inner chamber path by sampling `outerHalfWidthAt`
  /// so the glass wall, crystal base cushion, and water meniscus align with zero gap.
  void _buildVaseSilhouettePath(
    Path path, {
    required double cx,
    required _VaseMetrics m,
    required VaseShapeType type,
    required bool isInner,
  }) {
    path.reset();
    final topY = isInner ? (m.topRimY + 4.5) : m.topRimY;
    final bottomY = isInner ? m.innerBaseY : m.baseY;
    const steps = 56;
    final rightXs = List<double>.filled(steps + 1, 0.0);
    final rightYs = List<double>.filled(steps + 1, 0.0);

    for (int i = 0; i <= steps; i++) {
      final y = ui.lerpDouble(topY, bottomY - 5.0, i / steps)!;
      final hw = isInner
          ? m.innerHalfWidthAt(y, type)
          : m.outerHalfWidthAt(y, type);
      rightXs[i] = hw;
      rightYs[i] = y;
    }

    path.moveTo(cx - rightXs[0], rightYs[0]);
    for (int i = 1; i < steps; i++) {
      final mx = cx - (rightXs[i] + rightXs[i + 1]) * 0.5;
      final my = (rightYs[i] + rightYs[i + 1]) * 0.5;
      path.quadraticBezierTo(cx - rightXs[i], rightYs[i], mx, my);
    }
    path.lineTo(cx - rightXs[steps], rightYs[steps]);

    final botHW = rightXs[steps];
    final botY = rightYs[steps];
    final botCurveDepth = (botHW * 0.25).clamp(7.0, 15.0);
    path.cubicTo(
      cx - botHW * 0.72,
      bottomY + botCurveDepth,
      cx + botHW * 0.72,
      bottomY + botCurveDepth,
      cx + botHW,
      botY,
    );

    for (int i = steps - 1; i > 0; i--) {
      final mx = cx + (rightXs[i] + rightXs[i - 1]) * 0.5;
      final my = (rightYs[i] + rightYs[i - 1]) * 0.5;
      path.quadraticBezierTo(cx + rightXs[i], rightYs[i], mx, my);
    }
    path.lineTo(cx + rightXs[0], rightYs[0]);
    path.close();
  }

  void _drawBackGlassWall(
    Canvas canvas,
    double cx,
    _VaseMetrics m,
    VaseShapeType type,
  ) {
    final palette = _GlassPalette.forShape(type);

    // 1. Fresnel 3D Cylindrical Glass Back Shell
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - m.bellyHalfW, m.neckY),
        Offset(cx + m.bellyHalfW, m.neckY),
        [
          palette.edgeDark,
          palette.edgeMid,
          palette.coreTint,
          palette.coreTint,
          palette.edgeMid,
          palette.edgeDark,
        ],
        const [0.0, 0.14, 0.34, 0.66, 0.86, 1.0],
      );
    canvas.drawPath(_vaseOuterPath, _paint);
    _paint.shader = null;

    // 2. Heavy Solid Crystal Base Puck
    _drawCrystalBasePuck(canvas, cx, m, palette);

    // 3. Soft internal chamber rim line
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = palette.innerTint.withValues(alpha: 0.26);
    canvas.drawPath(_vaseInnerPath, _paint);

    // 4. Recessed Dark Mouth Interior Bowl + Back Rolled Glass Rim
    final rimEH = m.ellipseHalfHeight(m.mouthHalfW);
    final mouthCenter = Offset(cx, m.topRimY + 1.5);
    final rimRect = Rect.fromCenter(
      center: mouthCenter,
      width: m.mouthHalfW * 2.0,
      height: rimEH * 2.0,
    );

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, m.topRimY - rimEH),
        Offset(cx, m.topRimY + rimEH),
        [
          const Color(0x52052E4A),
          palette.edgeMid.withValues(alpha: 0.28),
        ],
      );
    canvas.drawOval(rimRect.deflate(2.5), _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = palette.rimHighlight.withValues(alpha: 0.62);
    canvas.drawArc(rimRect, math.pi, math.pi, false, _paint);

    _paint
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.82);
    canvas.drawArc(
      rimRect.deflate(1.2),
      math.pi + 0.18,
      math.pi - 0.36,
      false,
      _paint,
    );
  }

  /// Renders the thick solid refractive crystal puck at the bottom of the vase.
  void _drawCrystalBasePuck(
    Canvas canvas,
    double cx,
    _VaseMetrics m,
    _GlassPalette palette,
  ) {
    canvas.save();
    canvas.clipPath(_vaseOuterPath);

    final puckTopY = m.innerBaseY - 4.0;
    final puckRect = Rect.fromLTRB(
      cx - m.baseHalfW - 14,
      puckTopY,
      cx + m.baseHalfW + 14,
      m.baseY + 16,
    );

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, puckTopY),
        Offset(cx, m.baseY + 8),
        [
          const Color(0x0080EEFF),
          palette.innerTint.withValues(alpha: 0.65),
          palette.edgeDark.withValues(alpha: 0.78),
        ],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawRect(puckRect, _paint);

    final floorEH = m.ellipseHalfHeight(m.baseHalfW) * 0.82;
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..shader = null
      ..color = const Color(0xAAE2FDFF);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, m.innerBaseY),
        width: (m.baseHalfW - m.wallThickness) * 1.92,
        height: floorEH * 2.0,
      ),
      0.12,
      math.pi - 0.24,
      false,
      _paint,
    );

    canvas.restore();
  }

  /// Draws the submerged botanical stems with authentic Snell refraction jump at `waterTopY`.
  void _drawUnderwaterStems({
    required Canvas canvas,
    required double cx,
    required _VaseMetrics metrics,
    required double waterTopY,
    required bool hasWater,
    required double bloomFraction,
  }) {
    final usingSprites = _GardenFlowerSpriteCache.instance.hasStages(
      config.flowerType,
    );
    if (!hasWater) {
      canvas.save();
      canvas.clipPath(_vaseInnerPath);
      final fadeTop = metrics.topRimY + 6;
      final fadeBot = metrics.neckY + 22;
      final topX = usingSprites ? cx : cx + 5;
      final botX = usingSprites ? cx - 1.5 : cx + 2;
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(topX, fadeTop),
          Offset(botX, fadeBot),
          const [Color(0xCC359438), Color(0x00359438)],
        );
      canvas.drawLine(Offset(topX, fadeTop), Offset(botX, fadeBot), _paint);
      _paint.shader = null;
      canvas.restore();
      return;
    }

    canvas.save();
    canvas.clipPath(_vaseInnerPath);
    canvas.clipRect(
      Rect.fromLTRB(
        cx - metrics.bellyHalfW - 4,
        waterTopY,
        cx + metrics.bellyHalfW + 4,
        metrics.innerBaseY + 6,
      ),
    );

    const refractShift = 3.2;
    final stemBaseY = metrics.innerBaseY - 2.5;
    final neckMidY = metrics.topRimY + 6;
    final stemExitX = usingSprites
        ? cx
        : ui.lerpDouble(cx + 12, cx + 1, bloomFraction.clamp(0.0, 1.0))!;

    // When using real flower sprites, seamlessly connect the air-gap stem from vase rim down to waterTopY
    if (usingSprites && waterTopY > neckMidY + 2) {
      canvas.restore();
      canvas.save();
      canvas.clipPath(_vaseInnerPath);
      canvas.clipRect(
        Rect.fromLTRB(
          cx - metrics.mouthHalfW - 4,
          neckMidY,
          cx + metrics.mouthHalfW + 4,
          waterTopY + 1.5,
        ),
      );
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.4
        ..strokeCap = StrokeCap.round
        ..shader = null
        ..color = const Color(0xD82F943A);
      _scratchPath
        ..reset()
        ..moveTo(cx, neckMidY)
        ..quadraticBezierTo(
          cx + 1.2,
          (neckMidY + waterTopY) * 0.5,
          cx + refractShift * 0.4,
          waterTopY + 1.5,
        );
      canvas.drawPath(_scratchPath, _paint);
      canvas.restore();

      canvas.save();
      canvas.clipPath(_vaseInnerPath);
      canvas.clipRect(
        Rect.fromLTRB(
          cx - metrics.bellyHalfW - 4,
          waterTopY,
          cx + metrics.bellyHalfW + 4,
          metrics.innerBaseY + 6,
        ),
      );
    }

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(stemExitX, waterTopY),
        Offset(cx - 2 + refractShift, stemBaseY),
        const [
          Color(0xEA2EA45C),
          Color(0xDC238B54),
          Color(0xCA176D4A),
          Color(0xBC12563F),
        ],
        const [0.0, 0.45, 0.80, 1.0],
      );
    _scratchPath
      ..reset()
      ..moveTo(stemExitX + refractShift * 0.5, neckMidY)
      ..quadraticBezierTo(
        cx + 6 + refractShift,
        (neckMidY + stemBaseY) * 0.55,
        cx - 2 + refractShift,
        stemBaseY,
      );
    canvas.drawPath(_scratchPath, _paint);

    if (bloomFraction > 0.05) {
      final sideAlpha = bloomFraction.clamp(0.0, 1.0);
      _paint
        ..strokeWidth = 4.8
        ..shader = ui.Gradient.linear(
          Offset(cx, waterTopY),
          Offset(cx, stemBaseY),
          [
            const Color(0xDC26965B).withValues(alpha: 0.86 * sideAlpha),
            const Color(0xC0156448).withValues(alpha: 0.76 * sideAlpha),
          ],
        );

      _scratchPath
        ..reset()
        ..moveTo(cx - 8 + refractShift * 0.5, neckMidY)
        ..quadraticBezierTo(
          cx - 11 + refractShift,
          (neckMidY + stemBaseY) * 0.52,
          cx - 15 + refractShift,
          stemBaseY - 3.5,
        );
      canvas.drawPath(_scratchPath, _paint);

      _scratchPath
        ..reset()
        ..moveTo(cx + 9 + refractShift * 0.5, neckMidY)
        ..quadraticBezierTo(
          cx + 12 + refractShift,
          (neckMidY + stemBaseY) * 0.52,
          cx + 14 + refractShift,
          stemBaseY - 5.0,
        );
      canvas.drawPath(_scratchPath, _paint);
    }
    _paint.shader = null;
    canvas.restore();
  }

  /// Seamless 3D Volumetric Water Renderer:
  /// Eliminates polygon-vs-oval seam by bounding the water fill directly to the
  /// perspective 3D elliptical meniscus contour and adding Beer-Lambert depth + caustics.
  void _drawVolumetricWater({
    required Canvas canvas,
    required double cx,
    required _VaseMetrics metrics,
    required VaseShapeType type,
    required double fillFraction,
    required double waterTopY,
    required bool isStreamImpacting,
    required double pourT,
  }) {
    if (fillFraction <= 0.01) return;

    canvas.save();
    canvas.clipPath(_vaseInnerPath);

    final impactEnvelope = isStreamImpacting
        ? 1.0
        : (pourT >= 0.82 ? (1.0 - ((pourT - 0.82) / 0.18)).clamp(0.0, 1.0) : 0.0);
    final sloshTilt = 2.8 * impactEnvelope * math.sin(ambientPhase * 5.2);

    final meniscusHalfW = metrics.innerHalfWidthAt(waterTopY, type) + 0.8;
    final meniscusEH = metrics.ellipseHalfHeight(meniscusHalfW);
    final meniscusCenter = Offset(cx, waterTopY + sloshTilt * 0.25);
    final meniscusRect = Rect.fromCenter(
      center: meniscusCenter,
      width: meniscusHalfW * 2.0,
      height: meniscusEH * 2.0,
    );

    // 1. Seamless Water Body Fill bounded cleanly by the elliptical meniscus arc
    _scratchPath
      ..reset()
      ..moveTo(cx - meniscusHalfW, meniscusCenter.dy)
      ..arcTo(meniscusRect, math.pi, math.pi, false)
      ..lineTo(cx + metrics.bellyHalfW + 12, meniscusCenter.dy)
      ..lineTo(cx + metrics.bellyHalfW + 12, metrics.innerBaseY + 20)
      ..lineTo(cx - metrics.bellyHalfW - 12, metrics.innerBaseY + 20)
      ..lineTo(cx - metrics.bellyHalfW - 12, meniscusCenter.dy)
      ..close();

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, waterTopY - meniscusEH),
        Offset(cx, metrics.innerBaseY + 6),
        const [
          Color(0xD876FBFF),
          Color(0xE222B6E8),
          Color(0xEB0E78AF),
          Color(0xF5074B7D),
        ],
        const [0.0, 0.26, 0.68, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);

    // Lateral cylindrical Fresnel water shading
    _paint.shader = ui.Gradient.linear(
      Offset(cx - metrics.bellyHalfW, waterTopY),
      Offset(cx + metrics.bellyHalfW, waterTopY),
      const [
        Color(0x5288FFFF),
        Color(0x001CA8DC),
        Color(0x18042E4C),
        Color(0x4674F4FF),
      ],
      const [0.0, 0.22, 0.72, 1.0],
    );
    canvas.drawPath(_scratchPath, _paint);

    // 2. Animated Diagonal Underwater Caustic Light Ribbons
    for (int i = 0; i < 3; i++) {
      final offsetT = math.sin(ambientPhase * 1.4 + i * 2.1);
      final rx = cx + (-26.0 + i * 28.0) + offsetT * 8.0;
      _scratchPath
        ..reset()
        ..moveTo(rx - 12, waterTopY + 4)
        ..lineTo(rx + 6, waterTopY + 4)
        ..lineTo(rx - 18, metrics.innerBaseY + 4)
        ..lineTo(rx - 40, metrics.innerBaseY + 4)
        ..close();
      _paint.shader = ui.Gradient.linear(
        Offset(rx, waterTopY),
        Offset(rx - 22, metrics.innerBaseY),
        const [
          Color(0x36CCFFFF),
          Color(0x1450E8FF),
          Color(0x0050E8FF),
        ],
        const [0.0, 0.55, 1.0],
      );
      canvas.drawPath(_scratchPath, _paint);
    }

    // Internal bottom water-chamber glow pool
    _paint.shader = ui.Gradient.radial(
      Offset(cx + 4, metrics.innerBaseY - 4),
      metrics.baseHalfW * 1.25,
      const [
        Color(0x789EFFFF),
        Color(0x2832D4F4),
        Color(0x0032D4F4),
      ],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 4, metrics.innerBaseY - 4),
        width: metrics.baseHalfW * 2.0,
        height: 22,
      ),
      _paint,
    );
    _paint.shader = null;

    // 3. Effervescent 3D Glass Bubbles (plus turbulent splash-entry plunge plume)
    final waterDepth = math.max(20.0, metrics.innerBaseY - waterTopY);
    final normPhase = ambientPhase / (math.pi * 2.0);
    const bubbleCount = 16;
    for (int i = 0; i < bubbleCount; i++) {
      final seed = (i * 0.6180339887) % 1.0;
      final isPlumeBubble = isStreamImpacting && i >= 10;
      final cycle = (normPhase * (isPlumeBubble ? 2.4 : 1.0) + seed) % 1.0;
      final by = isPlumeBubble
          ? ui.lerpDouble(
              waterTopY + 6,
              math.min(metrics.innerBaseY - 8, waterTopY + waterDepth * 0.62),
              cycle,
            )!
          : ui.lerpDouble(metrics.innerBaseY - 6, waterTopY + 8, cycle)!;
      final localHalfW =
          math.max(12.0, metrics.innerHalfWidthAt(by, type) - 9.0);
      final laneOffset = isPlumeBubble
          ? (seed - 0.5) * 28.0 + math.sin(ambientPhase * 6.0 + i) * 4.5
          : (seed * 2.0 - 1.0) * localHalfW * 0.85 +
                math.sin(ambientPhase * 1.7 + i * 1.9) * 5.0;
      final bx = cx + laneOffset;
      final radius =
          (2.0 + (i % 4) * 1.05) * (0.72 + 0.28 * math.sin(cycle * math.pi));
      final alpha = math.sin(cycle * math.pi).clamp(0.0, 1.0);
      _drawGlossyBubble(canvas, Offset(bx, by), radius, alpha);
    }

    // 4. Unified Mirror-Luminous 3D Elliptical Surface Meniscus (zero seam!)
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        Offset(cx - meniscusHalfW * 0.20, meniscusCenter.dy - meniscusEH * 0.28),
        meniscusHalfW * 1.15,
        const [
          Color(0xEBEEFFFF),
          Color(0xCE9CF8FF),
          Color(0xD83AD4F4),
        ],
        const [0.0, 0.56, 1.0],
      );
    canvas.drawOval(meniscusRect, _paint);
    _paint.shader = null;

    if (impactEnvelope > 0.08) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.45 * impactEnvelope);
      final crestPath = _scratchPath..reset();
      const segs = 14;
      for (int i = 0; i <= segs; i++) {
        final f = i / segs;
        final x = ui.lerpDouble(
          cx - meniscusHalfW * 0.86,
          cx + meniscusHalfW * 0.86,
          f,
        )!;
        final y = meniscusCenter.dy +
            math.sin(f * math.pi * 2.6 + ambientPhase * 5.0) *
                2.0 *
                impactEnvelope;
        if (i == 0) {
          crestPath.moveTo(x, y);
        } else {
          crestPath.lineTo(x, y);
        }
      }
      canvas.drawPath(crestPath, _paint);
    }

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, meniscusCenter.dy - meniscusEH),
        Offset(cx, meniscusCenter.dy + meniscusEH),
        const [
          Color(0x88D8FFFF),
          Color(0xECFFFFFF),
        ],
      );
    canvas.drawOval(meniscusRect.deflate(0.7), _paint);
    _paint.shader = null;

    // 5. Concentric Elliptical Impact Ripples
    if (impactEnvelope > 0.05) {
      for (int r = 0; r < 3; r++) {
        final rippleT = ((normPhase * 3.2) + r * 0.33) % 1.0;
        final rw = meniscusHalfW * 1.72 * rippleT;
        final rh = meniscusEH * 1.65 * rippleT;
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1.0 - rippleT)
          ..color = Colors.white.withValues(
            alpha: (0.78 * (1.0 - rippleT) * impactEnvelope).clamp(0.0, 1.0),
          );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + 2, meniscusCenter.dy),
            width: rw,
            height: rh,
          ),
          _paint,
        );
      }
    }

    canvas.restore();
  }

  void _drawGlossyBubble(
    Canvas canvas,
    Offset center,
    double radius,
    double alphaScale,
  ) {
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = const Color(0xFF72EEFF).withValues(alpha: 0.28 * alphaScale);
    canvas.drawCircle(center, radius, _paint);

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..color = const Color(0xFFE8FFFF).withValues(alpha: 0.70 * alphaScale);
    canvas.drawCircle(center, radius, _paint);

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.94 * alphaScale);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.34, center.dy - radius * 0.34),
      radius * 0.33,
      _paint,
    );
  }

  /// Seamless, Zero-Hard-Cut 3D Botanical Renderer:
  /// - When `bloomFraction == 0.0`: renders the sculpted S-curved cylindrical stem,
  ///   2 asymmetrical twisted 3D leaves with lateral veins, and a 4-layer 3D Pink Tulip Bud!
  /// - As `bloomFraction` progresses `0.0 -> 1.0`:
  ///   the main stem smoothly straightens into the tall hero blossom while left & right
  ///   bouquet stems unfurl and all 3 buds open into lush 3D spherical-cup blossoms!
  void _drawAboveWaterBotanicals({
    required Canvas canvas,
    required double cx,
    required _VaseMetrics metrics,
    required double waterTopY,
    required bool hasWater,
    required double waterFraction,
    required double bloomFraction,
    required FlowerType flowerType,
  }) {
    if (_GardenFlowerSpriteCache.instance.hasStages(flowerType)) {
      _drawSpriteBotanicals(
        canvas: canvas,
        cx: cx,
        metrics: metrics,
        waterTopY: waterTopY,
        hasWater: hasWater,
        waterFraction: waterFraction,
        bloomFraction: bloomFraction,
        flowerType: flowerType,
      );
      return;
    }

    final sway = 0.032 * math.sin(ambientPhase);
    final upperClipTop = -160.0;
    final upperClipBottom = hasWater ? waterTopY : (metrics.topRimY + 10);
    final stemBaseY = math.min(upperClipBottom + 2, metrics.topRimY + 10);

    final tB = bloomFraction.clamp(0.0, 1.0);
    final centerMorph = Curves.easeOutCubic.transform(tB);

    final growthLift = 12.0 * waterFraction.clamp(0.0, 1.0);
    final preBloomBudPos = Offset(
      cx + 26.0 + 4.0 * math.sin(ambientPhase),
      metrics.topRimY - 46.0 - growthLift,
    );
    final fullBloomCenterPos = Offset(
      cx + 1.0 + 3.2 * math.sin(ambientPhase),
      metrics.topRimY - 82.0,
    );
    final centerPos = Offset.lerp(preBloomBudPos, fullBloomCenterPos, centerMorph)!;
    final primaryBaseX = ui.lerpDouble(cx + 11.0, cx + 1.0, centerMorph)!;
    final primaryCtrl = Offset.lerp(
      Offset(cx + 15.0, metrics.topRimY - 18.0),
      Offset(cx - 3.0, metrics.topRimY - 42.0),
      centerMorph,
    )!;

    // 1. Background Collar Leaves unfurling around the vase rim during bloom
    if (tB > 0.04) {
      final collarScale = Curves.easeOutBack
          .transform(((tB - 0.04) / 0.72).clamp(0.0, 1.0))
          .clamp(0.0, 1.15);
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx - 17, metrics.topRimY - 3),
        angle: -2.58 + sway,
        length: 42 * collarScale,
        width: 13.8,
        curlSign: -1.0,
      );
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx + 17, metrics.topRimY - 3),
        angle: -0.54 + sway,
        length: 42 * collarScale,
        width: 13.8,
        curlSign: 1.0,
      );
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx - 7, metrics.topRimY - 22),
        angle: -2.06 + sway,
        length: 37 * collarScale,
        width: 12.2,
        curlSign: -1.0,
      );
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx + 8, metrics.topRimY - 20),
        angle: -1.06 + sway,
        length: 37 * collarScale,
        width: 12.2,
        curlSign: 1.0,
      );
    }

    // Helper for true cylindrical 3D shaded stems (shadow right, core emerald, specular left)
    void drawCylindricalStem(Offset start, Offset ctrl, Offset end, double sw) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, upperClipTop, 380, upperClipBottom + 3));
      _scratchPath
        ..reset()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);

      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..shader = null
        ..color = const Color(0xFF175E22);
      canvas.drawPath(_scratchPath, _paint);

      _paint
        ..strokeWidth = sw * 0.72
        ..color = const Color(0xFF339E39);
      canvas.drawPath(_scratchPath.shift(const Offset(-0.45, 0)), _paint);

      _paint
        ..strokeWidth = sw * 0.34
        ..color = const Color(0xFFA2F763);
      canvas.drawPath(_scratchPath.shift(const Offset(-1.25, -0.2)), _paint);
      canvas.restore();
    }

    // 2. Left & Right Side Stems sprouting smoothly outward during 100% bloom
    final leftExtendT = Curves.easeOutCubic.transform(
      ((tB - 0.08) / 0.62).clamp(0.0, 1.0),
    );
    final rightExtendT = Curves.easeOutCubic.transform(
      ((tB - 0.16) / 0.64).clamp(0.0, 1.0),
    );

    final leftTargetPos = Offset(
      cx - 48.0 + 3.2 * math.sin(ambientPhase + 0.7),
      metrics.topRimY - 50.0,
    );
    final rightTargetPos = Offset(
      cx + 49.0 + 3.2 * math.sin(ambientPhase + 1.4),
      metrics.topRimY - 46.0,
    );

    final leftTipPos = Offset.lerp(
      Offset(cx - 8, metrics.topRimY - 4),
      leftTargetPos,
      leftExtendT,
    )!;
    final rightTipPos = Offset.lerp(
      Offset(cx + 8, metrics.topRimY - 4),
      rightTargetPos,
      rightExtendT,
    )!;

    if (leftExtendT > 0.02) {
      drawCylindricalStem(
        Offset(cx - 8, stemBaseY),
        Offset.lerp(
          Offset(cx - 10, metrics.topRimY - 4),
          Offset(cx - 28, metrics.topRimY - 24),
          leftExtendT,
        )!,
        leftTipPos,
        5.6,
      );
    }
    if (rightExtendT > 0.02) {
      drawCylindricalStem(
        Offset(cx + 8, stemBaseY),
        Offset.lerp(
          Offset(cx + 10, metrics.topRimY - 4),
          Offset(cx + 28, metrics.topRimY - 22),
          rightExtendT,
        )!,
        rightTipPos,
        5.6,
      );
    }

    // 3. Primary Center Stem
    drawCylindricalStem(
      Offset(primaryBaseX, stemBaseY),
      primaryCtrl,
      centerPos,
      6.4,
    );

    // 4. Primary Stem's 2 Signature Asymmetrical Twisted 3D Leaves
    final leafNodeL = Offset.lerp(
      Offset(primaryBaseX + 6, metrics.topRimY - 18 - growthLift * 0.45),
      Offset(cx - 18, metrics.topRimY - 16),
      centerMorph,
    )!;
    final leafNodeR = Offset.lerp(
      Offset(primaryBaseX + 9, metrics.topRimY - 14 - growthLift * 0.45),
      Offset(cx + 18, metrics.topRimY - 15),
      centerMorph,
    )!;

    _drawCurledBotanicalLeaf(
      canvas,
      origin: leafNodeL,
      angle: ui.lerpDouble(-2.32, -2.38, centerMorph)! + sway,
      length: ui.lerpDouble(33.0, 31.0, centerMorph)!,
      width: 12.0,
      curlSign: -1.0,
    );
    _drawCurledBotanicalLeaf(
      canvas,
      origin: leafNodeR,
      angle: ui.lerpDouble(-0.42, -0.74, centerMorph)! + sway,
      length: ui.lerpDouble(36.0, 31.0, centerMorph)!,
      width: 12.6,
      curlSign: 1.0,
    );

    // 5. Render Pre-Bloom Sculpted 3D Tulip Bud OR Continuous Unfurling 3D Bouquet!
    if (tB <= 0.01) {
      _drawOrganicPinkTulipBud(
        canvas,
        center: centerPos,
        tiltAngle: 0.36 + sway * 1.2,
        scale: 1.06 + 0.10 * waterFraction.clamp(0.0, 1.0),
      );
      return;
    }

    final centerUnfurl = ((tB - 0.02) / 0.66).clamp(0.0, 1.0);
    final leftUnfurl = ((tB - 0.16) / 0.66).clamp(0.0, 1.0);
    final rightUnfurl = ((tB - 0.26) / 0.66).clamp(0.0, 1.0);

    _drawBouquetByType(
      canvas: canvas,
      flowerType: flowerType,
      centerPos: centerPos,
      leftPos: leftTipPos,
      rightPos: rightTipPos,
      centerUnfurl: centerUnfurl,
      leftUnfurl: leftUnfurl,
      rightUnfurl: rightUnfurl,
      leftAppear: leftExtendT,
      rightAppear: rightExtendT,
      sway: sway,
    );
  }

  /// Renders authentic extracted Flower Merge stage sprites (`0..3`) cleanly anchored at the
  /// crystal vase neck so both pre-bloom buds (`chưa nở`) and 100% full bloom (`nở hoa`)
  /// emerge organically out of the water vase without vector stems or hard cuts.
  void _drawSpriteBotanicals({
    required Canvas canvas,
    required double cx,
    required _VaseMetrics metrics,
    required double waterTopY,
    required bool hasWater,
    required double waterFraction,
    required double bloomFraction,
    required FlowerType flowerType,
  }) {
    final cache = _GardenFlowerSpriteCache.instance;
    final stages = cache.stagesFor(flowerType);
    if (stages == null || stages[0] == null || stages[3] == null) return;

    final boxH = switch (flowerType) {
      FlowerType.tulipPink || FlowerType.sunflower => 162.0,
      _ => 176.0,
    };
    final boxW = boxH * (640.0 / 600.0);
    final stemAnchor = Offset(cx, metrics.topRimY + 10.5);
    final rimMouthBottom =
        metrics.topRimY + metrics.ellipseHalfHeight(metrics.mouthHalfW) * 0.68;
    final clipBottom = hasWater
        ? math.min(waterTopY + 3.0, math.max(metrics.topRimY + 11.5, rimMouthBottom))
        : (metrics.topRimY + 11.0);

    void drawStage(
      ui.Image img, {
      required double scaleX,
      required double scaleY,
      required double angleRad,
      double alpha = 1.0,
    }) {
      if (alpha <= 0.01 || scaleX <= 0.01 || scaleY <= 0.01) return;
      _paint
        ..style = PaintingStyle.fill
        ..shader = null
        ..maskFilter = null
        ..blendMode = BlendMode.srcOver
        ..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0.0, -180.0, 380.0, clipBottom));
      canvas.translate(stemAnchor.dx, stemAnchor.dy);
      canvas.rotate(angleRad);
      canvas.scale(scaleX, scaleY);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(-boxW * 0.5, -boxH * (444.0 / 450.0), boxW, boxH),
        _paint,
      );
      canvas.restore();
    }

    final sway = 0.024 * math.sin(ambientPhase);
    final breatheY = 1.0 + 0.013 * math.sin(ambientPhase * 2.0);
    final tB = bloomFraction.clamp(0.0, 1.0);

    // 1. Pre-bloom state (`chưa nở` when water < 100% or revealing next vase)
    if (!is100Percent || tB <= 0.01 || isNewVaseReveal) {
      final wp = isNewVaseReveal ? 0.0 : waterFraction.clamp(0.0, 1.0);
      final stage0 = stages[0]!;
      final stage1 = stages[1] ?? stage0;

      // Cross threshold at 50%: smooth Spine-inspired bud-to-sprout pop (`00_01`)
      const threshold = 0.48;
      if (wp < threshold) {
        drawStage(
          stage0,
          scaleX: 1.18,
          scaleY: 1.18 * breatheY,
          angleRad: sway,
        );
      } else if (oldWaterProgress < threshold && wp < 0.62) {
        final popT = ((wp - threshold) / (0.62 - threshold)).clamp(0.0, 1.0);
        if (popT < 0.34) {
          final u = popT / 0.34;
          final sc = ui.lerpDouble(1.18, 0.52, Curves.easeInBack.transform(u))!;
          drawStage(stage0, scaleX: sc * 0.94, scaleY: sc * 1.08, angleRad: sway);
        } else {
          final u = (popT - 0.34) / 0.66;
          final sc = ui.lerpDouble(0.50, 1.08, Curves.easeOutBack.transform(u))!;
          drawStage(stage1, scaleX: sc, scaleY: sc * breatheY, angleRad: sway);
        }
      } else {
        drawStage(
          stage1,
          scaleX: 1.08,
          scaleY: 1.08 * breatheY,
          angleRad: sway,
        );
      }
      return;
    }

    // 2. Full 100% Bloom choreography (`đầy 100% -> nở hoa ra`, following `02_03` Spine curve)
    final startIdx = oldWaterProgress < 0.48 ? 0 : 1;
    final startImg = stages[startIdx] ?? stages[0]!;
    final startScale = startIdx == 0 ? 1.18 : 1.08;
    final stage2 = stages[2] ?? stages[3]!;
    final stage3 = stages[3]!;

    if (tB < 0.28) {
      // Anticipation stretch -> squash -> compress into bloom spark
      double sx = 1.0;
      double sy = 1.0;
      if (tB < 0.10) {
        final u = Curves.easeInOutCubic.transform(tB / 0.10);
        sx = ui.lerpDouble(1.0, 0.92, u)!;
        sy = ui.lerpDouble(1.0, 1.15, u)!;
      } else if (tB < 0.20) {
        final u = Curves.easeInOutCubic.transform((tB - 0.10) / 0.10);
        sx = ui.lerpDouble(0.92, 1.08, u)!;
        sy = ui.lerpDouble(1.15, 0.84, u)!;
      } else {
        final u = Curves.easeInCubic.transform((tB - 0.20) / 0.08);
        sx = ui.lerpDouble(1.08, 0.26, u)!;
        sy = ui.lerpDouble(0.84, 0.26, u)!;
      }
      drawStage(
        startImg,
        scaleX: startScale * sx,
        scaleY: startScale * sy,
        angleRad: sway * 0.5,
      );

      // Building golden bloom spark before burst
      if (tB > 0.14) {
        final chargeT = ((tB - 0.14) / 0.14).clamp(0.0, 1.0);
        final sparkCenter = Offset(cx, metrics.topRimY - 42);
        _fxPaint
          ..blendMode = BlendMode.plus
          ..maskFilter = null
          ..shader = ui.Gradient.radial(
            sparkCenter,
            48.0 * chargeT,
            [
              Colors.white.withValues(alpha: 0.72 * chargeT),
              const Color(0xFFFFE57F).withValues(alpha: 0.42 * chargeT),
              const Color(0x00FFE57F),
            ],
            const [0.0, 0.48, 1.0],
          );
        canvas.drawCircle(sparkCenter, 48.0 * chargeT, _fxPaint);
        _fxPaint
          ..shader = null
          ..blendMode = BlendMode.srcOver;
      }
    } else if (tB < 0.48) {
      // Unfurling rapidly through Stage 2 right inside the magic burst puff
      final u = Curves.easeOutCubic.transform(((tB - 0.28) / 0.20).clamp(0.0, 1.0));
      final sc = ui.lerpDouble(0.32, 1.04, u)!;
      drawStage(stage2, scaleX: sc, scaleY: sc, angleRad: sway * 0.6);
    } else {
      // Stage 3 full bouquet with Spine elastic settle (`1.07 -> 0.95 -> 1.02 -> 1.0`)
      if (tB < 0.56) {
        final crossAlpha = 1.0 - ((tB - 0.48) / 0.08).clamp(0.0, 1.0);
        drawStage(
          stage2,
          scaleX: 1.04,
          scaleY: 1.04,
          angleRad: sway * 0.7,
          alpha: crossAlpha * 0.65,
        );
      }

      final u = ((tB - 0.48) / 0.52).clamp(0.0, 1.0);
      double sx = 1.0;
      double sy = 1.0;
      if (u < 0.22) {
        final k = Curves.easeOutCubic.transform(u / 0.22);
        sx = ui.lerpDouble(0.82, 0.98, k)!;
        sy = ui.lerpDouble(0.76, 1.08, k)!;
      } else if (u < 0.48) {
        final k = Curves.easeInOutCubic.transform((u - 0.22) / 0.26);
        sx = ui.lerpDouble(0.98, 1.04, k)!;
        sy = ui.lerpDouble(1.08, 0.95, k)!;
      } else if (u < 0.74) {
        final k = Curves.easeInOutCubic.transform((u - 0.48) / 0.26);
        sx = ui.lerpDouble(1.04, 0.99, k)!;
        sy = ui.lerpDouble(0.95, 1.025, k)!;
      } else {
        final k = Curves.easeInOutCubic.transform((u - 0.74) / 0.26);
        sx = ui.lerpDouble(0.99, 1.0, k)!;
        sy = ui.lerpDouble(1.025, 1.0, k)!;
      }

      final appearAlpha = ((tB - 0.48) / 0.07).clamp(0.0, 1.0);
      drawStage(
        stage3,
        scaleX: sx,
        scaleY: sy * breatheY,
        angleRad: sway,
        alpha: appearAlpha,
      );
    }
  }

  /// Renders the 3-blossom 3D bouquet with bespoke palettes & petal geometry per milestone.
  void _drawBouquetByType({
    required Canvas canvas,
    required FlowerType flowerType,
    required Offset centerPos,
    required Offset leftPos,
    required Offset rightPos,
    required double centerUnfurl,
    required double leftUnfurl,
    required double rightUnfurl,
    required double leftAppear,
    required double rightAppear,
    required double sway,
  }) {
    switch (flowerType) {
      case FlowerType.trioDaisy:
      case FlowerType.tulipPink:
        final isVase1 = flowerType == FlowerType.tulipPink;

        if (leftAppear > 0.05) {
          _drawCupped3DGardenBlossom(
            canvas,
            center: leftPos,
            unfurlT: leftUnfurl,
            appearScale: 0.98 * leftAppear,
            faceTilt: -0.24 + sway,
            tipCol: isVase1
                ? const Color(0xFFFFC5DA)
                : const Color(0xFFFFB5A4),
            midCol: isVase1
                ? const Color(0xFFFF4D88)
                : const Color(0xFFFF5950),
            throatCol: isVase1
                ? const Color(0xFFB31252)
                : const Color(0xFFB81E24),
            stamenLight: const Color(0xFFFFF5AD),
            stamenDeep: const Color(0xFFE67800),
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DGardenBlossom(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.95 * rightAppear,
            faceTilt: 0.25 + sway,
            tipCol: const Color(0xFFF0DBFF),
            midCol: const Color(0xFFB360FF),
            throatCol: const Color(0xFF611CA0),
            stamenLight: const Color(0xFFFFF5AD),
            stamenDeep: const Color(0xFFE67800),
          );
        }
        _drawCupped3DGardenBlossom(
          canvas,
          center: centerPos,
          unfurlT: centerUnfurl,
          appearScale: 1.10,
          faceTilt: 0.03 + sway * 0.8,
          tipCol: const Color(0xFFFFFBB8),
          midCol: const Color(0xFFFFCE2A),
          throatCol: const Color(0xFFD96A00),
          stamenLight: const Color(0xFFFFFAD2),
          stamenDeep: const Color(0xFFD64B08),
        );
        break;

      case FlowerType.sunflower:
        if (leftAppear > 0.05) {
          _drawCupped3DSunflower(
            canvas,
            center: leftPos,
            unfurlT: leftUnfurl,
            appearScale: 0.88 * leftAppear,
            faceTilt: -0.22 + sway,
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DSunflower(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.88 * rightAppear,
            faceTilt: 0.22 + sway,
          );
        }
        _drawCupped3DSunflower(
          canvas,
          center: centerPos.translate(0, 4),
          unfurlT: centerUnfurl,
          appearScale: 1.12,
          faceTilt: sway * 0.7,
        );
        break;

      case FlowerType.scarletPoppy:
        if (leftAppear > 0.05) {
          _drawCupped3DGardenBlossom(
            canvas,
            center: leftPos,
            unfurlT: leftUnfurl,
            appearScale: 0.94 * leftAppear,
            faceTilt: -0.24 + sway,
            tipCol: const Color(0xFFFFA890),
            midCol: const Color(0xFFFF362B),
            throatCol: const Color(0xFF8C000A),
            stamenLight: const Color(0xFFFFE588),
            stamenDeep: const Color(0xFF3E1C33),
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DGardenBlossom(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.94 * rightAppear,
            faceTilt: 0.24 + sway,
            tipCol: const Color(0xFFFFD08A),
            midCol: const Color(0xFFFF6D00),
            throatCol: const Color(0xFFB33208),
            stamenLight: const Color(0xFFFFF59D),
            stamenDeep: const Color(0xFF4A192C),
          );
        }
        _drawCupped3DGardenBlossom(
          canvas,
          center: centerPos,
          unfurlT: centerUnfurl,
          appearScale: 1.10,
          faceTilt: sway * 0.8,
          tipCol: const Color(0xFFFF968C),
          midCol: const Color(0xFFE52220),
          throatCol: const Color(0xFF800B22),
          stamenLight: const Color(0xFFFFE57F),
          stamenDeep: const Color(0xFF2D122B),
        );
        break;

      case FlowerType.crystalLotus:
        if (leftAppear > 0.05) {
          _drawCupped3DCrystalLotus(
            canvas,
            center: leftPos,
            unfurlT: leftUnfurl,
            appearScale: 0.90 * leftAppear,
            faceTilt: -0.22 + sway,
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DCrystalLotus(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.90 * rightAppear,
            faceTilt: 0.22 + sway,
          );
        }
        _drawCupped3DCrystalLotus(
          canvas,
          center: centerPos.translate(0, 3),
          unfurlT: centerUnfurl,
          appearScale: 1.14,
          faceTilt: sway * 0.6,
        );
        break;
    }
  }

  /// Sculpted 3D Twisted Leaf:
  /// Soft blurred cast shadow, two-tone lamina divided by S-curved midrib,
  /// delicate lateral venation, and curled-over glossy underside tip fold.
  void _drawCurledBotanicalLeaf(
    Canvas canvas, {
    required Offset origin,
    required double angle,
    required double length,
    required double width,
    required double curlSign,
  }) {
    if (length <= 2.5) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);

    final tip = Offset(length, curlSign * width * 0.20);

    // 1. Soft Blurred Cast AO Shadow underneath leaf
    _scratchPath
      ..reset()
      ..moveTo(0, 2.0)
      ..cubicTo(
        length * 0.30,
        -width * 0.95 + 2.0,
        length * 0.72,
        -width * 0.75 + 2.0,
        tip.dx,
        tip.dy + 2.2,
      )
      ..cubicTo(
        length * 0.70,
        width * 0.92 + 2.0,
        length * 0.28,
        width * 1.02 + 2.0,
        0,
        2.0,
      )
      ..close();
    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = const Color(0x28032D3B);
    canvas.drawPath(_scratchPath, _fxPaint);

    // 2. Upper Sunlit Chartreuse-Lime Lamina
    _scratchPath
      ..reset()
      ..moveTo(0, 0)
      ..cubicTo(
        length * 0.28,
        -width * 1.06,
        length * 0.70,
        -width * 0.80,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(length * 0.48, tip.dy * 0.34, 0, 0)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(length * 0.1, -width),
        Offset(tip.dx, tip.dy * 0.4),
        const [
          Color(0xFFD2FF86),
          Color(0xFF70DF3C),
          Color(0xFF39A32A),
        ],
        const [0.0, 0.52, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);

    // 3. Lower Shaded Emerald Lamina
    _scratchPath
      ..reset()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.48, tip.dy * 0.34, tip.dx, tip.dy)
      ..cubicTo(
        length * 0.68,
        width * 0.98,
        length * 0.28,
        width * 1.06,
        0,
        0,
      )
      ..close();
    _paint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(length * 0.85, width),
      const [
        Color(0xFF47B82C),
        Color(0xFF207724),
        Color(0xFF104919),
      ],
      const [0.0, 0.60, 1.0],
    );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // 4. Subtle Botanical Lateral Veins
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x52DCEDC8);
    for (int v = 1; v <= 3; v++) {
      final vf = v * 0.22;
      final mx = length * vf;
      final my = tip.dy * (vf * 0.65);
      canvas.drawLine(
        Offset(mx, my),
        Offset(mx + length * 0.13, my - width * 0.46),
        _paint,
      );
      canvas.drawLine(
        Offset(mx, my),
        Offset(mx + length * 0.12, my + width * 0.44),
        _paint,
      );
    }

    // 5. Specular Sunlit Midrib Highlight Vein
    _scratchPath
      ..reset()
      ..moveTo(1.5, 0)
      ..quadraticBezierTo(
        length * 0.46,
        tip.dy * 0.30,
        length * 0.86,
        tip.dy * 0.82,
      );
    _paint
      ..strokeWidth = 1.5
      ..color = const Color(0xD8EBFFC4);
    canvas.drawPath(_scratchPath, _paint);

    // 6. Visible Turned/Curled Leaf Tip Fold for 3D depth
    final foldStart = Offset(length * 0.72, tip.dy * 0.72);
    _scratchPath
      ..reset()
      ..moveTo(foldStart.dx, foldStart.dy)
      ..quadraticBezierTo(
        length * 0.88,
        tip.dy - curlSign * width * 0.36,
        tip.dx + 1.5,
        tip.dy + curlSign * 2.0,
      )
      ..quadraticBezierTo(
        length * 0.84,
        tip.dy + curlSign * 0.5,
        foldStart.dx,
        foldStart.dy,
      )
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xBB9DF55E);
    canvas.drawPath(_scratchPath, _paint);

    canvas.restore();
  }

  /// Sculpted 4-Layer 3D Tulip Bud with Inter-Petal AO, Subsurface Rim Glow & 3-Sepal Calyx.
  void _drawOrganicPinkTulipBud(
    Canvas canvas, {
    required Offset center,
    required double tiltAngle,
    required double scale,
    Color innerPeakCol = const Color(0xFFE91E63),
    Color rightLightCol = const Color(0xFFFF9CC4),
    Color rightDeepCol = const Color(0xFF9C0E45),
    Color leftSunCol = const Color(0xFFFFD8E7),
    Color leftMidCol = const Color(0xFFFF4D8D),
    Color leftDeepCol = const Color(0xFFB5124E),
  }) {
    if (scale <= 0.02) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tiltAngle);
    canvas.scale(scale, scale);

    // Soft atmospheric AO behind bud
    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = const Color(0x28032430);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(2.0, -14), width: 34, height: 42),
      _fxPaint,
    );

    // 1. Recessed Inner Back Center Petal Peak
    _scratchPath
      ..reset()
      ..moveTo(-6.0, -8)
      ..cubicTo(-7.2, -24, -3.5, -37.5, 1.5, -40.5)
      ..cubicTo(6.8, -37.5, 8.2, -24, 6.0, -8)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(1.5, -40.5),
        const Offset(1.5, -8),
        [rightLightCol, innerPeakCol, const Color(0xFF6B0938)],
        const [0.0, 0.52, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Soft AO shadow cast onto inner peak by overlapping outer petals
    _fxPaint
      ..maskFilter = null
      ..color = const Color(0x3C4A0524);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(1.5, -16), width: 12, height: 22),
      _fxPaint,
    );

    // 2. Right Cupped Wrapping Petal
    _scratchPath
      ..reset()
      ..moveTo(-1.2, 6.0)
      ..cubicTo(18.0, 3.8, 20.5, -18.5, 10.2, -35.8)
      ..quadraticBezierTo(7.8, -38.4, 4.4, -34.2)
      ..cubicTo(1.2, -26.0, 0.6, -9.0, -1.2, 6.0)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(10.5, -24),
        28,
        [rightLightCol, leftMidCol, rightDeepCol],
        const [0.0, 0.50, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Overlap AO seam where foreground left petal wraps across right petal
    _fxPaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..maskFilter = null
      ..color = const Color(0x464A0626);
    canvas.drawPath(
      _scratchPath
        ..reset()
        ..moveTo(2.4, 5.2)
        ..cubicTo(6.2, -8, 5.2, -25, 0.0, -35.5),
      _fxPaint,
    );
    _fxPaint.style = PaintingStyle.fill;

    // 3. Foreground Hero Sunlit Belly Petal (3D spherical highlight + translucent rim glow)
    _scratchPath
      ..reset()
      ..moveTo(2.4, 6.2)
      ..cubicTo(-18.5, 3.6, -20.0, -19.5, -7.2, -37.8)
      ..quadraticBezierTo(-3.6, -40.5, -0.2, -36.0)
      ..cubicTo(5.0, -25.2, 6.2, -7.5, 2.4, 6.2)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(-9.5, -25),
        32,
        [leftSunCol, leftMidCol, leftDeepCol],
        const [0.0, 0.56, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Subsurface backlit lip sheen
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.44);
    canvas.drawPath(
      _scratchPath
        ..reset()
        ..moveTo(-12.2, -16.0)
        ..quadraticBezierTo(-10.0, -33.0, -2.5, -38.2),
      _paint,
    );

    // Specular belly highlight crescent
    _paint
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.36);
    canvas.drawPath(
      _scratchPath
        ..reset()
        ..moveTo(-9.6, -6.5)
        ..quadraticBezierTo(-12.2, -18.5, -6.6, -29.5),
      _paint,
    );

    // 4. Sculpted 3-Sepal 3D Green Receptacle Calyx
    for (int s = -1; s <= 1; s++) {
      canvas.save();
      canvas.translate(s * 3.8, 4.0);
      canvas.rotate(s * 0.42);
      _scratchPath
        ..reset()
        ..moveTo(0, 4.5)
        ..cubicTo(-5.2, 0.5, -4.6, -7.5, 0, -10.5)
        ..cubicTo(4.6, -7.5, 5.2, 0.5, 0, 4.5)
        ..close();
      _paint
        ..style = PaintingStyle.fill
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          const Offset(-3, -10),
          const Offset(3, 4),
          const [Color(0xFF9DF75D), Color(0xFF288425), Color(0xFF155417)],
          const [0.0, 0.62, 1.0],
        );
      canvas.drawPath(_scratchPath, _paint);
      _paint.shader = null;
      canvas.restore();
    }

    canvas.restore();
  }

  /// True 3D Spherical-Bowl Petal Projection Helper:
  /// Projects a cupped 3D petal oriented at `azimuthRad` around the blossom and `cupPitch`
  /// into 2D camera space with realistic foreshortening, soft AO shadow, velvety gradient,
  /// botanical central fold, and backlit subsurface edge glow (no flat cartoon outlines!).
  void _draw3DSculptedPetal(
    Canvas canvas, {
    required double azimuthRad,
    required double cupElevationRad,
    required double length,
    required double halfWidth,
    required double baseRadius,
    required Color tipCol,
    required Color midCol,
    required Color throatCol,
    double notchedHeart = 1.0,
    double cameraTilt = 0.68,
  }) {
    final sinA = math.sin(azimuthRad);
    final cosA = math.cos(azimuthRad);
    final cosE = math.cos(cupElevationRad);
    final sinE = math.sin(cupElevationRad);

    // 3D outward petal vector projected into camera space (`cosP = sqrt(1 - cameraTilt^2)`)
    final cosP = math.sqrt(math.max(0.0, 1.0 - cameraTilt * cameraTilt));
    final vx = sinA * cosE;
    final vy = -(sinE * cosP + cosA * cosE * cameraTilt);
    final apparentAngle = math.atan2(vx, -vy);
    final foreshorten = math.sqrt(vx * vx + vy * vy).clamp(0.42, 1.08);

    // Depth cue: front petals (`cosA < 0`) lean slightly toward camera, back petals stand tall (`cosA > 0`)
    final isFrontFacing = cosA < 0.0;
    final projLen = length * foreshorten;
    final anchorX = sinA * baseRadius;
    final anchorY = -cosA * baseRadius * cameraTilt + 2.0;

    canvas.save();
    canvas.translate(anchorX, anchorY);
    canvas.rotate(apparentAngle);

    final notchDip = notchedHeart > 0.5 ? 0.94 : 1.0;
    final shoulderCtrl = notchedHeart > 0.5 ? 1.15 : 0.92;
    _petalPath
      ..reset()
      ..moveTo(0, 0)
      ..cubicTo(
        -halfWidth * 0.46,
        -projLen * 0.24,
        -halfWidth * shoulderCtrl,
        -projLen * 0.66,
        -halfWidth * (notchedHeart > 0.5 ? 0.72 : 0.46),
        -projLen * 0.92,
      )
      ..quadraticBezierTo(
        -halfWidth * (notchedHeart > 0.5 ? 0.34 : 0.16),
        -projLen * (notchedHeart > 0.5 ? 1.07 : 1.03),
        0,
        -projLen * notchDip,
      )
      ..quadraticBezierTo(
        halfWidth * (notchedHeart > 0.5 ? 0.34 : 0.16),
        -projLen * (notchedHeart > 0.5 ? 1.07 : 1.03),
        halfWidth * (notchedHeart > 0.5 ? 0.72 : 0.46),
        -projLen * 0.92,
      )
      ..cubicTo(
        halfWidth * shoulderCtrl,
        -projLen * 0.66,
        halfWidth * 0.46,
        -projLen * 0.24,
        0,
        0,
      )
      ..close();

    // 1. Inter-Petal Ambient Occlusion Shadow
    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = throatCol.withValues(alpha: isFrontFacing ? 0.28 : 0.20);
    canvas.drawPath(_petalPath.shift(const Offset(0.8, 2.4)), _fxPaint);

    // 2. Velvety Spherical Gradient + Cross-Petal Light Shading
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        Offset(-halfWidth * 0.24, -projLen * 0.88),
        projLen * 1.08,
        [tipCol, midCol, throatCol],
        const [0.0, 0.54, 1.0],
      );
    canvas.drawPath(_petalPath, _paint);
    _paint.shader = null;

    // 3. Soft Center Crease Fold & Subsurface Translucent Rim Light
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..color = throatCol.withValues(alpha: 0.20);
    canvas.drawLine(
      Offset(0, -projLen * 0.18),
      Offset(0, -projLen * 0.72),
      _paint,
    );

    _paint
      ..strokeWidth = 1.35
      ..color = Colors.white.withValues(alpha: isFrontFacing ? 0.36 : 0.28);
    canvas.drawPath(_petalPath, _paint);

    canvas.restore();
  }

  /// True 3D Cupped Multi-Layered Velvet Blossom:
  /// Replaces flat 2D outlines with back-to-front 3D spherical bowl projection, blurred AO,
  /// deep sunlit throat, 3D hemispherical pollen cushion, arched filaments & anthers!
  void _drawCupped3DGardenBlossom(
    Canvas canvas, {
    required Offset center,
    required double unfurlT,
    required double appearScale,
    required double faceTilt,
    required Color tipCol,
    required Color midCol,
    required Color throatCol,
    required Color stamenLight,
    required Color stamenDeep,
  }) {
    if (appearScale <= 0.02) return;

    if (unfurlT < 0.26) {
      final budScale = appearScale * (0.86 + 0.24 * (unfurlT / 0.26));
      _drawOrganicPinkTulipBud(
        canvas,
        center: center,
        tiltAngle: faceTilt,
        scale: budScale,
        innerPeakCol: throatCol,
        rightLightCol: tipCol,
        rightDeepCol: throatCol,
        leftSunCol: tipCol,
        leftMidCol: midCol,
        leftDeepCol: throatCol,
      );
      if (unfurlT <= 0.12) return;
    }

    final openRaw = ((unfurlT - 0.10) / 0.90).clamp(0.0, 1.0);
    final openBounce = Curves.easeOutBack.transform(openRaw).clamp(0.0, 1.08);
    final spread = ui.lerpDouble(0.36, 1.0, openBounce)!;
    final cupElevation = ui.lerpDouble(1.12, 0.42, openRaw)!;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(faceTilt);
    canvas.scale(appearScale * spread, appearScale * spread);

    // Subtle atmospheric shadow behind blossom
    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..color = const Color(0x24042E3B);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 6), width: 44, height: 32),
      _fxPaint,
    );

    // Layer 1: Tall 3D Back Rim Petals (`azimuth ~ 0`, left/right flanks behind receptacle)
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: -0.78,
      cupElevationRad: cupElevation,
      length: 39.0,
      halfWidth: 13.0,
      baseRadius: 3.0,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: 0.78,
      cupElevationRad: cupElevation,
      length: 39.0,
      halfWidth: 13.0,
      baseRadius: 3.0,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: 0.0,
      cupElevationRad: cupElevation + 0.08,
      length: 41.0,
      halfWidth: 14.0,
      baseRadius: 3.5,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );

    // Layer 2: Lateral Wing Petals cupping sides
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: -1.62,
      cupElevationRad: cupElevation - 0.08,
      length: 36.0,
      halfWidth: 12.6,
      baseRadius: 3.0,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: 1.62,
      cupElevationRad: cupElevation - 0.08,
      length: 36.0,
      halfWidth: 12.6,
      baseRadius: 3.0,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );

    // Layer 3: Deep Bowl Throat Shadow + 3D Hemispherical Pollen Cushion & Shaded Stamens
    _fxPaint
      ..maskFilter = null
      ..color = throatCol.withValues(alpha: 0.44);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 2.5), width: 28, height: 22),
      _fxPaint,
    );

    final coreRect = Rect.fromCenter(
      center: const Offset(0, 1.8),
      width: 19.0,
      height: 14.2,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(-2.6, -1.6),
        12.5,
        [stamenLight, const Color(0xFFFFB300), stamenDeep],
        const [0.0, 0.56, 1.0],
      );
    canvas.drawOval(coreRect, _paint);
    _paint.shader = null;

    // 10 delicate arched stamens + 3D shaded pollen spheres
    const stamenAngles = <double>[
      -2.5, -1.9, -1.2, -0.5, 0.2, 0.9, 1.6, 2.3, -0.8, 1.1,
    ];
    for (int b = 0; b < stamenAngles.length; b++) {
      final sa = stamenAngles[b];
      final dist = b >= 8 ? 3.8 : 7.6;
      final tip = Offset(math.cos(sa) * dist, 1.5 + math.sin(sa) * dist * 0.72);
      final base = Offset(math.cos(sa) * dist * 0.35, 2.0 + math.sin(sa) * dist * 0.2);
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05
        ..strokeCap = StrokeCap.round
        ..color = stamenDeep.withValues(alpha: 0.75);
      canvas.drawLine(base, tip, _paint);

      _paint
        ..style = PaintingStyle.fill
        ..shader = ui.Gradient.radial(
          tip.translate(-0.6, -0.6),
          2.6,
          [const Color(0xFFFFFCE0), stamenLight, stamenDeep],
          const [0.0, 0.55, 1.0],
        );
      canvas.drawCircle(tip, b >= 8 ? 2.1 : 1.85, _paint);
    }
    _paint.shader = null;

    // Layer 4: Foreground Lower Cupping Petals (`azimuth ~ ±2.55`) overlapping throat edge
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: -2.48,
      cupElevationRad: cupElevation - 0.14,
      length: 30.5,
      halfWidth: 12.6,
      baseRadius: 3.8,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );
    _draw3DSculptedPetal(
      canvas,
      azimuthRad: 2.48,
      cupElevationRad: cupElevation - 0.14,
      length: 30.5,
      halfWidth: 12.6,
      baseRadius: 3.8,
      tipCol: tipCol,
      midCol: midCol,
      throatCol: throatCol,
    );

    canvas.restore();
  }

  /// 3D Sunflower with Alternating Saffron/Gold Ray Petals & 34-Seed Fibonacci Dome.
  void _drawCupped3DSunflower(
    Canvas canvas, {
    required Offset center,
    required double unfurlT,
    required double appearScale,
    required double faceTilt,
  }) {
    if (appearScale <= 0.02) return;
    final openRaw = unfurlT.clamp(0.0, 1.0);
    final spread = (0.35 + 0.65 * Curves.easeOutBack.transform(openRaw))
        .clamp(0.3, 1.12);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(faceTilt);
    canvas.scale(appearScale * spread, appearScale * spread * 0.78);

    // 2 Tiers of Golden Sunflower Ray Petals sorted back-to-front by Y!
    final petalIndices = <({double angle, bool isInner})>[];
    for (int ring = 0; ring < 2; ring++) {
      final offsetAngle = ring * (math.pi / 12.0);
      for (int i = 0; i < 12; i++) {
        petalIndices.add((
          angle: (i * math.pi * 2.0) / 12.0 + offsetAngle,
          isInner: ring == 1,
        ));
      }
    }
    // Sort by cos(angle) descending so back/top petals draw before foreground bottom petals
    petalIndices.sort(
      (a, b) => math.cos(b.angle).compareTo(math.cos(a.angle)),
    );

    for (final p in petalIndices) {
      canvas.save();
      canvas.rotate(p.angle);
      final tipY = p.isInner ? -33.5 : -37.5;
      _petalPath
        ..reset()
        ..moveTo(0, -10)
        ..cubicTo(-7.2, -18, -6.4, tipY * 0.80, 0, tipY)
        ..cubicTo(6.4, tipY * 0.80, 7.2, -18, 0, -10)
        ..close();

      // Subtle inter-petal shadow
      _paint
        ..style = PaintingStyle.fill
        ..shader = null
        ..color = const Color(0x366D2800);
      canvas.drawPath(_petalPath.shift(const Offset(0.5, 1.6)), _paint);

      _paint
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(0, tipY),
          const Offset(0, -10),
          p.isInner
              ? const [Color(0xFFFFFA9C), Color(0xFFFFB300), Color(0xFFD65E00)]
              : const [Color(0xFFFFE45E), Color(0xFFFF9300), Color(0xFFB33E00)],
          const [0.0, 0.56, 1.0],
        );
      canvas.drawPath(_petalPath, _paint);

      // Subtle petal longitudinal crease
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..shader = null
        ..color = const Color(0x389C3C00);
      canvas.drawLine(const Offset(0, -14), Offset(0, tipY * 0.78), _paint);
      canvas.restore();
    }
    _paint.shader = null;

    // 3D Domed Brown-Bronze Capitulum Disk + Fibonnaci Seed Pattern
    _fxPaint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..color = const Color(0x462B1206);
    canvas.drawCircle(const Offset(0, 1.5), 17.5, _fxPaint);

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(-3.5, -4.0),
        17.0,
        const [
          Color(0xFFA6662C),
          Color(0xFF5D3118),
          Color(0xFF2B1308),
        ],
        const [0.0, 0.58, 1.0],
      );
    canvas.drawCircle(Offset.zero, 15.2, _paint);
    _paint.shader = null;

    // 34 Fibonacci Golden-Angle (`2.399963 rad`) florets curving over 3D dome
    const goldenAngle = 2.3999632297;
    for (int s = 0; s < 34; s++) {
      final frac = math.sqrt((s + 0.5) / 34.0);
      final r = 13.6 * frac;
      final a = s * goldenAngle;
      final sx = math.cos(a) * r;
      final sy = math.sin(a) * r;
      final isOuterRim = frac > 0.76;
      _paint.color = isOuterRim
          ? const Color(0xFFFFCB3B)
          : (s.isEven ? const Color(0xFFD68D2E) : const Color(0xFF3E1C0C));
      canvas.drawCircle(Offset(sx, sy), isOuterRim ? 1.45 : 1.15, _paint);
    }

    canvas.restore();
  }

  /// 3-Tier Opalescent 3D Crystal Lotus with Translucent Prismatic Sheen & Nectar Crown.
  void _drawCupped3DCrystalLotus(
    Canvas canvas, {
    required Offset center,
    required double unfurlT,
    required double appearScale,
    required double faceTilt,
  }) {
    if (appearScale <= 0.02) return;
    final openRaw = unfurlT.clamp(0.0, 1.0);
    final spread = (0.35 + 0.65 * Curves.easeOutBack.transform(openRaw))
        .clamp(0.3, 1.12);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(faceTilt);
    canvas.scale(appearScale * spread, appearScale * spread * 0.80);

    // 2 Outer Lotus Petal Rings sorted back-to-front by Y
    final petals = <({double angle, int ring})>[];
    for (int ring = 0; ring < 2; ring++) {
      final rotOffset = ring * (math.pi / 8.0);
      for (int i = 0; i < 8; i++) {
        petals.add((angle: (i * math.pi * 2.0) / 8.0 + rotOffset, ring: ring));
      }
    }
    petals.sort((a, b) => math.cos(b.angle).compareTo(math.cos(a.angle)));

    for (final p in petals) {
      canvas.save();
      canvas.rotate(p.angle);
      final tipY = p.ring == 0 ? -38.0 : -30.5;
      _petalPath
        ..reset()
        ..moveTo(0, 0)
        ..cubicTo(-11.5, -10, -10.0, tipY * 0.74, 0, tipY)
        ..cubicTo(10.0, tipY * 0.74, 11.5, -10, 0, 0)
        ..close();

      _paint
        ..style = PaintingStyle.fill
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(0, tipY),
          Offset.zero,
          p.ring == 0
              ? const [
                  Color(0xFFFDF2FF),
                  Color(0xFFD596F0),
                  Color(0xFF7B339D),
                ]
              : const [
                  Color(0xFFFFFFFF),
                  Color(0xFFA8F6FF),
                  Color(0xFF3CBAD8),
                ],
          const [0.0, 0.56, 1.0],
        );
      canvas.drawPath(_petalPath, _paint);
      _paint.shader = null;

      // Iridescent crystal facet edge & central keel line
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = Colors.white.withValues(alpha: 0.78);
      canvas.drawPath(_petalPath, _paint);
      _paint
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: 0.42);
      canvas.drawLine(const Offset(0, -4), Offset(0, tipY * 0.85), _paint);
      canvas.restore();
    }

    // Inner upright opalescent crown halo + glowing golden lotus receptacle pod
    _fxPaint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..color = const Color(0x52FFF69E);
    canvas.drawCircle(Offset.zero, 13.5, _fxPaint);

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(-2.5, -2.5),
        10.5,
        const [
          Color(0xFFFFFFFF),
          Color(0xFFFFF39C),
          Color(0xFFF29C1F),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(Offset.zero, 9.2, _paint);
    _paint.shader = null;

    canvas.restore();
  }

  /// Physics-Driven Progressive Waterfall Ribbon & 3D Crown Splash:
  /// - `headT` (`0 -> 1`): stream shoots from tilted jar lip down to `waterImpactPt`
  /// - `tailT` (`0 -> 1`): stream detaches from jar lip and plunges into the water at finish!
  void _drawProgressiveWaterfallAndSplash({
    required Canvas canvas,
    required Offset jarCenter,
    required double jarTiltRad,
    required Offset vaseMouthCenter,
    required Offset waterImpactPt,
    required double headT,
    required double tailT,
    required double pourT,
  }) {
    if (headT <= 0.02 || tailT >= 0.98) return;

    final spoutPt = Offset(
      jarCenter.dx + 4.0 * math.cos(jarTiltRad) + 31.0 * math.sin(jarTiltRad),
      jarCenter.dy + 4.0 * math.sin(jarTiltRad) - 31.0 * math.cos(jarTiltRad),
    );

    final flutter = 1.4 * math.sin(ambientPhase * 4.0);
    final c1 = Offset(
      spoutPt.dx + (vaseMouthCenter.dx - spoutPt.dx) * 0.62 + 8,
      spoutPt.dy + 4,
    );
    final c2 = Offset(
      vaseMouthCenter.dx + 2 + flutter,
      vaseMouthCenter.dy + 16,
    );

    Offset evalStream(double t) {
      final u = 1.0 - t;
      final uu = u * u;
      final tt = t * t;
      return Offset(
        uu * u * spoutPt.dx +
            3 * uu * t * c1.dx +
            3 * u * tt * c2.dx +
            tt * t * waterImpactPt.dx,
        uu * u * spoutPt.dy +
            3 * uu * t * c1.dy +
            3 * u * tt * c2.dy +
            tt * t * waterImpactPt.dy,
      );
    }

    final tStart = Curves.easeInQuad.transform(tailT);
    final tEnd = Curves.easeInQuad.transform(headT);
    if (tEnd - tStart <= 0.02) return;

    final widthScale = (1.0 - tailT * 0.55).clamp(0.35, 1.0);

    const steps = 14;
    final leftPts = <Offset>[];
    final rightPts = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final u = i / steps;
      final t = ui.lerpDouble(tStart, tEnd, u)!;
      final pt = evalStream(t);
      final halfW = ui.lerpDouble(5.4, 8.8, t)! *
          widthScale *
          (i == 0 && tailT > 0.01 ? 0.35 : 1.0);
      leftPts.add(Offset(pt.dx - halfW, pt.dy + (1.0 - t) * 2.0));
      rightPts.add(Offset(pt.dx + halfW, pt.dy - (1.0 - t) * 2.0));
    }

    _scratchPath.reset();
    _scratchPath.moveTo(leftPts.first.dx, leftPts.first.dy);
    for (int i = 1; i < leftPts.length; i++) {
      _scratchPath.lineTo(leftPts[i].dx, leftPts[i].dy);
    }
    _scratchPath.quadraticBezierTo(
      evalStream(tEnd).dx,
      evalStream(tEnd).dy + 5.0,
      rightPts.last.dx,
      rightPts.last.dy,
    );
    for (int i = rightPts.length - 2; i >= 0; i--) {
      _scratchPath.lineTo(rightPts[i].dx, rightPts[i].dy);
    }
    _scratchPath.close();

    // Soft additive mist sheath around waterfall
    _fxPaint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..blendMode = BlendMode.plus
      ..color = const Color(0x3464F6FF);
    canvas.drawPath(_scratchPath, _fxPaint);
    _fxPaint.blendMode = BlendMode.srcOver;

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        spoutPt,
        waterImpactPt,
        const [
          Color(0xF0B2FFFF),
          Color(0xF038DCFA),
          Color(0xEA0FA4E8),
        ],
        const [0.0, 0.48, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xC2FFFFFF);
    canvas.drawPath(_scratchPath, _paint);

    // High-speed fluid foam highlights rushing down stream
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int s = 0; s < 4; s++) {
      final rawT0 = (((ambientPhase * 1.9 / math.pi) + s * 0.25) % 0.84);
      final rawT1 = (rawT0 + 0.13).clamp(0.0, 0.98);
      if (rawT1 <= tStart || rawT0 >= tEnd) continue;
      final st0 = rawT0.clamp(tStart, tEnd);
      final st1 = rawT1.clamp(tStart, tEnd);
      final p0 = evalStream(st0);
      final p1 = evalStream(st1);
      final lateral = (s.isEven ? -1.8 : 1.8) * widthScale;
      _paint
        ..strokeWidth = (2.2 - (s % 2) * 0.5) * widthScale
        ..color = Colors.white.withValues(alpha: 0.84);
      canvas.drawLine(
        p0.translate(lateral, 0),
        p1.translate(lateral, 0),
        _paint,
      );
    }

    // Trailing water droplets detaching after stream tail
    if (tailT > 0.05 && tailT < 0.95) {
      _paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xEE8EFFFF);
      for (int d = 0; d < 2; d++) {
        final dt = (tStart - 0.08 - d * 0.09).clamp(0.02, 0.95);
        if (dt < tStart) {
          canvas.drawCircle(evalStream(dt), 3.2 - d * 0.8, _paint);
        }
      }
    }

    // 3D Crown Splash Collar, Spikes, Impact Mist & Parabolic Droplets
    if (headT >= 0.92 && tailT < 0.92) {
      final splashAlpha = (1.0 - tailT).clamp(0.0, 1.0);
      final wScale = widthScale;

      _fxPaint
        ..style = PaintingStyle.fill
        ..maskFilter = null
        ..color = const Color(0x52AAFFFF).withValues(alpha: 0.42 * splashAlpha);
      canvas.drawOval(
        Rect.fromCenter(
          center: waterImpactPt,
          width: 38.0 * wScale,
          height: 13.0 * wScale,
        ),
        _fxPaint,
      );
      _fxPaint.color =
          const Color(0x88AAFFFF).withValues(alpha: 0.65 * splashAlpha);
      canvas.drawOval(
        Rect.fromCenter(
          center: waterImpactPt,
          width: 28.0 * wScale,
          height: 9.0 * wScale,
        ),
        _fxPaint,
      );

      // Sculpted 5-spike 3D splash crown
      for (int k = 0; k < 5; k++) {
        final frac = (k - 2) / 2.0; // -1 .. +1
        final baseX = waterImpactPt.dx + frac * 11.0 * wScale;
        final spikeH = (11.0 - frac.abs() * 3.5) * wScale *
            (0.75 + 0.25 * math.sin(ambientPhase * 5.0 + k));
        final tipX = baseX + frac * 6.5 * wScale;
        final tipY = waterImpactPt.dy - spikeH;
        _scratchPath
          ..reset()
          ..moveTo(baseX - 3.2 * wScale, waterImpactPt.dy)
          ..quadraticBezierTo(baseX, waterImpactPt.dy - spikeH * 0.5, tipX, tipY)
          ..quadraticBezierTo(
            baseX + 2.5 * wScale,
            waterImpactPt.dy - spikeH * 0.45,
            baseX + 3.4 * wScale,
            waterImpactPt.dy,
          )
          ..close();
        _paint
          ..style = PaintingStyle.fill
          ..color = const Color(0xE8D8FFFF).withValues(alpha: 0.86 * splashAlpha);
        canvas.drawPath(_scratchPath, _paint);
      }

      // Parabolic glistening water droplets
      for (int i = 0; i < 8; i++) {
        final cycle = ((ambientPhase * 2.5 / math.pi) + i * 0.125) % 1.0;
        final spreadAngle = -math.pi * 0.12 - (i / 7.0) * math.pi * 0.76;
        final horiz = math.cos(spreadAngle) * (9.0 + 24.0 * cycle);
        final vert =
            math.sin(spreadAngle) * 22.0 * cycle + 19.0 * cycle * cycle;
        final dropR = (3.3 * (1.0 - cycle * 0.62)) * wScale;
        final dp = Offset(waterImpactPt.dx + horiz, waterImpactPt.dy + vert - 4);

        _paint
          ..style = PaintingStyle.fill
          ..color = const Color(0xFFB4FFFF).withValues(
            alpha: (0.90 * (1.0 - cycle) * splashAlpha).clamp(0.0, 1.0),
          );
        canvas.drawCircle(dp, dropR, _paint);
        _paint.color = Colors.white.withValues(
          alpha: (0.95 * (1.0 - cycle) * splashAlpha).clamp(0.0, 1.0),
        );
        canvas.drawCircle(
          dp.translate(-dropR * 0.28, -dropR * 0.28),
          dropR * 0.36,
          _paint,
        );
      }
    }
  }

  /// Front Sculptural 3D Glass Wall:
  /// - Shape-specific 3D convex crystal flutes, faceted diamond planes, or gold/azure trim
  /// - Feathered studio window reflection & Fresnel rim shading (NO harsh uniform cartoon border!)
  /// - Heavy crystal base specular lens + 3D toroidal glass mouth collar
  void _drawFrontGlassOverlay(
    Canvas canvas,
    double cx,
    _VaseMetrics m,
    VaseShapeType type, {
    required bool hasWater,
  }) {
    final palette = _GlassPalette.forShape(type);

    // 1. Shape-Specific Sculpted Surface Details (clipped to outer contour)
    canvas.save();
    canvas.clipPath(_vaseOuterPath);

    if (type == VaseShapeType.flutedCrystal) {
      // 6 convex 3D vertical melon ribs sampled along exact profile
      const ribFractions = [-0.72, -0.44, -0.15, 0.15, 0.44, 0.72];
      const ribSteps = 18;
      for (final f in ribFractions) {
        _scratchPath.reset();
        for (int i = 0; i <= ribSteps; i++) {
          final y = ui.lerpDouble(m.neckY + 2, m.baseY - 4, i / ribSteps)!;
          final x = cx + m.outerHalfWidthAt(y, type) * f;
          if (i == 0) {
            _scratchPath.moveTo(x, y);
          } else {
            _scratchPath.lineTo(x, y);
          }
        }
        // Broad convex refraction glow + left sunlit highlight + right valley AO groove
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10.0
          ..strokeCap = StrokeCap.round
          ..shader = null
          ..color = const Color(0x28ECFFFF);
        canvas.drawPath(_scratchPath, _paint);

        _paint
          ..strokeWidth = 2.4
          ..color = const Color(0x8EFFFFFF);
        canvas.drawPath(_scratchPath.shift(const Offset(-1.2, 0)), _paint);

        _paint
          ..strokeWidth = 2.4
          ..color = const Color(0x460D487A);
        canvas.drawPath(_scratchPath.shift(const Offset(3.0, 0)), _paint);
      }
    } else if (type == VaseShapeType.prismLotus) {
      // Crisp multi-plane diamond facets catching alternating cool highlight & sapphire shadow
      final midH = m.baseY - m.neckY;
      final yTop = m.neckY;
      final yUpper = m.neckY + midH * 0.28;
      final yBelly = m.neckY + midH * 0.48;
      final yLower = m.neckY + midH * 0.74;
      final yBot = m.baseY - 4.0;

      final facetCols = [
        (0.0, 0.45, const Color(0x26FFFFFF)),
        (-0.45, 0.0, const Color(0x42D8F7FF)),
        (-0.98, -0.45, const Color(0x2A143678)),
        (0.45, 0.98, const Color(0x2E184888)),
      ];

      final tiers = <(double, double)>[
        (yTop, yUpper),
        (yUpper, yBelly),
        (yBelly, yLower),
        (yLower, yBot),
      ];

      for (int ti = 0; ti < tiers.length; ti++) {
        final (y0, y1) = tiers[ti];
        final hw0 = m.outerHalfWidthAt(y0, type);
        final hw1 = m.outerHalfWidthAt(y1, type);
        for (int fi = 0; fi < facetCols.length; fi++) {
          final (fL, fR, col) = facetCols[fi];
          _scratchPath
            ..reset()
            ..moveTo(cx + hw0 * fL, y0)
            ..lineTo(cx + hw0 * fR, y0)
            ..lineTo(cx + hw1 * fR, y1)
            ..lineTo(cx + hw1 * fL, y1)
            ..close();
          _paint
            ..style = PaintingStyle.fill
            ..shader = null
            ..color = col.withValues(alpha: (ti.isEven ? 0.22 : 0.14));
          canvas.drawPath(_scratchPath, _paint);
        }
      }

      // Luminous diamond ridge lines
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x88FFFFFF);
      for (final f in const [-0.46, 0.0, 0.46]) {
        _scratchPath
          ..reset()
          ..moveTo(cx + m.outerHalfWidthAt(yTop, type) * f, yTop)
          ..lineTo(cx + m.outerHalfWidthAt(yUpper, type) * f, yUpper)
          ..lineTo(cx + m.outerHalfWidthAt(yBelly, type) * f, yBelly)
          ..lineTo(cx + m.outerHalfWidthAt(yLower, type) * f, yLower)
          ..lineTo(cx + m.outerHalfWidthAt(yBot, type) * f, yBot);
        canvas.drawPath(_scratchPath, _paint);
      }
      // Horizontal facet waist rings
      for (final gy in [yUpper, yBelly, yLower]) {
        final ghw = m.outerHalfWidthAt(gy, type);
        final geh = m.ellipseHalfHeight(ghw) * 0.7;
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, gy), width: ghw * 2.0, height: geh * 2),
          0.06,
          math.pi - 0.12,
          false,
          _paint,
        );
      }
    }

    // 2. Signature Feathered Left Curved Studio Softbox Reflection (cached per vase geometry!)
    final hlTopY = m.neckY + 8.0;
    final hlBotY = m.innerBaseY - 10.0;
    final glassKey =
        '${type.name}|${cx.toStringAsFixed(1)}|${hlTopY.toStringAsFixed(1)}|${hlBotY.toStringAsFixed(1)}';
    final cachedGlassPaths = _frontGlassPathsCache.putIfAbsent(glassKey, () {
      const hlSteps = 32;
      final leftBandOuter = List<Offset>.generate(hlSteps + 1, (i) {
        final y = ui.lerpDouble(hlTopY, hlBotY, i / hlSteps)!;
        final hw = m.outerHalfWidthAt(y, type);
        return Offset(cx - hw * 0.80, y);
      });
      final leftBandInner = List<Offset>.generate(hlSteps + 1, (i) {
        final y = ui.lerpDouble(hlTopY, hlBotY, i / hlSteps)!;
        final hw = m.outerHalfWidthAt(y, type);
        return Offset(cx - hw * 0.61, y);
      });
      final softboxBand = Path()
        ..moveTo(leftBandOuter.first.dx, leftBandOuter.first.dy);
      for (int i = 1; i < hlSteps; i++) {
        final mid = Offset(
          (leftBandOuter[i].dx + leftBandOuter[i + 1].dx) * 0.5,
          (leftBandOuter[i].dy + leftBandOuter[i + 1].dy) * 0.5,
        );
        softboxBand.quadraticBezierTo(
          leftBandOuter[i].dx,
          leftBandOuter[i].dy,
          mid.dx,
          mid.dy,
        );
      }
      softboxBand.lineTo(leftBandOuter.last.dx, leftBandOuter.last.dy);
      softboxBand.lineTo(leftBandInner.last.dx, leftBandInner.last.dy);
      for (int i = hlSteps - 1; i > 0; i--) {
        final mid = Offset(
          (leftBandInner[i].dx + leftBandInner[i - 1].dx) * 0.5,
          (leftBandInner[i].dy + leftBandInner[i - 1].dy) * 0.5,
        );
        softboxBand.quadraticBezierTo(
          leftBandInner[i].dx,
          leftBandInner[i].dy,
          mid.dx,
          mid.dy,
        );
      }
      softboxBand
        ..lineTo(leftBandInner.first.dx, leftBandInner.first.dy)
        ..close();

      Path buildSmoothCurve(double topY, double botY, double xFactor) {
        const n = 24;
        final pts = List<Offset>.generate(n + 1, (i) {
          final y = ui.lerpDouble(topY, botY, i / n)!;
          return Offset(cx + m.outerHalfWidthAt(y, type) * xFactor, y);
        });
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < n; i++) {
          final mid = Offset(
            (pts[i].dx + pts[i + 1].dx) * 0.5,
            (pts[i].dy + pts[i + 1].dy) * 0.5,
          );
          path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
        }
        path.lineTo(pts.last.dx, pts.last.dy);
        return path;
      }

      return (
        softboxBand: softboxBand,
        leftGlint: buildSmoothCurve(hlTopY + 4, hlBotY - 12, -0.72),
        rightBounce: buildSmoothCurve(hlTopY + 12, hlBotY - 6, 0.82),
      );
    });

    _fxPaint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..shader = ui.Gradient.linear(
        Offset(cx - m.bellyHalfW * 0.8, hlTopY),
        Offset(cx - m.bellyHalfW * 0.5, hlBotY),
        const [
          Color(0x94FFFFFF),
          Color(0x46FFFFFF),
          Color(0x0CFFFFFF),
        ],
        const [0.0, 0.52, 1.0],
      );
    canvas.drawPath(cachedGlassPaths.softboxBand, _fxPaint);
    _fxPaint.shader = null;

    // Sharp crisp secondary specular glint along left curve
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        Offset(cx, hlTopY),
        Offset(cx, hlBotY),
        const [
          Color(0xD8FFFFFF),
          Color(0x4EFFFFFF),
          Color(0x00FFFFFF),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawPath(cachedGlassPaths.leftGlint, _paint);

    // Secondary warm cyan/ivory bounce rim along right curve
    _paint
      ..strokeWidth = 3.0
      ..shader = null
      ..color = palette.accentTint.withValues(alpha: 0.36);
    canvas.drawPath(cachedGlassPaths.rightBounce, _paint);

    // Heavy Crystal Bottom Puck Front Specular Crescent
    _scratchPath
      ..reset()
      ..moveTo(cx - m.baseHalfW * 0.78, m.baseY - 6)
      ..quadraticBezierTo(
        cx,
        m.baseY + 7,
        cx + m.baseHalfW * 0.78,
        m.baseY - 6,
      );
    _paint
      ..strokeWidth = 3.2
      ..color = Colors.white.withValues(alpha: 0.52);
    canvas.drawPath(_scratchPath, _paint);

    canvas.restore();

    // 3. Directional Fresnel Crystal Silhouette Edge (sunlit left-top, subtle sapphire right)
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - m.bellyHalfW, m.topRimY),
        Offset(cx + m.bellyHalfW, m.baseY),
        [
          palette.rimHighlight.withValues(alpha: 0.80),
          palette.edgeMid.withValues(alpha: 0.50),
          palette.rimHighlight.withValues(alpha: 0.65),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(_vaseOuterPath, _paint);
    _paint.shader = null;

    // 4. Sculpted Neck Collar Band (Beveled brushed gold for royalTall/ovalCeramic or crystal ring)
    final neckRect = Rect.fromCenter(
      center: Offset(cx, m.neckY + 1.0),
      width: m.neckHalfW * 2.02,
      height: m.ellipseHalfHeight(m.neckHalfW) * 1.32,
    );
    if (type == VaseShapeType.royalTall || type == VaseShapeType.ovalCeramic) {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(cx - m.neckHalfW, m.neckY),
          Offset(cx + m.neckHalfW, m.neckY),
          const [
            Color(0xCC9E6B12),
            Color(0xF8FFF2AA),
            Color(0xEDD1932C),
            Color(0xCC7A4E0B),
          ],
          const [0.0, 0.34, 0.68, 1.0],
        );
      canvas.drawArc(neckRect, 0.05, math.pi - 0.10, false, _paint);
      _paint.shader = null;

      // Center neck pearl jewel dot
      _paint
        ..style = PaintingStyle.fill
        ..color = type == VaseShapeType.royalTall
            ? const Color(0xFFFFD54F)
            : const Color(0xFFA8F8EC);
      canvas.drawCircle(
        Offset(cx, m.neckY + m.ellipseHalfHeight(m.neckHalfW) * 0.72),
        3.0,
        _paint,
      );
    } else {
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..color = hasWater
            ? const Color(0x7CFFEAA4)
            : const Color(0x66E0FFFF);
      canvas.drawArc(neckRect, 0.06, math.pi - 0.12, false, _paint);
    }

    // 5. Rolled 3D Toroidal Glass Mouth Lip (occluding stems cleanly)
    final rimEH = m.ellipseHalfHeight(m.mouthHalfW);
    final rimRect = Rect.fromCenter(
      center: Offset(cx, m.topRimY + 1.5),
      width: m.mouthHalfW * 2.0,
      height: rimEH * 2.0,
    );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..color = palette.innerTint.withValues(alpha: 0.64);
    canvas.drawArc(rimRect, 0.04, math.pi - 0.08, false, _paint);

    _paint
      ..strokeWidth = 2.4
      ..color = Colors.white.withValues(alpha: 0.86);
    canvas.drawArc(rimRect, 0.08, math.pi - 0.16, false, _paint);

    _paint
      ..strokeWidth = 1.4
      ..color = Colors.white;
    canvas.drawArc(rimRect, math.pi * 0.62, 0.32, false, _paint);
  }

  /// Detailed 3D Tilted Mini Crystal Potion Jar (matching `MagicSandJarComponent` craft):
  /// Fresnel glass chamber, thick glass bottom crescent, gravity-leveled cyan potion with
  /// 3D elliptical top meniscus, braided gold rope + knot, and bevelled `2048` hang-tag!
  void _drawTiltedMiniPotionJar({
    required Canvas canvas,
    required Offset jarCenter,
    required double tiltRad,
    required double visibility,
    required double pourT,
    required double enterT,
    required String numberText,
  }) {
    final remainingWater = (1.0 - pourT * 0.82).clamp(0.14, 1.0);

    canvas.save();
    canvas.translate(jarCenter.dx, jarCenter.dy);
    canvas.scale(visibility.clamp(0.0, 1.15), visibility.clamp(0.0, 1.15));

    canvas.save();
    canvas.rotate(tiltRad);

    _scratchPath
      ..reset()
      ..moveTo(-13, -32)
      ..quadraticBezierTo(-13, -24, -12, -20)
      ..cubicTo(-40, -13, -41, 22, -16, 31)
      ..quadraticBezierTo(0, 36, 16, 31)
      ..cubicTo(41, 22, 40, -13, 12, -20)
      ..quadraticBezierTo(13, -24, 13, -32)
      ..close();

    // 1. Fresnel 3D Mini Jar Glass Shell
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(-34, 0),
        const Offset(34, 0),
        const [
          Color(0xB80E6496),
          Color(0x524ED8FA),
          Color(0x28DCFDFF),
          Color(0x584ED8FA),
          Color(0xB80E6496),
        ],
        const [0.0, 0.20, 0.50, 0.80, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // 2. Draining Potion Liquid (kept horizontal to world gravity!)
    canvas.save();
    canvas.clipPath(_scratchPath);
    canvas.rotate(-tiltRad);
    final liquidTop = ui.lerpDouble(24.0, -12.0, remainingWater)!;
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(0, liquidTop),
        const Offset(0, 36),
        const [Color(0xEE84FFFF), Color(0xEE22C4EC), Color(0xEE0884C7)],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawRect(Rect.fromLTRB(-44, liquidTop, 44, 44), _paint);
    _paint.shader = null;

    // 3D elliptical liquid top surface in gravity orientation
    final surfRect = Rect.fromCenter(
      center: Offset(0, liquidTop),
      width: 68,
      height: 11,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xE8B4FFFF);
    canvas.drawOval(surfRect, _paint);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white;
    canvas.drawOval(surfRect, _paint);
    canvas.restore();

    // 3. Thick Crystal Belly Glint & Bottom Crescent Lens
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xCCFFFFFF);
    canvas.drawArc(
      const Rect.fromLTWH(-25, -12, 50, 36),
      math.pi * 0.72,
      math.pi * 0.48,
      false,
      _paint,
    );
    _paint
      ..strokeWidth = 2.6
      ..color = const Color(0x9AE2FDFF);
    canvas.drawArc(
      const Rect.fromLTWH(-20, 12, 40, 19),
      0.16,
      math.pi - 0.32,
      false,
      _paint,
    );

    // Subtle Fresnel glass edge + 3D toroidal jar mouth rim
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = const Color(0xDEE8FCFF);
    canvas.drawPath(_scratchPath, _paint);

    final mouthRect = Rect.fromCenter(
      center: const Offset(0, -32),
      width: 29,
      height: 8.5,
    );
    _paint
      ..strokeWidth = 4.2
      ..color = const Color(0x889AF4FF);
    canvas.drawOval(mouthRect, _paint);
    _paint
      ..strokeWidth = 2.0
      ..color = Colors.white;
    canvas.drawOval(mouthRect, _paint);

    // 4. Sculpted Brushed-Gold Collar Rope & Bead Knot
    _paint
      ..strokeWidth = 4.6
      ..color = const Color(0xFFD97706);
    canvas.drawLine(const Offset(-13, -21), const Offset(13, -21), _paint);
    _paint
      ..strokeWidth = 2.0
      ..color = const Color(0xFFFFF59D);
    canvas.drawLine(const Offset(-12, -22), const Offset(12, -22), _paint);

    _paint
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.radial(
        const Offset(-1.0, -21.0),
        4.2,
        const [Color(0xFFFFF9C4), Color(0xFFF59E0B), Color(0xFF92400E)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(const Offset(0, -20), 4.2, _paint);
    _paint.shader = null;

    canvas.restore();

    // 5. Beveled Butter-Cream `2048` Tag with Damped Pendulum Swing
    final knotWorld = Offset(
      20.0 * math.sin(tiltRad),
      -20.0 * math.cos(tiltRad),
    );
    const tagCenter = Offset(-1, 5);
    final arrivalSwing = (1.0 - enterT) * 0.28 * math.sin(enterT * math.pi * 2.0);
    final tagAngle = 0.44 + arrivalSwing + 0.045 * math.sin(ambientPhase * 2.0);
    final tagTopHole = Offset(
      tagCenter.dx + 10.0 * math.sin(tagAngle),
      tagCenter.dy - 10.0 * math.cos(tagAngle),
    );

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD97706);
    canvas.drawLine(knotWorld, tagTopHole, _paint);

    canvas.save();
    canvas.translate(tagCenter.dx, tagCenter.dy);
    canvas.rotate(tagAngle);

    final tagRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 52, height: 24),
      const Radius.circular(6),
    );

    _fxPaint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..color = const Color(0x3E042E40);
    canvas.drawRRect(tagRRect.shift(const Offset(0, 2.5)), _fxPaint);

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(0, -12),
        const Offset(0, 12),
        const [Color(0xFFFFFDF0), Color(0xFFF7E4B4)],
      );
    canvas.drawRRect(tagRRect, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFD7A85E);
    canvas.drawRRect(tagRRect, _paint);

    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFD97706);
    canvas.drawCircle(const Offset(0, -9), 1.8, _paint);

    _textPainter.text = TextSpan(
      text: numberText,
      style: const TextStyle(
        fontFamily: 'Baloo2',
        fontSize: 13.5,
        fontWeight: FontWeight.w900,
        height: 1.0,
        color: Color(0xFF1A2865),
      ),
    );
    _textPainter.layout();
    _textPainter.paint(
      canvas,
      Offset(-_textPainter.width * 0.5, 1.0 - _textPainter.height * 0.5),
    );

    canvas.restore();
    canvas.restore();
  }

  /// 3D Tumbling Real/Vector Petals, Magic Bloom Burst, Fluttering Butterflies & Sparkles
  void _drawFloatingPetalsAndSparkles({
    required Canvas canvas,
    required double cx,
    required double topY,
    required double intensity,
    required double bloomProgress,
    required FlowerType flowerType,
  }) {
    final cache = _GardenFlowerSpriteCache.instance;
    final usingSprites = cache.hasStages(flowerType);
    final crownCenterY = usingSprites ? topY - 40.0 : topY;

    // 1. Magic Bloom Burst FX (`SX_effect_ywbd`: golden burst puff + streamers + sparkles)
    if (bloomProgress >= 0.24 && bloomProgress <= 0.88) {
      final burstT = ((bloomProgress - 0.24) / 0.64).clamp(0.0, 1.0);
      final frameIdx = (burstT * 8).floor().clamp(0, 7);
      final burstImg = cache.burstFrames[frameIdx];
      if (burstImg != null) {
        final burstAlpha = burstT < 0.72
            ? 1.0
            : (1.0 - ((burstT - 0.72) / 0.28)).clamp(0.0, 1.0);
        final burstScale = ui.lerpDouble(0.76, 1.18, burstT)!;
        final size = 186.0 * burstScale;
        _fxPaint
          ..style = PaintingStyle.fill
          ..shader = null
          ..maskFilter = null
          ..blendMode = BlendMode.srcOver
          ..color = Colors.white.withValues(alpha: burstAlpha);
        canvas.drawImageRect(
          burstImg,
          Rect.fromLTWH(
            0,
            0,
            burstImg.width.toDouble(),
            burstImg.height.toDouble(),
          ),
          Rect.fromCenter(
            center: Offset(cx, crownCenterY + 6.0),
            width: size,
            height: size,
          ),
          _fxPaint,
        );
      }
    }

    // 2. Tumbling Real Flower Petals (fallback smoothly to vector petals if not cached)
    final petalImg = cache.petals[flowerType];
    final (petalLight, petalDeep) = switch (flowerType) {
      FlowerType.sunflower => (
          const Color(0xFFFFF59D),
          const Color(0xFFFFA000),
        ),
      FlowerType.scarletPoppy => (
          const Color(0xFFFFAB91),
          const Color(0xFFE53935),
        ),
      FlowerType.crystalLotus => (
          const Color(0xFFF3E5F5),
          const Color(0xFFBA68C8),
        ),
      _ => (
          const Color(0xFFFFC4D6),
          const Color(0xFFFF5C8A),
        ),
    };

    const baseOffsets = <Offset>[
      Offset(-98, 12),
      Offset(102, 10),
      Offset(-86, -42),
      Offset(90, -36),
      Offset(-62, -74),
      Offset(68, -70),
    ];

    for (int i = 0; i < baseOffsets.length; i++) {
      final b = baseOffsets[i];
      final driftX = 7.0 * math.sin(ambientPhase + i * 1.15);
      final driftY = 6.0 * math.cos(ambientPhase * 1.25 + i * 0.9);
      final pos = Offset(
        cx + b.dx * intensity + driftX,
        crownCenterY + b.dy + driftY,
      );
      final tumble = math.cos(ambientPhase * 1.8 + i * 1.3);
      final flipY = (0.36 + 0.64 * tumble.abs()) * intensity;
      final isBackSide = tumble < 0;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(0.45 * i + 0.25 * math.sin(ambientPhase + i));
      canvas.scale(intensity, flipY);

      if (petalImg != null) {
        _paint
          ..style = PaintingStyle.fill
          ..shader = null
          ..maskFilter = null
          ..blendMode = BlendMode.srcOver
          ..color = Colors.white.withValues(alpha: (0.94 * intensity).clamp(0.0, 1.0));
        canvas.drawImageRect(
          petalImg,
          Rect.fromLTWH(
            0,
            0,
            petalImg.width.toDouble(),
            petalImg.height.toDouble(),
          ),
          const Rect.fromLTWH(-7.5, -9.8, 15.0, 19.6),
          _paint,
        );
      } else {
        _scratchPath
          ..reset()
          ..moveTo(-8.5, 0)
          ..cubicTo(-4, -6.5, 5, -6.8, 8.5, -0.5)
          ..cubicTo(5, 5.8, -3, 5.2, -8.5, 0)
          ..close();
        _paint
          ..style = PaintingStyle.fill
          ..color = Colors.white
          ..shader = ui.Gradient.linear(
            const Offset(-8, -5),
            const Offset(8, 5),
            isBackSide
                ? [
                    petalDeep.withValues(alpha: (0.85 * intensity).clamp(0.0, 1.0)),
                    petalLight.withValues(alpha: (0.72 * intensity).clamp(0.0, 1.0)),
                  ]
                : [
                    petalLight.withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)),
                    petalDeep.withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)),
                  ],
          );
        canvas.drawPath(_scratchPath, _paint);
        _paint.shader = null;
      }
      canvas.restore();
    }

    // 3. Floating warm golden pollen fairy motes / glint orbs
    final glintImg = cache.glintDot;
    for (int m = 0; m < 8; m++) {
      final angle = m * 0.785 + ambientPhase * 0.4;
      final r = 54.0 + (m % 3) * 22.0;
      final mx = cx + math.cos(angle) * r;
      final my =
          crownCenterY - 12 + math.sin(angle * 1.3) * 44.0 - (ambientPhase % 6.28) * 1.5;
      final pulse = (0.4 + 0.6 * math.sin(ambientPhase * 2.5 + m)).clamp(0.0, 1.0);
      if (glintImg != null) {
        final gs = (6.0 + (m % 3) * 2.5) * pulse;
        _fxPaint
          ..style = PaintingStyle.fill
          ..shader = null
          ..maskFilter = null
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: (0.85 * intensity * pulse).clamp(0.0, 1.0));
        canvas.drawImageRect(
          glintImg,
          Rect.fromLTWH(
            0,
            0,
            glintImg.width.toDouble(),
            glintImg.height.toDouble(),
          ),
          Rect.fromCenter(center: Offset(mx, my), width: gs * 2, height: gs * 2),
          _fxPaint,
        );
      } else {
        _fxPaint
          ..style = PaintingStyle.fill
          ..maskFilter = null
          ..color = const Color(0xFFFFF59D).withValues(alpha: 0.28 * intensity * pulse);
        canvas.drawCircle(Offset(mx, my), 4.0, _fxPaint);
        _fxPaint.color =
            const Color(0xFFFFF59D).withValues(alpha: 0.72 * intensity * pulse);
        canvas.drawCircle(Offset(mx, my), 2.1, _fxPaint);
      }
    }
    _fxPaint
      ..maskFilter = null
      ..blendMode = BlendMode.srcOver;

    // 4. Twinkling Golden Sparkles (`fx_sparkle.png` + 4-point star glow)
    final sparkleImg = cache.sparkleStar;
    const starOffsets = <Offset>[
      Offset(-78, -56),
      Offset(82, -52),
      Offset(0, -92),
      Offset(-96, -8),
      Offset(100, -4),
    ];
    for (int s = 0; s < starOffsets.length; s++) {
      final twinkle =
          (0.45 + 0.55 * math.sin(ambientPhase * 3.0 + s * 1.4)).clamp(0.0, 1.0) *
              intensity;
      if (twinkle <= 0.08) continue;
      final pt = Offset(cx + starOffsets[s].dx, crownCenterY + starOffsets[s].dy);
      if (sparkleImg != null) {
        final sz = 16.0 * twinkle;
        _fxPaint
          ..style = PaintingStyle.fill
          ..shader = null
          ..maskFilter = null
          ..blendMode = BlendMode.plus
          ..color = const Color(0xFFFFF8C4).withValues(alpha: twinkle.clamp(0.0, 1.0));
        canvas.save();
        canvas.translate(pt.dx, pt.dy);
        canvas.rotate(ambientPhase * 0.4 + s);
        canvas.drawImageRect(
          sparkleImg,
          Rect.fromLTWH(
            0,
            0,
            sparkleImg.width.toDouble(),
            sparkleImg.height.toDouble(),
          ),
          Rect.fromCenter(center: Offset.zero, width: sz, height: sz),
          _fxPaint,
        );
        canvas.restore();
      } else {
        _drawFourPointStar(
          canvas,
          pt,
          7.8 * twinkle,
          const Color(0xFFFFFDE7),
        );
      }
    }
    _fxPaint.blendMode = BlendMode.srcOver;

    // 5. Animated Iridescent Morpho Butterflies (`sxch_an_hd`, matches Flower Merge bloom)
    final bBody = cache.butterflyBody;
    final bWingL = cache.butterflyWingL;
    final bWingR = cache.butterflyWingR;
    if (bBody != null && bWingL != null && bWingR != null && bloomProgress > 0.42) {
      final flyInT = Curves.easeOutCubic.transform(
        ((bloomProgress - 0.42) / 0.34).clamp(0.0, 1.0),
      );
      _drawAnimatedButterfly(
        canvas: canvas,
        body: bBody,
        wingL: bWingL,
        wingR: bWingR,
        center: Offset(
          cx + 76.0 * flyInT + 10.0 * math.sin(ambientPhase * 2.0),
          crownCenterY - 52.0 + 7.5 * math.cos(ambientPhase * 2.8),
        ),
        scale: 0.24 * flyInT,
        tiltRad: -0.34 + 0.14 * math.cos(ambientPhase * 2.0),
        flapPhase: ambientPhase * 9.5,
        alpha: flyInT,
      );
      _drawAnimatedButterfly(
        canvas: canvas,
        body: bBody,
        wingL: bWingL,
        wingR: bWingR,
        center: Offset(
          cx - 78.0 * flyInT + 9.0 * math.cos(ambientPhase * 2.2 + 1.1),
          crownCenterY - 26.0 + 6.5 * math.sin(ambientPhase * 2.6 + 0.8),
        ),
        scale: 0.18 * flyInT,
        tiltRad: 0.38 + 0.14 * math.sin(ambientPhase * 2.2),
        flapPhase: ambientPhase * 10.5 + 1.4,
        alpha: flyInT * 0.92,
      );
    }
  }

  void _drawAnimatedButterfly({
    required Canvas canvas,
    required ui.Image body,
    required ui.Image wingL,
    required ui.Image wingR,
    required Offset center,
    required double scale,
    required double tiltRad,
    required double flapPhase,
    required double alpha,
  }) {
    if (alpha <= 0.02 || scale <= 0.01) return;
    final flap = 0.22 + 0.78 * math.cos(flapPhase).abs();
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..maskFilter = null
      ..blendMode = BlendMode.srcOver
      ..color = Colors.white.withValues(alpha: alpha.clamp(0.0, 1.0));

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tiltRad);
    canvas.scale(scale, scale);

    // Left wing anchored smoothly along centerline (`x = -2`)
    canvas.save();
    canvas.translate(-2.0, 8.0);
    canvas.scale(flap, 1.0);
    canvas.drawImageRect(
      wingL,
      Rect.fromLTWH(0, 0, wingL.width.toDouble(), wingL.height.toDouble()),
      Rect.fromLTWH(
        -wingL.width.toDouble(),
        -wingL.height * 0.5,
        wingL.width.toDouble(),
        wingL.height.toDouble(),
      ),
      _paint,
    );
    canvas.restore();

    // Right wing anchored smoothly along centerline (`x = +2`)
    canvas.save();
    canvas.translate(2.0, 8.0);
    canvas.scale(flap, 1.0);
    canvas.drawImageRect(
      wingR,
      Rect.fromLTWH(0, 0, wingR.width.toDouble(), wingR.height.toDouble()),
      Rect.fromLTWH(
        0.0,
        -wingR.height * 0.5,
        wingR.width.toDouble(),
        wingR.height.toDouble(),
      ),
      _paint,
    );
    canvas.restore();

    // Body centered directly over the wing hinge
    canvas.drawImageRect(
      body,
      Rect.fromLTWH(0, 0, body.width.toDouble(), body.height.toDouble()),
      Rect.fromCenter(
        center: Offset.zero,
        width: body.width.toDouble(),
        height: body.height.toDouble(),
      ),
      _paint,
    );

    canvas.restore();
  }

  void _drawNewVaseRevealSparkles({
    required Canvas canvas,
    required double cx,
    required double cy,
    required double t,
  }) {
    final fade = (1.0 - t).clamp(0.0, 1.0);
    for (int i = 0; i < 10; i++) {
      final a = (i * math.pi * 2.0) / 10.0 + 0.3;
      final dist = 48.0 + 98.0 * Curves.easeOutCubic.transform(t);
      _drawFourPointStar(
        canvas,
        Offset(cx + dist * math.cos(a), cy + dist * math.sin(a) * 0.85),
        9.2 * fade,
        const Color(0xFFFFF9C4).withValues(alpha: fade),
      );
    }
  }

  void _drawFourPointStar(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
  ) {
    if (radius <= 0.5) return;

    // Soft radial star halo glow (no MaskFilter.blur per frame)
    _fxPaint
      ..style = PaintingStyle.fill
      ..maskFilter = null
      ..blendMode = BlendMode.plus
      ..color = color.withValues(alpha: color.a * 0.26);
    canvas.drawCircle(center, radius * 1.15, _fxPaint);
    _fxPaint.color = color.withValues(alpha: color.a * 0.45);
    canvas.drawCircle(center, radius * 0.65, _fxPaint);
    _fxPaint.blendMode = BlendMode.srcOver;

    final inner = radius * 0.24;
    _scratchPath
      ..reset()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + inner,
        center.dy - inner,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + inner,
        center.dy + inner,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - inner,
        center.dy + inner,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - inner,
        center.dy - inner,
        center.dx,
        center.dy - radius,
      )
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = color;
    canvas.drawPath(_scratchPath, _paint);
  }

  @override
  bool shouldRepaint(covariant _WaterGardenMasterPainter oldDelegate) {
    return oldDelegate.oldWaterProgress != oldWaterProgress ||
        oldDelegate.waterProgress != waterProgress ||
        oldDelegate.pourProgress != pourProgress ||
        oldDelegate.jarEnterProgress != jarEnterProgress ||
        oldDelegate.jarExitProgress != jarExitProgress ||
        oldDelegate.bloomProgress != bloomProgress ||
        oldDelegate.raysProgress != raysProgress ||
        oldDelegate.ambientPhase != ambientPhase ||
        oldDelegate.config.vaseId != config.vaseId ||
        oldDelegate.isNewVaseReveal != isNewVaseReveal ||
        oldDelegate.newVaseSparkleT != newVaseSparkleT ||
        oldDelegate.spriteVersion != spriteVersion;
  }
}


/// Reusable Side-by-Side Level Complete Monetization Action Bar (100% 3-Slice `UnityNineSlice`):
/// - Left Button: [UnityStackedCoinCtaButton] (`Button_Green.png` + `+${rewardCoins}`)
/// - Right Button: [UnityStackedAdCtaButton] (`Button_Yellow.png` + `Icon_Ads.png` + `+${rewardCoins * 2}`)
class LevelCompleteDualActionRow extends StatelessWidget {
  final int rewardCoins;
  final Animation<double> shimmerAnimation;
  final bool enabled;
  final VoidCallback onNextLevel;
  final VoidCallback onRewardX2;

  const LevelCompleteDualActionRow({
    super.key,
    required this.rewardCoins,
    required this.shimmerAnimation,
    this.enabled = true,
    required this.onNextLevel,
    required this.onRewardX2,
  });

  @override
  Widget build(BuildContext context) {
    final baseCoins = math.max(1, rewardCoins);
    final doubleCoins = baseCoins * 2;

    return Row(
      children: [
        Expanded(
          child: UnityStackedCoinCtaButton(
            key: const ValueKey('garden_next_level_btn'),
            label: 'Next Level',
            coinLabel: '+$baseCoins',
            sprite: 'Button_Green.png',
            unityHeight: 216,
            unityFontSize: 52,
            insetUnityWidth: 216,
            insetUnityHeight: 56,
            onTap: enabled ? onNextLevel : null,
          ),
        ),
        SizedBox(width: ux(context, 28)),
        Expanded(
          child: AnimatedBuilder(
            animation: shimmerAnimation,
            builder: (context, _) {
              return UnityStackedAdCtaButton(
                key: const ValueKey('garden_reward_x2_btn'),
                label: 'Reward x2',
                coinLabel: '+$doubleCoins',
                shimmerPhase: shimmerAnimation.value,
                unityHeight: 216,
                unityFontSize: 52,
                insetUnityWidth: 216,
                insetUnityHeight: 56,
                onTap: enabled ? onRewardX2 : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
