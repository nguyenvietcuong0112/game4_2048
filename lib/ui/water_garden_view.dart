import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

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

  @override
  void initState() {
    super.initState();
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
        final ribbonTop = math.max(coinsBottomSafeY, safeH * 0.066);
        final ribbonH = (safeH * 0.112).clamp(68.0, 92.0);
        final ribbonW = math.min(352.0, safeW - 20.0);

        final bottomPad = math.max(12.0, safeH * 0.020);
        const bottomControlsEstimatedH = 178.0;
        final stageTop = ribbonTop + ribbonH - 10.0;
        final stageBottom = math.max(
          stageTop + 176.0,
          safeH - bottomPad - bottomControlsEstimatedH + 8.0,
        );
        final stageAvailH = stageBottom - stageTop;

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
                        width: 380,
                        height: 418,
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

                // 3. Bottom Section: Gold-Rimmed Royal-Indigo Progress Card + Native Old-Theme CTA Buttons
                if (!_showClaimModal)
                  Positioned(
                    bottom: bottomPad,
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
                          constraints: const BoxConstraints(maxWidth: 372),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: Listenable.merge([
                                  _seqCtrl,
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
                              const SizedBox(height: 14),
                              if (is100 && !_showingNextVase)
                                _GardenTealPillButton(
                                  key: const ValueKey('garden_claim_btn'),
                                  label: 'Claim',
                                  width: 228,
                                  height: 68,
                                  fontSize: 23,
                                  enabled: !widget.isActionBusy,
                                  onTap: _handleClaimTapped,
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

  /// Level Complete Action Buttons:
  /// - Levels 1..6 (`!_effectiveShowRewardX2`): Single centered `Button_Green.png` (`Next Level` + `+coins`).
  /// - Level 7+ (`_effectiveShowRewardX2`): Side-by-side `Next Level` (`+coins`) & `Reward x2` (`+coins * 2` + `Icon_Ads.png`).
  Widget _buildDualNextAndRewardButtons() {
    if (!_effectiveShowRewardX2) {
      return Center(
        child: SizedBox(
          width: 236,
          child: _GardenNextLevelCoinButton(
            key: const ValueKey('garden_next_level_btn'),
            rewardCoins: math.max(1, widget.rewardCoins),
            enabled: !widget.isActionBusy,
            onTap: _handleNextLevelTapped,
          ),
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

  /// Panel 5 `"New Mechanic!"` Reward Popup Card styled 1:1 with the game's native popup kit:
  /// - `popup_bg.png` gold-rimmed royal-blue body
  /// - `Frame_Popup_Title.png` top header ribbon (`"New Mechanic!"` / `"Bonus Reward!"`)
  /// - `frame_content.png` warm cream inner well with 3D reward icon + coins + `#5A270B` title
  /// - `Button_Green.png` `"Claim"` CTA button!
  Widget _buildNewMechanicCard({
    required BuildContext context,
    required VaseMilestoneConfig config,
    required double maxCardHeight,
    required VoidCallback onClaim,
  }) {
    final modalHeaderTitle =
        config.unlockMechanicId != null ? 'New Mechanic!' : 'Bonus Reward!';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 334,
        maxHeight: math.max(276.0, maxCardHeight),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 330,
          height: 306,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              // 1. Gold-Rimmed Royal-Blue Popup Body (`popup_bg.png`)
              Positioned(
                left: 0,
                right: 0,
                top: 14,
                bottom: 0,
                child: Image.asset(
                  'assets/images/popup_bg.png',
                  fit: BoxFit.fill,
                ),
              ),

              // 2. Warm Cream Inner Content Well (`frame_content.png`)
              Positioned(
                left: 19,
                right: 19,
                top: 56,
                height: 162,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/frame_content.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
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
                                  right: 6,
                                  bottom: 2,
                                  child: _SingleNodeUnitySdfText(
                                    '+${config.rewardCoins}',
                                    fontSize: 19.5,
                                    material: UnityTextMaterial.winCoinAmount,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            config.rewardTitle,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: const TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: 23.0,
                              fontWeight: FontWeight.w800,
                              fontVariations: [FontVariation('wght', 800)],
                              height: 1.06,
                              color: Color(0xFF5A270B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Bottom Native `Button_Green.png` `"Claim"` CTA Button
              Positioned(
                bottom: 15,
                child: _GardenTealPillButton(
                  label: 'Claim',
                  width: 214,
                  height: 62,
                  fontSize: 22.0,
                  enabled: !widget.isActionBusy,
                  onTap: onClaim,
                ),
              ),

              // 4. Top Overlapping Ribbon (`Frame_Popup_Title.png`)
              Positioned(
                top: 0,
                width: 248,
                height: 50,
                child: Container(
                  key: ValueKey<String>(modalHeaderTitle),
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/Frame_Popup_Title.png',
                          fit: BoxFit.fill,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 2, 22, 6),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _SingleNodeUnitySdfText(
                            modalHeaderTitle,
                            fontSize: 21.0,
                            material: UnityTextMaterial.popupTitle,
                          ),
                        ),
                      ),
                    ],
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

/// Single-node SDF Text widget rendering exact `UnityTextMaterial` strokes & 3D drop underlay
/// via `CustomPaint` behind a **single** `Text` widget so `find.text(...)` matches `findsOneWidget`!
class _SingleNodeUnitySdfText extends StatelessWidget {
  final String text;
  final double fontSize;
  final UnityTextMaterial material;

  const _SingleNodeUnitySdfText(
    this.text, {
    required this.fontSize,
    required this.material,
  });

  @override
  Widget build(BuildContext context) {
    final weightVal = material.fontWeight.value.toDouble();
    final variations = material.fontFamily == 'Baloo2'
        ? [FontVariation('wght', weightVal)]
        : null;

    TextStyle buildStyle({Paint? foreground, Color? color}) => TextStyle(
          fontFamily: material.fontFamily,
          fontSize: fontSize,
          fontWeight: material.fontWeight,
          fontVariations: variations,
          letterSpacing: material.letterSpacing,
          height: 1.08,
          foreground: foreground,
          color: color,
        );

    final faceChild = material.faceTop != material.faceBottom
        ? Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: buildStyle(
              foreground: Paint()
                ..shader = ui.Gradient.linear(
                  Offset(0, fontSize * 0.12),
                  Offset(0, fontSize * 0.98),
                  [material.faceTop, material.faceBottom],
                ),
            ),
          )
        : Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: buildStyle(color: material.faceTop),
          );

    return CustomPaint(
      painter: _SdfOutlineLayerPainter(
        text: text,
        fontSize: fontSize,
        material: material,
      ),
      child: faceChild,
    );
  }
}

class _SdfOutlineLayerPainter extends CustomPainter {
  final String text;
  final double fontSize;
  final UnityTextMaterial material;

  const _SdfOutlineLayerPainter({
    required this.text,
    required this.fontSize,
    required this.material,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;
    final weightVal = material.fontWeight.value.toDouble();
    final variations = material.fontFamily == 'Baloo2'
        ? [FontVariation('wght', weightVal)]
        : null;

    final innerSw = (fontSize * material.strokeRatio).clamp(1.2, 16.0);
    final outerSw = material.outerStrokeColor != null
        ? (fontSize * material.outerStrokeRatio).clamp(innerSw + 0.6, 20.0)
        : innerSw;
    final dropY = fontSize * material.underlayYRatio;

    TextStyle strokeStyle(double width, Color color) => TextStyle(
          fontFamily: material.fontFamily,
          fontSize: fontSize,
          fontWeight: material.fontWeight,
          fontVariations: variations,
          letterSpacing: material.letterSpacing,
          height: 1.08,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round
            ..color = color,
        );

    final tp = TextPainter(textDirection: TextDirection.ltr);

    void paintLayer(double width, Color color, double dy) {
      tp.text = TextSpan(text: text, style: strokeStyle(width, color));
      tp.layout();
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) * 0.5,
          (size.height - tp.height) * 0.5 + dy,
        ),
      );
    }

    // 1. 3D Drop Underlay
    if (dropY > 0.15) {
      paintLayer(outerSw, material.underlayColor, dropY);
    }
    // 2. Optional Outer Stroke
    if (material.outerStrokeColor != null) {
      paintLayer(outerSw, material.outerStrokeColor!, 0.0);
    }
    // 3. Primary Inner Stroke
    paintLayer(innerSw, material.strokeColor, 0.0);
  }

  @override
  bool shouldRepaint(covariant _SdfOutlineLayerPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.fontSize != fontSize ||
        oldDelegate.material != material;
  }
}

/// Left Level Complete CTA Button (Native Old Theme):
/// Gold-rimmed `Button_Green.png` with `"Next Level"` (`ctaGreen`) on top
/// and `Inset_Button_CTA.png` (`Icon_Coin.png` + `+coins`) below!
class _GardenNextLevelCoinButton extends StatefulWidget {
  final int rewardCoins;
  final bool enabled;
  final VoidCallback onTap;

  const _GardenNextLevelCoinButton({
    super.key,
    required this.rewardCoins,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_GardenNextLevelCoinButton> createState() =>
      _GardenNextLevelCoinButtonState();
}

class _GardenNextLevelCoinButtonState
    extends State<_GardenNextLevelCoinButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const height = 74.0;
    final active = widget.enabled;
    final textMat =
        active ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;

    Widget body = SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/Button_Green.png',
              fit: BoxFit.fill,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _SingleNodeUnitySdfText(
                      'Next Level',
                      fontSize: 18.5,
                      material: textMat,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // Native recessed dark-green coin inset (`Inset_Button_CTA.png`)
                SizedBox(
                  height: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/Inset_Button_CTA.png',
                          fit: BoxFit.fill,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _GoldCoinBadgeIcon(size: 16.5),
                            const SizedBox(width: 5),
                            _SingleNodeUnitySdfText(
                              '+${widget.rewardCoins}',
                              fontSize: 15.0,
                              material: textMat,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!active) {
      body = ColorFiltered(
        colorFilter: UnityButtonColorFilters.disabledSilver,
        child: body,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              if (_pressed) setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: active ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: body,
      ),
    );
  }
}

/// Right Level Complete Monetization CTA Button (Native Old Theme):
/// Gold-rimmed `Button_Yellow.png` with `"Reward x2"` (`ctaYellowButton`) on top,
/// coin icon + `+${doubledCoins}` below, and overlapping top-left `Icon_Ads.png` clapperboard badge!
class _GardenRewardX2CoinButton extends StatefulWidget {
  final int doubledCoins;
  final double shimmerPhase;
  final bool enabled;
  final VoidCallback onTap;

  const _GardenRewardX2CoinButton({
    super.key,
    required this.doubledCoins,
    required this.shimmerPhase,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_GardenRewardX2CoinButton> createState() =>
      _GardenRewardX2CoinButtonState();
}

class _GardenRewardX2CoinButtonState extends State<_GardenRewardX2CoinButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    const height = 74.0;
    final active = widget.enabled;
    final textMat =
        active ? UnityTextMaterial.ctaYellowButton : UnityTextMaterial.ctaGray;
    final breath = _pressed
        ? 0.94
        : (active
            ? (1.0 + 0.015 * math.sin(widget.shimmerPhase * math.pi * 4.0))
            : 1.0);

    Widget body = SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. Native Gold-Rimmed Golden-Orange Pill (`Button_Yellow.png`)
          Positioned.fill(
            child: Image.asset(
              'assets/images/Button_Yellow.png',
              fit: BoxFit.fill,
            ),
          ),

          // 2. Subtle Diagonal Golden Shimmer Sweep inside the button face
          if (active)
            Positioned(
              left: 8,
              right: 8,
              top: 6,
              bottom: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ButtonShimmerSweepPainter(
                      phase: (widget.shimmerPhase * 2.0) % 1.0,
                    ),
                  ),
                ),
              ),
            ),

          // 3. Stacked `"Reward x2"` + Recessed Doubled-Coin Pill
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 7, 14, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _SingleNodeUnitySdfText(
                        'Reward x2',
                        fontSize: 18.5,
                        material: textMat,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: const Color(0x4D7A2E00),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: const Color(0x58FFE082),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _GoldCoinBadgeIcon(size: 16.5),
                      const SizedBox(width: 5),
                      _SingleNodeUnitySdfText(
                        '+${widget.doubledCoins}',
                        fontSize: 15.0,
                        material: textMat,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Overlapping Top-Left 3D Clapperboard Badge (`Icon_Ads.png` — exact match with `LoseOverlay`)
          Positioned(
            left: -5,
            top: -11,
            width: 37,
            height: 39,
            child: Image.asset(
              'assets/images/Icon_Ads.png',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );

    if (!active) {
      body = ColorFiltered(
        colorFilter: UnityButtonColorFilters.disabledSilver,
        child: body,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              if (_pressed) setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: active ? () => setState(() => _pressed = false) : null,
      child: Transform.scale(
        scale: breath,
        child: body,
      ),
    );
  }
}

class _ButtonShimmerSweepPainter extends CustomPainter {
  final double phase;

  const _ButtonShimmerSweepPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    if (phase > 0.52) return;
    final t = (phase / 0.52).clamp(0.0, 1.0);
    final sweepX = ui.lerpDouble(-size.width * 0.45, size.width * 1.35, t)!;
    final bandW = size.width * 0.30;

    final path = Path()
      ..moveTo(sweepX, 0)
      ..lineTo(sweepX + bandW, 0)
      ..lineTo(sweepX + bandW - 18, size.height)
      ..lineTo(sweepX - 18, size.height)
      ..close();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(sweepX - 10, 0),
        Offset(sweepX + bandW, 0),
        const [
          Color(0x00FFFFFF),
          Color(0x46FFFDE7),
          Color(0x00FFFFFF),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ButtonShimmerSweepPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class _GoldCoinBadgeIcon extends StatelessWidget {
  final double size;

  const _GoldCoinBadgeIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/Icon_Coin.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => SizedBox(
        width: size,
        height: size,
        child: const CustomPaint(painter: _MiniGoldCoinPainter()),
      ),
    );
  }
}

/// Native Old-Theme Gold-Rimmed Green CTA Button (`Button_Green.png`) for `"Claim"`.
class _GardenTealPillButton extends StatefulWidget {
  final String label;
  final double width;
  final double height;
  final double fontSize;
  final bool enabled;
  final VoidCallback onTap;

  const _GardenTealPillButton({
    super.key,
    required this.label,
    required this.width,
    required this.height,
    required this.fontSize,
    this.enabled = true,
    required this.onTap,
  });

  @override
  State<_GardenTealPillButton> createState() => _GardenTealPillButtonState();
}

class _GardenTealPillButtonState extends State<_GardenTealPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    final textMat =
        active ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;

    Widget body = SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/Button_Green.png',
              fit: BoxFit.fill,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 9),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _SingleNodeUnitySdfText(
                widget.label,
                fontSize: widget.fontSize,
                material: textMat,
              ),
            ),
          ),
        ],
      ),
    );

    if (!active) {
      body = ColorFiltered(
        colorFilter: UnityButtonColorFilters.disabledSilver,
        child: body,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              if (_pressed) setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: active ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: body,
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
            Color(0xFF1B1046),
            Color(0xFF120B32),
            Color(0xFF0A0720),
          ],
          const [0.0, 0.52, 1.0],
        );
      canvas.drawRect(rect, _paint);
      _paint.shader = null;
    }

    // 1. Soft Magical Royal-Violet & Cyan Aura behind the 3D Crystal Vase
    final breathe = 1.0 + 0.04 * math.sin(ambientPhase);
    final stageCenter = Offset(
      size.width * 0.5,
      size.height * stageCenterYFraction,
    );
    final outerR = math.min(size.width, size.height) * 0.62 * breathe;
    _paint
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        stageCenter,
        outerR,
        const [
          Color(0x4242E8FF),
          Color(0x287E57C2),
          Color(0x12FFD54F),
          Color(0x001A1046),
        ],
        const [0.0, 0.42, 0.72, 1.0],
      );
    canvas.drawCircle(stageCenter, outerR, _paint);

    // 2. Warm Golden Halo behind the Top `'Level / Complete!'` Wave Header
    final headerCenter = Offset(size.width * 0.5, size.height * 0.12);
    final headerR = math.min(size.width, size.height) * 0.36 * breathe;
    _paint.shader = ui.Gradient.radial(
      headerCenter,
      headerR,
      const [
        Color(0x3EFFE082),
        Color(0x1CFFB300),
        Color(0x00FFB300),
      ],
      const [0.0, 0.52, 1.0],
    );
    canvas.drawCircle(headerCenter, headerR, _paint);
    _paint.shader = null;
    _paint.blendMode = BlendMode.srcOver;

    // 3. Subtle Floating Golden & Cyan Starlight Bokeh Motes
    for (int i = 0; i < 14; i++) {
      final seed = i * 1.73;
      final fx = 0.08 +
          ((i * 0.193) % 0.84) +
          0.020 * math.sin(ambientPhase + seed);
      final rawY =
          ((i * 0.137) - (ambientPhase / (math.pi * 2.0)) * 0.16) % 1.0;
      final fy = rawY < 0 ? rawY + 1.0 : rawY;
      final radius = 2.2 + (i % 4) * 2.1;
      final alpha = (0.08 + 0.10 * math.sin(ambientPhase * 2.0 + seed))
          .clamp(0.02, 0.20);
      final baseColor =
          i.isEven ? const Color(0xFFFFE082) : const Color(0xFF80F8FF);
      _paint.color = baseColor.withValues(alpha: alpha);
      canvas.drawCircle(
        Offset(fx * size.width, fy * size.height),
        radius,
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OldThemeStageBackdropPainter oldDelegate) =>
      oldDelegate.ambientPhase != ambientPhase ||
      oldDelegate.drawSolidScrim != drawSolidScrim ||
      oldDelegate.stageCenterYFraction != stageCenterYFraction;
}

/// Classic Old-Theme 2-Line `'Level' / 'Complete!'` Golden Wave Header Painter
/// matching `WinOverlay._buildTwoLineWaveLevelComplete` (`PoetsenOne` + `UnityTextMaterial.levelCompleteWave`):
/// - 2-pass per-line rendering (Pass 1: all 3D drop shadows & brown/orange strokes; Pass 2: golden gradient faces)
///   so neighboring character outlines never overlap faces!
/// - Continuous `C∞` sine wave (`sin(ambientValue * 4π - phase)`) for silky 60/120Hz motion.
class _OldThemeLevelCompleteHeaderPainter extends CustomPainter {
  final double ambientValue;

  static final TextPainter _tp = TextPainter(textDirection: TextDirection.ltr);

  _OldThemeLevelCompleteHeaderPainter({required this.ambientValue});

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final fs1 = (h * 0.44).clamp(26.0, 42.0);
    final fs2 = (h * 0.40).clamp(24.0, 38.0);
    final waveAmp = (h * 0.032).clamp(1.8, 3.0);

    _drawWaveLine(
      canvas: canvas,
      centerX: size.width * 0.5,
      baselineCenterY: h * 0.29,
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
    const mat = UnityTextMaterial.levelCompleteWave;
    final innerSw = (fontSize * mat.strokeRatio).clamp(1.6, 12.0);
    final outerSw =
        (fontSize * mat.outerStrokeRatio).clamp(innerSw + 0.8, 16.0);
    final dropY = fontSize * mat.underlayYRatio;

    TextStyle styleWith(Paint foreground) => TextStyle(
          fontFamily: mat.fontFamily,
          fontSize: fontSize,
          fontWeight: mat.fontWeight,
          height: 1.05,
          foreground: foreground,
        );

    final measureStyle = TextStyle(
      fontFamily: mat.fontFamily,
      fontSize: fontSize,
      fontWeight: mat.fontWeight,
      height: 1.05,
      color: Colors.white,
    );

    final widths = <double>[];
    double totalW = 0.0;
    double lineH = fontSize;
    for (int i = 0; i < text.length; i++) {
      _tp.text = TextSpan(text: text[i], style: measureStyle);
      _tp.layout();
      widths.add(_tp.width);
      totalW += _tp.width;
      lineH = _tp.height;
    }

    final scale = totalW > maxWidth ? (maxWidth / totalW) : 1.0;

    final underlayStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerSw
        ..strokeJoin = StrokeJoin.round
        ..color = mat.underlayColor,
    );
    final outerStrokeStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerSw
        ..strokeJoin = StrokeJoin.round
        ..color = mat.outerStrokeColor!,
    );
    final innerStrokeStyle = styleWith(
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = innerSw
        ..strokeJoin = StrokeJoin.round
        ..color = mat.strokeColor,
    );
    final faceStyle = styleWith(
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, fontSize * 0.12),
          Offset(0, fontSize * 0.96),
          [mat.faceTop, mat.faceBottom],
        ),
    );

    canvas.save();
    canvas.translate(centerX, baselineCenterY);
    if (scale < 0.999) {
      canvas.scale(scale, scale);
    }

    // Pass 1: 3D Drop Underlay + Outer Crimson-Brown Stroke + Inner Warm-Orange Stroke
    double cursorX = -totalW * 0.5;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final waveAngle = ambientValue * math.pi * 4.0 - (i + phaseOffset) * 0.42;
      final waveDy = math.sin(waveAngle) * waveAmp;
      final topY = -lineH * 0.5 + waveDy;

      _tp.text = TextSpan(text: ch, style: underlayStyle);
      _tp.layout();
      _tp.paint(canvas, Offset(cursorX, topY + dropY));

      _tp.text = TextSpan(text: ch, style: outerStrokeStyle);
      _tp.layout();
      _tp.paint(canvas, Offset(cursorX, topY));

      _tp.text = TextSpan(text: ch, style: innerStrokeStyle);
      _tp.layout();
      _tp.paint(canvas, Offset(cursorX, topY));

      cursorX += widths[i];
    }

    // Pass 2: Crisp White-to-Gold Gradient Faces
    cursorX = -totalW * 0.5;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final waveAngle = ambientValue * math.pi * 4.0 - (i + phaseOffset) * 0.42;
      final waveDy = math.sin(waveAngle) * waveAmp;
      final topY = -lineH * 0.5 + waveDy;

      _tp.text = TextSpan(text: ch, style: faceStyle);
      _tp.layout();
      _tp.paint(canvas, Offset(cursorX, topY));

      cursorX += widths[i];
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

class _MiniGoldCoinPainter extends CustomPainter {
  const _MiniGoldCoinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * 0.5, size.height * 0.5);
    final r = size.width * 0.46;
    final p = Paint()..isAntiAlias = true;

    p.color = const Color(0xFFD97706);
    canvas.drawCircle(c.translate(0, 1.2), r, p);

    p
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(c.dx - r, c.dy - r),
        Offset(c.dx + r, c.dy + r),
        const [Color(0xFFFFF59D), Color(0xFFFFB300)],
      );
    canvas.drawCircle(c, r, p);
    p.shader = null;

    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = const Color(0xEEFFFDE7);
    canvas.drawCircle(c, r * 0.68, p);
  }

  @override
  bool shouldRepaint(covariant _MiniGoldCoinPainter oldDelegate) => false;
}

/// Parametric geometry metrics for each of the 5 sculpted 3D Vase shapes.
class _VaseMetrics {
  final double topRimY;
  final double neckY;
  final double baseY;
  final double mouthHalfW;
  final double neckHalfW;
  final double bellyHalfW;
  final double baseHalfW;

  const _VaseMetrics({
    required this.topRimY,
    required this.neckY,
    required this.baseY,
    required this.mouthHalfW,
    required this.neckHalfW,
    required this.bellyHalfW,
    required this.baseHalfW,
  });

  static _VaseMetrics forShape(VaseShapeType type, double centerY) {
    return switch (type) {
      // Plump spherical glass fishbowl (Panel 3!)
      VaseShapeType.fishbowl => _VaseMetrics(
          topRimY: centerY - 64,
          neckY: centerY - 46,
          baseY: centerY + 116,
          mouthHalfW: 59,
          neckHalfW: 52,
          bellyHalfW: 108,
          baseHalfW: 61,
        ),
      // Plump rounded crystal-ceramic bowl (Panels 4 & 5!)
      VaseShapeType.ovalCeramic => _VaseMetrics(
          topRimY: centerY - 66,
          neckY: centerY - 47,
          baseY: centerY + 116,
          mouthHalfW: 57,
          neckHalfW: 50,
          bellyHalfW: 105,
          baseHalfW: 59,
        ),
      // Melon-ribbed fluted crystal vase (Panel 6!)
      VaseShapeType.flutedCrystal => _VaseMetrics(
          topRimY: centerY - 72,
          neckY: centerY - 50,
          baseY: centerY + 116,
          mouthHalfW: 54,
          neckHalfW: 46,
          bellyHalfW: 108,
          baseHalfW: 58,
        ),
      // Regal high-shoulder royal amphora
      VaseShapeType.royalTall => _VaseMetrics(
          topRimY: centerY - 80,
          neckY: centerY - 54,
          baseY: centerY + 116,
          mouthHalfW: 51,
          neckHalfW: 40,
          bellyHalfW: 98,
          baseHalfW: 56,
        ),
      // Faceted diamond-lotus crystal vase
      VaseShapeType.prismLotus => _VaseMetrics(
          topRimY: centerY - 70,
          neckY: centerY - 50,
          baseY: centerY + 116,
          mouthHalfW: 56,
          neckHalfW: 47,
          bellyHalfW: 105,
          baseHalfW: 58,
        ),
    };
  }

  /// Half-width of the interior chamber at height `y` (used for the 3D elliptical meniscus!).
  double innerHalfWidthAt(double y, VaseShapeType type) {
    final t = ((y - neckY) / (baseY - neckY)).clamp(0.0, 1.0);
    final profile = switch (type) {
      VaseShapeType.fishbowl => math.sin(t * math.pi * 0.88 + 0.18),
      VaseShapeType.ovalCeramic => math.sin(t * math.pi * 0.88 + 0.18),
      VaseShapeType.flutedCrystal => math.sin(t * math.pi * 0.85 + 0.20),
      VaseShapeType.royalTall =>
        math.pow(math.sin(t * math.pi * 0.90 + 0.14), 0.78).toDouble(),
      VaseShapeType.prismLotus => math.sin(t * math.pi * 0.88 + 0.16),
    };
    final rawW = ui.lerpDouble(neckHalfW, bellyHalfW, profile.clamp(0.0, 1.0))!;
    final baseTaper = t > 0.82 ? ((t - 0.82) / 0.18).clamp(0.0, 1.0) : 0.0;
    final outerW = ui.lerpDouble(rawW, baseHalfW, baseTaper * 0.75)!;
    return math.max(18.0, outerW - 6.5);
  }
}

/// Zero-Allocation Master 3D Painter for the Garden Stage (`380 x 418` virtual canvas):
/// Renders in strict physical back-to-front 3D order for authentic glass/water/stem refraction.
class _WaterGardenMasterPainter extends CustomPainter {
  final VaseMilestoneConfig config;
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

  static final Path _vaseOuterPath = Path();
  static final Path _vaseInnerPath = Path();
  static final Path _scratchPath = Path();
  static final Path _petalPath = Path();
  static final Paint _paint = Paint()..isAntiAlias = true;
  static final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  _WaterGardenMasterPainter({
    required this.config,
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
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paint
      ..color = Colors.white
      ..shader = null
      ..style = PaintingStyle.fill;

    final cx = size.width * 0.5;
    final cy = size.height * 0.575;
    final metrics = _VaseMetrics.forShape(config.shapeType, cy);

    // 0. Celebration Sunburst God-Rays behind the vase (on 100% bloom or new-vase reveal)
    if (raysProgress > 0.01) {
      _drawCelebrationSunburst(
        canvas,
        Offset(cx, metrics.topRimY + 28),
        raysProgress,
      );
    }

    // 1. 3D Cream-Ivory Stone Pedestal + Refracted Cyan Water Caustics
    _drawPedestal(
      canvas,
      cx: cx,
      topSurfaceY: metrics.baseY + 2,
      causticIntensity: waterProgress.clamp(0.0, 1.0),
    );

    // Build exact outer & inner 3D sculpted vase paths
    _buildVaseSilhouettePath(
      _vaseOuterPath,
      cx: cx,
      m: metrics,
      type: config.shapeType,
      inset: 0.0,
    );
    _buildVaseSilhouettePath(
      _vaseInnerPath,
      cx: cx,
      m: metrics,
      type: config.shapeType,
      inset: 6.0,
    );

    // Compute live rising water surface Y
    final clampedFill = waterProgress.clamp(0.0, 1.0);
    final maxFillTopY = metrics.neckY + 11.0;
    final minFillBottomY = metrics.baseY - 8.0;
    final waterTopY =
        ui.lerpDouble(minFillBottomY, maxFillTopY, clampedFill)!;

    // 2. Back Crystal Glass Wall & Back Rim Half
    _drawBackGlassWall(canvas, cx, metrics);

    // 3. Underwater Refracted Stem Segment (drawn behind the water volume!)
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

    // 4. Volumetric 3D Water Body + Sloshing Perspective Elliptical Meniscus + Ripples + 20 Bubbles
    _drawVolumetricWater(
      canvas: canvas,
      cx: cx,
      metrics: metrics,
      fillFraction: clampedFill,
      waterTopY: waterTopY,
      isStreamImpacting: isStreamTouchingWater,
      pourT: pourProgress,
    );

    // 5. Above-Water Botanical Stems, Curled Two-Tone Leaves & Continuous Bud -> 3/4 Bouquet Bloom!
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

    // 6. Parabolic Trajectory of Mini `2048` Potion Jar & Progressive Waterfall Stream
    final enterT = jarEnterProgress.clamp(0.0, 1.0);
    final exitT = jarExitProgress.clamp(0.0, 1.0);
    final jarVisibility = (enterT * (1.0 - exitT)).clamp(0.0, 1.0);

    // Smooth curved flight arc from upper-left into pouring hover spot, then graceful upward exit
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

    // Smooth wrist-pour rotation (`0.18 rad` upright -> `1.02 rad` pouring -> `0.42 rad` upright exit)
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
          clampedFill > 0.03 ? waterTopY : (metrics.baseY - 14),
        ),
        headT: streamHeadT,
        tailT: streamTailT,
        pourT: pourProgress,
      );
    }

    // 7. Front Crystal Glass Wall, Sculpted Flutes/Facets, Warm Gold Neck Ring & Rolled Rim
    _drawFrontGlassOverlay(
      canvas,
      cx,
      metrics,
      config.shapeType,
      hasWater: clampedFill > 0.02,
    );

    // 8. Tilted Mini Crystal Potion Jar + Gravity-Level Draining Liquid + Golden Rope + `2048` Tag
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

    // 9. Cupped 3D Drifting Petals & 4-Point Starlight Sparkles (100% Bloom or New Vase Reveal)
    if (bloomProgress > 0.14) {
      _drawFloatingPetalsAndSparkles(
        canvas: canvas,
        cx: cx,
        topY: metrics.topRimY - 24,
        intensity: ((bloomProgress - 0.14) / 0.86).clamp(0.0, 1.0),
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
    const maxR = 192.0;

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        center,
        maxR,
        [
          const Color(0xFFFFF9C4).withValues(alpha: 0.58 * p),
          const Color(0xFFFFE082).withValues(alpha: 0.22 * p),
          const Color(0x00FFE082),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(center, maxR, _paint);
    _paint.shader = null;

    const rayCount = 16;
    final rot = ambientPhase * 0.30;
    for (int i = 0; i < rayCount; i++) {
      final a = (i * math.pi * 2.0) / rayCount + rot;
      const halfSpan = 0.072;
      _scratchPath
        ..reset()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + maxR * math.cos(a - halfSpan),
          center.dy + maxR * math.sin(a - halfSpan),
        )
        ..lineTo(
          center.dx + maxR * math.cos(a + halfSpan),
          center.dy + maxR * math.sin(a + halfSpan),
        )
        ..close();

      _paint
        ..color = Colors.white
        ..shader = ui.Gradient.radial(
          center,
          maxR,
          [
            const Color(0xFFFFFDE7).withValues(alpha: 0.36 * p),
            const Color(0x00FFFDE7),
          ],
        );
      canvas.drawPath(_scratchPath, _paint);
    }
    _paint.shader = null;
  }

  void _drawPedestal(
    Canvas canvas, {
    required double cx,
    required double topSurfaceY,
    required double causticIntensity,
  }) {
    const topW = 240.0;
    const topH = 40.0;
    const rimThickness = 16.5;

    // 1. Deep royal-indigo floor shadow on dark stage
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = const Color(0x7804021A);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, topSurfaceY + rimThickness + 8),
        width: topW + 24,
        height: topH + 14,
      ),
      _paint,
    );

    // 2. Seamless 3D Solid Warm-Ivory Stone Cylinder Wall
    final bottomRect = Rect.fromCenter(
      center: Offset(cx, topSurfaceY + rimThickness),
      width: topW,
      height: topH,
    );
    final sideWallRect = Rect.fromLTRB(
      cx - topW * 0.5,
      topSurfaceY,
      cx + topW * 0.5,
      topSurfaceY + rimThickness,
    );

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - topW * 0.5, topSurfaceY),
        Offset(cx + topW * 0.5, topSurfaceY),
        const [
          Color(0xFFCBBBA0),
          Color(0xFFF0E7D4),
          Color(0xFFDDD1B8),
          Color(0xFFB39E7F),
        ],
        const [0.0, 0.32, 0.68, 1.0],
      );
    canvas.drawOval(bottomRect, _paint);
    canvas.drawRect(sideWallRect, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0x668D7759);
    canvas.drawArc(bottomRect, 0.0, math.pi, false, _paint);

    // 3. Sunlit stone top ellipse
    final topRect = Rect.fromCenter(
      center: Offset(cx, topSurfaceY),
      width: topW,
      height: topH,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, topSurfaceY - topH * 0.5),
        Offset(cx, topSurfaceY + topH * 0.5),
        const [
          Color(0xFFFFFEF9),
          Color(0xFFF0E3C9),
        ],
      );
    canvas.drawOval(topRect, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xEEFFFFFF);
    canvas.drawOval(topRect.deflate(1.2), _paint);

    // 4. Glass base contact shadow + refracted cyan caustic glow on stone!
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x2C084B66);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, topSurfaceY + 1),
        width: 140,
        height: 21,
      ),
      _paint,
    );

    if (causticIntensity > 0.02) {
      _paint
        ..color = Colors.white
        ..shader = ui.Gradient.radial(
          Offset(cx + 6, topSurfaceY + 2),
          64,
          [
            const Color(0xFF5CF4FF).withValues(alpha: 0.48 * causticIntensity),
            const Color(0x005CF4FF),
          ],
        );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx + 6, topSurfaceY + 2),
          width: 126,
          height: 20,
        ),
        _paint,
      );
      _paint.shader = null;
    }
  }

  void _buildVaseSilhouettePath(
    Path path, {
    required double cx,
    required _VaseMetrics m,
    required VaseShapeType type,
    required double inset,
  }) {
    path.reset();
    final neckW = math.max(14.0, m.neckHalfW - inset * 0.75);
    final bellyW = math.max(24.0, m.bellyHalfW - inset);
    final baseW = math.max(18.0, m.baseHalfW - inset * 0.8);
    final topY = m.topRimY + (inset > 0 ? 4.0 : 0.0);
    final neckY = m.neckY;
    final baseY = m.baseY - inset;
    final midH = baseY - neckY;

    if (type == VaseShapeType.prismLotus) {
      final upperFacetY = neckY + midH * 0.30;
      final lowerFacetY = neckY + midH * 0.72;
      path.moveTo(cx - neckW, topY);
      path.lineTo(cx - neckW, neckY);
      path.lineTo(cx - bellyW * 0.90, upperFacetY);
      path.lineTo(cx - bellyW, (upperFacetY + lowerFacetY) * 0.5);
      path.lineTo(cx - bellyW * 0.84, lowerFacetY);
      path.lineTo(cx - baseW, baseY - 6);
      path.quadraticBezierTo(cx, baseY + 8, cx + baseW, baseY - 6);
      path.lineTo(cx + bellyW * 0.84, lowerFacetY);
      path.lineTo(cx + bellyW, (upperFacetY + lowerFacetY) * 0.5);
      path.lineTo(cx + bellyW * 0.90, upperFacetY);
      path.lineTo(cx + neckW, neckY);
      path.lineTo(cx + neckW, topY);
      path.close();
      return;
    }

    final shoulderCtrlY = switch (type) {
      VaseShapeType.royalTall => neckY + midH * 0.12,
      VaseShapeType.ovalCeramic => neckY + midH * 0.17,
      _ => neckY + midH * 0.16,
    };
    final lowerCtrlY = switch (type) {
      VaseShapeType.royalTall => neckY + midH * 0.72,
      _ => neckY + midH * 0.84,
    };

    path.moveTo(cx - neckW, topY);
    path.quadraticBezierTo(
      cx - neckW * 0.95,
      (topY + neckY) * 0.5,
      cx - neckW,
      neckY,
    );
    path.cubicTo(
      cx - bellyW * 1.07,
      shoulderCtrlY,
      cx - bellyW * 1.05,
      lowerCtrlY,
      cx - baseW,
      baseY - 6,
    );
    path.quadraticBezierTo(cx, baseY + 9, cx + baseW, baseY - 6);
    path.cubicTo(
      cx + bellyW * 1.05,
      lowerCtrlY,
      cx + bellyW * 1.07,
      shoulderCtrlY,
      cx + neckW,
      neckY,
    );
    path.quadraticBezierTo(
      cx + neckW * 0.95,
      (topY + neckY) * 0.5,
      cx + neckW,
      topY,
    );
    path.close();
  }

  void _drawBackGlassWall(Canvas canvas, double cx, _VaseMetrics m) {
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - m.bellyHalfW, m.neckY),
        Offset(cx + m.bellyHalfW, m.baseY),
        const [
          Color(0x98ECFDFF),
          Color(0x6464D8F6),
          Color(0x583BB9E2),
          Color(0x8CC8F9FF),
        ],
        const [0.0, 0.38, 0.72, 1.0],
      );
    canvas.drawPath(_vaseOuterPath, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0x78B8F6FF);
    canvas.drawPath(_vaseInnerPath, _paint);

    final rimRect = Rect.fromCenter(
      center: Offset(cx, m.topRimY + 2),
      width: m.mouthHalfW * 2.0,
      height: 20,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x42AEEFFF);
    canvas.drawOval(rimRect, _paint);

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..color = const Color(0xCCE8FCFF);
    canvas.drawArc(rimRect, math.pi, math.pi, false, _paint);
  }

  /// Draws the submerged portion of the botanical stems.
  /// Notice in Panel 6 (`!hasWater`, empty crystal vase), the stem softly fades right inside the frosted neck
  /// instead of sticking down like a rigid pole to the bottom!
  void _drawUnderwaterStems({
    required Canvas canvas,
    required double cx,
    required _VaseMetrics metrics,
    required double waterTopY,
    required bool hasWater,
    required double bloomFraction,
  }) {
    if (!hasWater) {
      // Empty crystal vase (Panel 6): soft short refracted neck stem fading smoothly into frosted glass
      canvas.save();
      canvas.clipPath(_vaseInnerPath);
      final fadeTop = metrics.topRimY + 6;
      final fadeBot = metrics.neckY + 22;
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.8
        ..strokeCap = StrokeCap.round
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(cx + 5, fadeTop),
          Offset(cx + 2, fadeBot),
          const [Color(0xCC359438), Color(0x00359438)],
        );
      canvas.drawLine(Offset(cx + 5, fadeTop), Offset(cx + 2, fadeBot), _paint);
      _paint.shader = null;
      canvas.restore();
      return;
    }

    canvas.save();
    canvas.clipPath(_vaseInnerPath);
    canvas.clipRect(
      Rect.fromLTRB(
        cx - metrics.bellyHalfW,
        waterTopY,
        cx + metrics.bellyHalfW,
        metrics.baseY,
      ),
    );

    const refractShift = 2.6;
    final stemBaseY = math.min(metrics.baseY - 34, waterTopY + 95);
    final neckMidY = metrics.topRimY + 6;
    final stemExitX = ui.lerpDouble(cx + 12, cx + 1, bloomFraction.clamp(0.0, 1.0))!;

    // Soft underwater depth-faded main stem
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(stemExitX, waterTopY),
        Offset(cx + 2, stemBaseY),
        const [
          Color(0xC8248B58),
          Color(0x52166954),
          Color(0x000E524E),
        ],
        const [0.0, 0.65, 1.0],
      );
    _scratchPath
      ..reset()
      ..moveTo(stemExitX + refractShift * 0.4, neckMidY)
      ..quadraticBezierTo(
        cx + 6 + refractShift,
        (neckMidY + stemBaseY) * 0.55,
        cx - 2 + refractShift,
        stemBaseY,
      );
    canvas.drawPath(_scratchPath, _paint);

    // Side bouquet stems smoothly fading in during 100% bloom
    if (bloomFraction > 0.05) {
      final sideAlpha = bloomFraction.clamp(0.0, 1.0);
      _paint
        ..strokeWidth = 5.0
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(cx, waterTopY),
          Offset(cx, stemBaseY - 12),
          [
            const Color(0xBC228654).withValues(alpha: 0.72 * sideAlpha),
            const Color(0x00125B4A),
          ],
        );

      _scratchPath
        ..reset()
        ..moveTo(cx - 8 + refractShift * 0.4, neckMidY)
        ..quadraticBezierTo(
          cx - 11 + refractShift,
          (neckMidY + stemBaseY) * 0.5,
          cx - 15 + refractShift,
          stemBaseY - 10,
        );
      canvas.drawPath(_scratchPath, _paint);

      _scratchPath
        ..reset()
        ..moveTo(cx + 9 + refractShift * 0.4, neckMidY)
        ..quadraticBezierTo(
          cx + 12 + refractShift,
          (neckMidY + stemBaseY) * 0.5,
          cx + 14 + refractShift,
          stemBaseY - 12,
        );
      canvas.drawPath(_scratchPath, _paint);
    }
    _paint.shader = null;
    canvas.restore();
  }

  void _drawVolumetricWater({
    required Canvas canvas,
    required double cx,
    required _VaseMetrics metrics,
    required double fillFraction,
    required double waterTopY,
    required bool isStreamImpacting,
    required double pourT,
  }) {
    if (fillFraction <= 0.008) return;

    canvas.save();
    canvas.clipPath(_vaseInnerPath);

    final leftBound = cx - metrics.bellyHalfW - 6;
    final rightBound = cx + metrics.bellyHalfW + 6;

    // Smooth damped slosh & wave amplitude reactive to live pouring
    final impactEnvelope = isStreamImpacting
        ? 1.0
        : (pourT >= 0.86 ? (1.0 - ((pourT - 0.86) / 0.14)).clamp(0.0, 1.0) : 0.0);
    final waveAmp = 1.6 + 2.8 * impactEnvelope;
    final sloshTilt = 2.6 * impactEnvelope * math.sin(ambientPhase * 5.0);

    // 1. Main Volumetric Liquid Body with Animated S-Wave + Slosh Profile
    _scratchPath
      ..reset()
      ..moveTo(leftBound, metrics.baseY + 14)
      ..lineTo(leftBound, waterTopY - sloshTilt);

    const segs = 18;
    final dx = (rightBound - leftBound) / segs;
    for (int i = 0; i <= segs; i++) {
      final frac = (i / segs) * 2.0 - 1.0;
      final x = leftBound + i * dx;
      final wave = waveAmp * math.sin(i * 0.62 + ambientPhase * 3.0) +
          (waveAmp * 0.42) * math.cos(i * 1.15 - ambientPhase * 2.0) +
          sloshTilt * frac;
      _scratchPath.lineTo(x, waterTopY + wave);
    }
    _scratchPath
      ..lineTo(rightBound, metrics.baseY + 14)
      ..close();

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, waterTopY - 4),
        Offset(cx, metrics.baseY),
        const [
          Color(0xF07EFBFF),
          Color(0xF020C6EE),
          Color(0xF20A92D6),
          Color(0xF50564A8),
        ],
        const [0.0, 0.28, 0.72, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Luminous inner aqua caustic core glow
    final waterMidY = (waterTopY + metrics.baseY) * 0.54;
    final glowR = math.max(30.0, (metrics.baseY - waterTopY) * 0.60);
    _paint
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        Offset(cx - 6, waterMidY),
        glowR,
        const [
          Color(0x6896FFFF),
          Color(0x0020C6EE),
        ],
      );
    canvas.drawCircle(Offset(cx - 6, waterMidY), glowR, _paint);
    _paint.shader = null;

    // 2. 18 Buoyant 3D Effervescent Bubbles + Turbulent Plunge Bubble Plume under stream!
    final colHeight = math.max(14.0, metrics.baseY - waterTopY - 10);
    final normPhase = ambientPhase / (math.pi * 2.0);

    for (int b = 0; b < 18; b++) {
      final rise = ((normPhase * (1.3 + (b % 3) * 0.45) + b * 0.163) % 1.0);
      final by = metrics.baseY - 8 - rise * colHeight;
      if (by <= waterTopY + 5 || by >= metrics.baseY - 6) continue;

      final maxHalfW = metrics.innerHalfWidthAt(by, config.shapeType) - 10;
      final spread = ((b * 0.37) % 1.0) * 2.0 - 1.0;
      final wobble = 3.8 * math.sin(ambientPhase * 2.0 + b * 1.3);
      final bx = cx + spread * maxHalfW * 0.78 + wobble;
      final br = 1.9 + (b % 4) * 1.45;
      _drawGlossyBubble(canvas, Offset(bx, by), br, 1.0);
    }

    // Extra plunging micro-bubbles right below the waterfall impact!
    if (impactEnvelope > 0.05) {
      for (int p = 0; p < 7; p++) {
        final cyc = ((normPhase * 3.2 + p * 0.14) % 1.0);
        final plungeDepth = math.min(colHeight * 0.65, 48.0) * math.sin(cyc * math.pi);
        final py = waterTopY + 6 + plungeDepth;
        if (py >= metrics.baseY - 6) continue;
        final px = cx + 2 + (p - 3) * 4.5 + 5.0 * math.sin(cyc * 6.0 + p);
        final pr = (1.8 + (p % 3) * 1.1) * impactEnvelope;
        _drawGlossyBubble(canvas, Offset(px, py), pr, impactEnvelope);
      }
    }

    // 3. 3D Perspective Elliptical Meniscus Surface (Matches Panels 3 & 4!)
    final meniscusHalfW = metrics.innerHalfWidthAt(waterTopY, config.shapeType);
    final meniscusH = (meniscusHalfW * 0.22).clamp(9.0, 21.0);
    final meniscusRect = Rect.fromCenter(
      center: Offset(cx, waterTopY),
      width: meniscusHalfW * 2.0,
      height: meniscusH,
    );

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx, waterTopY - meniscusH * 0.5),
        Offset(cx, waterTopY + meniscusH * 0.5),
        const [
          Color(0xF0B2FFFF),
          Color(0xD448E6FA),
        ],
      );
    canvas.drawOval(meniscusRect, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xDEFFFFFF);
    canvas.drawOval(meniscusRect.deflate(0.8), _paint);

    // Concentric elliptical impact ripples
    if (impactEnvelope > 0.05) {
      for (int r = 0; r < 3; r++) {
        final rippleT = ((normPhase * 3.0) + r * 0.33) % 1.0;
        final rw = meniscusHalfW * 1.78 * rippleT;
        final rh = meniscusH * 0.86 * rippleT;
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.9 * (1.0 - rippleT)
          ..color = Colors.white.withValues(
            alpha: (0.76 * (1.0 - rippleT) * impactEnvelope).clamp(0.0, 1.0),
          );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + 2, waterTopY),
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
      ..color = Colors.white.withValues(alpha: 0.26 * alphaScale);
    canvas.drawCircle(center, radius, _paint);

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = const Color(0xFFE0FFFF).withValues(alpha: 0.62 * alphaScale);
    canvas.drawCircle(center, radius, _paint);

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.92 * alphaScale);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.34, center.dy - radius * 0.34),
      radius * 0.32,
      _paint,
    );
  }

  /// Seamless, Zero-Hard-Cut Botanical Renderer:
  /// - When `bloomFraction == 0.0` (Panels 3 & 6): renders the S-curved green stem,
  ///   2 asymmetrical curled two-tone leaves, and the signature plump 3-petal cupped Pink Tulip Bud!
  /// - As `bloomFraction` progresses `0.0 -> 1.0` (Panels 4 & 5):
  ///   NO sudden pop! The main stem smoothly straightens & rises into the hero center blossom while
  ///   the Left & Right stems sprout outward along Bezier paths, collar leaves unfurl, and all 3 buds
  ///   continuously open their 6 ruffled velvet petals in 3/4 perspective!
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
    final sway = 0.032 * math.sin(ambientPhase);
    final upperClipTop = -160.0;
    final upperClipBottom = hasWater ? waterTopY : (metrics.topRimY + 10);
    final stemBaseY = math.min(upperClipBottom + 2, metrics.topRimY + 10);

    final tB = bloomFraction.clamp(0.0, 1.0);
    final centerMorph = Curves.easeOutCubic.transform(tB);

    // Smoothly interpolate the primary stem from Panel 3's graceful right-leaning S-curve
    // into Panel 4's tall hero center stem — ZERO discontinuity at `bloomFraction == 0`!
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

    // 1. Background collar leaves that unfurl around the crystal rim during bloom
    if (tB > 0.04) {
      final collarScale = Curves.easeOutBack
          .transform(((tB - 0.04) / 0.72).clamp(0.0, 1.0))
          .clamp(0.0, 1.15);
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx - 17, metrics.topRimY - 3),
        angle: -2.58 + sway,
        length: 41 * collarScale,
        width: 13.5,
        curlSign: -1.0,
      );
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx + 17, metrics.topRimY - 3),
        angle: -0.54 + sway,
        length: 41 * collarScale,
        width: 13.5,
        curlSign: 1.0,
      );
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx - 7, metrics.topRimY - 22),
        angle: -2.06 + sway,
        length: 36 * collarScale,
        width: 12.0,
        curlSign: -1.0,
      );
      _drawCurledBotanicalLeaf(
        canvas,
        origin: Offset(cx + 8, metrics.topRimY - 20),
        angle: -1.06 + sway,
        length: 36 * collarScale,
        width: 12.0,
        curlSign: 1.0,
      );
    }

    // Helper for cylindrical 3D shaded stems
    void drawCylindricalStem(Offset start, Offset ctrl, Offset end, double sw) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, upperClipTop, 380, upperClipBottom + 3));
      _scratchPath
        ..reset()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);

      // Rich emerald outer stem body
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..strokeCap = StrokeCap.round
        ..shader = null
        ..color = const Color(0xFF237B2B);
      canvas.drawPath(_scratchPath, _paint);

      // Sunlit lime highlight along left-center of stem cylinder
      _paint
        ..strokeWidth = sw * 0.48
        ..color = const Color(0xFF7CE84F);
      canvas.drawPath(_scratchPath.shift(const Offset(-1.0, 0)), _paint);
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
        5.5,
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
        5.5,
      );
    }

    // 3. Primary Center Stem
    drawCylindricalStem(
      Offset(primaryBaseX, stemBaseY),
      primaryCtrl,
      centerPos,
      6.2,
    );

    // 4. Primary Stem's 2 Signature Asymmetrical Curled Leaves (Panels 3 & 6 -> gracefully tucked in Panel 4!)
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
      length: ui.lerpDouble(31.0, 30.0, centerMorph)!,
      width: 11.5,
      curlSign: -1.0,
    );
    _drawCurledBotanicalLeaf(
      canvas,
      origin: leafNodeR,
      angle: ui.lerpDouble(-0.42, -0.74, centerMorph)! + sway,
      length: ui.lerpDouble(34.0, 30.0, centerMorph)!,
      width: 12.2,
      curlSign: 1.0,
    );

    // 5. Render Pre-Bloom Pink Tulip Bud OR Continuous Unfurling 3/4-Perspective Bouquet!
    if (tB <= 0.01) {
      _drawOrganicPinkTulipBud(
        canvas,
        center: centerPos,
        tiltAngle: 0.40 + sway * 1.2,
        scale: 1.02 + 0.10 * waterFraction.clamp(0.0, 1.0),
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

  /// Renders the 3-blossom 3/4-perspective bouquet with bespoke palettes & petal shapes per milestone,
  /// smoothly morphing each flower from a cupped bud (`unfurl == 0`) into a lush open blossom (`unfurl == 1`).
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
        // Signature Reference Art Trio Bouquet (`media_1794542250218_05b9588a.jpg` Panels 4 & 5):
        // Left: Warm Coral-Rose | Center: Tall Sunny Buttercup Gold | Right: Soft Lavender-Orchid Violet!
        final isVase1 = flowerType == FlowerType.tulipPink;

        // Draw side blossoms slightly behind or beside hero center for natural bouquet depth
        if (leftAppear > 0.05) {
          _drawCupped3DGardenBlossom(
            canvas,
            center: leftPos,
            unfurlT: leftUnfurl,
            appearScale: 0.98 * leftAppear,
            faceTilt: -0.24 + sway,
            tipCol: isVase1
                ? const Color(0xFFFFB8D2)
                : const Color(0xFFFFAB98),
            midCol: isVase1
                ? const Color(0xFFFF5286)
                : const Color(0xFFFF5A52),
            throatCol: isVase1
                ? const Color(0xFFC2185B)
                : const Color(0xFFC92626),
            stamenLight: const Color(0xFFFFF3A1),
            stamenDeep: const Color(0xFFEA7B00),
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DGardenBlossom(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.95 * rightAppear,
            faceTilt: 0.25 + sway,
            tipCol: const Color(0xFFEBD6FF),
            midCol: const Color(0xFFB162FF),
            throatCol: const Color(0xFF6B21A8),
            stamenLight: const Color(0xFFFFF3A1),
            stamenDeep: const Color(0xFFEA7B00),
          );
        }
        // Hero Tall Center Sunny Golden-Yellow Blossom
        _drawCupped3DGardenBlossom(
          canvas,
          center: centerPos,
          unfurlT: centerUnfurl,
          appearScale: 1.08,
          faceTilt: 0.03 + sway * 0.8,
          tipCol: const Color(0xFFFFF9B2),
          midCol: const Color(0xFFFFCF2E),
          throatCol: const Color(0xFFE07200),
          stamenLight: const Color(0xFFFFF8C8),
          stamenDeep: const Color(0xFFD95308),
        );
        break;

      case FlowerType.sunflower:
        if (leftAppear > 0.05) {
          _drawCupped3DSunflower(
            canvas,
            center: leftPos,
            unfurlT: leftUnfurl,
            appearScale: 0.86 * leftAppear,
            faceTilt: -0.22 + sway,
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DSunflower(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.86 * rightAppear,
            faceTilt: 0.22 + sway,
          );
        }
        _drawCupped3DSunflower(
          canvas,
          center: centerPos.translate(0, 4),
          unfurlT: centerUnfurl,
          appearScale: 1.10,
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
            tipCol: const Color(0xFFFF9E80),
            midCol: const Color(0xFFFF3D32),
            throatCol: const Color(0xFF9A0007),
            stamenLight: const Color(0xFFFFE082),
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
            tipCol: const Color(0xFFFFCC80),
            midCol: const Color(0xFFFF6D00),
            throatCol: const Color(0xFFBF360C),
            stamenLight: const Color(0xFFFFF59D),
            stamenDeep: const Color(0xFF4A192C),
          );
        }
        _drawCupped3DGardenBlossom(
          canvas,
          center: centerPos,
          unfurlT: centerUnfurl,
          appearScale: 1.08,
          faceTilt: sway * 0.8,
          tipCol: const Color(0xFFFF8A80),
          midCol: const Color(0xFFE52521),
          throatCol: const Color(0xFF880E25),
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
            appearScale: 0.88 * leftAppear,
            faceTilt: -0.22 + sway,
          );
        }
        if (rightAppear > 0.05) {
          _drawCupped3DCrystalLotus(
            canvas,
            center: rightPos,
            unfurlT: rightUnfurl,
            appearScale: 0.88 * rightAppear,
            faceTilt: 0.22 + sway,
          );
        }
        _drawCupped3DCrystalLotus(
          canvas,
          center: centerPos.translate(0, 3),
          unfurlT: centerUnfurl,
          appearScale: 1.12,
          faceTilt: sway * 0.6,
        );
        break;
    }
  }

  /// Two-Tone Curled 3D Botanical Leaf (`media_1794542235625_7780e9a4.png`):
  /// Sunlit chartreuse-lime upper half + shaded emerald-forest lower half along an S-curved midrib!
  void _drawCurledBotanicalLeaf(
    Canvas canvas, {
    required Offset origin,
    required double angle,
    required double length,
    required double width,
    required double curlSign,
  }) {
    if (length <= 2.0) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(angle);

    final tip = Offset(length, curlSign * width * 0.18);

    // Subtle underside shadow
    _scratchPath
      ..reset()
      ..moveTo(0, 1.5)
      ..cubicTo(
        length * 0.30,
        -width * 0.95 + 1.5,
        length * 0.72,
        -width * 0.75 + 1.5,
        tip.dx,
        tip.dy + 1.5,
      )
      ..cubicTo(
        length * 0.70,
        width * 0.92 + 1.5,
        length * 0.28,
        width * 1.02 + 1.5,
        0,
        1.5,
      )
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = const Color(0x28043847);
    canvas.drawPath(_scratchPath, _paint);

    // Upper sunlit lime half of leaf blade
    _scratchPath
      ..reset()
      ..moveTo(0, 0)
      ..cubicTo(
        length * 0.28,
        -width * 1.05,
        length * 0.70,
        -width * 0.82,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(length * 0.50, tip.dy * 0.35, 0, 0)
      ..close();
    _paint
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(0, -width),
        tip,
        const [Color(0xFFB4FA6B), Color(0xFF5BCE35)],
      );
    canvas.drawPath(_scratchPath, _paint);

    // Lower shaded emerald half of leaf blade
    _scratchPath
      ..reset()
      ..moveTo(0, 0)
      ..quadraticBezierTo(length * 0.50, tip.dy * 0.35, tip.dx, tip.dy)
      ..cubicTo(
        length * 0.68,
        width * 0.96,
        length * 0.28,
        width * 1.05,
        0,
        0,
      )
      ..close();
    _paint
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(length * 0.8, width),
        const [Color(0xFF43AD29), Color(0xFF1E6E22)],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Curved midrib highlight vein
    _scratchPath
      ..reset()
      ..moveTo(1.5, 0)
      ..quadraticBezierTo(
        length * 0.45,
        tip.dy * 0.28,
        length * 0.82,
        tip.dy * 0.78,
      );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xDCDCEDC8);
    canvas.drawPath(_scratchPath, _paint);

    canvas.restore();
  }

  /// Authentic 3-Petal Cupped Pink Tulip Bud (`media_1794542235625_7780e9a4.png` Panel 3 & Panel 6!):
  /// Plump egg-cup silhouette with 3 distinct rounded overlapping tulip tips (W-cleft crown),
  /// sunlit peach-pink foreground belly, deep raspberry crease, and sculpted green receptacle cup!
  void _drawOrganicPinkTulipBud(
    Canvas canvas, {
    required Offset center,
    required double tiltAngle,
    required double scale,
    Color innerPeakCol = const Color(0xFFE91E63),
    Color rightLightCol = const Color(0xFFFF8AB8),
    Color rightDeepCol = const Color(0xFFB81452),
    Color leftSunCol = const Color(0xFFFFC8DD),
    Color leftMidCol = const Color(0xFFFF5894),
    Color leftDeepCol = const Color(0xFFD4185C),
  }) {
    if (scale <= 0.02) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tiltAngle);
    canvas.scale(scale, scale);

    // Subtle soft shadow behind bud
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = const Color(0x24043848);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(1.5, -14), width: 28, height: 36),
      _paint,
    );

    // 1. Tucked Inner Center Tulip Petal Tip (forming the middle crown peak!)
    _scratchPath
      ..reset()
      ..moveTo(-5.5, -10)
      ..cubicTo(-6.5, -24, -3.0, -36.5, 1.5, -39.0)
      ..cubicTo(6.2, -36.5, 7.5, -24, 5.5, -10)
      ..close();
    _paint
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(1.5, -39),
        const Offset(1.5, -10),
        [rightLightCol, innerPeakCol, const Color(0xFF880E4F)],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);

    // 2. Right Cupped Wrapping Outer Petal (forming the right rounded tulip lobe!)
    _scratchPath
      ..reset()
      ..moveTo(-1, 5.5)
      ..cubicTo(16.5, 3.5, 19.0, -18.0, 9.8, -34.5)
      ..quadraticBezierTo(7.6, -37.0, 4.4, -33.5)
      ..cubicTo(1.2, -25.5, 0.8, -9.0, -1, 5.5)
      ..close();
    _paint
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(10, -35),
        const Offset(4, 6),
        [rightLightCol, leftMidCol, rightDeepCol],
        const [0.0, 0.52, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Crease shadow where left hero petal overlaps right petal
    _scratchPath
      ..reset()
      ..moveTo(2, 4.5)
      ..cubicTo(5.8, -8, 4.8, -24, 0.0, -34.5);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x4A6A0B37);
    canvas.drawPath(_scratchPath, _paint);

    // 3. Left Sunlit Foreground Hero Petal (full rounded belly + soft rounded top-left tulip peak!)
    _scratchPath
      ..reset()
      ..moveTo(2.2, 5.8)
      ..cubicTo(-17.0, 3.5, -19.0, -19.0, -6.8, -36.8)
      ..quadraticBezierTo(-3.6, -39.2, -0.4, -35.2)
      ..cubicTo(4.6, -25.0, 5.6, -7.5, 2.2, 5.8)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(-14, -35),
        const Offset(6, 6),
        [leftSunCol, leftMidCol, leftDeepCol],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Creamy-pink sunlit specular highlight crescent on left belly
    _scratchPath
      ..reset()
      ..moveTo(-10.2, -7.0)
      ..quadraticBezierTo(-12.5, -19.0, -6.5, -30.5);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.48);
    canvas.drawPath(_scratchPath, _paint);

    // 4. Seamless 3D Cupped Green Sepal Calyx Base
    _scratchPath
      ..reset()
      ..moveTo(-8.8, 1.5)
      ..quadraticBezierTo(0, 10.0, 8.8, 1.5)
      ..quadraticBezierTo(0, 4.8, -8.8, 1.5)
      ..close();
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        const Offset(-8, 1),
        const Offset(8, 9),
        const [Color(0xFF8BF056), Color(0xFF288226)],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    canvas.restore();
  }

  /// 3/4-Perspective Multi-Layered Ruffled Velvet Blossom (`media_1794542250218_05b9588a.jpg` Panels 4 & 5!):
  /// - Smoothly unfurls from a cupped bud (`unfurlT == 0.0`) into a lush 6-petal 3/4-tilted garden cup (`unfurlT == 1.0`)!
  /// - 3 tall sunlit back scalloped fan petals + warm throat shadow + foreshortened oval golden stamen cluster
  ///   with upward-curving golden filaments + 3 foreshortened overlapping front petals cupping the center!
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

    // Smooth cross-morph from closed colored bud (`unfurlT < 0.28`) into open 3/4 cupped flower!
    if (unfurlT < 0.28) {
      final budScale = appearScale * (0.85 + 0.25 * (unfurlT / 0.28));
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

    final openRaw = ((unfurlT - 0.12) / 0.88).clamp(0.0, 1.0);
    final openBounce = Curves.easeOutBack.transform(openRaw);
    final spread = (0.32 + 0.68 * openBounce).clamp(0.25, 1.14);
    final perspY = ui.lerpDouble(0.96, 0.80, openRaw)!;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(faceTilt);
    canvas.scale(appearScale * spread, appearScale * spread * perspY);

    // Subtle soft shadow tucked strictly beneath the flower cup
    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = const Color(0x26053645);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 6), width: 38, height: 28),
      _paint,
    );

    void drawPlumpHeartPetal({
      required double angleDeg,
      required double length,
      required double halfWidth,
      required double baseAnchorY,
      required bool isFront,
    }) {
      canvas.save();
      canvas.translate(0, baseAnchorY);
      canvas.rotate(angleDeg * math.pi / 180.0);

      // Plump rounded-heart cupped petal with clear inter-petal separation notch!
      _petalPath
        ..reset()
        ..moveTo(0, 0)
        ..cubicTo(
          -halfWidth * 0.42,
          -length * 0.22,
          -halfWidth * 1.16,
          -length * 0.66,
          -halfWidth * 0.72,
          -length * 0.94,
        )
        // Left rounded heart lobe -> gentle center dimple -> right rounded heart lobe
        ..quadraticBezierTo(
          -halfWidth * 0.34,
          -length * 1.07,
          0,
          -length * 0.96,
        )
        ..quadraticBezierTo(
          halfWidth * 0.34,
          -length * 1.07,
          halfWidth * 0.72,
          -length * 0.94,
        )
        ..cubicTo(
          halfWidth * 1.16,
          -length * 0.66,
          halfWidth * 0.42,
          -length * 0.22,
          0,
          0,
        )
        ..close();

      // Warm ambient occlusion shadow between overlapping petals
      _paint
        ..style = PaintingStyle.fill
        ..shader = null
        ..color = throatCol.withValues(alpha: isFront ? 0.42 : 0.28);
      canvas.drawPath(_petalPath.shift(const Offset(1.0, 2.2)), _paint);

      // 3-stop painterly velvet gradient (sunlit rounded tip -> rich mid -> deep warm cup)
      _paint
        ..style = PaintingStyle.fill
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(0, -length * 1.05),
          Offset.zero,
          [tipCol, midCol, throatCol],
          const [0.0, 0.56, 1.0],
        );
      canvas.drawPath(_petalPath, _paint);
      _paint.shader = null;

      // Subtle warm petal edge definition (prevents adjacent petals from fusing into a flat blob!)
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = throatCol.withValues(alpha: 0.34);
      canvas.drawPath(_petalPath, _paint);

      // Soft central velvet crease & sunlit lobe sheen
      _paint
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round
        ..color = throatCol.withValues(alpha: 0.20);
      canvas.drawLine(
        Offset(0, -length * 0.20),
        Offset(0, -length * 0.72),
        _paint,
      );

      _paint
        ..strokeWidth = 1.8
        ..color = Colors.white.withValues(alpha: isFront ? 0.34 : 0.26);
      canvas.drawLine(
        Offset(-halfWidth * 0.32, -length * 0.88),
        Offset(-halfWidth * 0.12, -length * 0.95),
        _paint,
      );

      canvas.restore();
    }

    // Layer 1: 3 Tall Back Petals fanning open behind the cup
    drawPlumpHeartPetal(
      angleDeg: -50,
      length: 37.5,
      halfWidth: 12.6,
      baseAnchorY: -1.5,
      isFront: false,
    );
    drawPlumpHeartPetal(
      angleDeg: 50,
      length: 37.5,
      halfWidth: 12.6,
      baseAnchorY: -1.5,
      isFront: false,
    );
    drawPlumpHeartPetal(
      angleDeg: 0,
      length: 39.5,
      halfWidth: 13.4,
      baseAnchorY: -2.0,
      isFront: false,
    );

    // Layer 2: 2 Side Cupping Petals
    drawPlumpHeartPetal(
      angleDeg: -104,
      length: 34.5,
      halfWidth: 12.4,
      baseAnchorY: 0.5,
      isFront: false,
    );
    drawPlumpHeartPetal(
      angleDeg: 104,
      length: 34.5,
      halfWidth: 12.4,
      baseAnchorY: 0.5,
      isFront: false,
    );

    // Deep warm cup shadow before the golden pollen heart
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(0, 1.5),
        15.5,
        [throatCol.withValues(alpha: 0.82), throatCol.withValues(alpha: 0.0)],
      );
    canvas.drawCircle(const Offset(0, 1.5), 15.5, _paint);
    _paint.shader = null;

    // Layer 3: Plump 3D Golden-Amber Pollen Cushion + Tactile Pollen Beads (NO white spider lines!)
    final coreRect = Rect.fromCenter(
      center: const Offset(0, 1.5),
      width: 19.5,
      height: 15.0,
    );
    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(-2.5, -1.5),
        12.5,
        [stamenLight, const Color(0xFFFFB300), stamenDeep],
        const [0.0, 0.58, 1.0],
      );
    canvas.drawOval(coreRect, _paint);
    _paint.shader = null;

    // Ring of plump warm golden pollen spheres around the cushion
    const beadOffsets = <Offset>[
      Offset(-6.5, -1.0),
      Offset(-4.0, -4.2),
      Offset(0.0, -5.0),
      Offset(4.0, -4.2),
      Offset(6.5, -1.0),
      Offset(5.2, 2.8),
      Offset(0.0, 3.8),
      Offset(-5.2, 2.8),
      Offset(-2.0, -0.8),
      Offset(2.2, -0.6),
    ];
    for (int b = 0; b < beadOffsets.length; b++) {
      final bo = beadOffsets[b];
      _paint.color = stamenDeep.withValues(alpha: 0.45);
      canvas.drawCircle(bo.translate(0.5, 1.0), 2.1, _paint);
      _paint.color = b >= 8 ? const Color(0xFFFFF9C4) : stamenLight;
      canvas.drawCircle(bo, 2.0, _paint);
    }

    // Layer 4: 2 Foreshortened Front-Lip Petals cupping neatly beneath the golden pollen heart!
    drawPlumpHeartPetal(
      angleDeg: -152,
      length: 28.5,
      halfWidth: 12.4,
      baseAnchorY: 5.5,
      isFront: true,
    );
    drawPlumpHeartPetal(
      angleDeg: 152,
      length: 28.5,
      halfWidth: 12.4,
      baseAnchorY: 5.5,
      isFront: true,
    );

    canvas.restore();
  }

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
    canvas.scale(appearScale * spread, appearScale * spread * 0.84);

    for (int ring = 0; ring < 2; ring++) {
      final offsetAngle = ring * (math.pi / 12.0);
      for (int i = 0; i < 12; i++) {
        canvas.save();
        canvas.rotate((i * math.pi * 2.0) / 12.0 + offsetAngle);
        final tipY = ring == 0 ? -36.0 : -32.0;
        _petalPath
          ..reset()
          ..moveTo(0, -9)
          ..cubicTo(-7.8, -18, -7.2, tipY * 0.82, 0, tipY)
          ..cubicTo(7.2, tipY * 0.82, 7.8, -18, 0, -9)
          ..close();
        _paint
          ..style = PaintingStyle.fill
          ..color = Colors.white
          ..shader = ui.Gradient.linear(
            Offset(0, tipY),
            const Offset(0, -9),
            ring == 0
                ? const [Color(0xFFFFE066), Color(0xFFEA6C00)]
                : const [Color(0xFFFFF59D), Color(0xFFFFA000)],
          );
        canvas.drawPath(_petalPath, _paint);
        canvas.restore();
      }
    }
    _paint.shader = null;

    // Rich 3/4 cushioned bronze-amber seed disk
    _paint
      ..color = Colors.white
      ..shader = ui.Gradient.radial(
        const Offset(-3, -3),
        16,
        const [Color(0xFF8D5524), Color(0xFF3E2014)],
      );
    canvas.drawCircle(Offset.zero, 14.5, _paint);
    _paint.shader = null;

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xDDFFB300);
    canvas.drawCircle(Offset.zero, 13.0, _paint);

    canvas.restore();
  }

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
    canvas.scale(appearScale * spread, appearScale * spread * 0.84);

    for (int ring = 0; ring < 2; ring++) {
      const count = 8;
      final rotOffset = ring * (math.pi / count);
      final tipY = ring == 0 ? -36.0 : -28.0;
      for (int i = 0; i < count; i++) {
        canvas.save();
        canvas.rotate((i * math.pi * 2.0) / count + rotOffset);
        _petalPath
          ..reset()
          ..moveTo(0, 0)
          ..cubicTo(-11, -10, -10, tipY * 0.76, 0, tipY)
          ..cubicTo(10, tipY * 0.76, 11, -10, 0, 0)
          ..close();
        _paint
          ..style = PaintingStyle.fill
          ..color = Colors.white
          ..shader = ui.Gradient.linear(
            Offset(0, tipY),
            Offset.zero,
            ring == 0
                ? const [Color(0xFFF3E5F5), Color(0xFFBA68C8)]
                : const [Color(0xFFFFFFFF), Color(0xFF80DEEA)],
          );
        canvas.drawPath(_petalPath, _paint);
        _paint.shader = null;

        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = const Color(0xCCFFFFFF);
        canvas.drawPath(_petalPath, _paint);
        canvas.restore();
      }
    }

    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFF59D);
    canvas.drawCircle(Offset.zero, 8.5, _paint);

    canvas.restore();
  }

  /// Physics-Driven Progressive Waterfall Ribbon:
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

    final flutter = 1.3 * math.sin(ambientPhase * 4.0);
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

    // Sample left & right edges along `[tStart .. tEnd]` for a silky progressive fluid ribbon
    const steps = 14;
    final leftPts = <Offset>[];
    final rightPts = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final u = i / steps;
      final t = ui.lerpDouble(tStart, tEnd, u)!;
      final pt = evalStream(t);
      final halfW = ui.lerpDouble(5.6, 8.8, t)! *
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

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        spoutPt,
        waterImpactPt,
        const [
          Color(0xF0A8FFFF),
          Color(0xF032D8FA),
          Color(0xEA0FA4E8),
        ],
        const [0.0, 0.48, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Glossy outer fluid edge sheen
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xB4FFFFFF);
    canvas.drawPath(_scratchPath, _paint);

    // Animated rushing white foam streaks sliding down the waterfall
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
      final lateral = (s.isEven ? -1.9 : 1.9) * widthScale;
      _paint
        ..strokeWidth = (2.3 - (s % 2) * 0.5) * widthScale
        ..color = Colors.white.withValues(alpha: 0.80);
      canvas.drawLine(
        p0.translate(lateral, 0),
        p1.translate(lateral, 0),
        _paint,
      );
    }

    // Trailing water droplets detaching after the stream tail!
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

    // Crown splash collar & parabolic leaping droplets once stream reaches `waterImpactPt`!
    if (headT >= 0.92 && tailT < 0.92) {
      final splashAlpha = (1.0 - tailT).clamp(0.0, 1.0);
      _paint
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.86 * splashAlpha);
      canvas.drawOval(
        Rect.fromCenter(
          center: waterImpactPt,
          width: 28.0 * widthScale,
          height: 8.0 * widthScale,
        ),
        _paint,
      );

      for (int i = 0; i < 8; i++) {
        final cycle = ((ambientPhase * 2.5 / math.pi) + i * 0.125) % 1.0;
        final spreadAngle = -math.pi * 0.12 - (i / 7.0) * math.pi * 0.76;
        final horiz = math.cos(spreadAngle) * (9.0 + 23.0 * cycle);
        final vert =
            math.sin(spreadAngle) * 21.0 * cycle + 18.0 * cycle * cycle;
        final dropR = (3.4 * (1.0 - cycle * 0.62)) * widthScale;

        _paint.color = Colors.white.withValues(
          alpha: (0.92 * (1.0 - cycle) * splashAlpha).clamp(0.0, 1.0),
        );
        canvas.drawCircle(
          Offset(waterImpactPt.dx + horiz, waterImpactPt.dy + vert - 3),
          dropR,
          _paint,
        );
      }
    }
  }

  void _drawFrontGlassOverlay(
    Canvas canvas,
    double cx,
    _VaseMetrics m,
    VaseShapeType type, {
    required bool hasWater,
  }) {
    // 1. Shape-specific Sculpted 3D Crystal Flutes / Facets (Panel 6 `flutedCrystal`!)
    if (type == VaseShapeType.flutedCrystal) {
      canvas.save();
      canvas.clipPath(_vaseOuterPath);
      const ribFractions = [-0.68, -0.35, 0.0, 0.35, 0.68];
      for (final f in ribFractions) {
        _scratchPath
          ..reset()
          ..moveTo(cx + m.neckHalfW * f * 0.88, m.neckY)
          ..cubicTo(
            cx + m.bellyHalfW * f * 1.06,
            m.neckY + (m.baseY - m.neckY) * 0.25,
            cx + m.bellyHalfW * f * 1.05,
            m.neckY + (m.baseY - m.neckY) * 0.80,
            cx + m.baseHalfW * f * 0.85,
            m.baseY,
          );
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10.5
          ..color = const Color(0x30ECFFFF);
        canvas.drawPath(_scratchPath, _paint);

        _paint
          ..strokeWidth = 2.6
          ..color = const Color(0x88FFFFFF);
        canvas.drawPath(_scratchPath, _paint);

        _paint
          ..strokeWidth = 2.8
          ..color = const Color(0x34066280);
        canvas.drawPath(_scratchPath.shift(const Offset(3.4, 0)), _paint);
      }
      canvas.restore();
    } else if (type == VaseShapeType.prismLotus) {
      canvas.save();
      canvas.clipPath(_vaseOuterPath);
      final midY = (m.neckY + m.baseY) * 0.5;
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = const Color(0x78FFFFFF);
      canvas.drawLine(
        Offset(cx - m.neckHalfW * 0.4, m.neckY),
        Offset(cx - m.bellyHalfW * 0.5, midY),
        _paint,
      );
      canvas.drawLine(
        Offset(cx - m.bellyHalfW * 0.5, midY),
        Offset(cx, m.baseY - 4),
        _paint,
      );
      canvas.drawLine(
        Offset(cx + m.neckHalfW * 0.4, m.neckY),
        Offset(cx + m.bellyHalfW * 0.5, midY),
        _paint,
      );
      canvas.drawLine(
        Offset(cx + m.bellyHalfW * 0.5, midY),
        Offset(cx, m.baseY - 4),
        _paint,
      );
      canvas.restore();
    }

    // 2. Signature Left Curved Window-Light Specular Glass Reflection
    canvas.save();
    canvas.clipPath(_vaseOuterPath);
    final highlightTopY = m.neckY + 13;
    final highlightBotY = m.baseY - 24;
    _scratchPath
      ..reset()
      ..moveTo(cx - m.neckHalfW * 0.68, highlightTopY)
      ..cubicTo(
        cx - m.bellyHalfW * 0.92,
        highlightTopY + (highlightBotY - highlightTopY) * 0.25,
        cx - m.bellyHalfW * 0.90,
        highlightTopY + (highlightBotY - highlightTopY) * 0.78,
        cx - m.baseHalfW * 0.62,
        highlightBotY,
      )
      ..cubicTo(
        cx - m.bellyHalfW * 0.74,
        highlightTopY + (highlightBotY - highlightTopY) * 0.74,
        cx - m.bellyHalfW * 0.76,
        highlightTopY + (highlightBotY - highlightTopY) * 0.28,
        cx - m.neckHalfW * 0.52,
        highlightTopY + 4,
      )
      ..close();

    _paint
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(cx - m.bellyHalfW, highlightTopY),
        Offset(cx - m.bellyHalfW * 0.6, highlightBotY),
        const [
          Color(0xBCFFFFFF),
          Color(0x68FFFFFF),
          Color(0x14FFFFFF),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawPath(_scratchPath, _paint);
    _paint.shader = null;

    // Secondary slender right rim reflection
    _scratchPath
      ..reset()
      ..moveTo(cx + m.neckHalfW * 0.65, highlightTopY + 12)
      ..quadraticBezierTo(
        cx + m.bellyHalfW * 0.88,
        (highlightTopY + highlightBotY) * 0.5,
        cx + m.baseHalfW * 0.64,
        highlightBotY - 8,
      );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x74FFFFFF);
    canvas.drawPath(_scratchPath, _paint);

    // Thick crystal glass bottom lens cushion highlight
    _scratchPath
      ..reset()
      ..moveTo(cx - m.baseHalfW * 0.85, m.baseY - 8)
      ..quadraticBezierTo(
        cx,
        m.baseY + 4,
        cx + m.baseHalfW * 0.85,
        m.baseY - 8,
      );
    _paint
      ..strokeWidth = 5.6
      ..color = const Color(0x9EE8FFFF);
    canvas.drawPath(_scratchPath, _paint);
    canvas.restore();

    // 3. Outer Fresnel Crystal Rim Stroke
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..color = const Color(0xD2FFFFFF);
    canvas.drawPath(_vaseOuterPath, _paint);

    // Warm sunlit champagne-gold neck collar ring (`media_1794542235625_7780e9a4.png` Panel 3!)
    final neckRect = Rect.fromCenter(
      center: Offset(cx, m.neckY + 1),
      width: m.neckHalfW * 2.02,
      height: 11,
    );
    _paint
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..color = hasWater ? const Color(0x98FFE89E) : const Color(0x72E0FFFF);
    canvas.drawArc(neckRect, 0.06, math.pi - 0.12, false, _paint);

    // 4. Rolled 3D Crystal Collar & Front Lip (occluding stems & incoming stream!)
    final rimRect = Rect.fromCenter(
      center: Offset(cx, m.topRimY + 2),
      width: m.mouthHalfW * 2.0,
      height: 20,
    );
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.8
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x7EB2F5FF);
    canvas.drawArc(rimRect, 0.05, math.pi - 0.10, false, _paint);

    _paint
      ..strokeWidth = 2.8
      ..color = const Color(0xF6FFFFFF);
    canvas.drawArc(rimRect, 0.08, math.pi - 0.16, false, _paint);
  }

  /// Miniature twin of the Ingame Crystal Potion Jar (`Panel 3`):
  /// Bulbous crystal jar tilted ~58°, gravity-level draining cyan liquid inside,
  /// twisted golden rope collar, and pendulum-swinging butter-cream `2048` tag!
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
      ..lineTo(-12, -21)
      ..cubicTo(-35, -14, -36, 22, -17, 30)
      ..quadraticBezierTo(0, 35, 17, 30)
      ..cubicTo(36, 22, 35, -14, 12, -21)
      ..lineTo(13, -32)
      ..close();

    _paint
      ..style = PaintingStyle.fill
      ..shader = null
      ..color = const Color(0x7CDCFCFF);
    canvas.drawPath(_scratchPath, _paint);

    // Draining cyan water inside the tilted jar (kept horizontal to world gravity!)
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

    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xEEFFFFFF);
    canvas.drawLine(Offset(-36, liquidTop), Offset(36, liquidTop), _paint);
    canvas.restore();

    // Specular belly highlight & crystal outline
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
      ..strokeWidth = 2.4
      ..color = const Color(0xEEFFFFFF);
    canvas.drawPath(_scratchPath, _paint);

    _paint.strokeWidth = 3.0;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, -32), width: 29, height: 8),
      _paint,
    );

    // Twisted Golden Rope Collar around neck (`y = -21`)
    _paint
      ..strokeWidth = 4.0
      ..color = const Color(0xFFF59E0B);
    canvas.drawLine(const Offset(-13, -21), const Offset(13, -21), _paint);
    _paint
      ..strokeWidth = 1.8
      ..color = const Color(0xFFFFF59D);
    canvas.drawLine(const Offset(-12, -22), const Offset(12, -22), _paint);

    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFFFB300);
    canvas.drawCircle(const Offset(0, -20), 3.8, _paint);

    canvas.restore();

    // Butter-Cream `2048` Number Tag with natural damped pendulum swing!
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
      ..strokeWidth = 1.8
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

    _paint
      ..style = PaintingStyle.fill
      ..color = const Color(0x3A042E40);
    canvas.drawRRect(tagRRect.shift(const Offset(0, 2.5)), _paint);

    _paint.color = const Color(0xFFFFF8E1);
    canvas.drawRRect(tagRRect, _paint);

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

  /// Plump Cupped 3D Floating Petals & Twinkling Starlight Sparkles (Panels 4 & 5!)
  void _drawFloatingPetalsAndSparkles({
    required Canvas canvas,
    required double cx,
    required double topY,
    required double intensity,
    required FlowerType flowerType,
  }) {
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
      final driftX = 6.5 * math.sin(ambientPhase + i * 1.15);
      final driftY = 5.5 * math.cos(ambientPhase * 1.25 + i * 0.9);
      final pos = Offset(cx + b.dx * intensity + driftX, topY + b.dy + driftY);

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(0.45 * i + 0.22 * math.sin(ambientPhase + i));
      canvas.scale(intensity, intensity);

      // Plump cupped 3D teardrop petal (matches floating pink petals on left & right of Panel 4 & 5!)
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
          [
            petalLight.withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)),
            petalDeep.withValues(alpha: (0.95 * intensity).clamp(0.0, 1.0)),
          ],
        );
      canvas.drawPath(_scratchPath, _paint);
      _paint.shader = null;
      canvas.restore();
    }

    const starOffsets = <Offset>[
      Offset(-78, -56),
      Offset(82, -52),
      Offset(0, -98),
      Offset(-96, -8),
      Offset(100, -4),
    ];
    for (int s = 0; s < starOffsets.length; s++) {
      final twinkle =
          (0.45 + 0.55 * math.sin(ambientPhase * 3.0 + s * 1.4)).clamp(0.0, 1.0) *
              intensity;
      if (twinkle <= 0.08) continue;
      _drawFourPointStar(
        canvas,
        Offset(cx + starOffsets[s].dx, topY + starOffsets[s].dy),
        7.5 * twinkle,
        const Color(0xFFFFFDE7),
      );
    }
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
        9.0 * fade,
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
    return oldDelegate.waterProgress != waterProgress ||
        oldDelegate.pourProgress != pourProgress ||
        oldDelegate.jarEnterProgress != jarEnterProgress ||
        oldDelegate.jarExitProgress != jarExitProgress ||
        oldDelegate.bloomProgress != bloomProgress ||
        oldDelegate.raysProgress != raysProgress ||
        oldDelegate.ambientPhase != ambientPhase ||
        oldDelegate.config.vaseId != config.vaseId ||
        oldDelegate.isNewVaseReveal != isNewVaseReveal ||
        oldDelegate.newVaseSparkleT != newVaseSparkleT;
  }
}


/// Reusable Side-by-Side Level Complete Monetization Action Bar:
/// - Left Button: `Next Level` + Coin Icon + `+${rewardCoins}`
/// - Right Button: `Reward x2` (Ad Icon) + Coin Icon + `+${rewardCoins * 2}`
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
          child: _GardenNextLevelCoinButton(
            key: const ValueKey('garden_next_level_btn'),
            rewardCoins: baseCoins,
            enabled: enabled,
            onTap: onNextLevel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedBuilder(
            animation: shimmerAnimation,
            builder: (context, _) {
              return _GardenRewardX2CoinButton(
                key: const ValueKey('garden_reward_x2_btn'),
                doubledCoins: doubleCoins,
                shimmerPhase: shimmerAnimation.value,
                enabled: enabled,
                onTap: onRewardX2,
              );
            },
          ),
        ),
      ],
    );
  }
}
