import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// Level Complete Overlay combining a smooth 2-line `'Level' / 'Complete!'` wave header (`PoetsenOne`)
/// with the redesigned `Victory` reward layout & denser one-shot Confetti FX:
/// - Dark backdrop scrim (`rgba(10, 8, 28, 0.90)`)
/// - Stage 1 (`0.0s .. 0.72s`): 2-line `'Level'` / `'Complete!'` (`UnityTextMaterial.levelCompleteWave`
///   with `PoetsenOne` font) ripples in letter-by-letter with a continuous C-infinity wave + warm glow,
///   then glides effortlessly on the GPU (`Transform.translate`, zero layout passes) to the top header!
/// - Stage 2 (`seq >= 0.46`):
///   1. One-shot 60/120Hz `_VictoryConfettiPainter` (96 colorful pieces launching from upper-left & upper-right
///      downward over ~4.4s before smoothly fading out and unmounting)
///   2. Center rotating 12-ray sunbeam starburst + golden aura + `Reward_Coin.png` (`428x323`)
///      with `${rewardCoins}` (`UnityTextMaterial.winCoinAmount`) overlapping bottom-right
///   3. `Time | Moves | Combo` summary pill positioned cleanly between the coin pile and CTA
///   4. Bottom `"Continue"` `Button_CTA.png` (`499x221`) triggering curved `Icon_Coin.png` flight to HUD
class WinOverlay extends StatefulWidget {
  final String levelLabel;
  final int rewardCoins;
  final String timeFormatted;
  final int movesCount;
  final int comboCount;
  final VoidCallback? onStage2Shown;
  final ValueChanged<int>? onCoinChunkArrived;
  final VoidCallback onNextLevel;

  const WinOverlay({
    super.key,
    required this.levelLabel,
    required this.rewardCoins,
    this.timeFormatted = '01:55',
    this.movesCount = 0,
    this.comboCount = 0,
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
  late final AnimationController _confettiCtrl;
  late final AnimationController _coinFlyCtrl;

  bool _confettiStarted = false;
  bool _confettiFinished = false;
  bool _stage2Notified = false;
  bool _collecting = false;
  final Set<int> _arrivedCoinIndices = {};

  static const int _flyingCoinCount = 7;
  static const String _line1Text = 'Level';
  static const String _line2Text = 'Complete!';

  @override
  void initState() {
    super.initState();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _sequenceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1650),
    )
      ..addListener(_checkStageTransition)
      ..forward();

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _confettiFinished = true);
        }
      });

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
    if (!_confettiStarted && _sequenceCtrl.value >= 0.38) {
      _confettiStarted = true;
      _confettiCtrl.forward(from: 0.0);
    }
    if (!_stage2Notified && _sequenceCtrl.value >= 0.46) {
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

  void _onTapContinue() {
    if (_collecting) return;
    setState(() => _collecting = true);
    _coinFlyCtrl.forward(from: 0.0);
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _sequenceCtrl.dispose();
    _confettiCtrl.dispose();
    _coinFlyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_sequenceCtrl, _coinFlyCtrl]),
      builder: (context, _) {
        final seq = _sequenceCtrl.value;
        final bgAlpha = (seq / 0.16).clamp(0.0, 1.0) * 0.90;

        return ColoredBox(
          color: Color.fromRGBO(10, 8, 28, bgAlpha),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // One-shot Celebratory Confetti FX: flies in from top-left & top-right downward for ~2.8s, then turns off
              if (_confettiStarted && !_confettiFinished)
                IgnorePointer(
                  key: const ValueKey('win_confetti_fx'),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _VictoryConfettiPainter(
                        progress: _confettiCtrl,
                        scale1080: uxScale(context),
                      ),
                    ),
                  ),
                ),

              _buildWinSequenceBody(context, seq),

              if (_collecting) _buildFlyingCoinsLayer(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWinSequenceBody(BuildContext context, double seq) {
    final stage1GlowFade =
        seq > 0.36 ? (1.0 - ((seq - 0.36) / 0.24)).clamp(0.0, 1.0) : 1.0;

    // Smooth 726ms S-curve glide (`seq` `0.36 -> 0.80`) driven purely via GPU `Transform.translate`
    final glideT = Curves.easeInOutCubic.transform(
      ((seq - 0.36) / 0.44).clamp(0.0, 1.0),
    );
    final stage2Raw = ((seq - 0.44) / 0.40).clamp(0.0, 1.0);
    final coinRaw = ((seq - 0.44) / 0.38).clamp(0.0, 1.0);
    final statsRaw = ((seq - 0.50) / 0.38).clamp(0.0, 1.0);
    final ctaRaw = ((seq - 0.55) / 0.38).clamp(0.0, 1.0);

    final coinPop = Curves.easeOutBack.transform(coinRaw);
    final statsPop = Curves.easeOutBack.transform(statsRaw);
    final ctaPop = Curves.easeOutBack.transform(ctaRaw);

    Widget wrapFade(double alpha, Widget child) {
      final a = alpha.clamp(0.0, 1.0);
      if (a <= 0.005) return const SizedBox.shrink();
      return a >= 0.999 ? child : Opacity(opacity: a, child: child);
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final safeW = constraints.maxWidth;
          final safeH = constraints.maxHeight;
          final centerY = safeH * 0.5;

          final headerBoxH = ux(context, 300);
          final minHeaderCenterY = ux(context, 108) + headerBoxH * 0.5;
          final targetHeaderCenterY = math.max(
            minHeaderCenterY,
            centerY - math.min(ux(context, 495), safeH * 0.308),
          );
          final headerGlideDy =
              (centerY - targetHeaderCenterY) * (1.0 - glideT);

          final stage1AuraSize = ux(context, 780);
          final auraBoxSize = ux(context, 920);
          final coinW = ux(context, 428);
          final coinH = ux(context, 323);
          final rewardsCenterY = centerY + ux(context, 8);

          final statsCenterY =
              centerY + math.min(ux(context, 300), safeH * 0.175);

          final ctaW = ux(context, 499);
          final ctaH = ux(context, 221);
          final ctaCenterY =
              centerY + math.min(ux(context, 585), safeH * 0.348);

          final coinScale = (0.68 + 0.32 * coinPop) *
              (_collecting ? (1.0 - _coinFlyCtrl.value * 0.22) : 1.0);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Stage 1 Central Warm Glow behind 2-line `'Level / Complete!'`
              if (stage1GlowFade > 0.01)
                Positioned(
                  left: (safeW - stage1AuraSize) * 0.5,
                  top: targetHeaderCenterY - stage1AuraSize * 0.5,
                  width: stage1AuraSize,
                  height: stage1AuraSize,
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: Offset(0, headerGlideDy),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _UnityWinCoinAuraPainter(
                            ambient: _ambientCtrl,
                            scale1080: uxScale(context),
                            showCrossFlare: false,
                            intensity: (0.85 * stage1GlowFade).clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Stage 2: Rotating Sunbeam Starburst + Golden Glow + Sparkles
              if (stage2Raw > 0.005)
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
                          intensity: coinRaw,
                        ),
                      ),
                    ),
                  ),
                ),

              // Stage 2: Golden Crown Coin Pile (`Reward_Coin.png`) + Bottom-Right Amount
              if (coinRaw > 0.005)
                Positioned(
                  left: (safeW - coinW) * 0.5,
                  top: rewardsCenterY - coinH * 0.5,
                  width: coinW,
                  height: coinH,
                  child: Transform.scale(
                    scale: coinScale,
                    child: wrapFade(
                      coinRaw,
                      RepaintBoundary(
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Image.asset(
                              'assets/images/Reward_Coin.png',
                              width: coinW,
                              height: coinH,
                              fit: BoxFit.contain,
                            ),
                            Positioned(
                              right: -ux(context, 16),
                              bottom: -ux(context, 22),
                              child: UnitySdfText(
                                '${widget.rewardCoins}',
                                unityFontSize: 108,
                                material: UnityTextMaterial.winCoinAmount,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Smooth 2-Line `'Level' / 'Complete!'` (`PoetsenOne` font):
              // Ripples in at screen center, glides on GPU (`Transform.translate`) up to the top header!
              Positioned(
                left: 0,
                right: 0,
                top: targetHeaderCenterY - headerBoxH * 0.5,
                height: headerBoxH,
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: Offset(0, headerGlideDy),
                    child: Center(
                      child: _buildTwoLineWaveLevelComplete(
                        context,
                        seq: seq,
                        glideT: glideT,
                      ),
                    ),
                  ),
                ),
              ),

              // Stage 2: 3-Stat Card (`Time | Moves | Combo`)
              if (statsRaw > 0.005)
                Positioned(
                  left: 0,
                  right: 0,
                  top: statsCenterY - ux(context, 62),
                  child: Center(
                    child: Transform.scale(
                      scale: 0.76 + 0.24 * statsPop,
                      child: wrapFade(
                        statsRaw,
                        RepaintBoundary(
                          child: _buildWinStatsRow(context),
                        ),
                      ),
                    ),
                  ),
                ),

              // Stage 2: Bottom `"Continue"` Gold-Rimmed Green Pill (`Button_CTA.png`, `499x221`)
              if (ctaRaw > 0.005)
                Positioned(
                  left: (safeW - ctaW) * 0.5,
                  top: ctaCenterY - ctaH * 0.5,
                  child: Transform.scale(
                    scale: 0.78 + 0.22 * ctaPop,
                    child: wrapFade(
                      ctaRaw,
                      RepaintBoundary(
                        child: UnityCtaButton(
                          label: 'Continue',
                          unityWidth: 499,
                          unityHeight: 221,
                          unityFontSize: 68,
                          onTap: _collecting ? null : _onTapContinue,
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

  /// Silky 120Hz 2-line `'Level' / 'Complete!'` wave header (`PoetsenOne` + `UnityTextMaterial.levelCompleteWave`):
  /// - 2-pass per-line rendering (Pass 1: all drop shadows & strokes; Pass 2: all golden gradient faces)
  ///   so outlines never cut across neighboring characters.
  /// - Single continuous `C∞` sine wave (`sin(ambVal * 4π - phase)`) with zero V-kink velocity jumps
  ///   and zero phase switches during the center-to-header glide.
  Widget _buildTwoLineWaveLevelComplete(
    BuildContext context, {
    required double seq,
    required double glideT,
  }) {
    final blockScale = ui.lerpDouble(1.04, 0.94, glideT)!;
    final waveAmp = ui.lerpDouble(ux(context, 11.5), ux(context, 6.0), glideT)!;

    return AnimatedBuilder(
      animation: _ambientCtrl,
      builder: (context, _) {
        final ambVal = _ambientCtrl.value;
        return Transform.scale(
          scale: blockScale,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ux(context, 40),
                vertical: ux(context, 18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTwoPassWaveLine(
                    context,
                    text: _line1Text,
                    unityFontSize: 132,
                    seq: seq,
                    baseDelay: 0.00,
                    charStagger: 0.022,
                    phaseOffset: 1.4,
                    ambVal: ambVal,
                    waveAmp: waveAmp,
                  ),
                  Transform.translate(
                    offset: Offset(0, -ux(context, 18)),
                    child: _buildTwoPassWaveLine(
                      context,
                      text: _line2Text,
                      unityFontSize: 120,
                      seq: seq,
                      baseDelay: 0.068,
                      charStagger: 0.019,
                      phaseOffset: 0.0,
                      ambVal: ambVal,
                      waveAmp: waveAmp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTwoPassWaveLine(
    BuildContext context, {
    required String text,
    required double unityFontSize,
    required double seq,
    required double baseDelay,
    required double charStagger,
    required double phaseOffset,
    required double ambVal,
    required double waveAmp,
  }) {
    const mat = UnityTextMaterial.levelCompleteWave;
    final fs = ux(context, unityFontSize);
    final innerSw = (fs * mat.strokeRatio).clamp(1.2, 22.0);
    final outerSw = (fs * mat.outerStrokeRatio).clamp(innerSw + 0.8, 28.0);
    final dropY = fs * mat.underlayYRatio;
    final riseDist = ux(context, 28);

    TextStyle styleWith(Paint foreground) => TextStyle(
          fontFamily: mat.fontFamily,
          fontSize: fs,
          fontWeight: mat.fontWeight,
          height: 1.05,
          foreground: foreground,
        );

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
          Offset(0, fs * 0.12),
          Offset(0, fs * 0.96),
          [mat.faceTop, mat.faceBottom],
        ),
    );

    final backRow = <Widget>[];
    final faceRow = <Widget>[];

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final charStart = baseDelay + i * charStagger;
      final u = ((seq - charStart) / 0.22).clamp(0.0, 1.0);

      final alpha = Curves.easeOut.transform((u / 0.42).clamp(0.0, 1.0));
      final charScale = 0.34 + 0.66 * Curves.easeOutBack.transform(u);
      final enterDy = (1.0 - Curves.easeOutCubic.transform(u)) * riseDist;
      final waveEnv = Curves.easeInOut.transform(u);

      // Continuous C∞ smooth sine wave (`2` exact cycles per 3.6s loop -> seamless wrap)
      final waveAngle = ambVal * math.pi * 4.0 - (i + phaseOffset) * 0.42;
      final waveDy = math.sin(waveAngle) * waveAmp * waveEnv;
      final totalDy = enterDy + waveDy;

      Widget wrapMotion(Widget child) {
        Widget res = Transform.translate(
          offset: Offset(0, totalDy),
          child: Transform.scale(scale: charScale, child: child),
        );
        if (alpha <= 0.005) {
          res = Opacity(opacity: 0.0, child: res);
        } else if (alpha < 0.999) {
          res = Opacity(opacity: alpha, child: res);
        }
        return res;
      }

      backRow.add(
        ExcludeSemantics(
          child: wrapMotion(
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Transform.translate(
                  offset: Offset(0, dropY),
                  child: Text(ch, style: underlayStyle),
                ),
                Text(ch, style: outerStrokeStyle),
                Text(ch, style: innerStrokeStyle),
              ],
            ),
          ),
        ),
      );

      faceRow.add(
        wrapMotion(
          Text(ch, style: faceStyle),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: backRow),
        Row(mainAxisSize: MainAxisSize.min, children: faceRow),
      ],
    );
  }

  Widget _buildWinStatsRow(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ux(context, 48),
        vertical: ux(context, 18),
      ),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(24, 14, 62, 0.74),
        borderRadius: BorderRadius.circular(ux(context, 38)),
        border: Border.all(
          color: const Color(0x6BFFB915),
          width: ux(context, 2.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Time (Clock icon + Time + timeFormatted in neon green)
          _buildStatItem(
            context,
            icon: _buildClockIcon(context),
            label: 'Time',
            value: widget.timeFormatted,
          ),
          _buildStatDivider(context),

          // 2. Moves (Arrow in circle + Moves + movesCount in neon green)
          _buildStatItem(
            context,
            icon: _buildMovesIcon(context),
            label: 'Moves',
            value: '${widget.movesCount}',
          ),
          _buildStatDivider(context),

          // 3. Combo (Star outline + Combo + comboCount in neon green)
          _buildStatItem(
            context,
            icon: _buildComboStarIcon(context),
            label: 'Combo',
            value: '${widget.comboCount}',
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required Widget icon,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        icon,
        SizedBox(width: ux(context, 16)),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ux(context, 38),
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.05,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ux(context, 44),
                fontWeight: FontWeight.w900,
                color: const Color(0xFF69F0AE),
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatDivider(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ux(context, 32)),
      child: Container(
        width: ux(context, 2.0),
        height: ux(context, 68),
        color: Colors.white.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _buildClockIcon(BuildContext context) {
    final size = ux(context, 64);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ClockIconPainter(scale: uxScale(context)),
      ),
    );
  }

  Widget _buildMovesIcon(BuildContext context) {
    final size = ux(context, 64);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MovesArrowIconPainter(scale: uxScale(context)),
      ),
    );
  }

  Widget _buildComboStarIcon(BuildContext context) {
    final size = ux(context, 64);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ComboStarIconPainter(scale: uxScale(context)),
      ),
    );
  }

  /// Curved Bezier flight of golden `Icon_Coin.png` sprites up into top-left `CoinsWidget`.
  Widget _buildFlyingCoinsLayer(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final startCenter = Offset(
      screen.width * 0.5,
      screen.height * 0.5 - ux(context, 42),
    );
    final targetCoinIcon = Offset(
      ux(context, UnityCoinsWidget.coinCenterXUnity),
      topPad + ux(context, UnityCoinsWidget.coinCenterYUnity),
    );

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

      final coinSz = ux(context, 98) * (1.05 - 0.18 * eased);
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

class _ConfettiSeed {
  final bool fromLeft;
  final double startXEdge1080;
  final double startYFrac;
  final double xReachFrac;
  final double vyInitFrac;
  final double fallDistFrac;
  final double delay;
  final double lifeSpan;
  final double sz1080;
  final double swayAmp1080;
  final double spinRate;
  final int colIdx;
  final int shapeKind; // 0: oval disc, 1: streamer ribbon, 2: foil petal

  const _ConfettiSeed({
    required this.fromLeft,
    required this.startXEdge1080,
    required this.startYFrac,
    required this.xReachFrac,
    required this.vyInitFrac,
    required this.fallDistFrac,
    required this.delay,
    required this.lifeSpan,
    required this.sz1080,
    required this.swayAmp1080,
    required this.spinRate,
    required this.colIdx,
    required this.shapeKind,
  });
}

/// One-shot 60/120Hz Celebratory Confetti FX Painter (`progress` `0.0 -> 1.0` over ~4.4s):
/// Launches 96 colorful 3D-tumbling confetti discs, ribbons, and foil petals (`48` upper-left + `48` upper-right),
/// arcing inward with air-drag and fluttering downward before smoothly fading out and unmounting.
class _VictoryConfettiPainter extends CustomPainter {
  final Animation<double> progress;
  final double scale1080;

  static const List<Color> _palette = [
    Color(0xFF00D4FF), // Electric Cyan
    Color(0xFF00F0C6), // Aqua Mint
    Color(0xFF6CE800), // Bright Lime
    Color(0xFF00E858), // Vivid Emerald
    Color(0xFFFF2ED1), // Hot Magenta
    Color(0xFFF68EFF), // Candy Pink
    Color(0xFFFF7B00), // Vivid Orange
    Color(0xFFFF4A00), // Tangerine Red-Orange
    Color(0xFFFFE600), // Sunshine Yellow
    Color(0xFFFFB400), // Warm Amber
    Color(0xFF8B82FF), // Periwinkle Violet
  ];

  static final List<_ConfettiSeed> _cannonSeeds = _buildCannonParticles();

  static List<_ConfettiSeed> _buildCannonParticles() {
    final rng = math.Random(204837);
    final list = <_ConfettiSeed>[];
    const perSide = 48;

    for (int side = 0; side < 2; side++) {
      final fromLeft = side == 0;
      for (int idx = 0; idx < perSide; idx++) {
        final fromTopCeiling = (idx % 4) == 3;
        final startXEdge1080 = fromTopCeiling
            ? (18.0 + rng.nextDouble() * 175.0)
            : (-30.0 + rng.nextDouble() * 14.0);
        final startYFrac = fromTopCeiling
            ? (-0.03 + rng.nextDouble() * 0.035)
            : (0.01 + rng.nextDouble() * 0.25);

        // Stratified across 8 horizontal bands so coverage is lush and even without clumping
        final band = (idx % 8) / 8.0;
        final xReachFrac = 0.065 + band * 0.43 + rng.nextDouble() * 0.055;
        final vyInitFrac = fromTopCeiling
            ? (0.01 + rng.nextDouble() * 0.045)
            : (-0.075 + rng.nextDouble() * 0.11);
        final fallDistFrac = 0.74 + rng.nextDouble() * 0.26;

        final delay = (idx / (perSide - 1)) * 0.36 + rng.nextDouble() * 0.024;
        final lifeSpan = 0.55 + rng.nextDouble() * 0.06;

        final sz1080 = 26.0 + rng.nextDouble() * 20.0;
        final swayAmp1080 = 18.0 + rng.nextDouble() * 22.0;
        final rawSpin = 10.5 + rng.nextDouble() * 6.5;
        final spinRate = fromLeft ? rawSpin : -rawSpin;
        final colIdx = (idx * 3 + side * 5 + rng.nextInt(3)) % _palette.length;

        final shapeRoll = idx % 10;
        final shapeKind = shapeRoll < 5
            ? 0 // glossy oval disc (50%)
            : (shapeRoll < 8 ? 1 : 2); // streamer ribbon (30%) / foil petal (20%)

        list.add(
          _ConfettiSeed(
            fromLeft: fromLeft,
            startXEdge1080: startXEdge1080,
            startYFrac: startYFrac,
            xReachFrac: xReachFrac,
            vyInitFrac: vyInitFrac,
            fallDistFrac: fallDistFrac,
            delay: delay,
            lifeSpan: lifeSpan,
            sz1080: sz1080,
            swayAmp1080: swayAmp1080,
            spinRate: spinRate,
            colIdx: colIdx,
            shapeKind: shapeKind,
          ),
        );
      }
    }
    return list;
  }

  const _VictoryConfettiPainter({
    required this.progress,
    required this.scale1080,
  }) : super(repaint: progress);

  double _u(double px1080) => px1080 * scale1080;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0.001 || t >= 0.999 || size.width <= 1 || size.height <= 1) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final dragNorm = 1.0 - math.exp(-3.8);

    for (final p in _cannonSeeds) {
      if (t <= p.delay) continue;
      final u = (t - p.delay) / p.lifeSpan;
      if (u <= 0.0 || u >= 1.0) continue;

      final fadeIn = (u / 0.05).clamp(0.0, 1.0);
      final fadeOut = u > 0.72
          ? Curves.easeInQuad.transform(((1.0 - u) / 0.28).clamp(0.0, 1.0))
          : 1.0;

      // 3D tumbling spin + subtle specular glint when catching light face-on
      final tumble = u * p.spinRate + p.colIdx * 0.45;
      final minorRatio = 0.18 + 0.82 * math.cos(tumble).abs();
      final glint = 0.88 + 0.12 * minorRatio;
      final alpha = (fadeIn * fadeOut * glint).clamp(0.0, 1.0);
      if (alpha <= 0.015) continue;

      // Inward burst decelerated by air drag + gentle leaf-flutter sway
      final dragX = (1.0 - math.exp(-3.8 * u)) / dragNorm;
      final swayEnvelope = (u * 2.0).clamp(0.0, 1.0);
      final sway = math.sin(u * math.pi * 3.6 + p.spinRate) *
          _u(p.swayAmp1080) *
          swayEnvelope;
      final startX = p.fromLeft
          ? _u(p.startXEdge1080)
          : (size.width - _u(p.startXEdge1080));
      final inwardDx = size.width * p.xReachFrac * dragX + sway;
      final x = p.fromLeft ? (startX + inwardDx) : (startX - inwardDx);

      // Slight upper-corner loft curving smoothly into downward flutter fall
      final loftDy = size.height * p.vyInitFrac * (1.0 - math.exp(-4.5 * u));
      final fallDy =
          size.height * p.fallDistFrac * math.pow(u, 1.28).toDouble();
      final y = size.height * p.startYFrac + loftDy + fallDy;

      final yaw = (p.fromLeft ? 0.35 : -0.35) +
          0.45 * math.sin(u * math.pi * 2.8 + p.colIdx) +
          tumble * 0.18;

      paint.color =
          _palette[p.colIdx % _palette.length].withValues(alpha: alpha);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(yaw);
      if (p.shapeKind == 1) {
        final rw = _u(p.sz1080) * 1.38;
        final rh = _u(p.sz1080) * 0.42 * minorRatio;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: rw, height: rh),
            Radius.circular(_u(5)),
          ),
          paint,
        );
      } else if (p.shapeKind == 2) {
        final pw = _u(p.sz1080) * 0.86;
        final ph = pw * minorRatio;
        canvas.rotate(math.pi * 0.25);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: pw, height: ph),
            Radius.circular(_u(4)),
          ),
          paint,
        );
      } else {
        final ow = _u(p.sz1080);
        final oh = ow * 0.65 * minorRatio;
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: ow, height: oh),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VictoryConfettiPainter oldDelegate) =>
      oldDelegate.scale1080 != scale1080;
}

/// Pure GPU additive (`BlendMode.plus`) painter for `Victory.png`:
/// 1. 12 rotating soft white-gold sunbeam wedges (`sunburst`)
/// 2. Warm golden-amber radial halo & bright white-gold core behind `Reward_Coin.png`
/// 3. Outward-drifting soft white-gold bokeh orbs
class _UnityWinCoinAuraPainter extends CustomPainter {
  final Animation<double> ambient;
  final double scale1080;
  final bool showCrossFlare;
  final double intensity;

  static const int _rayCount = 12;

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

    // 1. Rotating 12-Ray White-Gold Radial Starburst (`Victory.png` sunbeams)
    if (showCrossFlare) {
      final rayR = _u(455) * breathe;
      final stepAngle = (math.pi * 2.0) / _rayCount;
      // Advance by exactly 2 ray pitches per cycle so `ambient.value` 1.0 -> 0.0 wraps seamlessly
      final baseRot = ambient.value * stepAngle * 2.0;
      final halfWedge = stepAngle * 0.23;

      final wedgesPath = Path();
      for (int i = 0; i < _rayCount; i++) {
        final a = baseRot + i * stepAngle;
        wedgesPath.moveTo(center.dx, center.dy);
        wedgesPath.lineTo(
          center.dx + math.cos(a - halfWedge) * rayR,
          center.dy + math.sin(a - halfWedge) * rayR,
        );
        wedgesPath.lineTo(
          center.dx + math.cos(a + halfWedge) * rayR,
          center.dy + math.sin(a + halfWedge) * rayR,
        );
        wedgesPath.close();
      }

      final rayPaint = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          center,
          rayR,
          [
            Color.fromRGBO(255, 252, 236, 0.42 * intensity),
            Color.fromRGBO(255, 240, 190, 0.24 * intensity),
            Color.fromRGBO(255, 214, 128, 0.08 * intensity),
            const Color.fromRGBO(255, 214, 128, 0.0),
          ],
          const [0.0, 0.42, 0.76, 1.0],
        );
      canvas.drawPath(wedgesPath, rayPaint);
    }

    // 2. Soft Warm White-Gold Outer Halo
    final outerR = _u(395) * breathe;
    final outerPaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        center,
        outerR,
        [
          Color.fromRGBO(255, 235, 165, 0.46 * intensity),
          Color.fromRGBO(255, 198, 92, 0.24 * intensity),
          Color.fromRGBO(186, 128, 255, 0.08 * intensity),
          const Color.fromRGBO(186, 128, 255, 0.0),
        ],
        const [0.0, 0.36, 0.72, 1.0],
      );
    canvas.drawCircle(center, outerR, outerPaint);

    // 3. Bright White-Gold Core behind `Reward_Coin.png`
    final coreR = _u(225) * breathe;
    final corePaint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(
        center,
        coreR,
        [
          Color.fromRGBO(255, 255, 245, 0.56 * intensity),
          Color.fromRGBO(255, 216, 102, 0.28 * intensity),
          const Color.fromRGBO(255, 190, 48, 0.0),
        ],
        const [0.0, 0.55, 1.0],
      );
    canvas.drawCircle(center, coreR, corePaint);

    // 4. Outward-drifting soft white-gold bokeh sparkles
    final bokehPaint = Paint()..blendMode = BlendMode.plus;
    for (final (ang, baseDist, travel, sz1080, seedPhase) in _sparkleSeeds) {
      final lifeT = (ambient.value * 1.5 + seedPhase) % 1.0;
      final env = lifeT < 0.24
          ? (lifeT / 0.24)
          : math.pow(1.0 - (lifeT - 0.24) / 0.76, 1.35).toDouble();
      final alpha = (env * 0.90 * intensity).clamp(0.0, 1.0);
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
          Color.fromRGBO(255, 242, 198, alpha * 0.62),
          Color.fromRGBO(255, 206, 112, alpha * 0.20),
          const Color.fromRGBO(255, 206, 112, 0.0),
        ],
        const [0.0, 0.28, 0.62, 1.0],
      );
      canvas.drawCircle(pos, radius, bokehPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UnityWinCoinAuraPainter old) {
    return old.scale1080 != scale1080 ||
        old.showCrossFlare != showCrossFlare ||
        old.intensity != intensity;
  }
}

class _ClockIconPainter extends CustomPainter {
  final double scale;
  _ClockIconPainter({required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);
    final r = w * 0.44;

    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, 2.4 * scale)
      ..color = Colors.white;
    canvas.drawCircle(c, r, circlePaint);

    final handPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, 2.2 * scale)
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;

    // Hour hand at 12
    canvas.drawLine(c, Offset(c.dx, c.dy - r * 0.54), handPaint);
    // Minute hand at ~4
    canvas.drawLine(c, Offset(c.dx + r * 0.56, c.dy + r * 0.24), handPaint);

    // Center pivot dot
    canvas.drawCircle(c, math.max(1.5, 2.0 * scale), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ClockIconPainter oldDelegate) =>
      oldDelegate.scale != scale;
}

class _MovesArrowIconPainter extends CustomPainter {
  final double scale;
  _MovesArrowIconPainter({required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final c = Offset(w * 0.5, h * 0.5);
    final r = w * 0.44;

    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, 2.4 * scale)
      ..color = Colors.white;
    canvas.drawCircle(c, r, circlePaint);

    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, 2.4 * scale)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    // Horizontal arrow shaft
    canvas.drawLine(
      Offset(c.dx - r * 0.44, c.dy),
      Offset(c.dx + r * 0.46, c.dy),
      arrowPaint,
    );

    // Arrowhead
    final headPath = Path()
      ..moveTo(c.dx + r * 0.16, c.dy - r * 0.36)
      ..lineTo(c.dx + r * 0.48, c.dy)
      ..lineTo(c.dx + r * 0.16, c.dy + r * 0.36);
    canvas.drawPath(headPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _MovesArrowIconPainter oldDelegate) =>
      oldDelegate.scale != scale;
}

class _ComboStarIconPainter extends CustomPainter {
  final double scale;
  _ComboStarIconPainter({required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final cy = h * 0.5;
    final outerR = w * 0.44;
    final innerR = w * 0.21;

    final starPath = Path();
    for (int i = 0; i < 5; i++) {
      final outerAngle = -math.pi / 2.0 + i * (2.0 * math.pi / 5.0);
      final innerAngle = outerAngle + math.pi / 5.0;

      final ox = cx + math.cos(outerAngle) * outerR;
      final oy = cy + math.sin(outerAngle) * outerR;
      if (i == 0) {
        starPath.moveTo(ox, oy);
      } else {
        starPath.lineTo(ox, oy);
      }

      final ix = cx + math.cos(innerAngle) * innerR;
      final iy = cy + math.sin(innerAngle) * innerR;
      starPath.lineTo(ix, iy);
    }
    starPath.close();

    final starPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.8, 2.4 * scale)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawPath(starPath, starPaint);
  }

  @override
  bool shouldRepaint(covariant _ComboStarIconPainter oldDelegate) =>
      oldDelegate.scale != scale;
}
