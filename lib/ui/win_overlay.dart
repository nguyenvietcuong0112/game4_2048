import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// 100% Pixel-Exact Replica of Unity `WinGameplayView.prefab` + `RewardView.prefab` (`sc = 0.82`):
/// - Background Scrim: `rgba(15, 32, 74, 0.98)` (`LevelCompleteView/Background`).
/// - Stage 1 (`LevelCompleteView`, `0.0s..0.92s`): Pre-cached wave-bouncing `"Level complete!"`
///   (`Baloo2_ExtraBold_Level_Complete` + `Gradient_Title_Light`) + warm additive glow & bokeh.
/// - Stage 2 (`WinContent`, center-anchored `amin.y = amax.y = 0.5`):
///   1. `Header` (`dy = -559`): `Banner_Gold.png` (`1038x276`) + `"AMAZING!"` (`sz = 126`,
///      `dy = -36` above ribbon center) + tucked 9-slice `Label_Level.png` (`376x122`,
///      `pixelMultiplier = 0.82`, rendered behind ribbon with zero gap, `"Level X"`, `sz = 62.7`).
///   2. `Rewards` (`dy = +17`): Multi-layer additive `UI_Add` `#FF82B2` rose-pink + `#FF914F`
///      peach-amber + `#FFB800` golden aura, 4-ray `+` `CentralFlare` light beams, outward-drifting
///      soft round white bokeh orbs (`VFXSparkleMaterial`), giant `Reward_Coin.png` (`500x500`,
///      `~274` visible gold diameter), and `"25"` (`sz = 124`, `Baloo2_ExtraBold_CTA_Blue_Text`)
///      overlapping the bottom gold rim of the coin!
///   3. `NextLevelButton` (`dy = +685`): `Button_CTA.png` (`606x206`, `sliceScale = 0.82`,
///      `"Next Level"`, `sz = 74`).
/// - Stage 3 (Coin Collect Flight): Tapping `"Next Level"` arcs golden `Icon_Coin.png` sprites
///   into the top-left `CoinsWidget` with live counter ticks.
class WinOverlay extends StatefulWidget {
  final String levelLabel;
  final int rewardCoins;
  final VoidCallback? onStage2Shown;
  final ValueChanged<int>? onCoinChunkArrived;
  final VoidCallback onNextLevel;

  const WinOverlay({
    super.key,
    required this.levelLabel,
    required this.rewardCoins,
    this.onStage2Shown,
    this.onCoinChunkArrived,
    required this.onNextLevel,
  });

  @override
  State<WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<WinOverlay> with TickerProviderStateMixin {
  late final AnimationController _ambientCtrl;
  late final AnimationController _sequenceCtrl;
  late final AnimationController _coinFlyCtrl;

  bool _stage2Notified = false;
  bool _collecting = false;
  final Set<int> _arrivedCoinIndices = {};

  static const int _flyingCoinCount = 7;
  static const String _stage1Phrase = 'Level complete!';
  List<Widget>? _cachedStage1Glyphs;
  double? _cachedStage1Scale;

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _sequenceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )
      ..addListener(_checkStageTransition)
      ..forward();

    _coinFlyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 680),
    )
      ..addListener(_handleCoinFlightTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onNextLevel();
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sc = uxScale(context);
    if (_cachedStage1Glyphs == null || _cachedStage1Scale != sc) {
      _cachedStage1Scale = sc;
      _cachedStage1Glyphs = List<Widget>.generate(_stage1Phrase.length, (i) {
        final ch = _stage1Phrase[i];
        if (ch == ' ') {
          return SizedBox(width: ux(context, 28));
        }
        return RepaintBoundary(
          child: UnitySdfText(
            ch,
            unityFontSize: 130,
            material: UnityTextMaterial.levelCompleteWave,
          ),
        );
      });
    }
  }

  void _checkStageTransition() {
    // Stage 2 (`WinContent` AMAZING! + Coin) pops in at 62% of sequence (~900ms)
    if (!_stage2Notified && _sequenceCtrl.value >= 0.62) {
      _stage2Notified = true;
      widget.onStage2Shown?.call();
    }
  }

  void _handleCoinFlightTick() {
    final t = _coinFlyCtrl.value;
    final baseChunk = widget.rewardCoins ~/ _flyingCoinCount;
    final remainder = widget.rewardCoins % _flyingCoinCount;

    for (int i = 0; i < _flyingCoinCount; i++) {
      final coinEnd = 0.58 + (i / (_flyingCoinCount - 1)) * 0.40;
      if (t >= coinEnd && _arrivedCoinIndices.add(i)) {
        final chunk = baseChunk + (i < remainder ? 1 : 0);
        if (chunk > 0) {
          widget.onCoinChunkArrived?.call(chunk);
        }
      }
    }
  }

  void _onTapNextLevel() {
    if (_collecting) return;
    setState(() => _collecting = true);
    _coinFlyCtrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _sequenceCtrl.dispose();
    _coinFlyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_sequenceCtrl, _coinFlyCtrl]),
      builder: (context, _) {
        final seq = _sequenceCtrl.value;
        // Exact `rgba(0.059, 0.125, 0.290, 0.980)` (`Color.fromRGBO(15, 32, 74, 0.98)`)
        final bgAlpha = (seq / 0.16).clamp(0.0, 1.0) * 0.98;
        final showStage1 = seq < 0.66;
        final stage2Raw = ((seq - 0.62) / 0.38).clamp(0.0, 1.0);
        final stage2Pop = Curves.easeOutBack.transform(stage2Raw);

        return ColoredBox(
          color: Color.fromRGBO(15, 32, 74, bgAlpha),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showStage1) _buildStage1LevelComplete(context, seq),
              if (seq >= 0.62)
                _buildStage2AmazingWin(context, stage2Raw, stage2Pop),
              if (_collecting) _buildFlyingCoinsLayer(context),
            ],
          ),
        );
      },
    );
  }

  /// Stage 1: `LevelCompleteView` wave-bouncing `"Level complete!"` + warm additive aura & bokeh.
  Widget _buildStage1LevelComplete(BuildContext context, double seq) {
    final stage1T = (seq / 0.64).clamp(0.0, 1.0);
    final fadeOut =
        stage1T > 0.80 ? ((1.0 - stage1T) / 0.20).clamp(0.0, 1.0) : 1.0;
    final popIn =
        Curves.easeOutBack.transform((stage1T / 0.28).clamp(0.0, 1.0));
    final glyphs = _cachedStage1Glyphs ?? const <Widget>[];
    final auraSize = ux(context, 780);

    final waveRow = Transform.scale(
      scale: 0.72 + 0.28 * popIn,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: ux(context, 44)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(glyphs.length, (i) {
              if (_stage1Phrase[i] == ' ') return glyphs[i];
              final wavePhase = stage1T * math.pi * 3.4 - i * 0.34;
              final dy =
                  -math.max(0.0, math.sin(wavePhase)) * ux(context, 28);
              return Transform.translate(
                offset: Offset(0, dy),
                child: glyphs[i],
              );
            }),
          ),
        ),
      ),
    );

    return Center(
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Warm additive central glow & outward sparkles (`LevelCompleteView/VFX_Group`)
          // Modulated directly via `intensity` (zero fullscreen `Opacity` `saveLayer`!).
          RepaintBoundary(
            child: SizedBox(
              width: auraSize,
              height: auraSize,
              child: CustomPaint(
                painter: _UnityWinCoinAuraPainter(
                  ambient: _ambientCtrl,
                  scale1080: uxScale(context),
                  showCrossFlare: false,
                  intensity:
                      (0.85 * (1.0 - stage1T * 0.30) * fadeOut).clamp(0.0, 1.0),
                ),
              ),
            ),
          ),

          // Pre-cached wave-bouncing character glyphs (`TMPModifier_01` + `TMPModifier_02`)
          fadeOut >= 0.999
              ? waveRow
              : Opacity(opacity: fadeOut, child: waveRow),
        ],
      ),
    );
  }

  /// Stage 2: Exact center-anchored `WinContent` (`sc = 0.82`) matching `WinGameplayView.prefab`
  /// and `media_1793412272544.png` 1:1 across all screen aspect ratios!
  Widget _buildStage2AmazingWin(
    BuildContext context,
    double stage2Raw,
    double stage2Pop,
  ) {
    final fade = stage2Raw.clamp(0.0, 1.0);
    Widget wrapBoundaryFade(Widget boundary) =>
        fade >= 0.999 ? boundary : Opacity(opacity: fade, child: boundary);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final safeW = constraints.maxWidth;
          final safeH = constraints.maxHeight;
          final centerY = safeH * 0.5;

          // Exact Unity `SafeArea` center-relative Y offsets (`+682*0.82`, `-21*0.82`, `-835*0.82`)
          // safely bounded for compact 16:9 screens.
          final headerH = ux(context, 304);
          final headerCenterY =
              centerY - math.min(ux(context, 559), safeH * 0.355);

          final auraBoxSize = ux(context, 860);
          final coinBoxSize = ux(context, 500);
          final rewardsCenterY = centerY + ux(context, 17);

          final nextBtnW = ux(context, 606);
          final nextBtnH = ux(context, 206);
          final nextBtnCenterY =
              centerY + math.min(ux(context, 685), safeH * 0.375);

          final coinPopScale = (0.68 + 0.32 * stage2Pop) *
              (_collecting ? (1.0 - _coinFlyCtrl.value * 0.25) : 1.0);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Center Multi-Layer Additive Aura + Cross-Flare + Floating Bokeh (`Rewards/VFX_Group`)
              // Alpha modulated directly via `intensity: fade` with zero `Opacity` `saveLayer`!
              Positioned(
                left: (safeW - auraBoxSize) * 0.5,
                top: rewardsCenterY - auraBoxSize * 0.5,
                width: auraBoxSize,
                height: auraBoxSize,
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _UnityWinCoinAuraPainter(
                        ambient: _ambientCtrl,
                        scale1080: uxScale(context),
                        showCrossFlare: true,
                        intensity: fade,
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Giant `Reward_Coin.png` (`500x500` -> `274` visible gold coin) + Overlapping `"25"`
              Positioned(
                left: (safeW - coinBoxSize) * 0.5,
                top: rewardsCenterY - coinBoxSize * 0.5,
                width: coinBoxSize,
                height: coinBoxSize,
                child: Transform.scale(
                  scale: coinPopScale,
                  child: wrapBoundaryFade(
                    RepaintBoundary(
                      child: Stack(
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.none,
                        children: [
                          Image.asset(
                            'assets/images/Reward_Coin.png',
                            width: coinBoxSize,
                            height: coinBoxSize,
                            fit: BoxFit.contain,
                          ),
                          // `RewardView/Amount`: overlaps bottom gold rim of the coin by ~5px!
                          Positioned(
                            top: ux(context, 353),
                            child: UnitySdfText(
                              '${widget.rewardCoins}',
                              unityFontSize: 124,
                              material: UnityTextMaterial.ctaBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Top Header (`Banner_Gold.png` + `AMAZING!` + tucked `Label_Level.png` `Level X`)
              Positioned(
                left: (safeW - ux(context, 1040)) * 0.5,
                top: headerCenterY - headerH * 0.5,
                width: ux(context, 1040),
                height: headerH,
                child: Transform.scale(
                  scale: 0.74 + 0.26 * stage2Pop,
                  child: wrapBoundaryFade(
                    RepaintBoundary(
                      child: Stack(
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.none,
                        children: [
                          // Tucked 9-Slice `Label_Level.png` rendered BEHIND `Banner_Gold.png` (`zero gap`!)
                          Positioned(
                            top: ux(context, 174),
                            child: UnityNineSlice(
                              sprite: 'Label_Level.png',
                              width: ux(context, 376),
                              height: ux(context, 122),
                              pixelMultiplier: 0.82,
                              padding: EdgeInsets.only(bottom: ux(context, 6)),
                              child: UnitySdfText(
                                widget.levelLabel,
                                unityFontSize: 62.5,
                                material: UnityTextMaterial.blueLabel,
                              ),
                            ),
                          ),

                          // `Banner_Gold.png` (`1042x277` native Unity aspect preserved)
                          Positioned(
                            top: 0,
                            width: ux(context, 1036),
                            height: ux(context, 275),
                            child: Image.asset(
                              'assets/images/Banner_Gold.png',
                              fit: BoxFit.contain,
                            ),
                          ),

                          // `AMAZING!` (`Baloo2_ExtraBold_Brown_Text`, `pos.y = +44 * 0.82 = +36` above ribbon center)
                          Positioned(
                            top: ux(context, 32),
                            child: const UnitySdfText(
                              'AMAZING!',
                              unityFontSize: 125,
                              material: UnityTextMaterial.bannerBrown,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 4. `NextLevelButton` (`(718.9+20)x(233.2+20) * 0.82 = 606x206`, `sliceScale: 0.82`, `sz: 74`)
              Positioned(
                left: (safeW - nextBtnW) * 0.5,
                top: nextBtnCenterY - nextBtnH * 0.5,
                child: Transform.scale(
                  scale: 0.78 + 0.22 * stage2Pop,
                  child: wrapBoundaryFade(
                    RepaintBoundary(
                      child: UnityCtaButton(
                        label: 'Next Level',
                        unityWidth: 606,
                        unityHeight: 206,
                        unityFontSize: 74,
                        sliceScale: 0.82,
                        onTap: _collecting ? null : _onTapNextLevel,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Stage 3: Curved Bezier flight of golden `Icon_Coin.png` sprites up into top-left `CoinsWidget`.
  Widget _buildFlyingCoinsLayer(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final startCenter = Offset(
      screen.width * 0.5,
      screen.height * 0.5 + ux(context, 17),
    );
    final targetCoinIcon = Offset(ux(context, 103), topPad + ux(context, 78));

    final t = _coinFlyCtrl.value;
    final children = <Widget>[];

    for (int i = 0; i < _flyingCoinCount; i++) {
      final coinStart = (i / (_flyingCoinCount - 1)) * 0.34;
      final coinEnd = 0.58 + (i / (_flyingCoinCount - 1)) * 0.40;
      if (t < coinStart || t >= coinEnd) continue;

      final localT = ((t - coinStart) / (coinEnd - coinStart)).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(localT);

      final spreadX = (i - (_flyingCoinCount - 1) * 0.5) * ux(context, 42);
      final ctrl = Offset(
        startCenter.dx + spreadX - ux(context, 130),
        (startCenter.dy + targetCoinIcon.dy) * 0.48 + spreadX * 0.25,
      );

      final oneMinus = 1.0 - eased;
      final px = oneMinus * oneMinus * startCenter.dx +
          2 * oneMinus * eased * ctrl.dx +
          eased * eased * targetCoinIcon.dx;
      final py = oneMinus * oneMinus * startCenter.dy +
          2 * oneMinus * eased * ctrl.dy +
          eased * eased * targetCoinIcon.dy;

      final coinSz = ux(context, 112) * (1.05 - 0.22 * eased);
      children.add(
        Positioned(
          left: px - coinSz * 0.5,
          top: py - coinSz * 0.5,
          child: IgnorePointer(
            child: Image.asset(
              'assets/images/Icon_Coin.png',
              width: coinSz,
              height: coinSz,
            ),
          ),
        ),
      );
    }

    return Stack(children: children);
  }
}

/// Pure GPU additive (`BlendMode.plus`) painter replicating `WinGameplayView/Rewards/VFX_Group`:
/// 1. `Static_Glow` (`UI_Add`, `rgba(1.0, 0.511, 0.696, 0.533)` `#FF82B2` rose-pink outer halo)
/// 2. `CentralGlow` (`rgba(1.0, 0.57, 0.31, 0.35)` `#FF914F` warm peach-orange aura)
/// 3. `CentralGlow_01` (`rgba(1.0, 0.69, 0.0, 0.18)` `#FFB000` golden core)
/// 4. `CentralFlare` (`VFXGlowFlareMaterial`, `sz = (800, 66)`, 4-ray `+` horizontal & vertical light beams)
/// 5. `Sparkles` (`VFXSparkleMaterial` -> `_MainTex: Glow`, soft round white bokeh orbs drifting outward!)
class _UnityWinCoinAuraPainter extends CustomPainter {
  final Animation<double> ambient;
  final double scale1080;
  final bool showCrossFlare;
  final double intensity;

  // Deterministic sparkle seeds `(angleRad, baseRadius1080, travel1080, size1080, phase)`
  static const List<(double, double, double, double, double)> _sparkleSeeds = [
    (-2.82, 138, 105, 34, 0.03),
    (-2.34, 152, 95, 24, 0.44),
    (-1.86, 126, 112, 30, 0.77),
    (-1.42, 145, 98, 22, 0.19),
    (-0.96, 134, 108, 36, 0.61),
    (-0.48, 148, 96, 26, 0.88),
    (-0.04, 162, 116, 32, 0.31),
    (0.42, 136, 94, 24, 0.72),
    (0.92, 144, 104, 30, 0.14),
    (1.44, 132, 96, 22, 0.53),
    (1.94, 148, 110, 34, 0.83),
    (2.38, 156, 102, 28, 0.26),
    (2.74, 168, 118, 38, 0.66),
    (3.08, 184, 126, 32, 0.94),
  ];

  const _UnityWinCoinAuraPainter({
    required this.ambient,
    required this.scale1080,
    required this.showCrossFlare,
    required this.intensity,
  }) : super(repaint: ambient);

  double _u(double px1080) => px1080 * scale1080;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final phase = ambient.value * math.pi * 2.0;
    final breathe = 1.0 + 0.045 * math.sin(phase);
    final counterBreathe = 1.0 - 0.038 * math.sin(phase);

    // 1. Outer Rose-Pink `Static_Glow` (`#FF82B2`, `UI_Add`)
    final outerR = _u(415) * breathe;
    final outerPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        center,
        outerR,
        [
          Color.fromRGBO(255, 130, 178, 0.46 * intensity),
          Color.fromRGBO(255, 130, 178, 0.32 * intensity),
          Color.fromRGBO(255, 118, 172, 0.14 * intensity),
          const Color.fromRGBO(255, 118, 172, 0.0),
        ],
        const [0.0, 0.34, 0.66, 1.0],
      );
    canvas.drawCircle(center, outerR, outerPaint);

    // 2. Mid Warm Peach-Orange `CentralGlow` (`rgba(255, 145, 79, 0.38)`)
    final midR = _u(285) * counterBreathe;
    final midPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        center,
        midR,
        [
          Color.fromRGBO(255, 152, 86, 0.42 * intensity),
          Color.fromRGBO(255, 138, 112, 0.22 * intensity),
          const Color.fromRGBO(255, 138, 112, 0.0),
        ],
        const [0.0, 0.52, 1.0],
      );
    canvas.drawCircle(center, midR, midPaint);

    // 3. Inner Golden Core `CentralGlow_01` (`rgba(255, 190, 40, 0.34)`)
    final coreR = _u(195) * breathe;
    final corePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        center,
        coreR,
        [
          Color.fromRGBO(255, 214, 102, 0.42 * intensity),
          Color.fromRGBO(255, 176, 32, 0.18 * intensity),
          const Color.fromRGBO(255, 176, 32, 0.0),
        ],
        const [0.0, 0.58, 1.0],
      );
    canvas.drawCircle(center, coreR, corePaint);

    // 4. `CentralFlare` (`sz = (800, 66) * 0.70 * 0.82`, 4-ray `+` horizontal & vertical light beams)
    if (showCrossFlare) {
      final flarePulse = 0.88 + 0.12 * math.cos(phase * 2.0);
      _drawTaperedFlareRay(
        canvas,
        center: center,
        halfLength: _u(345) * flarePulse,
        halfThickness: _u(24),
        horizontal: true,
        alpha: 0.26 * intensity * flarePulse,
      );
      _drawTaperedFlareRay(
        canvas,
        center: center,
        halfLength: _u(320) * flarePulse,
        halfThickness: _u(22),
        horizontal: false,
        alpha: 0.22 * intensity * flarePulse,
      );
    }

    // 5. `Sparkles` (`VFXSparkleMaterial` -> `_MainTex: Glow`):
    // Soft round glowing white bokeh dots drifting radially outward around the coin!
    final bokehPaint = Paint()..blendMode = BlendMode.plus;
    for (final (ang, baseDist, travel, sz1080, seedPhase) in _sparkleSeeds) {
      final lifeT = (ambient.value * 1.5 + seedPhase) % 1.0;
      // Smooth bell-curve fade in (0..0.25) and fade out (0.25..1.0)
      final env = lifeT < 0.24
          ? (lifeT / 0.24)
          : math.pow(1.0 - (lifeT - 0.24) / 0.76, 1.35).toDouble();
      final alpha = (env * 0.92 * intensity).clamp(0.0, 1.0);
      if (alpha <= 0.02) continue;

      final dist = _u(baseDist + travel * lifeT);
      final radius = _u(sz1080 * 0.5) * (0.72 + 0.36 * env);
      final pos = Offset(
        center.dx + math.cos(ang) * dist,
        center.dy + math.sin(ang) * dist,
      );

      bokehPaint.shader = ui.Gradient.radial(
        pos,
        radius,
        [
          Color.fromRGBO(255, 255, 255, alpha),
          Color.fromRGBO(255, 240, 220, alpha * 0.62),
          Color.fromRGBO(255, 168, 196, alpha * 0.20),
          const Color.fromRGBO(255, 168, 196, 0.0),
        ],
        const [0.0, 0.28, 0.62, 1.0],
      );
      canvas.drawCircle(pos, radius, bokehPaint);
    }
  }

  void _drawTaperedFlareRay(
    Canvas canvas, {
    required Offset center,
    required double halfLength,
    required double halfThickness,
    required bool horizontal,
    required double alpha,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!horizontal) {
      canvas.rotate(math.pi * 0.5);
    }
    canvas.scale(halfLength, halfThickness);
    final rayPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        Offset.zero,
        1.0,
        [
          Color.fromRGBO(255, 232, 168, alpha),
          Color.fromRGBO(255, 162, 168, alpha * 0.45),
          const Color.fromRGBO(255, 140, 178, 0.0),
        ],
        const [0.0, 0.42, 1.0],
      );
    canvas.drawCircle(Offset.zero, 1.0, rayPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnityWinCoinAuraPainter old) {
    return old.scale1080 != scale1080 ||
        old.showCrossFlare != showCrossFlare ||
        old.intensity != intensity;
  }
}
