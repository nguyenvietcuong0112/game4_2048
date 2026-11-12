import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart'
    show
        BlurStyle,
        Canvas,
        Color,
        Colors,
        Curves,
        FontWeight,
        MaskFilter,
        Offset,
        Paint,
        Path,
        RRect,
        Radius,
        Rect,
        Shadow,
        TextDirection,
        TextPainter,
        TextSpan,
        TextStyle;
import '../models/palette.dart';

/// Above-board 3D Crystal-Glass Water Bottle / Potion Flask (`hũ nước` — matches the crystal-clear
/// glass bottle, rolled toroidal glass collar, translucent liquid with effervescent bubbles,
/// dynamic S-wave meniscus, and fluid water stream in `com.chaos.drink.sort` `play_0.png`).
class MagicSandJarComponent extends PositionComponent {
  BlockColorStyle _style;
  final int levelNumber;
  int targetNumber;

  double _appearProgress = 1.0;
  double _fillProgress = 0.0;
  double _glowIntensity = 0.0;
  double _openProgress = 0.0;
  double _shakeIntensity = 0.0;
  double? _explicitCurtainOpenProgress;
  bool _externalStreamActive = false;
  double _externalStreamSideSign = 1.0;
  double _animTime = 0.0;
  double _surfaceWavePhase = 0.0;
  bool _isOpened = false;

  ui.Image? _haloImg;
  final Path _scratchPath = Path();

  MagicSandJarComponent({
    required BlockColorStyle style,
    required this.levelNumber,
    this.targetNumber = 4096,
    required Vector2 centerPosition,
    required double jarWidth,
    required double jarHeight,
    double initialAppearProgress = 1.0,
  })  : _style = style,
        _appearProgress = initialAppearProgress.clamp(0.0, 1.0),
        super(
          position: centerPosition,
          size: Vector2(jarWidth, jarHeight),
          anchor: Anchor.center,
          priority: 92,
        ) {
    _cacheSprites();
  }

  void _cacheSprites() {
    if (Flame.images.containsKey('Explosion_Halo.png')) {
      try {
        _haloImg = Flame.images.fromCache('Explosion_Halo.png');
      } catch (_) {}
    }
  }

  BlockColorStyle get style => _style;
  double get appearProgress => _appearProgress;
  double get fillProgress => _fillProgress;
  double get glowIntensity => _glowIntensity;
  double get shakeIntensity => _shakeIntensity;
  double get openProgress => _openProgress;
  bool get isOpened => _isOpened;

  bool get isAnimating =>
      (_appearProgress > 0.001 && _appearProgress < 0.999) ||
      _shakeIntensity > 0.001 ||
      _glowIntensity > 0.001 ||
      _externalStreamActive ||
      (_fillProgress > 0.001 && !_isOpened) ||
      (_isOpened && _openProgress < 1.0);

  double get _easedCurtainOpen {
    final raw = (_explicitCurtainOpenProgress ?? (_fillProgress / 0.32))
        .clamp(0.0, 1.0);
    return Curves.easeInOutCubic.transform(raw);
  }

  double get _easedFill =>
      Curves.easeInOutSine.transform(_fillProgress.clamp(0.0, 1.0));

  double _localSurfaceY(double h) =>
      ui.lerpDouble(h * 0.895, h * 0.365, _easedFill)!;

  /// Smooth, rock-steady pose during active pouring, transitioning gently to a soft cushion breath once full.
  ({double scale, double dx, double dy, double angle}) _computePoseTransform() {
    final isActivelyPouring =
        _externalStreamActive || (_fillProgress > 0.001 && _fillProgress < 0.96);
    if (isActivelyPouring) {
      return (scale: 1.0, dx: 0.0, dy: 0.0, angle: 0.0);
    }
    final settleT = _fillProgress >= 0.96
        ? ((_fillProgress - 0.96) / 0.04).clamp(0.0, 1.0)
        : 0.0;
    final effSway = _shakeIntensity * settleT;
    final scale = 1.0 +
        0.032 * _glowIntensity * settleT +
        0.010 * math.sin(_animTime * 9.0) * effSway;
    final angle = math.sin(_animTime * 10.5) * 0.016 * effSway;
    final dx = math.sin(_animTime * 9.5) * size.x * 0.004 * effSway;
    final dy = math.cos(_animTime * 11.0) * size.y * 0.004 * effSway;
    return (scale: scale, dx: dx, dy: dy, angle: angle);
  }

  Vector2 _localToStage(double lx, double ly) {
    final w = size.x;
    final h = size.y;
    final cx = w * 0.5;
    final cy = h * 0.52;
    final pose = _computePoseTransform();
    final rx = (lx - cx) * pose.scale;
    final ry = (ly - cy) * pose.scale;
    final ca = math.cos(pose.angle);
    final sa = math.sin(pose.angle);
    final tx = rx * ca - ry * sa + cx + pose.dx;
    final ty = rx * sa + ry * ca + cy + pose.dy;
    return Vector2(
      position.x - w * 0.5 + tx,
      position.y - h * 0.5 + ty,
    );
  }

  /// World-space coordinates of the bottle's open oval mouth (`(w * 0.5, h * 0.080)`).
  Vector2 get mouthWorldPos => _localToStage(size.x * 0.5, size.y * 0.080);

  /// World-space coordinates of the live rising liquid meniscus center (`(w * 0.5, surfaceY)`).
  Vector2 get liquidSurfaceWorldPos =>
      _localToStage(size.x * 0.5, _localSurfaceY(size.y));

  /// Exact half-width of the vertical water column inside the jar neck in stage coordinates.
  double get neckStreamHalfWidthWorld =>
      size.x * 0.056 * _computePoseTransform().scale;

  void updateStyle(BlockColorStyle newStyle) {
    _style = newStyle;
  }

  void updateTargetNumber(int newTarget) {
    targetNumber = newTarget;
  }

  void resetJarState({double initialAppearProgress = 1.0}) {
    _appearProgress = initialAppearProgress.clamp(0.0, 1.0);
    _fillProgress = 0.0;
    _glowIntensity = 0.0;
    _openProgress = 0.0;
    _shakeIntensity = 0.0;
    _explicitCurtainOpenProgress = null;
    _externalStreamActive = false;
    _isOpened = false;
  }

  void setWinSequenceState({
    double appearProgress = 1.0,
    required double fillProgress,
    required double glowIntensity,
    required double shakeIntensity,
    required double openProgress,
    double? curtainOpenProgress,
    bool externalStreamActive = false,
    double externalStreamSideSign = 1.0,
  }) {
    _appearProgress = appearProgress.clamp(0.0, 1.0);
    _fillProgress = fillProgress.clamp(0.0, 1.0);
    _glowIntensity = glowIntensity.clamp(0.0, 1.0);
    _shakeIntensity = shakeIntensity.clamp(0.0, 1.0);
    _openProgress = openProgress.clamp(0.0, 1.0);
    _explicitCurtainOpenProgress = curtainOpenProgress?.clamp(0.0, 1.0);
    _externalStreamActive = externalStreamActive;
    _externalStreamSideSign = externalStreamSideSign >= 0 ? 1.0 : -1.0;
    if (_openProgress > 0.01) {
      _isOpened = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    final clampedDt = dt.clamp(0.0, 0.05);
    _animTime += clampedDt;
    final isPouringNow =
        _externalStreamActive || (_fillProgress > 0.005 && _fillProgress < 0.98);
    final waveSpeed = isPouringNow ? 7.6 : 2.8;
    _surfaceWavePhase =
        (_surfaceWavePhase + clampedDt * waveSpeed) % (math.pi * 200.0);
  }

  void _applyLocalPoseToCanvas(Canvas canvas, double w, double h) {
    final cx = w * 0.5;
    final cy = h * 0.52;
    if (_appearProgress < 0.995) {
      final popScale = 0.36 +
          0.64 * Curves.easeOutBack.transform(_appearProgress.clamp(0.0, 1.0));
      canvas.translate(cx, cy);
      canvas.scale(popScale, popScale);
      canvas.translate(-cx, -cy);
    }
    final pose = _computePoseTransform();
    if ((pose.scale - 1.0).abs() > 1e-4 ||
        pose.dx.abs() > 1e-3 ||
        pose.dy.abs() > 1e-3 ||
        pose.angle.abs() > 1e-4) {
      canvas.translate(cx + pose.dx, cy + pose.dy);
      canvas.scale(pose.scale, pose.scale);
      canvas.rotate(pose.angle);
      canvas.translate(-cx, -cy);
    }
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    if (w <= 4 || h <= 4 || _appearProgress <= 0.005) return;

    canvas.save();
    _applyLocalPoseToCanvas(canvas, w, h);

    // 0. Outer Ambient Halo & Opening God-Rays
    if (_glowIntensity > 0.01 || _openProgress > 0.01 || _appearProgress < 0.995) {
      _drawOuterAuraAndGodRays(canvas, w, h);
    }

    // 1. Unified back-to-front Potion Pouch Water Jar (Idle & Pouring/Filled)
    _drawCompletePotionPouchJar(canvas, w, h);

    // 2. When Jar Completes (`_openProgress >= 0.15`), emit luminous Crystal-Aqua Water Sparkles & Bubbles
    if (_openProgress >= 0.15) {
      _drawCrystalWaterCompletionBloom(canvas, w, h);
    }

    canvas.restore();
  }

  /// Renders the foreground glass lip, water-surface impact ripples & crown droplets,
  /// twisted golden neck rope, and target goal tag OVER the unbroken `BoardSandStreamToJarVfx` stream!
  void renderStreamForegroundOcclusion(
    Canvas stageCanvas, {
    required bool isStreamTouchingSurface,
    required double streamImpactAlpha,
  }) {
    final w = size.x;
    final h = size.y;
    if (w <= 4 || h <= 4 || _appearProgress <= 0.005) return;

    stageCanvas.save();
    stageCanvas.translate(position.x - w * 0.5, position.y - h * 0.5);
    _applyLocalPoseToCanvas(stageCanvas, w, h);

    final easedOpen = _easedCurtainOpen;
    final surfaceY = _localSurfaceY(h);
    final glassBodyPath = _buildPotNeckAndBellyClipPath(w, h);

    // 1. Concentric surface ripples + cute upward crown-splash droplets OVER the plunging stream tip (`media_1794051150239.png`)
    if (isStreamTouchingSurface && streamImpactAlpha > 0.02) {
      stageCanvas.save();
      stageCanvas.clipPath(glassBodyPath);
      _drawWaterSurfaceRipples(
        stageCanvas,
        w: w,
        h: h,
        surfaceY: surfaceY,
        alphaScale: streamImpactAlpha,
      );
      _drawSurfaceImpactCrownDroplets(
        stageCanvas,
        w: w,
        h: h,
        surfaceY: surfaceY,
        alpha: streamImpactAlpha,
      );
      stageCanvas.restore();
    }

    // 2. Specular vertical glass belly reflections OVER the vertical water stream
    _drawExposedBellyGlassHighlights(
      stageCanvas,
      w: w,
      h: h,
      glassBodyPath: glassBodyPath,
      openProgress: easedOpen,
    );

    // 3. Translucent crystal-aqua FRONT glass mouth lip OVER the stream entry at `0.080 * h`
    _drawCrystalAquaMouthCollar(
      stageCanvas,
      w: w,
      h: h,
      frontLipOnly: true,
    );

    // 4. 3D Twisted Golden Rope Collar + Butter-Cream Target Tag (`4096`) OVER the glass neck!
    _drawGoldenRopeAndKnot(stageCanvas, w: w, h: h, openProgress: easedOpen);
    _drawTargetGoalTag(stageCanvas, w: w, h: h, openProgress: easedOpen);

    stageCanvas.restore();
  }

  /// Renders the complete Potion Pouch Water Jar in strict physical back-to-front order.
  void _drawCompletePotionPouchJar(Canvas canvas, double w, double h) {
    final cx = w * 0.5;
    final isPouringOrFull = _fillProgress > 0.005;
    final easedOpen = _easedCurtainOpen;
    final easedFill = _easedFill;

    // 1. Soft dark navy ground drop shadow right beneath the rounded aqua-glass bowl
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.948),
        width: w * 0.66,
        height: h * 0.082,
      ),
      Paint()
        ..color = const Color(0x64020D2A)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.032),
    );

    final glassBodyPath = _buildPotNeckAndBellyClipPath(w, h);

    // 2. Crystal-Aqua Glass Base Bowl, Concave Neck & Belly Chamber
    _drawCrystalAquaGlassBody(
      canvas,
      w: w,
      h: h,
      glassBodyPath: glassBodyPath,
      openProgress: easedOpen,
    );

    // 3. Rolled 3D Crystal-Aqua Top Mouth Rim & Recessed Oval Opening
    _drawCrystalAquaMouthCollar(
      canvas,
      w: w,
      h: h,
      frontLipOnly: false,
    );

    // 4. Rising Liquid Pool, Bubbles & Surface Ripples (and standalone vertical stream when `_externalStreamActive == false`)
    if (isPouringOrFull) {
      _drawBottleLiquidColumn(
        canvas,
        w: w,
        h: h,
        bellyPath: glassBodyPath,
        fillFraction: easedFill,
        isPouring: _fillProgress < 0.98,
        includeVerticalStream: !_externalStreamActive,
      );

      if (!_externalStreamActive) {
        _drawExposedBellyGlassHighlights(
          canvas,
          w: w,
          h: h,
          glassBodyPath: glassBodyPath,
          openProgress: easedOpen,
        );
        _drawCrystalAquaMouthCollar(
          canvas,
          w: w,
          h: h,
          frontLipOnly: true,
        );
      }
    }

    // 4b. Subtle luminous mystery "?" watermark on the transparent glass belly when idle/empty
    if (_fillProgress < 0.28) {
      _drawMysteryQuestionMark(
        canvas,
        w: w,
        h: h,
        bellyPath: glassBodyPath,
      );
    }

    // 5. 3D Volumetric 8-Lobe Cream-Ivory Accordion Pleated Cloth Skirt
    _drawPleatedClothPouch(
      canvas,
      w: w,
      h: h,
      openProgress: easedOpen,
    );

    // Subtle white curtain-flutter motion arcs when pouch opens during pouring (`media_1794051150239.png`)
    if ((_externalStreamActive || (_fillProgress > 0.015 && _fillProgress < 0.88)) &&
        easedOpen > 0.15) {
      final flutterEnv = _externalStreamActive
          ? easedOpen.clamp(0.0, 1.0)
          : math
              .sin(((_fillProgress - 0.015) / 0.865).clamp(0.0, 1.0) * math.pi)
              .clamp(0.0, 1.0);
      _drawCurtainFlutterArcs(
        canvas,
        w: w,
        h: h,
        alpha: flutterEnv * 0.86,
        drawLeft: !_externalStreamActive || _externalStreamSideSign > 0,
        drawRight: !_externalStreamActive || _externalStreamSideSign < 0,
      );
    }

    // 6 & 7. When `_externalStreamActive == false`, draw Golden Rope & Target Tag directly;
    // when `_externalStreamActive == true`, `renderStreamForegroundOcclusion` draws them IN FRONT OF the stream!
    if (!_externalStreamActive) {
      _drawGoldenRopeAndKnot(canvas, w: w, h: h, openProgress: easedOpen);
      _drawTargetGoalTag(canvas, w: w, h: h, openProgress: easedOpen);
    }

    // 8. Subtle luminous belly glow when filling / full matching final block style
    final bellyGlowAlpha =
        (0.22 * easedFill + 0.28 * _glowIntensity).clamp(0.0, 0.52);
    if (bellyGlowAlpha > 0.01 && easedOpen > 0.2) {
      canvas.drawCircle(
        Offset(cx, h * 0.62),
        w * 0.30,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset(cx, h * 0.62),
            w * 0.30,
            [
              Color.lerp(_style.topBright, Colors.white, 0.40)!
                  .withValues(alpha: bellyGlowAlpha),
              _style.topBright.withValues(alpha: 0.0),
            ],
          ),
      );
    }
  }

  /// Mysterious frosted "?" watermark on the transparent glass belly when idle/empty
  void _drawMysteryQuestionMark(
    Canvas canvas, {
    required double w,
    required double h,
    required Path bellyPath,
  }) {
    if (_fillProgress >= 0.28) return;
    final qAlpha =
        ((0.28 - _fillProgress) / 0.28).clamp(0.0, 1.0) * _appearProgress;
    if (qAlpha <= 0.02) return;

    final cx = w * 0.5;
    final cy = h * 0.59;
    final fontSize = (h * 0.24).clamp(24.0, 72.0);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.44 * qAlpha),
          shadows: [
            Shadow(
              offset: const Offset(0, 1.8),
              blurRadius: 3.5,
              color: const Color(0x3D000000).withValues(alpha: 0.24 * qAlpha),
            ),
            Shadow(
              offset: Offset.zero,
              blurRadius: 6.0,
              color: const Color(0x66FFFFFF).withValues(alpha: 0.35 * qAlpha),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.clipPath(bellyPath);
    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width * 0.5, cy - textPainter.height * 0.5),
    );
    canvas.restore();
  }

  /// Draws the rich crystal-aqua glass neck (`y = 0.078..0.28 * h`), exposed rounded bottom glass bowl
  /// (`y = 0.78..0.962 * h`), and sapphire-aqua glass belly chamber behind the pleated cloth.
  void _drawCrystalAquaGlassBody(
    Canvas canvas, {
    required double w,
    required double h,
    required Path glassBodyPath,
    required double openProgress,
  }) {
    final cx = w * 0.5;

    canvas.save();
    canvas.clipPath(glassBodyPath);

    // A. Upper Concave Crystal-Aqua Glass Neck (`y = 0.075..0.30 * h`)
    final neckRect = Rect.fromLTWH(cx - w * 0.25, h * 0.070, w * 0.50, h * 0.235);
    canvas.drawRect(
      neckRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(neckRect.left, h * 0.18),
          Offset(neckRect.right, h * 0.18),
          const [
            Color(0xFF074C7B),
            Color(0xFF28B5DC),
            Color(0xFF1076AC),
            Color(0xFF0D6B9E),
            Color(0xFF33C2E8),
            Color(0xFF064672),
          ],
          const [0.0, 0.20, 0.44, 0.62, 0.82, 1.0],
        ),
    );

    // Soft cast shadow directly beneath the rolled glass mouth collar
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.128),
        width: w * 0.44,
        height: h * 0.048,
      ),
      Paint()..color = const Color(0x52042B4E),
    );

    // Crisp vertical specular reflection streaks on the left & right of the cyan glass neck
    final leftNeckSpec = Path()
      ..moveTo(cx - w * 0.155, h * 0.122)
      ..quadraticBezierTo(cx - w * 0.138, h * 0.195, cx - w * 0.158, h * 0.268)
      ..lineTo(cx - w * 0.126, h * 0.268)
      ..quadraticBezierTo(cx - w * 0.108, h * 0.195, cx - w * 0.124, h * 0.122)
      ..close();
    canvas.drawPath(
      leftNeckSpec,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - w * 0.14, h * 0.122),
          Offset(cx - w * 0.14, h * 0.268),
          [
            Colors.white.withValues(alpha: 0.78),
            const Color(0xFFA8F2FF).withValues(alpha: 0.52),
          ],
        ),
    );

    final rightNeckSpec = Path()
      ..moveTo(cx + w * 0.142, h * 0.125)
      ..quadraticBezierTo(cx + w * 0.128, h * 0.195, cx + w * 0.146, h * 0.266);
    canvas.drawPath(
      rightNeckSpec,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (w * 0.018).clamp(1.2, 2.8)
        ..color = const Color(0xFFB8F6FF).withValues(alpha: 0.65),
    );

    // B. Middle Sapphire-Aqua Glass Chamber (`y = 0.27..0.80 * h`, revealed when curtains part)
    if (openProgress > 0.005) {
      final bellyRect = Rect.fromLTWH(0, h * 0.26, w, h * 0.56);
      canvas.drawRect(
        bellyRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, h * 0.27),
            Offset(cx, h * 0.82),
            const [
              Color(0xD8083B72),
              Color(0xE00A518E),
              Color(0xE8086E98),
            ],
            const [0.0, 0.52, 1.0],
          ),
      );
    }

    // C. Exposed Rounded Crystal-Aqua Glass Bottom Bowl (`y = 0.77..0.965 * h`)
    final baseRect = Rect.fromLTWH(cx - w * 0.38, h * 0.76, w * 0.76, h * 0.21);
    canvas.drawRect(
      baseRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, h * 0.785),
          Offset(cx, h * 0.962),
          const [
            Color(0xFF04344E),
            Color(0xFF065E7C),
            Color(0xFF0B8EAE),
            Color(0xFF22D4EE),
            Color(0xFF9CF8FF),
          ],
          const [0.0, 0.28, 0.58, 0.84, 1.0],
        ),
    );

    // Horizontal cyan-glass internal refraction glow across the rounded bowl floor
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.905),
        width: w * 0.58,
        height: h * 0.075,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, h * 0.915),
          w * 0.30,
          const [
            Color(0xCCBBFBFF),
            Color(0x8824D8F2),
            Color(0x00087A9A),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    // Dark-teal cast shadow band directly underneath the ruffled cloth skirt hem
    if (openProgress < 0.99) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, h * 0.818),
          width: w * 0.72 * (1.0 - 0.35 * openProgress),
          height: h * 0.075,
        ),
        Paint()..color = const Color(0x88032B42),
      );
    }

    // Gleaming white + ice-cyan curved specular crescents along the bottom glass bowl rim
    final bottomCrescentPath = Path()
      ..moveTo(cx - w * 0.305, h * 0.862)
      ..cubicTo(
        cx - w * 0.285,
        h * 0.936,
        cx - w * 0.12,
        h * 0.950,
        cx - w * 0.03,
        h * 0.948,
      )
      ..moveTo(cx + w * 0.05, h * 0.948)
      ..cubicTo(
        cx + w * 0.15,
        h * 0.948,
        cx + w * 0.285,
        h * 0.932,
        cx + w * 0.305,
        h * 0.862,
      );
    canvas.drawPath(
      bottomCrescentPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (w * 0.022).clamp(1.6, 3.4)
        ..color = Colors.white.withValues(alpha: 0.90),
    );

    // Left glass bowl shoulder bright reflection dot
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx - w * 0.275, h * 0.875),
        width: w * 0.055,
        height: h * 0.032,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );

    canvas.restore();

    // Crisp crystal-aqua outer contour on the exposed neck (`y <= 0.28 * h`) and bottom bowl (`y >= 0.77 * h`)
    canvas.save();
    if (openProgress <= 0.01) {
      final clip = Path()
        ..addRect(Rect.fromLTWH(0, 0, w, h * 0.285))
        ..addRect(Rect.fromLTWH(0, h * 0.77, w, h * 0.23));
      canvas.clipPath(clip);
    }
    canvas.drawPath(
      glassBodyPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.018).clamp(1.3, 2.8)
        ..color = const Color(0xCC063E62),
    );
    canvas.drawPath(
      glassBodyPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.010).clamp(0.9, 1.8)
        ..color = const Color(0xCC9AF2FF),
    );
    canvas.restore();
  }

  /// Draws the thick 3D rolled crystal-aqua toroidal mouth rim at `(cx, 0.080 * h)`.
  void _drawCrystalAquaMouthCollar(
    Canvas canvas, {
    required double w,
    required double h,
    required bool frontLipOnly,
  }) {
    final cx = w * 0.5;
    final mouthCy = h * 0.080;
    final outerRimRect = Rect.fromCenter(
      center: Offset(cx, mouthCy),
      width: w * 0.505,
      height: h * 0.112,
    );
    final innerMouthRect = Rect.fromCenter(
      center: Offset(cx, mouthCy - h * 0.004),
      width: w * 0.392,
      height: h * 0.068,
    );

    if (frontLipOnly) {
      // Translucent glossy front glass lip drawn OVER the pouring water stream
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, mouthCy, w, h * 0.09));
      canvas.drawOval(
        outerRimRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, mouthCy),
            Offset(cx, outerRimRect.bottom),
            [
              const Color(0xFFE0FCFF).withValues(alpha: 0.52),
              const Color(0xFF42CBF0).withValues(alpha: 0.42),
              const Color(0xFF0A5C8F).withValues(alpha: 0.46),
            ],
            const [0.0, 0.52, 1.0],
          ),
      );
      canvas.drawOval(
        outerRimRect.deflate(w * 0.008),
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (w * 0.016).clamp(1.3, 2.6)
          ..color = Colors.white.withValues(alpha: 0.88),
      );
      canvas.drawOval(
        innerMouthRect,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (w * 0.012).clamp(1.0, 2.0)
          ..color = const Color(0xFFD6FAFF).withValues(alpha: 0.90),
      );
      canvas.restore();
      return;
    }

    // Full 3D rolled crystal-aqua glass collar
    canvas.drawOval(
      outerRimRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx - w * 0.12, outerRimRect.top),
          Offset(cx + w * 0.12, outerRimRect.bottom),
          const [
            Color(0xFFECFEFF),
            Color(0xFF8BE9FF),
            Color(0xFF22B0DA),
            Color(0xFF0B6294),
          ],
          const [0.0, 0.34, 0.72, 1.0],
        ),
    );

    // Outer dark-aqua glass contour + inner bright white specular torus ridge
    canvas.drawOval(
      outerRimRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.014).clamp(1.0, 2.2)
        ..color = const Color(0xB807466E),
    );
    canvas.drawOval(
      outerRimRect.deflate(w * 0.011),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.018).clamp(1.3, 2.8)
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    // Recessed deep ocean-aqua oval mouth opening
    canvas.save();
    canvas.clipPath(Path()..addOval(innerMouthRect));
    canvas.drawRect(
      innerMouthRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, innerMouthRect.top),
          Offset(cx, innerMouthRect.bottom),
          const [
            Color(0xFF084B84),
            Color(0xFF147FB8),
            Color(0xFF42C8EB),
          ],
          const [0.0, 0.56, 1.0],
        ),
    );
    // Subtle inner back-wall cyan highlight arc
    canvas.drawOval(
      innerMouthRect.translate(0, h * 0.014),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = h * 0.016
        ..color = const Color(0xFFB4F6FF).withValues(alpha: 0.52),
    );
    canvas.restore();

    // Crisp icy rim around the inner mouth opening
    canvas.drawOval(
      innerMouthRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.012).clamp(1.0, 2.1)
        ..color = const Color(0xFFE2FCFF).withValues(alpha: 0.94),
    );
  }

  /// Specular vertical glass reflections on the exposed center glass belly when curtains part.
  void _drawExposedBellyGlassHighlights(
    Canvas canvas, {
    required double w,
    required double h,
    required Path glassBodyPath,
    required double openProgress,
  }) {
    if (openProgress <= 0.05) return;
    final cx = w * 0.5;
    canvas.save();
    canvas.clipPath(glassBodyPath);

    final alpha = (openProgress * 0.52).clamp(0.0, 0.55);
    final leftBellyStreak = Path()
      ..moveTo(cx - w * 0.14, h * 0.31)
      ..quadraticBezierTo(cx - w * 0.19, h * 0.56, cx - w * 0.16, h * 0.80);
    canvas.drawPath(
      leftBellyStreak,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (w * 0.022).clamp(1.4, 3.2)
        ..color = Colors.white.withValues(alpha: alpha),
    );

    final rightBellyStreak = Path()
      ..moveTo(cx + w * 0.14, h * 0.32)
      ..quadraticBezierTo(cx + w * 0.18, h * 0.56, cx + w * 0.15, h * 0.79);
    canvas.drawPath(
      rightBellyStreak,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (w * 0.016).clamp(1.0, 2.4)
        ..color = const Color(0xFFB8F6FF).withValues(alpha: alpha * 0.85),
    );

    canvas.restore();
  }

  /// Subtle white motion arcs beside the fluttering skirt (`media_1794051150239.png`).
  void _drawCurtainFlutterArcs(
    Canvas canvas, {
    required double w,
    required double h,
    required double alpha,
    bool drawLeft = true,
    bool drawRight = true,
  }) {
    if (alpha <= 0.02) return;
    final pulse = 0.009 * math.sin(_animTime * 14.0) * w;
    final arcPaint = Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = (w * 0.0135).clamp(1.15, 2.4)
      ..color = Colors.white.withValues(alpha: alpha);
    final outerArcPaint = Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeWidth = (w * 0.0105).clamp(0.95, 1.9)
      ..color = Colors.white.withValues(alpha: alpha * 0.74);

    if (drawLeft) {
      final leftInner = Path()
        ..moveTo(w * 0.016 - pulse, h * 0.535)
        ..quadraticBezierTo(
          -w * 0.020 - pulse,
          h * 0.620,
          -w * 0.002 - pulse,
          h * 0.715,
        );
      final leftOuter = Path()
        ..moveTo(-w * 0.014 - pulse, h * 0.558)
        ..quadraticBezierTo(
          -w * 0.044 - pulse,
          h * 0.622,
          -w * 0.028 - pulse,
          h * 0.688,
        );
      canvas.drawPath(leftInner, arcPaint);
      canvas.drawPath(leftOuter, outerArcPaint);
    }

    if (drawRight) {
      final rightInner = Path()
        ..moveTo(w * 0.984 + pulse, h * 0.630)
        ..quadraticBezierTo(
          w * 1.020 + pulse,
          h * 0.702,
          w * 0.996 + pulse,
          h * 0.782,
        );
      final rightOuter = Path()
        ..moveTo(w * 1.014 + pulse, h * 0.650)
        ..quadraticBezierTo(
          w * 1.042 + pulse,
          h * 0.712,
          w * 1.024 + pulse,
          h * 0.768,
        );
      canvas.drawPath(rightInner, arcPaint);
      canvas.drawPath(rightOuter, outerArcPaint);
    }
  }

  /// 3D Volumetric 8-Lobe Plump Bulb Cream-Ivory Accordion Pleated Cloth Pouch (`bao vải xếp ly`):
  /// - At rest (`media_1794051081001.png`): puffs outward into a plump, round garlic-bulb shoulder
  ///   under the golden rope (`shoulderOuter = 0.395 * w`, `bellyOuter = 0.456 * w`) and tucks
  ///   gently INWARD at the scalloped hem (`hemOuter = 0.398 * w`)!
  /// - When pouring (`media_1794051150239.png`): sweeps apart like real 3D accordion curtains
  ///   flaring to `0.505 * w` so all 4 right pleats fan out cleanly beneath the `4096` tag!
  void _drawPleatedClothPouch(
    Canvas canvas, {
    required double w,
    required double h,
    required double openProgress,
  }) {
    final cx = w * 0.5;
    const tBounds = <double>[0.0, 0.16, 0.39, 0.68, 1.0];

    void drawCurtainSide(double sideSign) {
      // `sideSign = -1.0` for left curtain, `+1.0` for right curtain
      final neckOuter = (0.222 + 0.008 * openProgress) * w;
      final neckInner = (0.088 * openProgress) * w;

      // Upper-shoulder cubic control: puffs generously outward right below the golden rope!
      final shoulderOuter = (0.395 + 0.025 * openProgress) * w;
      final shoulderInner = (0.145 * openProgress) * w;
      final shoulderY = h * (0.338 + 0.010 * openProgress);

      // Lower-belly cubic control: widest plump roundness at rest, flaring gracefully when open!
      final bellyOuter = (0.456 + 0.052 * openProgress) * w;
      final bellyInner = (0.215 * openProgress) * w;
      final bellyY = h * (0.585 - 0.015 * openProgress);

      // Scalloped hem: tucks INWARD (`0.398 * w < bellyOuter`) when closed (`media_1794051081001.png`),
      // and flares OUTWARD (`0.498 * w`) when parted open (`media_1794051150239.png`)!
      final hemOuter = ui.lerpDouble(0.398, 0.498, openProgress)! * w;
      final hemInner = (0.232 * openProgress) * w;

      Offset neckPt(int j) {
        final t = tBounds[j];
        final xOff = ui.lerpDouble(neckOuter, neckInner, t)!;
        // Follow the curved 3D smile of the golden rope collar (`0.252 * h` at sides -> `0.282 * h` at center)
        final normX = (xOff / math.max(1.0, neckOuter)).clamp(0.0, 1.0);
        final y = ui.lerpDouble(h * 0.282, h * 0.252, normX * normX)!;
        return Offset(cx + sideSign * xOff, y);
      }

      Offset shoulderPt(int j) => Offset(
            cx +
                sideSign *
                    ui.lerpDouble(shoulderOuter, shoulderInner, tBounds[j])!,
            shoulderY,
          );

      Offset bellyPt(int j) => Offset(
            cx + sideSign * ui.lerpDouble(bellyOuter, bellyInner, tBounds[j])!,
            bellyY,
          );

      Offset hemPt(int j) {
        final t = tBounds[j];
        final archT = math.pow(t, 0.78).toDouble();
        final closedHemY = ui.lerpDouble(h * 0.735, h * 0.818, archT)!;
        final openHemY = ui.lerpDouble(h * 0.728, h * 0.798, archT)!;
        return Offset(
          cx + sideSign * ui.lerpDouble(hemOuter, hemInner, t)!,
          ui.lerpDouble(closedHemY, openHemY, openProgress)!,
        );
      }

      // 1. Dark Aqua-Sage 3D Undulating Cloth Underside Hem (`media_1794051081001.png` & `media_1794051150239.png`)
      final undersidePath = Path();
      final firstHem = hemPt(0);
      undersidePath.moveTo(firstHem.dx, firstHem.dy);
      for (int k = 0; k < 4; k++) {
        final p0 = hemPt(k);
        final p1 = hemPt(k + 1);
        final midX = (p0.dx + p1.dx) * 0.5;
        final midHemY = (p0.dy + p1.dy) * 0.5;
        final bulge = h * (0.020 + 0.004 * k);
        undersidePath.quadraticBezierTo(midX, midHemY + bulge, p1.dx, p1.dy);
      }
      for (int k = 4; k >= 0; k--) {
        final p = hemPt(k);
        final tuckX = p.dx - sideSign * w * (k == 0 ? 0.032 : 0.015);
        final tuckY = p.dy + h * (k == 0 ? 0.026 : 0.036);
        undersidePath.lineTo(tuckX, tuckY);
      }
      undersidePath.close();

      canvas.drawPath(
        undersidePath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx + sideSign * w * 0.42, h * 0.74),
            Offset(cx + sideSign * w * 0.14, h * 0.845),
            const [
              Color(0xFF1E8494),
              Color(0xFF1A6575),
              Color(0xFF0E4759),
            ],
            const [0.0, 0.54, 1.0],
          ),
      );

      // 2. Draw the 4 Plump Volumetric 3D Milk-Cream Accordion Lobes (`k = 0..3`)
      for (int k = 0; k < 4; k++) {
        final n0 = neckPt(k);
        final n1 = neckPt(k + 1);
        final s0 = shoulderPt(k);
        final s1 = shoulderPt(k + 1);
        final b0 = bellyPt(k);
        final b1 = bellyPt(k + 1);
        final h0 = hemPt(k);
        final h1 = hemPt(k + 1);

        final scallopBulge = h * (0.018 + 0.004 * k);
        final scallopCtrl = Offset(
          (h0.dx + h1.dx) * 0.5,
          (h0.dy + h1.dy) * 0.5 + scallopBulge,
        );

        final lobePath = Path()
          ..moveTo(n0.dx, n0.dy)
          ..lineTo(n1.dx, n1.dy)
          ..cubicTo(s1.dx, s1.dy, b1.dx, b1.dy, h1.dx, h1.dy)
          ..quadraticBezierTo(scallopCtrl.dx, scallopCtrl.dy, h0.dx, h0.dy)
          ..cubicTo(b0.dx, b0.dy, s0.dx, s0.dy, n0.dx, n0.dy)
          ..close();

        // Warm, soft, luminous milk-cream cylindrical shading (`media_1794051081001.png`)
        final leftBellyX = math.min(b0.dx, b1.dx);
        final rightBellyX = math.max(b0.dx, b1.dx);
        final outerDim = (k == 0) ? 0.06 : (k == 1 ? 0.02 : 0.0);

        final cLeftCrease = Color.lerp(
          const Color(0xFFD6CEBE),
          const Color(0xFFBEB5A3),
          outerDim + (sideSign < 0 && k == 0 ? 0.08 : 0.0),
        )!;
        final cSunlitCrown = Color.lerp(
          const Color(0xFFFFFEFA),
          const Color(0xFFFBF6EC),
          outerDim,
        )!;
        final cMilkCream = Color.lerp(
          const Color(0xFFF9F3E7),
          const Color(0xFFEDE5D5),
          outerDim,
        )!;
        final cWarmSlope = Color.lerp(
          const Color(0xFFE9E0CE),
          const Color(0xFFD9CFBC),
          outerDim,
        )!;
        final cRightCrease = Color.lerp(
          const Color(0xFFCAC0AD),
          const Color(0xFFB3A995),
          outerDim + (sideSign > 0 && k == 0 ? 0.12 : 0.0),
        )!;

        canvas.drawPath(
          lobePath,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(leftBellyX, bellyY),
              Offset(rightBellyX, bellyY),
              [
                cLeftCrease,
                cSunlitCrown,
                cMilkCream,
                cWarmSlope,
                cRightCrease,
              ],
              const [0.0, 0.28, 0.56, 0.84, 1.0],
            ),
        );

        // Bright top-shoulder sky highlight on the plump upper bulge + soft warm hem bounce
        canvas.drawPath(
          lobePath,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset((n0.dx + n1.dx) * 0.5, (n0.dy + n1.dy) * 0.5),
              Offset((h0.dx + h1.dx) * 0.5, (h0.dy + h1.dy) * 0.5),
              [
                const Color(0xFF9C896C).withValues(alpha: 0.12),
                Colors.white.withValues(alpha: 0.24),
                Colors.white.withValues(alpha: 0.0),
                const Color(0xFFBEB4A2).withValues(alpha: 0.12),
              ],
              const [0.0, 0.18, 0.78, 1.0],
            ),
        );

        // Crisp sunlit cream rim along each lobe's plump rounded bottom scallop
        final hemRimPath = Path()
          ..moveTo(h0.dx, h0.dy)
          ..quadraticBezierTo(scallopCtrl.dx, scallopCtrl.dy, h1.dx, h1.dy);
        canvas.drawPath(
          hemRimPath,
          Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeCap = ui.StrokeCap.round
            ..strokeWidth = (w * 0.012).clamp(1.0, 2.0)
            ..color = const Color(0xFFFFFEFA).withValues(alpha: 0.92),
        );

        // Soft warm valley crease separating adjacent pleats
        if (k > 0) {
          final valleyPath = Path()
            ..moveTo(n0.dx, n0.dy)
            ..cubicTo(s0.dx, s0.dy, b0.dx, b0.dy, h0.dx, h0.dy);
          canvas.drawPath(
            valleyPath,
            Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = (w * 0.0075).clamp(0.65, 1.4)
              ..color = const Color(0xFFB5AB98).withValues(alpha: 0.42),
          );
        }
      }

      // Inner curtain edge highlight when parted open (`media_1794051150239.png`)
      if (openProgress > 0.02) {
        final ni = neckPt(4);
        final si = shoulderPt(4);
        final bi = bellyPt(4);
        final hi = hemPt(4);
        final innerEdge = Path()
          ..moveTo(ni.dx, ni.dy)
          ..cubicTo(si.dx, si.dy, bi.dx, bi.dy, hi.dx, hi.dy);
        canvas.drawPath(
          innerEdge,
          Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeCap = ui.StrokeCap.round
            ..strokeWidth = (w * 0.013).clamp(1.0, 2.2)
            ..color =
                const Color(0xFFF7F0E2).withValues(alpha: 0.85 * openProgress),
        );
      }
    }

    drawCurtainSide(-1.0);
    drawCurtainSide(1.0);

    // Gentle center valley crease when closed (`openProgress < 0.05`)
    if (openProgress < 0.05) {
      final seamAlpha = ((0.05 - openProgress) / 0.05) * 0.34;
      canvas.drawLine(
        Offset(cx, h * 0.282),
        Offset(cx, h * 0.818),
        Paint()
          ..strokeWidth = (w * 0.0075).clamp(0.65, 1.35)
          ..color = const Color(0xFFB5AB98).withValues(alpha: seamAlpha),
      );
    }
  }

  /// Continuous 3D Twisted Golden Rope Collar (`dây thừng vàng xoắn`) cinching the neck at `y = 0.244..0.284 * h`.
  /// Uses a continuous 3D gold rope tube + 22 overlapping diagonal cable twists (never bead-necklace circles!).
  void _drawGoldenRopeAndKnot(
    Canvas canvas, {
    required double w,
    required double h,
    required double openProgress,
  }) {
    final cx = w * 0.5;
    final leftX = cx - w * 0.232;
    final rightX = cx + w * 0.232;
    final sideY = h * 0.242;
    final midCtrlY = h * 0.324; // Apex sits at `0.5 * 0.242 + 0.5 * 0.324 = 0.283 * h`!
    final ropeThick = (h * 0.036).clamp(3.6, 7.6);

    Offset ropeCurve(double t) {
      final om = 1.0 - t;
      return Offset(
        om * om * leftX + 2.0 * om * t * cx + t * t * rightX,
        om * om * sideY + 2.0 * om * t * midCtrlY + t * t * sideY,
      );
    }

    final centerArc = Path()
      ..moveTo(leftX, sideY)
      ..quadraticBezierTo(cx, midCtrlY, rightX, sideY);

    // 1. Soft warm cast shadow onto the plump cream pleats directly under the golden rope
    canvas.drawPath(
      centerArc.shift(Offset(0, h * 0.014)),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = ropeThick * 1.15
        ..color = const Color(0x424A2A05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
    );

    // 2. Continuous 3D dark-bronze outer rim + rich golden-amber continuous rope core
    canvas.drawPath(
      centerArc,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = ropeThick * 1.06
        ..color = const Color(0xFF9C5404),
    );
    canvas.drawPath(
      centerArc,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = ropeThick * 0.88
        ..shader = ui.Gradient.linear(
          Offset(cx, sideY - ropeThick * 0.5),
          Offset(cx, midCtrlY + ropeThick * 0.5),
          const [
            Color(0xFFFFF4B2),
            Color(0xFFF9C838),
            Color(0xFFD17D0A),
          ],
          const [0.0, 0.48, 1.0],
        ),
    );

    // 3. 22 Diagonal 3D Twisted Cable Strands blended seamlessly along the continuous gold rope!
    const int twistCount = 22;
    final strandLen = ropeThick * 1.25;
    final strandThick = ropeThick * 0.54;

    for (int i = 0; i < twistCount; i++) {
      final t = (i + 0.5) / twistCount;
      final pt = ropeCurve(t);
      final dtTangent = Offset(
        2.0 * (1.0 - t) * (cx - leftX) + 2.0 * t * (rightX - cx),
        2.0 * (1.0 - t) * (midCtrlY - sideY) + 2.0 * t * (sideY - midCtrlY),
      );
      final tangentAngle = math.atan2(dtTangent.dy, dtTangent.dx);
      final twistAngle = tangentAngle - 0.52;

      canvas.save();
      canvas.translate(pt.dx, pt.dy);
      canvas.rotate(twistAngle);

      final strandRRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: strandLen,
          height: strandThick,
        ),
        Radius.circular(strandThick * 0.5),
      );
      canvas.drawRRect(
        strandRRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, -strandThick * 0.5),
            Offset(0, strandThick * 0.5),
            const [
              Color(0xFFFFF9CC),
              Color(0xFFFBD046),
              Color(0xFFBE6B06),
            ],
            const [0.0, 0.46, 1.0],
          ),
      );
      canvas.restore();
    }
  }

  /// Warm Butter-Cream Parchment Target Tag (`$targetNumber`) + Plump 3D Golden Cord Loop:
  /// - Idle (`media_1794051081001.png`): centered at `(cx, 0.510 * h)` with vertical 3D gold loop to neck rope.
  /// - Pouring/Full (`media_1794051150239.png`): swings onto the flared right curtain `(0.685 * w, 0.505 * h)`
  ///   tilted `-0.26 rad` (`-15°` counter-clockwise) so the cream pleats frame the tag cleanly!
  void _drawTargetGoalTag(
    Canvas canvas, {
    required double w,
    required double h,
    required double openProgress,
  }) {
    final cx = w * 0.5;
    final clampedOpen = openProgress.clamp(0.0, 1.0);
    final swingT = Curves.easeOutBack.transform(clampedOpen);
    final idleSway = math.sin(_animTime * 1.8) * 0.018 * (1.0 - clampedOpen);

    final tagCenterX = ui.lerpDouble(cx, w * 0.772, swingT)!;
    final tagCenterY = ui.lerpDouble(h * 0.510, h * 0.472, swingT)!;
    final tagRot = ui.lerpDouble(0.0, -0.27, swingT)! + idleSway;
    final perspScale = ui.lerpDouble(1.0, 0.88, clampedOpen)!;

    final tagW = w * 0.422 * perspScale;
    final tagH = h * 0.274 * perspScale;
    final tagR = Radius.circular(w * 0.044 * perspScale);

    // Grommet local offset relative to `tagCenter` is `(0, -tagH * 0.325)`
    final eyeletLocalOffsetY = -tagH * 0.325;
    final eyeletWorld = Offset(
      tagCenterX - math.sin(tagRot) * eyeletLocalOffsetY,
      tagCenterY + math.cos(tagRot) * eyeletLocalOffsetY,
    );

    // 1. Draw Tag Card (Shadow + 3D Lower Bevel + Butter-Cream Face + Grommet + Target Text)
    canvas.save();
    canvas.translate(tagCenterX, tagCenterY);
    canvas.rotate(tagRot);
    canvas.translate(-tagCenterX, -tagCenterY);

    final tagRect = Rect.fromCenter(
      center: Offset(tagCenterX, tagCenterY),
      width: tagW,
      height: tagH,
    );
    final tagRRect = RRect.fromRectAndRadius(tagRect, tagR);

    // Warm soft cast shadow onto the cream pleats behind the tag
    canvas.drawRRect(
      tagRRect.shift(Offset(0, h * 0.020)),
      Paint()
        ..color = const Color(0x422B1904)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.022),
    );

    // 3D warm golden-tan lower card thickness lip (`media_1794051081001.png`)
    canvas.drawRRect(
      tagRRect.shift(Offset(0, h * 0.013)),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(tagRect.left, tagRect.bottom),
          Offset(tagRect.right, tagRect.bottom),
          const [
            Color(0xFFC28E3E),
            Color(0xFFD6A454),
            Color(0xFFB88334),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );

    // Warm butter-cream parchment face
    canvas.drawRRect(
      tagRRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(tagCenterX, tagRect.top),
          Offset(tagCenterX, tagRect.bottom),
          const [
            Color(0xFFFFF9E6),
            Color(0xFFFEECC4),
            Color(0xFFF5D38E),
          ],
          const [0.0, 0.52, 1.0],
        ),
    );

    // Crisp bright cream top-inner highlight & warm subtle border
    canvas.drawRRect(
      tagRRect.deflate(0.8),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
          Offset(tagCenterX, tagRect.top),
          Offset(tagCenterX, tagRect.bottom),
          [
            const Color(0xFFFFFEF8).withValues(alpha: 0.92),
            const Color(0xFFD8AB5E).withValues(alpha: 0.55),
          ],
        ),
    );

    // 3D Golden Eyelet / Grommet Ring + Dark Hole near top-center of tag
    final eyeletCenter = Offset(tagCenterX, tagCenterY + eyeletLocalOffsetY);
    final eyeletOuterR = (w * 0.030).clamp(3.2, 6.6);
    final eyeletInnerR = eyeletOuterR * 0.54;

    canvas.drawCircle(
      eyeletCenter.translate(0, h * 0.005),
      eyeletOuterR,
      Paint()..color = const Color(0x555E3806),
    );
    canvas.drawCircle(
      eyeletCenter,
      eyeletOuterR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(
            eyeletCenter.dx - eyeletOuterR * 0.25,
            eyeletCenter.dy - eyeletOuterR * 0.25,
          ),
          eyeletOuterR * 1.2,
          const [
            Color(0xFFFFF5B8),
            Color(0xFFF7C438),
            Color(0xFFBC6E08),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );
    canvas.drawCircle(
      eyeletCenter,
      eyeletInnerR,
      Paint()..color = const Color(0xFF4A2A08),
    );

    // Bold Rounded Deep-Navy Target Goal Number (`4096`, `2048`, etc.) auto-fitted cleanly inside tag!
    final textStr = '$targetNumber';
    final baseFontSize = (tagH * 0.49).clamp(14.0, 42.0);
    final textPainter = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontSize,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0B457C),
          letterSpacing: -0.4,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final maxTextW = tagW * 0.80;
    final fitScale =
        textPainter.width > maxTextW ? (maxTextW / textPainter.width) : 1.0;

    canvas.save();
    final textCenterY = tagCenterY + tagH * 0.085;
    canvas.translate(tagCenterX, textCenterY);
    canvas.scale(fitScale, fitScale);
    final embossPainter = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.45),
          letterSpacing: -0.4,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    embossPainter.paint(
      canvas,
      Offset(-textPainter.width * 0.5, -textPainter.height * 0.5 + 1.0),
    );
    textPainter.paint(
      canvas,
      Offset(-textPainter.width * 0.5, -textPainter.height * 0.5),
    );
    canvas.restore();

    canvas.restore();

    // 2. Plump Double-Strand 3D Golden Cord Loop connecting from the Neck Rope RIGHT INTO the Grommet Hole!
    final ropeAttach = Offset(
      ui.lerpDouble(cx, cx + w * 0.108, swingT)!,
      ui.lerpDouble(h * 0.283, h * 0.268, swingT)!,
    );
    final cordCtrl = Offset(
      (ropeAttach.dx + eyeletWorld.dx) * 0.5 + w * 0.018 * swingT,
      (ropeAttach.dy + eyeletWorld.dy) * 0.5 + h * 0.008 * swingT,
    );
    final cordPath = Path()
      ..moveTo(ropeAttach.dx, ropeAttach.dy)
      ..quadraticBezierTo(
        cordCtrl.dx,
        cordCtrl.dy,
        eyeletWorld.dx,
        eyeletWorld.dy,
      );

    final cordW = (w * 0.024).clamp(2.2, 4.6);
    canvas.drawPath(
      cordPath.shift(Offset(w * 0.007, h * 0.008)),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = cordW * 1.15
        ..color = const Color(0x453B2104),
    );
    canvas.drawPath(
      cordPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = cordW
        ..color = const Color(0xFFC8780A),
    );
    canvas.drawPath(
      cordPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = cordW * 0.58
        ..color = const Color(0xFFFFE784),
    );
  }

  /// Concentric cyan-white surface ripple rings on the liquid surface inside the jar
  /// (visible both while pouring in `media_1794051150239.png` and when full in Panel 4!).
  void _drawWaterSurfaceRipples(
    Canvas canvas, {
    required double w,
    required double h,
    required double surfaceY,
    required double alphaScale,
  }) {
    if (alphaScale <= 0.02) return;
    final ringCenter = Offset(w * 0.5, surfaceY + h * 0.006);

    for (int i = 0; i < 3; i++) {
      final ringPhase = (_surfaceWavePhase * 0.26 + i * 0.333) % 1.0;
      final ringRx = w * (0.055 + 0.22 * ringPhase);
      final ringRy = ringRx * 0.27;
      final ringAlpha = (1.0 - ringPhase) * alphaScale * 0.86;
      if (ringAlpha <= 0.02) continue;
      final ringColor = i == 0
          ? Colors.white
          : const Color(0xFFE4FFFF);
      canvas.drawOval(
        Rect.fromCenter(
          center: ringCenter,
          width: ringRx * 2,
          height: ringRy * 2,
        ),
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (1.85 * (1.0 - ringPhase * 0.40)).clamp(0.85, 2.4)
          ..color = ringColor.withValues(alpha: ringAlpha),
      );
    }
  }

  /// Foreground splash collar + cute upward crown-splash droplets where the vertical stream
  /// plunges into `surfaceY` inside the jar (`media_1794051150239.png`).
  void _drawSurfaceImpactCrownDroplets(
    Canvas canvas, {
    required double w,
    required double h,
    required double surfaceY,
    required double alpha,
  }) {
    if (alpha <= 0.02) return;
    final cx = w * 0.5;
    final impactY = surfaceY + h * 0.006;

    // 1. Bright foamy cyan-white splash collar hugging the stream entry
    final collarRect = Rect.fromCenter(
      center: Offset(cx, impactY),
      width: w * 0.21,
      height: h * 0.036,
    );
    canvas.drawOval(
      collarRect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, impactY),
          w * 0.11,
          [
            Colors.white.withValues(alpha: 0.92 * alpha),
            Color.lerp(_style.topBright, Colors.white, 0.45)!
                .withValues(alpha: 0.72 * alpha),
            _style.topBright.withValues(alpha: 0.0),
          ],
          const [0.0, 0.58, 1.0],
        ),
    );

    final crownArc = Path()
      ..moveTo(cx - w * 0.095, impactY - h * 0.004)
      ..quadraticBezierTo(
        cx,
        impactY + h * 0.020,
        cx + w * 0.095,
        impactY - h * 0.004,
      );
    canvas.drawPath(
      crownArc,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (w * 0.015).clamp(1.2, 2.6)
        ..color = Colors.white.withValues(alpha: 0.92 * alpha),
    );

    // 2. Cute glossy crown droplets hopping outward & upward inside the belly
    final lightWater = Color.lerp(_style.topBright, Colors.white, 0.50)!;
    final midWater = _style.topBright;
    final deepWater = _style.bottomLip;

    for (int i = 0; i < 4; i++) {
      final isLeft = i < 2;
      final side = isLeft ? -1.0 : 1.0;
      final slot = i % 2;
      final cycle = (_surfaceWavePhase * 0.42 + i * 0.27) % 1.0;
      final arcLift = math.sin(cycle * math.pi);
      final spread = w * (0.068 + 0.058 * slot + 0.055 * cycle);
      final liftY = h * (0.022 + 0.036 * (1 - slot * 0.25)) * arcLift;

      final head = Offset(cx + side * spread, impactY - liftY);
      final tail = Offset(
        cx + side * (spread * 0.62),
        impactY - liftY * 0.35 + h * 0.004,
      );
      final dropAlpha = (math.sin(cycle * math.pi) * alpha * 0.95).clamp(0.0, 1.0);
      _drawGlossyTeardropSplash(
        canvas,
        tailPt: tail,
        headCenter: head,
        headRadius: (w * (slot == 0 ? 0.018 : 0.013)).clamp(1.3, 3.6),
        lightColor: lightWater,
        midColor: midWater,
        deepColor: deepWater,
        alpha: dropAlpha,
      );
    }
  }

  /// Glossy 3D teardrop splash droplet above/inside the bottle during pouring.
  void _drawGlossyTeardropSplash(
    Canvas canvas, {
    required Offset tailPt,
    required Offset headCenter,
    required double headRadius,
    required Color lightColor,
    required Color midColor,
    required Color deepColor,
    required double alpha,
  }) {
    if (alpha <= 0.02 || headRadius <= 0.5) return;
    final dx = headCenter.dx - tailPt.dx;
    final dy = headCenter.dy - tailPt.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 1.0) return;

    final ux = dx / len;
    final uy = dy / len;
    final nx = -uy;
    final ny = ux;

    final tip = Offset(
      headCenter.dx + ux * headRadius,
      headCenter.dy + uy * headRadius,
    );
    final sideLeft = Offset(
      headCenter.dx + nx * headRadius,
      headCenter.dy + ny * headRadius,
    );
    final sideRight = Offset(
      headCenter.dx - nx * headRadius,
      headCenter.dy - ny * headRadius,
    );

    final dropPath = Path()
      ..moveTo(tailPt.dx, tailPt.dy)
      ..quadraticBezierTo(
        tailPt.dx + ux * len * 0.52 + nx * headRadius * 0.55,
        tailPt.dy + uy * len * 0.52 + ny * headRadius * 0.55,
        sideLeft.dx,
        sideLeft.dy,
      )
      ..arcToPoint(
        tip,
        radius: Radius.circular(headRadius),
        clockwise: true,
      )
      ..arcToPoint(
        sideRight,
        radius: Radius.circular(headRadius),
        clockwise: true,
      )
      ..quadraticBezierTo(
        tailPt.dx + ux * len * 0.52 - nx * headRadius * 0.55,
        tailPt.dy + uy * len * 0.52 - ny * headRadius * 0.55,
        tailPt.dx,
        tailPt.dy,
      )
      ..close();

    canvas.drawPath(
      dropPath,
      Paint()
        ..shader = ui.Gradient.linear(
          tip,
          tailPt,
          [
            lightColor.withValues(alpha: alpha),
            midColor.withValues(alpha: alpha),
            deepColor.withValues(alpha: 0.90 * alpha),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          headCenter.dx + ux * headRadius * 0.25,
          headCenter.dy - headRadius * 0.28,
        ),
        width: headRadius * 1.05,
        height: headRadius * 0.55,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.85 * alpha),
    );
  }

  /// Rising liquid pool, 3D elliptical meniscus disc, underwater plunge caustic glow,
  /// concentric white ripples, rising bubbles, and optional standalone vertical stream
  /// (`media_1794051150239.png` & `media_1794007349252.png` Panels 3-4).
  void _drawBottleLiquidColumn(
    Canvas canvas, {
    required double w,
    required double h,
    required Path bellyPath,
    required double fillFraction,
    required bool isPouring,
    bool includeVerticalStream = true,
  }) {
    final clampedFill = fillFraction.clamp(0.0, 1.0);
    if (clampedFill <= 0.005) return;

    final cx = w * 0.5;
    final baseY = h * 0.945;
    final surfaceY = _localSurfaceY(h);

    // Smoothly blend slosh amplitude down as the jar finishes filling (zero step jump!)
    final pourBlend = isPouring
        ? ((0.99 - clampedFill) / 0.14).clamp(0.0, 1.0)
        : 0.0;
    final activeAmp = h * (0.015 + 0.006 * math.sin(_surfaceWavePhase * 1.35).abs());
    final calmAmp = h * 0.0065;
    final sloshAmp = ui.lerpDouble(calmAmp, activeAmp, pourBlend)!;
    final phase = _surfaceWavePhase;

    // Dynamic liquid pool colors matching final block's exact color palette
    final lightWater = Color.lerp(_style.topBright, Colors.white, 0.42)!;
    final meniscusColor = Color.lerp(_style.rimHighlight, Colors.white, 0.55)!;
    final midWater = _style.topBright;
    final bodyWater = _style.topMid;
    final deepWater = _style.bottomLip;

    // --- PART A: Rising Liquid Pool + Underwater Plunge Caustic + 3D Meniscus + Bubbles ---
    canvas.save();
    canvas.clipPath(bellyPath);

    final waveLeftY = surfaceY + math.sin(phase) * sloshAmp;
    final waveCtrl1Y = surfaceY + math.cos(phase + 0.8) * sloshAmp * 0.9;
    final waveCtrl2Y = surfaceY - math.sin(phase + 0.8) * sloshAmp * 0.9;
    final waveRightY = surfaceY - math.sin(phase) * sloshAmp;

    final waterPath = Path()
      ..moveTo(0, waveLeftY)
      ..cubicTo(w * 0.34, waveCtrl1Y, w * 0.66, waveCtrl2Y, w, waveRightY)
      ..lineTo(w, baseY + 8)
      ..lineTo(0, baseY + 8)
      ..close();

    canvas.drawPath(
      waterPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, surfaceY),
          Offset(cx, baseY),
          [
            lightWater.withValues(alpha: 0.96),
            midWater.withValues(alpha: 0.94),
            bodyWater.withValues(alpha: 0.95),
            deepWater.withValues(alpha: 0.96),
            lightWater.withValues(alpha: 0.96),
          ],
          const [0.0, 0.20, 0.56, 0.82, 1.0],
        ),
    );

    // Underwater electric-cyan plunge caustic column right beneath `(cx, surfaceY)` while pouring!
    if (pourBlend > 0.02) {
      final plungeDepth = math.min(baseY - surfaceY, h * 0.28);
      if (plungeDepth > 4.0) {
        final plungeRect = Rect.fromCenter(
          center: Offset(cx, surfaceY + plungeDepth * 0.42),
          width: w * 0.36,
          height: plungeDepth * 1.15,
        );
        canvas.drawOval(
          plungeRect,
          Paint()
            ..blendMode = ui.BlendMode.plus
            ..shader = ui.Gradient.radial(
              Offset(cx, surfaceY + plungeDepth * 0.20),
              w * 0.22,
              [
                Colors.white.withValues(alpha: 0.56 * pourBlend),
                lightWater.withValues(alpha: 0.44 * pourBlend),
                midWater.withValues(alpha: 0.0),
              ],
              const [0.0, 0.52, 1.0],
            ),
        );
      }
    }

    // Bright internal floor bounce glow at the bottom of the water pool (`media_1794051150239.png`)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h * 0.885),
        width: w * 0.60,
        height: h * 0.105,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, h * 0.895),
          w * 0.31,
          [
            Colors.white.withValues(alpha: 0.74),
            lightWater.withValues(alpha: 0.56),
            midWater.withValues(alpha: 0.0),
          ],
          const [0.0, 0.52, 1.0],
        ),
    );

    // 3D Elliptical Meniscus Disc on top of the water pool (`media_1794051150239.png`)
    final meniscusRect = Rect.fromCenter(
      center: Offset(cx, surfaceY + h * 0.006),
      width: w * 0.68,
      height: h * 0.082,
    );
    canvas.drawOval(
      meniscusRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, meniscusRect.top),
          Offset(cx, meniscusRect.bottom),
          [
            meniscusColor.withValues(alpha: 0.92),
            lightWater.withValues(alpha: 0.95),
            Colors.white.withValues(alpha: 0.84),
          ],
          const [0.0, 0.58, 1.0],
        ),
    );
    canvas.drawOval(
      meniscusRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.012).clamp(1.0, 2.2)
        ..color = Colors.white.withValues(alpha: 0.88),
    );

    // Ambient surface ripples (when `_externalStreamActive`, foreground occlusion draws crisp impact ripples over the stream tip!)
    final baseRippleScale = _externalStreamActive ? 0.36 : 1.0;
    _drawWaterSurfaceRipples(
      canvas,
      w: w,
      h: h,
      surfaceY: surfaceY,
      alphaScale: (clampedFill * 3.5).clamp(0.0, 1.0) * baseRippleScale,
    );

    // Cute glossy rising bubbles inside the water pool
    final bubbleCount = isPouring ? 12 : 8;
    for (int i = 0; i < bubbleCount; i++) {
      final seed = ((i * 137.5) % 100.0) / 100.0;
      final bx = cx +
          (seed - 0.5) * w * 0.48 +
          math.sin(_animTime * 2.4 + i * 1.4) * w * 0.018;
      final speed = 0.20 + 0.07 * (i % 3);
      final bubbleT = (_animTime * speed + i * (1.0 / bubbleCount)) % 1.0;
      final by = ui.lerpDouble(baseY - h * 0.05, surfaceY + h * 0.035, bubbleT)!;
      if (by < surfaceY + h * 0.025 || by > baseY - h * 0.03) continue;
      final r = 1.8 + (i % 3) * 0.9;
      canvas.drawCircle(
        Offset(bx, by),
        r,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = const Color(0xFFE8FFFF).withValues(alpha: 0.62),
      );
      canvas.drawCircle(
        Offset(bx - r * 0.30, by - r * 0.30),
        r * 0.36,
        Paint()..color = Colors.white.withValues(alpha: 0.90),
      );
    }

    canvas.restore();

    // --- PART B: Standalone Vertical Stream (used when `_externalStreamActive == false`, e.g. isolated unit tests) ---
    if (includeVerticalStream && isPouring && fillFraction < 0.97) {
      final streamFade = ((0.97 - fillFraction) / 0.09).clamp(0.0, 1.0);
      final tailDropT = ((fillFraction - 0.86) / 0.11).clamp(0.0, 1.0);
      final streamTopY = ui.lerpDouble(h * 0.080, surfaceY, tailDropT)!;
      final streamBotY = surfaceY + h * 0.012;

      if (streamBotY > streamTopY + 3.0) {
        canvas.save();
        canvas.clipPath(bellyPath);

        final breathe = 1.0 + 0.030 * math.sin(_surfaceWavePhase * 2.0);
        final topHalfW = w * 0.058 * breathe;
        final waistHalfW = w * 0.050 * breathe;
        final funnelHalfW = w * (0.108 + 0.012 * math.cos(_surfaceWavePhase * 1.8));
        final funnelStartY = ui.lerpDouble(streamTopY, streamBotY, 0.82)!;

        final streamFunnelPath = Path()
          ..moveTo(cx - topHalfW, streamTopY)
          ..lineTo(cx - waistHalfW, funnelStartY)
          ..quadraticBezierTo(
            cx - waistHalfW * 1.25,
            streamBotY - h * 0.006,
            cx - funnelHalfW,
            streamBotY,
          )
          ..quadraticBezierTo(
            cx,
            streamBotY + h * 0.024,
            cx + funnelHalfW,
            streamBotY,
          )
          ..quadraticBezierTo(
            cx + waistHalfW * 1.25,
            streamBotY - h * 0.006,
            cx + waistHalfW,
            funnelStartY,
          )
          ..lineTo(cx + topHalfW, streamTopY)
          ..close();

        canvas.drawPath(
          streamFunnelPath,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(cx - topHalfW * 1.4, streamTopY),
              Offset(cx + topHalfW * 1.4, streamBotY),
              [
                Colors.white.withValues(alpha: 0.78 * streamFade),
                midWater.withValues(alpha: 0.94 * streamFade),
                lightWater.withValues(alpha: 0.96 * streamFade),
                midWater.withValues(alpha: 0.94 * streamFade),
                Colors.white.withValues(alpha: 0.72 * streamFade),
              ],
              const [0.0, 0.22, 0.50, 0.78, 1.0],
            ),
        );

        final specHalfW = waistHalfW * 0.30;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              cx - waistHalfW * 0.36,
              streamTopY,
              cx - waistHalfW * 0.36 + specHalfW * 2.0,
              streamBotY,
            ),
            Radius.circular(specHalfW),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.56 * streamFade),
        );

        _drawSurfaceImpactCrownDroplets(
          canvas,
          w: w,
          h: h,
          surfaceY: surfaceY,
          alpha: streamFade,
        );

        canvas.restore();
      }
    }
  }

  /// Combined Concave Neck + Plump Belly + Rounded Aqua-Glass Bottom Bowl silhouette (`y = 0.080..0.962 * h`).
  Path _buildPotNeckAndBellyClipPath(double w, double h) {
    final cx = w * 0.5;
    final neckTopHalfW = w * 0.218;
    final neckWaistHalfW = w * 0.194;
    final ropeHalfW = w * 0.220;
    final bellyHalfW = w * 0.382;
    final baseShoulderHalfW = w * 0.358;

    final neckTopY = h * 0.080;
    final neckWaistY = h * 0.192;
    final ropeY = h * 0.272;
    final bellyMidY = h * 0.575;
    final baseShoulderY = h * 0.832;
    final baseBottomY = h * 0.962;

    return Path()
      ..moveTo(cx - neckTopHalfW, neckTopY)
      ..lineTo(cx + neckTopHalfW, neckTopY)
      // Concave glass neck down to rope collar
      ..quadraticBezierTo(
        cx + neckWaistHalfW,
        neckWaistY,
        cx + ropeHalfW,
        ropeY,
      )
      // Plump bell belly down to exposed glass base shoulder
      ..cubicTo(
        cx + bellyHalfW,
        h * 0.39,
        cx + bellyHalfW * 1.02,
        bellyMidY,
        cx + baseShoulderHalfW,
        baseShoulderY,
      )
      // Smoothly rounded crystal-aqua bottom glass bowl (`media_1794051081001.png`)
      ..cubicTo(
        cx + baseShoulderHalfW * 0.96,
        h * 0.936,
        cx + w * 0.18,
        baseBottomY,
        cx,
        baseBottomY,
      )
      ..cubicTo(
        cx - w * 0.18,
        baseBottomY,
        cx - baseShoulderHalfW * 0.96,
        h * 0.936,
        cx - baseShoulderHalfW,
        baseShoulderY,
      )
      // Left belly up to rope collar
      ..cubicTo(
        cx - bellyHalfW * 1.02,
        bellyMidY,
        cx - bellyHalfW,
        h * 0.39,
        cx - ropeHalfW,
        ropeY,
      )
      // Left concave glass neck up to mouth
      ..quadraticBezierTo(
        cx - neckWaistHalfW,
        neckWaistY,
        cx - neckTopHalfW,
        neckTopY,
      )
      ..close();
  }

  /// Luminous Crystal-Aqua Water Sparkle & Pearlescent Bubble Bloom when the filled Potion Jar completes
  /// (`media_1794007349252.png` Panel 4 — replaces the old solid brown-outlined polygon star).
  void _drawCrystalWaterCompletionBloom(Canvas canvas, double w, double h) {
    final bloomT = ((_openProgress - 0.15) / 0.85).clamp(0.0, 1.0);
    if (bloomT <= 0.01) return;
    final eased = Curves.easeOutCubic.transform(bloomT);
    final env = math.sin(bloomT * math.pi * 0.85).clamp(0.25, 1.0);
    final cx = w * 0.5;
    final mouthY = h * 0.078;

    // 1. Soft crystal-aqua fountain glow at the jar mouth
    final glowCenter = Offset(cx, mouthY - h * 0.06 * eased);
    final glowR = w * (0.28 + 0.24 * eased);
    canvas.drawCircle(
      glowCenter,
      glowR,
      Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          glowCenter,
          glowR,
          [
            Colors.white.withValues(alpha: 0.78 * env),
            Color.lerp(_style.topBright, Colors.white, 0.45)!
                .withValues(alpha: 0.54 * env),
            _style.topBright.withValues(alpha: 0.0),
          ],
          const [0.0, 0.48, 1.0],
        ),
    );

    // 2. Effervescent pearlescent bubbles floating upward from the filled jar
    for (int i = 0; i < 7; i++) {
      final seed = (i * 0.6180339) % 1.0;
      final localT = ((eased * 1.15 + seed * 0.35) % 1.0);
      final spreadX = (seed - 0.5) * w * (0.34 + 0.38 * localT) +
          math.sin(_animTime * 4.2 + i) * w * 0.025;
      final by = mouthY + h * 0.04 - h * (0.12 + 0.34 * localT);
      final bx = cx + spreadX;
      final br = (w * (0.018 + 0.012 * (i % 3)) * (1.0 - 0.35 * localT))
          .clamp(1.6, 5.2);
      final bAlpha = (math.sin(localT * math.pi) * env * 0.90).clamp(0.0, 1.0);
      if (bAlpha <= 0.02) continue;

      canvas.drawCircle(
        Offset(bx, by),
        br,
        Paint()
          ..color = Color.lerp(_style.topBright, Colors.white, 0.45)!
              .withValues(alpha: 0.35 * bAlpha),
      );
      canvas.drawCircle(
        Offset(bx, by),
        br,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.15
          ..color = Colors.white.withValues(alpha: 0.85 * bAlpha),
      );
      canvas.drawCircle(
        Offset(bx - br * 0.32, by - br * 0.32),
        br * 0.34,
        Paint()..color = Colors.white.withValues(alpha: bAlpha),
      );
    }

    // 3. Crisp 4-pointed pure white/cyan water glints twinkling around the upper jar
    for (int k = 0; k < 5; k++) {
      final ang = -math.pi * 0.85 + (k / 4.0) * math.pi * 0.70;
      final dist = w * (0.24 + 0.22 * eased + 0.05 * (k % 2));
      final gx = cx + math.cos(ang) * dist;
      final gy = mouthY + h * 0.06 + math.sin(ang) * dist * 0.82 - h * 0.06 * eased;
      final twinkle = (0.55 + 0.45 * math.sin(_animTime * 9.0 + k * 1.7)) * env;
      final r = w * (0.045 + 0.018 * (k % 2)) * twinkle;
      if (r <= 1.0) continue;

      final starPath = Path()
        ..moveTo(gx, gy - r)
        ..quadraticBezierTo(gx, gy, gx + r * 0.85, gy)
        ..quadraticBezierTo(gx, gy, gx, gy + r)
        ..quadraticBezierTo(gx, gy, gx - r * 0.85, gy)
        ..quadraticBezierTo(gx, gy, gx, gy - r)
        ..close();
      canvas.drawPath(
        starPath,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..color = const Color(0xFF88FCFF).withValues(alpha: 0.75 * env),
      );
      canvas.drawCircle(
        Offset(gx, gy),
        r * 0.28,
        Paint()..color = Colors.white.withValues(alpha: 0.95 * env),
      );
    }
  }

  void _drawOuterAuraAndGodRays(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.5, h * 0.54);
    final popAura = (_appearProgress > 0.01 && _appearProgress < 1.0)
        ? math.sin(_appearProgress * math.pi) * 0.65
        : 0.0;
    final auraIntensity =
        math.max(math.max(_glowIntensity, _openProgress), popAura).clamp(0.0, 1.0);
    final auraRadius = w * (0.62 + 0.36 * auraIntensity + 0.24 * _openProgress);

    final aquaRim =
        Color.lerp(const Color(0xFFB4FEFF), _style.rimHighlight, 0.20)!;
    final aquaMid =
        Color.lerp(const Color(0xFF28EAFF), _style.topBright, 0.22)!;
    final aquaDeep =
        Color.lerp(const Color(0xFF08B8E8), _style.accent, 0.22)!;

    canvas.drawCircle(
      center,
      auraRadius,
      Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          center,
          auraRadius,
          [
            aquaRim.withValues(alpha: 0.68 * auraIntensity),
            aquaMid.withValues(alpha: 0.40 * auraIntensity),
            aquaDeep.withValues(alpha: 0.0),
          ],
          const [0.0, 0.52, 1.0],
        ),
    );

    if (_haloImg != null) {
      final haloSz = auraRadius * 2.1;
      final dst = Rect.fromCenter(center: center, width: haloSz, height: haloSz);
      final src = Rect.fromLTWH(
        0,
        0,
        _haloImg!.width.toDouble(),
        _haloImg!.height.toDouble(),
      );
      canvas.drawImageRect(
        _haloImg!,
        src,
        dst,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..colorFilter = ui.ColorFilter.mode(
            aquaMid.withValues(alpha: 0.62 * auraIntensity),
            ui.BlendMode.modulate,
          ),
      );
    }

    if (_openProgress > 0.05) {
      final rayAlpha = ((_openProgress - 0.05) / 0.95).clamp(0.0, 1.0);
      final rayOrigin = Offset(w * 0.5, h * 0.078);
      const rayCount = 8;
      final rayLen = w * (0.48 + 0.42 * _openProgress);
      final halfW = w * 0.052;
      final rayPaint = Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, -rayLen),
          [
            Colors.white.withValues(alpha: 0.48 * rayAlpha),
            aquaRim.withValues(alpha: 0.28 * rayAlpha),
            aquaMid.withValues(alpha: 0.0),
          ],
          const [0.0, 0.55, 1.0],
        );

      _scratchPath
        ..reset()
        ..moveTo(0, 0)
        ..lineTo(-halfW, -rayLen)
        ..lineTo(halfW, -rayLen)
        ..close();

      for (int i = 0; i < rayCount; i++) {
        final angle = _animTime * 1.4 + (i * math.pi * 2.0 / rayCount);
        canvas.save();
        canvas.translate(rayOrigin.dx, rayOrigin.dy);
        canvas.rotate(angle);
        canvas.drawPath(_scratchPath, rayPaint);
        canvas.restore();
      }
    }
  }
}

/// Step 1 VFX: Luminous Crystal-Aqua Water Surge & Ripple Halo on Final Block Merge
/// (`media_1794007349252.png` Panel 1-2).
class FinalTileLightExplosionVfx extends PositionComponent {
  final Vector2 centerPos;
  final BlockColorStyle style;
  final double cellSize;
  final double duration;
  double _elapsed = 0.0;

  ui.Image? _haloImg;
  ui.Image? _ringImg;
  ui.Image? _sparkleImg;

  late final List<(double angle, double speed, double scale, bool useAccent)>
      _sparks;
  late final Float32List _rstTransforms;
  late final Float32List _texRects;
  late final Int32List _colors;
  final Paint _atlasPaint = Paint()
    ..blendMode = ui.BlendMode.plus
    ..filterQuality = ui.FilterQuality.low;

  FinalTileLightExplosionVfx({
    required this.centerPos,
    required this.style,
    required this.cellSize,
    this.duration = 0.68,
  }) : super(priority: 122) {
    if (Flame.images.containsKey('Explosion_Halo.png')) {
      _haloImg = Flame.images.fromCache('Explosion_Halo.png');
    }
    if (Flame.images.containsKey('Glow_Ring.png')) {
      _ringImg = Flame.images.fromCache('Glow_Ring.png');
    }
    if (Flame.images.containsKey('Sparkle_01.png')) {
      _sparkleImg = Flame.images.fromCache('Sparkle_01.png');
    }

    const count = 24;
    final rng = math.Random(901);
    _sparks = List.generate(count, (i) {
      final baseAngle = (i / count) * math.pi * 2.0;
      final angle = baseAngle + (rng.nextDouble() - 0.5) * 0.22;
      final speed = cellSize * (1.25 + rng.nextDouble() * 1.65);
      final scale = 0.65 + rng.nextDouble() * 0.65;
      return (angle, speed, scale, i.isEven);
    });
    _rstTransforms = Float32List(count * 4);
    _texRects = Float32List(count * 4);
    _colors = Int32List(count);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt.clamp(0.0, 0.05);
    if (_elapsed >= duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / duration).clamp(0.0, 1.0);
    final easeOut = 1.0 - math.pow(1.0 - t, 3).toDouble();
    final fade = (1.0 - t).clamp(0.0, 1.0);

    final aquaRim =
        Color.lerp(const Color(0xFFB8FFFF), style.rimHighlight, 0.22)!;
    final aquaMid =
        Color.lerp(const Color(0xFF28EAFF), style.topBright, 0.25)!;
    final aquaDeep = Color.lerp(const Color(0xFF069CD4), style.accent, 0.25)!;

    // 1. Expanding crystal-aqua radial light flash & water-ripple shockwave ring
    final ringRadius = cellSize * (0.45 + 1.85 * easeOut);
    canvas.drawCircle(
      Offset(centerPos.x, centerPos.y),
      ringRadius,
      Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(centerPos.x, centerPos.y),
          ringRadius,
          [
            Colors.white.withValues(alpha: 0.85 * fade),
            aquaMid.withValues(alpha: 0.56 * fade),
            aquaDeep.withValues(alpha: 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );

    // Crisp concentric liquid ripple ring around the final block
    canvas.drawCircle(
      Offset(centerPos.x, centerPos.y),
      cellSize * (0.38 + 1.32 * easeOut),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.048 * fade).clamp(1.2, 4.5)
        ..color = aquaRim.withValues(alpha: 0.78 * fade),
    );

    if (_ringImg != null) {
      final sz = ringRadius * 2.1;
      final dst = Rect.fromCenter(
        center: Offset(centerPos.x, centerPos.y),
        width: sz,
        height: sz,
      );
      final src = Rect.fromLTWH(
        0,
        0,
        _ringImg!.width.toDouble(),
        _ringImg!.height.toDouble(),
      );
      canvas.drawImageRect(
        _ringImg!,
        src,
        dst,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..colorFilter = ui.ColorFilter.mode(
            aquaRim.withValues(alpha: 0.85 * fade),
            ui.BlendMode.modulate,
          ),
      );
    }

    if (_haloImg != null) {
      final sz = ringRadius * 2.5;
      final dst = Rect.fromCenter(
        center: Offset(centerPos.x, centerPos.y),
        width: sz,
        height: sz,
      );
      final src = Rect.fromLTWH(
        0,
        0,
        _haloImg!.width.toDouble(),
        _haloImg!.height.toDouble(),
      );
      canvas.drawImageRect(
        _haloImg!,
        src,
        dst,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..colorFilter = ui.ColorFilter.mode(
            aquaMid.withValues(alpha: 0.72 * fade),
            ui.BlendMode.modulate,
          ),
      );
    }

    // 2. Hardware-batched radial crystal-aqua sparks
    final spImg = _sparkleImg;
    if (spImg != null) {
      final sw = spImg.width.toDouble();
      final sh = spImg.height.toDouble();
      final hx = sw * 0.5;
      final hy = sh * 0.5;
      final baseSize = cellSize * 0.42;

      for (int i = 0; i < _sparks.length; i++) {
        final (angle, speed, sc, useAccent) = _sparks[i];
        final dist = speed * easeOut;
        final px = centerPos.x + math.cos(angle) * dist;
        final py = centerPos.y + math.sin(angle) * dist;
        final targetSz = baseSize * sc * (1.0 - 0.55 * t);
        final scaleFactor = targetSz / math.max(1.0, sw);
        final rot = angle + t * 3.2;
        final scos = scaleFactor * math.cos(rot);
        final ssin = scaleFactor * math.sin(rot);

        final idx4 = i * 4;
        _rstTransforms[idx4] = scos;
        _rstTransforms[idx4 + 1] = ssin;
        _rstTransforms[idx4 + 2] = px - scos * hx + ssin * hy;
        _rstTransforms[idx4 + 3] = py - ssin * hx - scos * hy;
        _texRects[idx4] = 0.0;
        _texRects[idx4 + 1] = 0.0;
        _texRects[idx4 + 2] = sw;
        _texRects[idx4 + 3] = sh;

        final c = useAccent ? aquaRim : aquaMid;
        _colors[i] = c.withValues(alpha: (fade * 0.95).clamp(0.0, 1.0)).toARGB32();
      }

      canvas.drawRawAtlas(
        spImg,
        _rstTransforms,
        _texRects,
        _colors,
        ui.BlendMode.modulate,
        null,
        _atlasPaint,
      );
    }
  }
}

/// Step 2 VFX: Single Unbroken 3D Crystal-Aqua Pouring Water Stream (`media_1794051150239.png` & `media_1794007349252.png`):
/// - Renders ONE continuous G1/C1-smooth composite water curve from `finalTileCenter` -> sweeping outer C-belly ->
///   round circular top `Apex` -> vertical entry into `jar.mouthWorldPos` -> straight vertical plunge inside
///   the glass neck right into `jar.liquidSurfaceWorldPos` (ZERO seam at the jar mouth!).
/// - Immediately composites `jar.renderStreamForegroundOcclusion(...)` on top so the stream passes behind the
///   translucent front mouth lip, behind the golden neck rope & target tag, and melts into the rising water surface!
class BoardSandStreamToJarVfx extends PositionComponent {
  final Vector2 finalTileCenter;
  final BlockColorStyle style;
  final Vector2 Function() targetMouthProvider;
  final MagicSandJarComponent? jar;
  final double cellSize;

  double _elapsed = 0.0;
  double _flowPhase = 0.0;
  final double _totalDuration = 1.14;
  late final double _archSideSign;

  double get archSideSign => _archSideSign;

  final Path _outerStreamPath = Path();
  final Path _coreStreamPath = Path();
  final Path _innerShadowPath = Path();
  final Path _specularStripePath = Path();
  final Path _leftEdgePath = Path();
  final Path _rightEdgePath = Path();

  BoardSandStreamToJarVfx({
    required this.finalTileCenter,
    required List<Vector2> boardOrigins,
    required this.targetMouthProvider,
    required this.style,
    required this.cellSize,
    this.jar,
  }) : super(priority: 125) {
    assert(boardOrigins.isNotEmpty || finalTileCenter.length >= 0);
    final target = jar?.mouthWorldPos ?? targetMouthProvider();
    final dxToMouth = finalTileCenter.x - target.x;
    // Sweep gracefully around the right side (`+1.0`) like `media_1794051150239.png` unless the tile is far left.
    _archSideSign = dxToMouth < -cellSize * 0.85 ? -1.0 : 1.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final clamped = dt.clamp(0.0, 0.05);
    _elapsed += clamped;
    _flowPhase += clamped * 18.5;
    if (_elapsed >= _totalDuration) {
      removeFromParent();
    }
  }

  (Offset pos, Offset tangent, Offset normal) _evalCubic(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3,
    double u,
  ) {
    final c = u.clamp(0.0, 1.0);
    final om = 1.0 - c;
    final om2 = om * om;
    final om3 = om2 * om;
    final c2 = c * c;
    final c3 = c2 * c;

    final bx =
        om3 * p0.dx + 3.0 * om2 * c * p1.dx + 3.0 * om * c2 * p2.dx + c3 * p3.dx;
    final by =
        om3 * p0.dy + 3.0 * om2 * c * p1.dy + 3.0 * om * c2 * p2.dy + c3 * p3.dy;

    final tx = 3.0 * om2 * (p1.dx - p0.dx) +
        6.0 * om * c * (p2.dx - p1.dx) +
        3.0 * c2 * (p3.dx - p2.dx);
    final ty = 3.0 * om2 * (p1.dy - p0.dy) +
        6.0 * om * c * (p2.dy - p1.dy) +
        3.0 * c2 * (p3.dy - p2.dy);
    final tLen = math.max(1e-4, math.sqrt(tx * tx + ty * ty));
    final ux = tx / tLen;
    final uy = ty / tLen;
    return (Offset(bx, by), Offset(ux, uy), Offset(-uy, ux));
  }

  /// Evaluates position, unit tangent, unit normal, and base half-width along the unbroken
  /// 3-segment composite trajectory `s ∈ [0, 1]` (`Start -> Apex -> Mouth -> Interior Water Surface`).
  ({Offset pos, Offset tangent, Offset normal, double halfWidth})
      _sampleCompositePourCurve({
    required Vector2 mouth,
    required double s,
  }) {
    final sc = s.clamp(0.0, 1.0);
    final hasInterior = jar != null;
    final sApex = hasInterior ? 0.54 : 0.68;
    final sMouth = hasInterior ? 0.78 : 1.00;

    final baseHalfW = cellSize * 0.285;
    final neckHalfW = jar?.neckStreamHalfWidthWorld ?? (cellSize * 0.095);
    final jarHalfW = jar != null ? jar!.size.x * 0.5 : cellSize * 1.15;

    final apex = Offset(
      mouth.x + _archSideSign * cellSize * 0.64,
      mouth.y - cellSize * 0.78,
    );
    final minClearX = mouth.x +
        _archSideSign * math.max(jarHalfW + cellSize * 0.68, cellSize * 1.88);
    final outerX = _archSideSign >= 0
        ? math.max(
            minClearX,
            math.max(finalTileCenter.x, mouth.x) + cellSize * 0.85,
          )
        : math.min(
            minClearX,
            math.min(finalTileCenter.x, mouth.x) - cellSize * 0.85,
          );

    if (sc <= sMouth) {
      final Offset rawPos;
      final Offset tang;
      final Offset norm;
      if (sc <= sApex) {
        final uA = (sc / sApex).clamp(0.0, 1.0);
        final p0 = Offset(finalTileCenter.x, finalTileCenter.y);
        final p1 = Offset(
          outerX,
          math.min(
            ui.lerpDouble(finalTileCenter.y, mouth.y, 0.48)!,
            mouth.y + cellSize * 0.65,
          ),
        );
        final p2 = Offset(ui.lerpDouble(apex.dx, outerX, 0.80)!, apex.dy);
        final eval = _evalCubic(p0, p1, p2, apex, uA);
        rawPos = eval.$1;
        tang = eval.$2;
        norm = eval.$3;
      } else {
        final uB = ((sc - sApex) / (sMouth - sApex)).clamp(0.0, 1.0);
        final q1 = Offset(apex.dx - _archSideSign * cellSize * 0.36, apex.dy);
        final q2 = Offset(mouth.x, mouth.y - cellSize * 0.46);
        final q3 = Offset(mouth.x, mouth.y);
        final eval = _evalCubic(apex, q1, q2, q3, uB);
        rawPos = eval.$1;
        tang = eval.$2;
        norm = eval.$3;
      }

      final uAB = (sc / sMouth).clamp(0.0, 1.0);
      // Smooth C1 laminar breathing that decays to 0 at both endpoints (`uAB = 0` and `uAB = 1` at `Mouth`)
      final swayEnv = math.sin(uAB * math.pi) * (1.0 - uAB);
      final gentleSway =
          math.sin(uAB * 6.0 - _flowPhase * 0.85) * cellSize * 0.011 * swayEnv;

      final taperU = Curves.easeOutCubic.transform(uAB);
      final breathe =
          1.0 + 0.026 * math.sin(uAB * 9.0 - _flowPhase) * math.sin(uAB * math.pi);
      final hw = ui.lerpDouble(baseHalfW, neckHalfW, taperU)! * breathe;

      return (
        pos: rawPos + norm * gentleSway,
        tangent: tang,
        normal: norm,
        halfWidth: hw,
      );
    } else {
      // Segment C (`sMouth .. 1.0`): Straight vertical plunge inside the glass neck into `liquidSurfaceWorldPos`!
      final uC = ((sc - sMouth) / (1.0 - sMouth)).clamp(0.0, 1.0);
      final surf = jar!.liquidSurfaceWorldPos;
      final startY = mouth.y;
      final endY = math.max(mouth.y + cellSize * 0.08, surf.y + cellSize * 0.03);
      final py = ui.lerpDouble(startY, endY, uC)!;

      final waistDip = 1.0 - 0.08 * math.sin(uC * math.pi);
      final impactFlare = uC > 0.76
          ? Curves.easeInQuad.transform(((uC - 0.76) / 0.24).clamp(0.0, 1.0)) *
              0.56
          : 0.0;
      final interiorBreathe =
          1.0 + 0.022 * math.sin(uC * 5.0 - _flowPhase) * math.sin(uC * math.pi);
      final hw = neckHalfW * (waistDip + impactFlare) * interiorBreathe;

      return (
        pos: Offset(mouth.x, py),
        tangent: const Offset(0.0, 1.0),
        normal: const Offset(-1.0, 0.0),
        halfWidth: hw,
      );
    }
  }

  void _buildClosedRibbon(
    Path path,
    List<Offset> sideA,
    List<Offset> sideB,
  ) {
    path.reset();
    if (sideA.isEmpty) return;
    path.moveTo(sideA.first.dx, sideA.first.dy);
    for (int i = 1; i < sideA.length; i++) {
      path.lineTo(sideA[i].dx, sideA[i].dy);
    }
    for (int i = sideB.length - 1; i >= 0; i--) {
      path.lineTo(sideB[i].dx, sideB[i].dy);
    }
    path.close();
  }

  void _buildOpenStrokePath(Path path, List<Offset> pts, int startIdx) {
    path.reset();
    if (pts.length <= startIdx + 1) return;
    path.moveTo(pts[startIdx].dx, pts[startIdx].dy);
    for (int i = startIdx + 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
  }

  void _drawUnbrokenCrystalWaterStream({
    required Canvas canvas,
    required Vector2 mouth,
    required double tailS,
    required double headS,
  }) {
    final span = headS - tailS;
    if (span <= 0.015) return;

    const int steps = 64;
    final leftOuter = <Offset>[];
    final rightOuter = <Offset>[];
    final leftCore = <Offset>[];
    final rightCore = <Offset>[];
    final innerShadowA = <Offset>[];
    final innerShadowB = <Offset>[];
    final specA = <Offset>[];
    final specB = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final localFrac = i / steps;
      final s = tailS + span * localFrac;
      final sample = _sampleCompositePourCurve(mouth: mouth, s: s);
      final pt = sample.pos;
      final norm = sample.normal;
      // `outerNorm` always points toward the convex outer crest of the C-arch!
      final outerNorm = norm * _archSideSign;

      final headTaper = (headS < 0.96 && localFrac > 0.85)
          ? (0.28 +
              0.72 * math.sin(((1.0 - localFrac) / 0.15) * (math.pi * 0.5)))
          : 1.0;
      final tailWindow = tailS > 0.015 ? 0.28 : 0.14;
      final tailMin = tailS > 0.015 ? 0.16 : 0.42;
      final tailTaper = localFrac < tailWindow
          ? (tailMin +
              (1.0 - tailMin) *
                  math.sin((localFrac / tailWindow) * (math.pi * 0.5)))
          : 1.0;

      final halfW = sample.halfWidth * headTaper * tailTaper;

      final outerW = halfW * 1.18;
      leftOuter.add(pt + norm * outerW);
      rightOuter.add(pt - norm * outerW);

      leftCore.add(pt + norm * halfW);
      rightCore.add(pt - norm * halfW);

      // Deep ocean-cerulean refraction band along the concave inner side of the stream (`media_1794051150239.png`)
      innerShadowA.add(pt - outerNorm * (halfW * 0.94));
      innerShadowB.add(pt - outerNorm * (halfW * 0.18));

      // Sleek continuous white-aqua specular highlight ribbon toward the outer-upper side
      final specCenter = pt + outerNorm * (halfW * 0.34);
      final specHalfW = halfW * 0.21;
      specA.add(specCenter + outerNorm * specHalfW);
      specB.add(specCenter - outerNorm * specHalfW);
    }

    _buildClosedRibbon(_outerStreamPath, leftOuter, rightOuter);
    _buildClosedRibbon(_coreStreamPath, leftCore, rightCore);
    _buildClosedRibbon(_innerShadowPath, innerShadowA, innerShadowB);
    _buildClosedRibbon(_specularStripePath, specA, specB);

    final edgeStartIdx = tailS > 0.015 ? 7 : 1;
    _buildOpenStrokePath(_leftEdgePath, leftCore, edgeStartIdx);
    _buildOpenStrokePath(_rightEdgePath, rightCore, edgeStartIdx);

    // Dynamic water stream colors matching final block's exact color
    final icyAqua = Color.lerp(style.topBright, Colors.white, 0.50)!;
    final brightAqua = style.topBright;
    final midAqua = style.topMid;
    final deepAqua = style.bottomLip;

    final needsTailFeather = tailS > 0.015;
    if (needsTailFeather) {
      final layerBounds = _outerStreamPath.getBounds().inflate(cellSize * 0.22);
      canvas.saveLayer(layerBounds, Paint());
    }

    // 1. Soft outer water glow halo matching block color
    canvas.drawPath(
      _outerStreamPath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..color = brightAqua.withValues(alpha: 0.40)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (cellSize * 0.046).clamp(2.0, 5.2),
        ),
    );

    // 2. Rich translucent cylindrical stream core matching block color
    final streamBounds = _coreStreamPath.getBounds();
    canvas.drawPath(
      _coreStreamPath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          streamBounds.bottomCenter,
          streamBounds.topCenter,
          [
            midAqua.withValues(alpha: 0.86),
            brightAqua.withValues(alpha: 0.92),
            icyAqua.withValues(alpha: 0.94),
            midAqua.withValues(alpha: 0.92),
          ],
          const [0.0, 0.42, 0.78, 1.0],
        ),
    );

    // 3. Deeper refraction band along the inner curve matching block depth
    canvas.drawPath(
      _innerShadowPath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..color = deepAqua.withValues(alpha: 0.36)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (cellSize * 0.022).clamp(1.0, 2.8),
        ),
    );

    // 4. Open meniscus side rims matching block highlight
    final rimPaint = Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round
      ..strokeWidth = (cellSize * 0.028).clamp(1.2, 2.7)
      ..color = icyAqua.withValues(alpha: 0.85);
    canvas.drawPath(_leftEdgePath, rimPaint);
    canvas.drawPath(_rightEdgePath, rimPaint);

    // 5. Sleek continuous glossy highlight ribbon
    canvas.drawPath(
      _specularStripePath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.56)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          (cellSize * 0.012).clamp(0.6, 1.6),
        ),
    );

    // 6. Effervescent translucent bubbles flowing smoothly inside the stream
    for (int k = 0; k < 10; k++) {
      final bubbleFrac = ((_flowPhase * 0.11 + k * 0.10) % 1.0);
      final s = tailS + span * bubbleFrac;
      if (s <= tailS + 0.05 || s >= headS - 0.04) continue;
      final sample = _sampleCompositePourCurve(mouth: mouth, s: s);
      final sideOff = ((k % 3) - 1) * sample.halfWidth * 0.36;
      final bCenter = sample.pos + sample.normal * sideOff;
      final br = (sample.halfWidth * (0.14 + 0.05 * (k % 3))).clamp(1.3, 4.2);
      final bAlpha = (math.sin(bubbleFrac * math.pi) * 0.76).clamp(0.0, 0.88);

      canvas.drawCircle(
        bCenter,
        br,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.05
          ..color = icyAqua.withValues(alpha: bAlpha),
      );
      canvas.drawCircle(
        Offset(bCenter.dx - br * 0.30, bCenter.dy - br * 0.30),
        br * 0.36,
        Paint()..color = Colors.white.withValues(alpha: bAlpha),
      );
    }

    // 7. Smooth cohesive liquid tail feathering (`BlendMode.dstIn`) when lifting off the board!
    if (needsTailFeather) {
      final tailSample = _sampleCompositePourCurve(mouth: mouth, s: tailS);
      final featherStart =
          tailSample.pos - tailSample.tangent * (cellSize * 0.04);
      final featherEnd =
          tailSample.pos + tailSample.tangent * (cellSize * 0.50);
      canvas.drawRect(
        _outerStreamPath.getBounds().inflate(cellSize * 0.25),
        Paint()
          ..blendMode = ui.BlendMode.dstIn
          ..shader = ui.Gradient.linear(
            featherStart,
            featherEnd,
            const [
              Color(0x00FFFFFF),
              Color(0x88FFFFFF),
              Color(0xFFFFFFFF),
            ],
            const [0.0, 0.52, 1.0],
          ),
      );
      canvas.restore();

      // Cute trailing micro-droplets detaching behind the lifting water tail (`media_1794051150239.png`)
      if (tailS < 0.90) {
        final tailEnv = ((0.90 - tailS) / 0.18).clamp(0.0, 1.0);
        for (int m = 0; m < 3; m++) {
          final lag = cellSize * (0.09 + 0.11 * m);
          final jitter =
              math.sin(_flowPhase * 0.5 + m * 2.1) * cellSize * 0.032;
          final dropPos = tailSample.pos -
              tailSample.tangent * lag +
              tailSample.normal * jitter;
          final r = (cellSize * (0.036 - 0.008 * m)).clamp(1.2, 3.6);
          final a = (tailEnv * (0.78 - 0.20 * m)).clamp(0.0, 1.0);
          canvas.drawCircle(
            dropPos,
            r,
            Paint()..color = brightAqua.withValues(alpha: a * 0.85),
          );
          canvas.drawCircle(
            Offset(dropPos.dx - r * 0.3, dropPos.dy - r * 0.3),
            r * 0.38,
            Paint()..color = Colors.white.withValues(alpha: a),
          );
        }
      }
    }
  }

  /// Centrifugal curved spray streaks, glossy 3D teardrop splashes along the arch crest,
  /// cute splash droplets near the jar mouth, and `))` motion arcs outside the C-belly (`media_1794051150239.png`).
  void _drawCentrifugalSprayAndMotionArcs({
    required Canvas canvas,
    required Vector2 mouth,
    required double tailS,
    required double headS,
  }) {
    final span = headS - tailS;
    if (span <= 0.06) return;

    final hasInterior = jar != null;
    final sMouth = hasInterior ? 0.78 : 1.00;
    final brightAqua =
        Color.lerp(const Color(0xFF98FCFF), style.topBright, 0.12)!;
    final midAqua = Color.lerp(const Color(0xFF14D2F8), style.topMid, 0.14)!;

    // 1. Short tapered glossy turquoise-aqua liquid splash wisps detaching off the upper dome (`media_1794051150239.png`)
    const wispRanges = <(double, double, double)>[
      (0.54, 0.70, 0.048),
      (0.68, 0.82, 0.072),
    ];
    for (int k = 0; k < wispRanges.length; k++) {
      final (f0, f1, baseGap) = wispRanges[k];
      final s0 = math.max(tailS + 0.03, sMouth * f0);
      final s1 = math.min(headS - 0.03, sMouth * f1);
      if (s1 - s0 <= 0.035) continue;

      final innerWisp = <Offset>[];
      final outerWisp = <Offset>[];
      const segs = 12;
      final maxHalfThick = (cellSize * (k == 0 ? 0.022 : 0.017)).clamp(0.9, 2.3);
      for (int i = 0; i <= segs; i++) {
        final t = i / segs;
        final s = ui.lerpDouble(s0, s1, t)!;
        final sample = _sampleCompositePourCurve(mouth: mouth, s: s);
        final outerNorm = sample.normal * _archSideSign;
        final swell = math.sin(t * math.pi);
        final centerDist =
            sample.halfWidth + cellSize * (baseGap + 0.032 * t);
        final halfT = maxHalfThick * swell;
        final cPt = sample.pos + outerNorm * centerDist;
        outerWisp.add(cPt + outerNorm * halfT);
        innerWisp.add(cPt - outerNorm * halfT);
      }
      final wispPath = Path();
      _buildClosedRibbon(wispPath, outerWisp, innerWisp);
      canvas.drawPath(
        wispPath,
        Paint()
          ..shader = ui.Gradient.linear(
            innerWisp.first,
            outerWisp.last,
            [
              midAqua.withValues(alpha: 0.78),
              brightAqua.withValues(alpha: 0.94),
              Colors.white.withValues(alpha: 0.88),
            ],
            const [0.0, 0.55, 1.0],
          ),
      );
    }

    // 2. Glossy water droplets flying along the outer crest of the C-arch
    const int dropletCount = 7;
    for (int i = 0; i < dropletCount; i++) {
      final phase = ((_flowPhase * 0.095 + i * (1.0 / dropletCount)) % 1.0);
      final s = tailS + math.min(span, sMouth - tailS) * phase;
      if (s <= tailS + 0.04 || s >= math.min(headS, sMouth) - 0.03) continue;

      final sample = _sampleCompositePourCurve(mouth: mouth, s: s);
      final outerNorm = sample.normal * _archSideSign;
      final sideSign = (i % 3 == 0) ? -1.0 : 1.0;
      final lateralDist =
          sample.halfWidth + cellSize * (0.042 + 0.028 * ((i * 5) % 3));
      final dropCenter = sample.pos + outerNorm * (sideSign * lateralDist);
      final r = (sample.halfWidth * (0.15 + 0.05 * (i % 3))).clamp(1.5, 4.4);
      final alpha = (math.sin(phase * math.pi) * 0.90).clamp(0.0, 1.0);

      // Draw elongated glossy teardrop aligned with `sample.tangent`
      canvas.save();
      canvas.translate(dropCenter.dx, dropCenter.dy);
      canvas.rotate(math.atan2(sample.tangent.dy, sample.tangent.dx));
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 2.5, height: r * 1.7),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(r, 0),
            Offset(-r, 0),
            [
              brightAqua.withValues(alpha: alpha * 0.96),
              midAqua.withValues(alpha: alpha * 0.88),
            ],
          ),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(r * 0.28, -r * 0.25),
          width: r * 0.95,
          height: r * 0.52,
        ),
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.95),
      );
      canvas.restore();
    }

    // 3. Cute splash droplets popping just outside the jar mouth rim (`media_1794051150239.png`)
    if (headS >= sMouth && tailS < sMouth + 0.14) {
      final mouthSplashAlpha = math
          .min((headS - sMouth + 0.08) / 0.12, (sMouth + 0.14 - tailS) / 0.14)
          .clamp(0.0, 1.0);
      final hop = math.sin(_flowPhase * 0.65).abs() * cellSize * 0.08;
      for (int m = 0; m < 2; m++) {
        final dx = -_archSideSign * cellSize * (0.28 + 0.14 * m);
        final dy = -cellSize * (0.14 + 0.12 * m) - hop * (1.0 - 0.25 * m);
        final p = Offset(mouth.x + dx, mouth.y + dy);
        final r = (cellSize * (m == 0 ? 0.048 : 0.032)).clamp(1.6, 4.4);
        canvas.drawCircle(
          p,
          r,
          Paint()..color = brightAqua.withValues(alpha: 0.90 * mouthSplashAlpha),
        );
        canvas.drawCircle(
          Offset(p.dx - r * 0.30, p.dy - r * 0.30),
          r * 0.38,
          Paint()..color = Colors.white.withValues(alpha: 0.95 * mouthSplashAlpha),
        );
      }
    }

    // 4. Softly bowed white parentheses flutter arcs `))` at the lower-curtain hem height,
    //    positioned cleanly outside the water stream (`media_1794051150239.png`)!
    if (jar != null && headS > 0.35 && tailS < 0.72) {
      final jw = jar!.size.x;
      final jh = jar!.size.y;
      final jarTop = jar!.position.y - jh * 0.5;
      final targetMidY = jarTop + jh * 0.695;

      // Find the outermost X of the active water stream near `targetMidY`
      double outerStreamEdgeX =
          jar!.position.x + _archSideSign * (jw * 0.48);
      for (int k = 0; k <= 16; k++) {
        final s = ui.lerpDouble(tailS, math.min(headS, sMouth), k / 16.0)!;
        final samp = _sampleCompositePourCurve(mouth: mouth, s: s);
        if ((samp.pos.dy - targetMidY).abs() <= jh * 0.22) {
          final edgeX = samp.pos.dx + _archSideSign * samp.halfWidth;
          if (_archSideSign >= 0) {
            outerStreamEdgeX = math.max(outerStreamEdgeX, edgeX);
          } else {
            outerStreamEdgeX = math.min(outerStreamEdgeX, edgeX);
          }
        }
      }

      final arcEnv = math
          .min((headS - 0.35) / 0.15, (0.72 - tailS) / 0.18)
          .clamp(0.0, 1.0);
      final pulse = 0.009 * math.sin(_flowPhase * 0.85) * jw * _archSideSign;
      final baseX = outerStreamEdgeX + _archSideSign * (jw * 0.042) + pulse;

      final innerArc = Path()
        ..moveTo(baseX, jarTop + jh * 0.625)
        ..quadraticBezierTo(
          baseX + _archSideSign * (jw * 0.036),
          jarTop + jh * 0.700,
          baseX + _archSideSign * (jw * 0.010),
          jarTop + jh * 0.778,
        );
      final outerArc = Path()
        ..moveTo(baseX + _archSideSign * (jw * 0.030), jarTop + jh * 0.648)
        ..quadraticBezierTo(
          baseX + _archSideSign * (jw * 0.058),
          jarTop + jh * 0.710,
          baseX + _archSideSign * (jw * 0.038),
          jarTop + jh * 0.764,
        );

      canvas.drawPath(
        innerArc,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeWidth = (jw * 0.0135).clamp(1.15, 2.4)
          ..color = Colors.white.withValues(alpha: 0.86 * arcEnv),
      );
      canvas.drawPath(
        outerArc,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeCap = ui.StrokeCap.round
          ..strokeWidth = (jw * 0.0105).clamp(0.95, 1.9)
          ..color = Colors.white.withValues(alpha: 0.64 * arcEnv),
      );
    }
  }

  /// Draws the dissolving liquid vortex at `finalTileCenter` while anchored (`tailS < 0.05`).
  void _drawSourceBlockLiquidPool(Canvas canvas, double tailS) {
    if (tailS >= 0.05) return;
    final env = ((0.05 - tailS) / 0.05).clamp(0.0, 1.0);
    final rx = cellSize * (0.24 + 0.12 * env);
    final ry = rx * 0.56;
    final poolRect = Rect.fromCenter(
      center: Offset(finalTileCenter.x, finalTileCenter.y),
      width: rx * 2.0,
      height: ry * 2.0,
    );

    final brightAqua = style.topBright;
    final midAqua = style.topMid;

    canvas.drawOval(
      poolRect,
      Paint()
        ..shader = ui.Gradient.radial(
          poolRect.center,
          rx,
          [
            brightAqua.withValues(alpha: 0.78 * env),
            midAqua.withValues(alpha: 0.62 * env),
            midAqua.withValues(alpha: 0.0),
          ],
          const [0.0, 0.62, 1.0],
        ),
    );
    canvas.drawOval(
      poolRect.deflate(rx * 0.18),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.026 * env).clamp(1.0, 2.6)
        ..color = Colors.white.withValues(alpha: 0.76 * env),
    );
  }

  /// Fallback front mouth glass lip when `jar == null` (e.g. standalone VFX tests).
  void _drawFallbackMouthFrontGlassLip(
    Canvas canvas,
    Vector2 targetMouth,
    double headS,
    double tailS,
  ) {
    if (headS < 0.88 || tailS >= 0.98) return;
    final fadeIn = ((headS - 0.88) / 0.12).clamp(0.0, 1.0);
    final fadeOut = ((0.98 - tailS) / 0.12).clamp(0.0, 1.0);
    final env = math.min(fadeIn, fadeOut);
    if (env <= 0.02) return;

    final spanX = cellSize * 0.46;
    final lipY = targetMouth.y + cellSize * 0.095;
    final lipArc = Path()
      ..moveTo(targetMouth.x - spanX, targetMouth.y + cellSize * 0.012)
      ..quadraticBezierTo(
        targetMouth.x,
        lipY,
        targetMouth.x + spanX,
        targetMouth.y + cellSize * 0.012,
      );

    canvas.drawPath(
      lipArc,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (cellSize * 0.048).clamp(1.8, 3.8)
        ..color = const Color(0xFFB4F4FF).withValues(alpha: 0.68 * env),
    );
    canvas.drawPath(
      lipArc,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (cellSize * 0.026).clamp(1.2, 2.4)
        ..color = Colors.white.withValues(alpha: 0.92 * env),
    );
  }

  @override
  void render(Canvas canvas) {
    final targetMouth = jar?.mouthWorldPos ?? targetMouthProvider();

    // Progressive stream head (`0 -> 1` in `0.24s`) and smooth cohesive tail (`0 -> 1` from `0.36s..1.08s`)
    final headS =
        Curves.easeOutCubic.transform((_elapsed / 0.24).clamp(0.0, 1.0));
    final tailS = _elapsed <= 0.36
        ? 0.0
        : Curves.easeInOutSine.transform(
            ((_elapsed - 0.36) / 0.72).clamp(0.0, 1.0),
          );

    _drawSourceBlockLiquidPool(canvas, tailS);

    // 1. Single unbroken 3D crystal-aqua water stream (`finalTileCenter -> Apex -> Mouth -> Interior Water Surface`)
    _drawUnbrokenCrystalWaterStream(
      canvas: canvas,
      mouth: targetMouth,
      tailS: tailS,
      headS: headS,
    );

    // 2. Centrifugal curved spray streaks, glossy teardrops & `))` motion arcs
    _drawCentrifugalSprayAndMotionArcs(
      canvas: canvas,
      mouth: targetMouth,
      tailS: tailS,
      headS: headS,
    );

    // 3. Exact physical foreground occlusion by the Potion Jar's front mouth lip, surface crown splash,
    //    glass highlights, golden neck rope, and target goal tag!
    if (jar != null) {
      final touchingSurface = headS >= 0.94 && tailS < 0.96;
      final impactAlpha = touchingSurface
          ? math
              .min((headS - 0.90) / 0.10, (0.96 - tailS) / 0.14)
              .clamp(0.0, 1.0)
          : 0.0;
      jar!.renderStreamForegroundOcclusion(
        canvas,
        isStreamTouchingSurface: touchingSurface,
        streamImpactAlpha: impactAlpha,
      );
    } else {
      _drawFallbackMouthFrontGlassLip(canvas, targetMouth, headS, tailS);
    }
  }
}

/// Step 3 & Step 4 VFX: Luminous Crystal-Aqua Fountain Burst & Fullscreen Transition Wave
/// (`media_1794007349252.png` Panel 4 -> WinOverlay).
class JarOpenAndFullscreenLightWaveVfx extends PositionComponent {
  final Vector2 Function() jarMouthProvider;
  final BlockColorStyle style;
  final double cellSize;
  final double totalDuration;
  double _elapsed = 0.0;

  ui.Image? _haloImg;
  ui.Image? _ringImg;

  JarOpenAndFullscreenLightWaveVfx({
    required this.jarMouthProvider,
    required this.style,
    required this.cellSize,
    this.totalDuration = 0.86,
  }) : super(priority: 150) {
    if (Flame.images.containsKey('Explosion_Halo.png')) {
      _haloImg = Flame.images.fromCache('Explosion_Halo.png');
    }
    if (Flame.images.containsKey('Glow_Ring.png')) {
      _ringImg = Flame.images.fromCache('Glow_Ring.png');
    }
  }

  double get currentFullscreenFlashIntensity {
    if (_elapsed < 0.14) return 0.0;
    if (_elapsed <= 0.48) {
      return ((_elapsed - 0.14) / 0.34).clamp(0.0, 1.0);
    }
    return (1.0 - (_elapsed - 0.48) / math.max(0.05, totalDuration - 0.48))
        .clamp(0.0, 1.0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt.clamp(0.0, 0.05);
    if (_elapsed >= totalDuration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final mouth = jarMouthProvider();
    final center = Offset(mouth.x, mouth.y);
    final t = (_elapsed / totalDuration).clamp(0.0, 1.0);

    final aquaRim =
        Color.lerp(const Color(0xFFC4FFFF), style.rimHighlight, 0.20)!;
    final aquaMid =
        Color.lerp(const Color(0xFF38EEFF), style.topBright, 0.22)!;

    // 1. Step 3: Jar Mouth Crystal-Aqua Light Burst (`0.0 -> 0.75`)
    if (t < 0.75) {
      final burstT = (t / 0.75).clamp(0.0, 1.0);
      final burstFade = (1.0 - burstT).clamp(0.0, 1.0);
      final burstR =
          cellSize * (0.6 + 3.2 * Curves.easeOutCubic.transform(burstT));

      if (_ringImg != null) {
        final dst = Rect.fromCenter(
          center: center,
          width: burstR * 2.0,
          height: burstR * 2.0,
        );
        final src = Rect.fromLTWH(
          0,
          0,
          _ringImg!.width.toDouble(),
          _ringImg!.height.toDouble(),
        );
        canvas.drawImageRect(
          _ringImg!,
          src,
          dst,
          Paint()
            ..blendMode = ui.BlendMode.plus
            ..colorFilter = ui.ColorFilter.mode(
              Colors.white.withValues(alpha: 0.90 * burstFade),
              ui.BlendMode.modulate,
            ),
        );
      }

      if (_haloImg != null) {
        final dst = Rect.fromCenter(
          center: center,
          width: burstR * 2.6,
          height: burstR * 2.6,
        );
        final src = Rect.fromLTWH(
          0,
          0,
          _haloImg!.width.toDouble(),
          _haloImg!.height.toDouble(),
        );
        canvas.drawImageRect(
          _haloImg!,
          src,
          dst,
          Paint()
            ..blendMode = ui.BlendMode.plus
            ..colorFilter = ui.ColorFilter.mode(
              aquaMid.withValues(alpha: 0.85 * burstFade),
              ui.BlendMode.modulate,
            ),
        );
      }
    }

    // 2. Step 4: Fullscreen Expanding Crystal-Aqua Light Wave (`t >= 0.12`)
    final flash = currentFullscreenFlashIntensity;
    if (flash > 0.01) {
      final expandT =
          ((_elapsed - 0.10) / (totalDuration - 0.10)).clamp(0.0, 1.0);
      final maxRadius =
          cellSize * (2.5 + 18.0 * Curves.easeInOutCubic.transform(expandT));

      canvas.drawCircle(
        center,
        maxRadius,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = ui.Gradient.radial(
            center,
            maxRadius,
            [
              Colors.white.withValues(alpha: (0.94 * flash).clamp(0.0, 1.0)),
              aquaRim.withValues(alpha: (0.82 * flash).clamp(0.0, 1.0)),
              aquaMid.withValues(alpha: (0.55 * flash).clamp(0.0, 1.0)),
              aquaMid.withValues(alpha: 0.0),
            ],
            const [0.0, 0.35, 0.72, 1.0],
          ),
      );
    }
  }
}
