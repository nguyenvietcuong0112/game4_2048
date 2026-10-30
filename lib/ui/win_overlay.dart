import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// Authentic two-stage replica of Unity `WinGameplayView.prefab` + `ref1.png`:
/// - Stage 1 (`LevelCompleteView`, `0.0s..0.95s`): Wave-bouncing golden `"Level complete!"`
///   (`Baloo2_ExtraBold_Level_Complete`) + central `ParticleFlare.png` & `Sparkle_01.png` burst.
/// - Stage 2 (`WinContent`, `ref1.png`): `Banner_Gold.png` (`"AMAZING!"`), tucked 9-slice
///   `Label_Level.png` (`"Level X"`), rose-gold `Glow_02.png` + `Sparkle_01.png` bokeh +
///   `Reward_Coin.png` + `"25"`, and 9-slice `Button_CTA.png` `"Next Level"`.
/// - Stage 3 (Coin Collect Flight): Tapping `"Next Level"` launches golden `Icon_Coin.png`
///   sprites along curved arcs into the top-left `CoinsWidget` with live counter ticks!
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

  // Exact sparkle layout sampled from `ref1.png` (angle rad, distance in 1080px units, size in 1080px, phase)
  static const List<(double, double, double, double)> _bokehSparkles = [
    (-2.38, 255, 18, 0.05),
    (-1.86, 210, 26, 0.32),
    (-1.58, 248, 16, 0.68),
    (-1.26, 246, 36, 0.16),
    (-0.84, 240, 28, 0.52),
    (0.05, 318, 34, 0.84),
    (2.42, 262, 32, 0.41),
    (3.08, 368, 44, 0.63),
  ];

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
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
      animation: Listenable.merge([_sequenceCtrl, _ambientCtrl, _coinFlyCtrl]),
      builder: (context, _) {
        final seq = _sequenceCtrl.value;
        final bgAlpha = (seq / 0.16).clamp(0.0, 1.0) * 0.91;
        final showStage1 = seq < 0.66;
        final stage2Raw = ((seq - 0.62) / 0.38).clamp(0.0, 1.0);
        final stage2Pop = Curves.easeOutBack.transform(stage2Raw);

        return Container(
          color: Color.fromRGBO(15, 32, 74, bgAlpha),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showStage1) _buildStage1LevelComplete(context, seq),
              if (seq >= 0.62) _buildStage2AmazingWin(context, stage2Raw, stage2Pop),
              if (_collecting) _buildFlyingCoinsLayer(context),
            ],
          ),
        );
      },
    );
  }

  /// Stage 1: `LevelCompleteView` wave-bouncing golden `"Level complete!"` + flare.
  Widget _buildStage1LevelComplete(BuildContext context, double seq) {
    final stage1T = (seq / 0.64).clamp(0.0, 1.0);
    final fadeOut = stage1T > 0.80 ? ((1.0 - stage1T) / 0.20).clamp(0.0, 1.0) : 1.0;
    final popIn = Curves.easeOutBack.transform((stage1T / 0.28).clamp(0.0, 1.0));
    const phrase = 'Level complete!';

    return Opacity(
      opacity: fadeOut,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft golden-pink central flare (`Glow_02.png` + `ParticleFlare.png`)
            Transform.scale(
              scale: 0.65 + 0.55 * stage1T,
              child: Opacity(
                opacity: (0.85 * (1.0 - stage1T * 0.45)).clamp(0.0, 1.0),
                child: Image.asset(
                  'assets/images/Glow_02.png',
                  width: ux(context, 780),
                  height: ux(context, 780),
                  color: const Color(0xFFFFB26B),
                  colorBlendMode: BlendMode.modulate,
                ),
              ),
            ),
            Transform.rotate(
              angle: stage1T * 0.65,
              child: Opacity(
                opacity: (0.75 * (1.0 - stage1T * 0.6)).clamp(0.0, 1.0),
                child: Image.asset(
                  'assets/images/ParticleFlare.png',
                  width: ux(context, 520),
                  height: ux(context, 520),
                ),
              ),
            ),

            // Wave-bouncing characters (`LevelCompleteView`)
            Transform.scale(
              scale: 0.72 + 0.28 * popIn,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: ux(context, 48)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(phrase.length, (i) {
                      final ch = phrase[i];
                      if (ch == ' ') {
                        return SizedBox(width: ux(context, 26));
                      }
                      final wavePhase = stage1T * math.pi * 3.4 - i * 0.34;
                      final dy = -math.max(0.0, math.sin(wavePhase)) * ux(context, 28);
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: UnitySdfText(
                          ch,
                          unityFontSize: 118,
                          material: UnityTextMaterial.levelCompleteWave,
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Stage 2: Exact `ref1.png` `WinContent` layout (`Banner_Gold.png`, `Label_Level.png`,
  /// `#FF82B2` `Glow_02.png`, `Sparkle_01.png` bokeh, `Reward_Coin.png` + `25`, `Next Level`).
  Widget _buildStage2AmazingWin(
    BuildContext context,
    double stage2Raw,
    double stage2Pop,
  ) {
    final pulse = 1.0 + 0.038 * math.sin(_ambientCtrl.value * math.pi * 2);
    final fade = stage2Raw.clamp(0.0, 1.0);

    return SafeArea(
      child: Opacity(
        opacity: fade,
        child: Column(
          children: [
            const Spacer(flex: 24),

            // 1. Top Gold Ribbon (`Banner_Gold.png`) + `AMAZING!` + 9-slice `Label_Level.png`
            Transform.scale(
              scale: 0.74 + 0.26 * stage2Pop,
              child: SizedBox(
                width: ux(context, 1030),
                height: ux(context, 316),
                child: Stack(
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // Tucked Blue 9-Slice `Label_Level.png` (`Level 19` in `ref1.png`)
                    Positioned(
                      bottom: ux(context, 2),
                      child: UnityNineSlice(
                        sprite: 'Label_Level.png',
                        width: ux(context, 356),
                        height: ux(context, 108),
                        padding: EdgeInsets.only(top: ux(context, 18)),
                        child: UnitySdfText(
                          widget.levelLabel,
                          unityFontSize: 54,
                          material: UnityTextMaterial.blueLabel,
                        ),
                      ),
                    ),

                    // `Banner_Gold.png` (`1042x277` native Unity aspect)
                    Positioned(
                      top: 0,
                      width: ux(context, 1024),
                      height: ux(context, 272),
                      child: Image.asset(
                        'assets/images/Banner_Gold.png',
                        fit: BoxFit.contain,
                      ),
                    ),

                    // `AMAZING!` (`Baloo2_ExtraBold_Brown_Text`)
                    Positioned(
                      top: ux(context, 34),
                      child: const UnitySdfText(
                        'AMAZING!',
                        unityFontSize: 118,
                        material: UnityTextMaterial.bannerBrown,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(flex: 12),

            // 2. Center Rose-Gold Halo (`Glow_02.png`) + `Sparkle_01.png` + `Reward_Coin.png` + `25`
            SizedBox(
              width: ux(context, 780),
              height: ux(context, 650),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Outer Rose-Pink `Glow_02.png` (`#FF82B2` from `WinGameplayView.prefab`)
                  Transform.scale(
                    scale: pulse,
                    child: Image.asset(
                      'assets/images/Glow_02.png',
                      width: ux(context, 740),
                      height: ux(context, 740),
                      color: const Color(0xEBFF82B2),
                      colorBlendMode: BlendMode.modulate,
                    ),
                  ),
                  // Inner Warm Golden Core Glow
                  Transform.scale(
                    scale: 2.0 - pulse,
                    child: Image.asset(
                      'assets/images/Glow_01.png',
                      width: ux(context, 470),
                      height: ux(context, 470),
                      color: const Color(0xD8FFC478),
                      colorBlendMode: BlendMode.modulate,
                    ),
                  ),

                  // Authentic `Sparkle_01.png` floating bokeh particles (`ref1.png`)
                  for (final (ang, dist, sz, phase) in _bokehSparkles)
                    Builder(
                      builder: (_) {
                        final tw = 0.35 +
                            0.65 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          (_ambientCtrl.value + phase) * math.pi * 2,
                                        ));
                        final r = ux(context, dist);
                        final s = ux(context, sz * 1.65);
                        return Transform.translate(
                          offset: Offset(math.cos(ang) * r, math.sin(ang) * r),
                          child: Opacity(
                            opacity: tw.clamp(0.0, 1.0),
                            child: Image.asset(
                              'assets/images/Sparkle_01.png',
                              width: s,
                              height: s,
                            ),
                          ),
                        );
                      },
                    ),

                  // Giant `Reward_Coin.png` + `"25"` (`Baloo2_ExtraBold_CTA_Blue_Text`)
                  Transform.scale(
                    scale: (0.68 + 0.32 * stage2Pop) *
                        (_collecting ? (1.0 - _coinFlyCtrl.value * 0.25) : 1.0),
                    child: SizedBox(
                      width: ux(context, 340),
                      height: ux(context, 382),
                      child: Stack(
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.none,
                        children: [
                          Image.asset(
                            'assets/images/Reward_Coin.png',
                            width: ux(context, 304),
                            height: ux(context, 304),
                            fit: BoxFit.contain,
                          ),
                          Positioned(
                            bottom: 0,
                            child: UnitySdfText(
                              '${widget.rewardCoins}',
                              unityFontSize: 112,
                              material: UnityTextMaterial.ctaBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 14),

            // 3. Authentic 9-Slice `Button_CTA.png` `"Next Level"` (`561x157` in `ref1.png`)
            Transform.scale(
              scale: 0.78 + 0.22 * stage2Pop,
              child: UnityCtaButton(
                label: 'Next Level',
                unityWidth: 572,
                unityHeight: 162,
                unityFontSize: 80,
                onTap: _collecting ? null : _onTapNextLevel,
              ),
            ),

            const Spacer(flex: 32),
          ],
        ),
      ),
    );
  }

  /// Stage 3: Curved Bezier flight of golden `Icon_Coin.png` sprites up into top-left `CoinsWidget`.
  Widget _buildFlyingCoinsLayer(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final startCenter = Offset(screen.width * 0.5, screen.height * 0.50);
    final targetCoinIcon = Offset(ux(context, 96), topPad + ux(context, 62));

    final t = _coinFlyCtrl.value;
    final children = <Widget>[];

    for (int i = 0; i < _flyingCoinCount; i++) {
      final coinStart = (i / (_flyingCoinCount - 1)) * 0.34;
      final coinEnd = 0.58 + (i / (_flyingCoinCount - 1)) * 0.40;
      if (t < coinStart || t >= coinEnd) continue;

      final localT = ((t - coinStart) / (coinEnd - coinStart)).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(localT);

      // Fan outward slightly before arcing up-left to `CoinsWidget`
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

      final coinSz = ux(context, 108) * (1.05 - 0.22 * eased);
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
