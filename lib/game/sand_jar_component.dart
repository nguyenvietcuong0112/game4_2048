import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart'
    show
        BlurStyle,
        BoxShadow,
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

  double _appearProgress = 1.0;
  double _fillProgress = 0.0;
  double _glowIntensity = 0.0;
  double _openProgress = 0.0;
  double _shakeIntensity = 0.0;
  double _animTime = 0.0;
  bool _isOpened = false;

  ui.Image? _haloImg;
  final Path _scratchPath = Path();

  MagicSandJarComponent({
    required BlockColorStyle style,
    required this.levelNumber,
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
      (_fillProgress > 0.001 && !_isOpened) ||
      (_isOpened && _openProgress < 1.0);

  double get _postPourShake {
    if (_fillProgress > 0.005 && _fillProgress < 0.90) {
      return 0.0;
    }
    if (_fillProgress >= 0.90 && _fillProgress < 0.98) {
      return ((_fillProgress - 0.90) / 0.08).clamp(0.0, 1.0) * _shakeIntensity;
    }
    return _shakeIntensity;
  }

  /// World-space coordinates of the pot's open oval mouth (exact center `(w * 0.5, h * 0.232)`).
  /// World-space coordinates of the bottle's open mouth (center of the top oval rim).
  Vector2 get mouthWorldPos {
    final effShake = _postPourShake;
    final throbScale = 1.0 +
        0.11 * _glowIntensity +
        0.042 * math.sin(_animTime * 26.0).abs() * effShake;
    final jitterX =
        math.cos(_animTime * 46.0) * size.x * 0.020 * effShake;
    final jitterY =
        math.sin(_animTime * 52.0) * size.y * 0.015 * effShake;
    return Vector2(
      position.x + jitterX,
      position.y + jitterY + (-0.345 * throbScale) * size.y,
    );
  }

  void updateStyle(BlockColorStyle newStyle) {
    _style = newStyle;
  }

  void resetJarState({double initialAppearProgress = 1.0}) {
    _appearProgress = initialAppearProgress.clamp(0.0, 1.0);
    _fillProgress = 0.0;
    _glowIntensity = 0.0;
    _openProgress = 0.0;
    _shakeIntensity = 0.0;
    _isOpened = false;
  }

  void setWinSequenceState({
    double appearProgress = 1.0,
    required double fillProgress,
    required double glowIntensity,
    required double shakeIntensity,
    required double openProgress,
  }) {
    _appearProgress = appearProgress.clamp(0.0, 1.0);
    _fillProgress = fillProgress.clamp(0.0, 1.0);
    _glowIntensity = glowIntensity.clamp(0.0, 1.0);
    _shakeIntensity = shakeIntensity.clamp(0.0, 1.0);
    _openProgress = openProgress.clamp(0.0, 1.0);
    if (_openProgress > 0.01) {
      _isOpened = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _animTime += dt.clamp(0.0, 0.05);
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    if (w <= 4 || h <= 4 || _appearProgress <= 0.005) return;

    canvas.save();

    final cx = w * 0.5;
    final cy = h * 0.52;
    final bool needsAppearFade = _appearProgress < 0.995;
    if (needsAppearFade) {
      final popScale = 0.36 +
          0.64 * Curves.easeOutBack.transform(_appearProgress.clamp(0.0, 1.0));
      canvas.translate(cx, cy);
      canvas.scale(popScale, popScale);
      canvas.translate(-cx, -cy);
    }

    // Keep bottle steady while receiving the poured water stream (`_fillProgress < 0.90`),
    // then wobble energetically once full (`_postPourShake`) before popping open!
    final effShake = _postPourShake;
    if (effShake > 0.001 || _glowIntensity > 0.001) {
      final wobbleAngle =
          math.sin(_animTime * 38.0) * 0.085 * effShake;
      final throbScale = 1.0 +
          0.11 * _glowIntensity +
          0.042 * math.sin(_animTime * 26.0).abs() * effShake;
      final jitterX = math.cos(_animTime * 46.0) * w * 0.020 * effShake;
      final jitterY = math.sin(_animTime * 52.0) * h * 0.015 * effShake;
      canvas.translate(cx + jitterX, cy + jitterY);
      canvas.scale(throbScale, throbScale);
      canvas.rotate(wobbleAngle);
      canvas.translate(-cx, -cy);
    }

    // 0. Outer Ambient Halo & Opening God-Rays (`Step 2, Step 3 & Step 4`)
    if (_glowIntensity > 0.01 || _openProgress > 0.01 || needsAppearFade) {
      _drawOuterAuraAndGodRays(canvas, w, h);
    }

    // 1. Draw the 3D Crystal Glass Water Bottle Body, Rolled Collar & Water
    _drawStaticBasePot(canvas, w, h);

    // 2. When `fillProgress > 0.005`, draw the rising liquid column & pouring stream inside the bottle!
    if (_fillProgress > 0.005) {
      _drawRisingConicalSandMound(canvas, w, h, _fillProgress);
    }

    // 3. When Jar Opens (`_openProgress >= 0.15`), erupt light & reveal the ascending 3D Golden Star/Gem!
    if (_openProgress >= 0.15) {
      final emergeT = ((_openProgress - 0.15) / 0.85).clamp(0.0, 1.0);
      final eased = 1.0 - math.pow(1.0 - emergeT, 3).toDouble();
      final objY = ui.lerpDouble(h * 0.155, -h * 0.15, eased)!;
      final objScale = ui.lerpDouble(0.85, 1.42, eased)!;

      canvas.drawCircle(
        Offset(w * 0.5, objY),
        w * 0.36 * objScale,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset(w * 0.5, objY),
            w * 0.36 * objScale,
            [
              Colors.white.withValues(alpha: 0.92),
              _style.rimHighlight.withValues(alpha: 0.68),
              _style.topBright.withValues(alpha: 0.0),
            ],
            const [0.0, 0.48, 1.0],
          ),
      );

      _draw3DFacetedGoldStarEmblem(
        canvas,
        center: Offset(w * 0.5, objY),
        radius: w * 0.19 * objScale,
        glowBoost: 1.0,
      );
    }

    canvas.restore();
  }

  /// Draws the glowing golden/celestial Mystery '?' Emblem in the center of the transparent glass belly
  /// with an ethereal pulsing aura and orbiting mystical star sparkles (Mystery Jar mode).
  void _drawMysteryQuestionMark(
    Canvas canvas, {
    required double w,
    required double h,
    required double alpha,
  }) {
    if (alpha <= 0.01) return;

    final cx = w * 0.5;
    final cy = h * 0.57;
    final breathe = 1.0 + 0.05 * math.sin(_animTime * 3.2);
    final pulseGlow = 0.75 + 0.25 * math.sin(_animTime * 4.2).abs();

    // 1. Mystical Celestial Aura Disc behind the '?'
    final auraR = w * 0.34 * breathe;
    canvas.drawCircle(
      Offset(cx, cy),
      auraR,
      Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          auraR,
          [
            const Color(0xFFFFF176).withValues(alpha: 0.40 * alpha * pulseGlow),
            const Color(0xFF40C4FF).withValues(alpha: 0.22 * alpha * pulseGlow),
            const Color(0xFF7C4DFF).withValues(alpha: 0.08 * alpha),
            const Color(0x00000000),
          ],
          const [0.0, 0.42, 0.72, 1.0],
        ),
    );

    // 2. Orbiting Mystical Sparkles
    for (int k = 0; k < 4; k++) {
      final angle = _animTime * 1.5 + k * (math.pi * 0.5);
      final dist = w * (0.23 + 0.03 * math.sin(_animTime * 2.6 + k));
      final sx = cx + math.cos(angle) * dist;
      final sy = cy + math.sin(angle) * (dist * 0.78);
      final spkPulse = (0.45 + 0.55 * math.sin(_animTime * 5.0 + k * 1.5)).clamp(0.0, 1.0);
      final spkR = (w * 0.022 * spkPulse * breathe).clamp(1.2, 4.0);

      final spkPaint = Paint()
        ..blendMode = ui.BlendMode.plus
        ..color = Colors.white.withValues(alpha: 0.88 * alpha * spkPulse);
      canvas.drawLine(Offset(sx - spkR * 2.0, sy), Offset(sx + spkR * 2.0, sy), spkPaint..strokeWidth = 1.2);
      canvas.drawLine(Offset(sx, sy - spkR * 2.0), Offset(sx, sy + spkR * 2.0), spkPaint..strokeWidth = 1.2);
      canvas.drawCircle(
        Offset(sx, sy),
        spkR * 0.75,
        Paint()..color = const Color(0xFFFFF9C4).withValues(alpha: alpha * spkPulse),
      );
    }

    // 3. Glowing Mystery '?' Text Glyph
    final fontSize = (h * 0.26 * breathe).clamp(24.0, 68.0);
    final textPainter = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          foreground: Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, cy - fontSize * 0.5),
              Offset(0, cy + fontSize * 0.5),
              [
                Colors.white.withValues(alpha: alpha),
                const Color(0xFFFFF59D).withValues(alpha: alpha),
                const Color(0xFFFFD54F).withValues(alpha: alpha),
                const Color(0xFFFF9800).withValues(alpha: alpha * 0.95),
              ],
              const [0.0, 0.32, 0.70, 1.0],
            ),
          shadows: [
            BoxShadow(
              color: const Color(0xFFFFE082).withValues(alpha: 0.85 * alpha * pulseGlow),
              blurRadius: fontSize * 0.35,
            ),
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.45 * alpha * pulseGlow),
              blurRadius: fontSize * 0.65,
            ),
            BoxShadow(
              color: const Color(0x66000000).withValues(alpha: 0.40 * alpha),
              offset: Offset(0, fontSize * 0.06),
              blurRadius: fontSize * 0.15,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(
      cx - textPainter.width * 0.5,
      cy - textPainter.height * 0.52,
    );
    textPainter.paint(canvas, textOffset);
  }

  /// Renders the 3D crystal-clear Glass Drink Bottle / Mystery Flask (`bình bí ẩn trong suốt`):
  /// - Soft ground shadow + 3D refractive crystal glass pedestal foot ring
  /// - Translucent clear-glass body allowing background to be visible through the flask
  /// - Glowing golden mystery '?' mark floating in the belly during gameplay (no color beforehand)
  /// - Thick rolled crystal-glass collar at the top with a recessed 3D oval mouth
  /// - Glossy curved left specular glass tube reflection (`sprTubeLight`) & right rim bounce (`sprTubeLight2`)
  void _drawStaticBasePot(Canvas canvas, double w, double h) {
    final isFillingOrFull = _fillProgress > 0.005;
    // When idle (Mystery Jar mode), use pristine transparent crystal glass palette with neutral tones.
    // When pouring/filling, smoothly blend into the winning liquid style!
    final styleBlend = isFillingOrFull
        ? Curves.easeOutQuad.transform((_fillProgress / 0.35).clamp(0.0, 1.0))
        : 0.0;

    final brightTop = Color.lerp(
      const Color(0xFFFFFFFF),
      Color.lerp(_style.topBright, Colors.white, 0.34)!,
      styleBlend,
    )!;
    final midColor = Color.lerp(
      const Color(0xFFCBEBFF),
      _style.topMid,
      styleBlend,
    )!;
    final deepShade = Color.lerp(
      const Color(0xFF0A1E36),
      Color.lerp(_style.bottomLip, const Color(0xFF061028), 0.48)!,
      styleBlend,
    )!;
    final glassRimLight = Color.lerp(
      const Color(0xFFE0F5FF),
      Color.lerp(_style.rimHighlight, const Color(0xFFD8F6FF), 0.55)!,
      styleBlend,
    )!;
    final darkOutline = Color.lerp(
      const Color(0xFF071424),
      Color.lerp(_style.bottomLip, const Color(0xFF040B1E), 0.52)!,
      styleBlend,
    )!;

    // 1. Soft Ground Drop Shadow beneath the Glass Bottle Base
    final shadowRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.930),
      width: w * 0.76,
      height: h * 0.080,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..color = const Color(0x5502061E)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.040),
    );

    // 2. 3D Refractive Glass Base Foot Ring (`y = 0.85..0.91 * h`)
    final baseFootRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.885),
        width: w * 0.74,
        height: h * 0.075,
      ),
      Radius.circular(h * 0.038),
    );
    canvas.drawRRect(
      baseFootRRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.15, h * 0.885),
          Offset(w * 0.85, h * 0.885),
          [
            deepShade.withValues(alpha: 0.50),
            midColor.withValues(alpha: 0.28),
            brightTop.withValues(alpha: 0.45),
            glassRimLight.withValues(alpha: 0.55),
            midColor.withValues(alpha: 0.28),
            deepShade.withValues(alpha: 0.50),
          ],
          const [0.0, 0.18, 0.38, 0.54, 0.78, 1.0],
        ),
    );
    canvas.drawRRect(
      baseFootRRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.018).clamp(1.2, 2.6)
        ..color = glassRimLight.withValues(alpha: 0.75),
    );

    // 3. Crystal-Clear 3D Glass Bottle Belly (100% transparent interior)
    final bellyPath = _buildPotBellyPath(w, h);

    canvas.drawPath(
      bellyPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.15, h * 0.25),
          Offset(w * 0.85, h * 0.88),
          [
            Colors.white.withValues(alpha: 0.14),
            glassRimLight.withValues(alpha: 0.08),
            const Color(0xFF0C2448).withValues(alpha: 0.12),
            const Color(0xFF06142E).withValues(alpha: 0.20),
          ],
          const [0.0, 0.35, 0.72, 1.0],
        ),
    );

    // 4. Mystery Jar '?' Emblem (visible during gameplay until water pours in!)
    final questionMarkAlpha = (1.0 - _fillProgress * 2.8).clamp(0.0, 1.0);
    if (questionMarkAlpha > 0.01) {
      _drawMysteryQuestionMark(
        canvas,
        w: w,
        h: h,
        alpha: questionMarkAlpha,
      );
    }

    // Glass wall highlights & collar (when idle)
    if (_fillProgress <= 0.005) {
      _drawGlassReflectionsCollarAndEmblem(
        canvas,
        w: w,
        h: h,
        bellyPath: bellyPath,
        brightTop: brightTop,
        midColor: midColor,
        deepShade: deepShade,
        glassRimLight: glassRimLight,
        darkOutline: darkOutline,
        isPouring: false,
        fillFraction: 0.0,
      );
    }
  }

  /// Draws the rolled crystal-glass collar & recessed mouth cavity (`y = 0.08..0.18 * h`).
  void _drawBottleCollarAndMouth(
    Canvas canvas, {
    required double w,
    required double h,
    required Color brightTop,
    required Color midColor,
    required Color deepShade,
    required Color glassRimLight,
    required Color darkOutline,
  }) {
    final outerRimRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.155),
      width: w * 0.52,
      height: h * 0.065,
    );
    canvas.drawOval(
      outerRimRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(outerRimRect.center.dx, outerRimRect.top),
          Offset(outerRimRect.center.dx, outerRimRect.bottom),
          [
            Colors.white.withValues(alpha: 0.90),
            glassRimLight.withValues(alpha: 0.85),
            midColor.withValues(alpha: 0.75),
            _style.bottomLip.withValues(alpha: 0.85),
          ],
          const [0.0, 0.30, 0.68, 1.0],
        ),
    );
    canvas.drawOval(
      outerRimRect.deflate(w * 0.012),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.020).clamp(1.4, 3.0)
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.drawOval(
      outerRimRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.018).clamp(1.2, 2.6)
        ..color = darkOutline.withValues(alpha: 0.75),
    );

    // Recessed 3D Inner Oval Glass Mouth Opening (`centerY = 0.155 * h`)
    final innerMouthRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.155),
      width: w * 0.36,
      height: h * 0.040,
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(innerMouthRect));
    canvas.drawRect(
      innerMouthRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(innerMouthRect.center.dx, innerMouthRect.top),
          Offset(innerMouthRect.center.dx, innerMouthRect.bottom),
          [
            deepShade,
            _style.bottomLip,
            midColor,
            brightTop,
          ],
          const [0.0, 0.38, 0.78, 1.0],
        ),
    );
    canvas.drawOval(
      innerMouthRect.translate(0, h * 0.008),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = h * 0.016
        ..color = Colors.white.withValues(alpha: 0.40),
    );
    canvas.restore();

    canvas.drawOval(
      innerMouthRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.015).clamp(1.0, 2.4)
        ..color = glassRimLight.withValues(alpha: 0.88),
    );
  }

  void _drawGlassReflectionsCollarAndEmblem(
    Canvas canvas, {
    required double w,
    required double h,
    required Path bellyPath,
    required Color brightTop,
    required Color midColor,
    required Color deepShade,
    required Color glassRimLight,
    required Color darkOutline,
    bool isPouring = false,
    double fillFraction = 0.32,
  }) {
    canvas.save();
    canvas.clipPath(bellyPath);

    // Soft cast shadow directly beneath the rolled glass collar onto the upper neck cylinder
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.190),
        width: w * 0.44,
        height: h * 0.040,
      ),
      Paint()..color = deepShade.withValues(alpha: isPouring ? 0.15 : 0.30),
    );

    // Left vertical glass reflection on the cylindrical neck
    final neckSpec = Rect.fromLTWH(w * 0.33, h * 0.165, w * 0.035, h * 0.095);
    canvas.drawRRect(
      RRect.fromRectAndRadius(neckSpec, Radius.circular(w * 0.015)),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Left glossy vertical curved glass tube reflection (`sprTubeLight` in `Bottle` `play_0.png`)
    final leftSpecPath = Path()
      ..moveTo(w * 0.17, h * 0.31)
      ..quadraticBezierTo(w * 0.09, h * 0.54, w * 0.19, h * 0.78)
      ..quadraticBezierTo(w * 0.13, h * 0.54, w * 0.23, h * 0.32)
      ..close();
    canvas.drawPath(
      leftSpecPath,
      Paint()..color = Colors.white.withValues(alpha: 0.68),
    );

    // Upper-left bright glass shoulder highlight dot
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.21, h * 0.32),
        width: w * 0.08,
        height: h * 0.046,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );

    // Right secondary glass tube bounce highlight (`sprTubeLight2`)
    final rightSpecPath = Path()
      ..moveTo(w * 0.83, h * 0.36)
      ..quadraticBezierTo(w * 0.89, h * 0.56, w * 0.81, h * 0.76);
    canvas.drawPath(
      rightSpecPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = w * 0.030
        ..color = glassRimLight.withValues(alpha: 0.58),
    );

    // Thick crystal glass bottom refraction curve
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.870),
        width: w * 0.65,
        height: h * 0.035,
      ),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.016).clamp(1.0, 2.2)
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    canvas.restore();

    // Crisp luminous glass outer rim (`outLine` in `play_0.png` & `play_2.png`)
    canvas.drawPath(
      bellyPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.024).clamp(1.6, 3.4)
        ..color = darkOutline.withValues(alpha: 0.70),
    );
    canvas.drawPath(
      bellyPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.015).clamp(1.0, 2.2)
        ..color = glassRimLight.withValues(alpha: 0.82),
    );

    if (!isPouring) {
      // Idle: draw the full rolled collar and recessed mouth on top of the empty neck
      _drawBottleCollarAndMouth(
        canvas,
        w: w,
        h: h,
        brightTop: brightTop,
        midColor: midColor,
        deepShade: deepShade,
        glassRimLight: glassRimLight,
        darkOutline: darkOutline,
      );
    } else {
      // Pouring (`play_0.png`): draw ONLY a translucent crystal-glass front collar lip & horizontal
      // glass refraction rings OVER the pouring water stream so the stream is 100% visible through the glass neck!
      final outerRimRect = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.155),
        width: w * 0.52,
        height: h * 0.065,
      );
      final innerMouthRect = Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.155),
        width: w * 0.36,
        height: h * 0.040,
      );
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, h * 0.155, w, h * 0.10));
      canvas.drawOval(
        outerRimRect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(outerRimRect.center.dx, h * 0.155),
            Offset(outerRimRect.center.dx, outerRimRect.bottom),
            [
              Colors.white.withValues(alpha: 0.36),
              glassRimLight.withValues(alpha: 0.28),
              _style.bottomLip.withValues(alpha: 0.24),
            ],
            const [0.0, 0.45, 1.0],
          ),
      );
      canvas.drawOval(
        outerRimRect.deflate(w * 0.012),
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (w * 0.018).clamp(1.2, 2.6)
          ..color = Colors.white.withValues(alpha: 0.75),
      );
      canvas.drawOval(
        innerMouthRect,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (w * 0.015).clamp(1.0, 2.2)
          ..color = Colors.white.withValues(alpha: 0.85),
      );
      canvas.restore();
    }
  }

  /// Draws a glossy 3D teardrop splash droplet (`wtd01` / `wtd02` in `com.chaos.drink.sort` `play_0.png`)
  /// with a pointed tail aimed toward `tailPt` and a plump rounded head centered at `headCenter`.
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

    // Glossy white curved highlight on the upper-outer dome of the teardrop (`play_0.png`)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(
          headCenter.dx + ux * headRadius * 0.25,
          headCenter.dy - headRadius * 0.28,
        ),
        width: headRadius * 1.05,
        height: headRadius * 0.55,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.82 * alpha),
    );
  }

  /// Renders the authentic `com.chaos.drink.sort` (`play_0.png` & `play_4.png`) liquid column inside the bottle:
  /// - Clean rising liquid body with 3D elliptical meniscus disc (`mat nuoc` / `hlWater` in `play_4.png`)
  /// - Lush S-curve sloshing wave crest (`play_0.png`) with curling left-wall splash tongue & sweeping white wave ribbon
  /// - Single unbroken vertical pouring water stream (`WaterSteam` in `play_0.png`) plunging straight down from
  ///   the open bottle mouth (`h * 0.232`) through the glass neck into the rising water surface, flaring out into a
  ///   wide curved liquid funnel base with a bright white crescent highlight and glossy 3D teardrop splash droplets!
  void _drawBottleLiquidColumn(
    Canvas canvas, {
    required double w,
    required double h,
    required Path bellyPath,
    required double fillFraction,
    required bool isPouring,
  }) {
    final clampedFill = fillFraction.clamp(0.0, 1.0);
    if (clampedFill <= 0.005) return;
    final baseY = h * 0.865;
    // Surface Y rises smoothly from the bottle base (`h * 0.865`) up to `0.28 * h` (`fill = 1.0`)
    final surfaceY = ui.lerpDouble(baseY, h * 0.28, clampedFill)!;

    final sloshAmp = isPouring
        ? h * (0.040 + 0.016 * math.sin(_animTime * 12.0).abs())
        : h * 0.009;
    final phase = isPouring ? (_animTime * 9.5) : (_animTime * 3.5);
    final tiltDy = isPouring
        ? math.sin(_animTime * 7.5) * h * 0.022
        : 0.0;

    final lightWater = Color.lerp(_style.topBright, Colors.white, 0.40)!;
    final meniscusColor = Color.lerp(_style.topBright, Colors.white, 0.50)!;
    final midWater = _style.topBright;
    final bodyWater = _style.topMid;
    final deepWater = _style.bottomLip;

    // --- PART A: Rising Liquid Body, 3D Meniscus Disc & S-Wave Surface (clipped to `bellyPath`) ---
    canvas.save();
    canvas.clipPath(bellyPath);

    // 1. Secondary Out-of-Phase Back Sloshing Wave (`surfaceWater2` / back rim of 3D meniscus)
    final backPhase = -phase * 1.12 + 1.2;
    final backAmp = sloshAmp * 0.85;
    final bLeftY =
        surfaceY - h * 0.022 - tiltDy * 0.5 + math.sin(backPhase) * backAmp;
    final bCtrl1Y =
        surfaceY - h * 0.032 + math.cos(backPhase + 0.6) * backAmp * 1.1;
    final bCtrl2Y =
        surfaceY - h * 0.032 - math.sin(backPhase + 0.4) * backAmp * 1.1;
    final bRightY =
        surfaceY - h * 0.022 + tiltDy * 0.5 - math.sin(backPhase) * backAmp;

    final backWavePath = Path()
      ..moveTo(0, bLeftY)
      ..cubicTo(
        w * 0.33,
        bCtrl1Y,
        w * 0.67,
        bCtrl2Y,
        w,
        bRightY,
      )
      ..lineTo(w, baseY + 10)
      ..lineTo(0, baseY + 10)
      ..close();

    canvas.drawPath(
      backWavePath,
      Paint()
        ..color =
            Color.lerp(_style.topBright, Colors.white, 0.34)!.withValues(alpha: 0.88),
    );

    // 2. Primary Sloshing Liquid Body (`mainWaterSingle` in `play_0.png` & `play_4.png`)
    // When pouring (`play_0.png`), the left & right walls surge upward while the front-right sweeps down in a lush S-wave!
    final double waveLeftY;
    final double waveCtrl1Y;
    final double waveCtrl2Y;
    final double waveRightY;
    if (isPouring) {
      final sWave = math.sin(phase) * sloshAmp * 0.35;
      waveLeftY = surfaceY - sloshAmp * 0.85 + sWave;
      waveCtrl1Y = surfaceY - sloshAmp * 0.25 + tiltDy;
      waveCtrl2Y = surfaceY + sloshAmp * 1.05 - tiltDy;
      waveRightY = surfaceY - sloshAmp * 0.55 - sWave;
    } else {
      waveLeftY = surfaceY + math.sin(_animTime * 3.5) * sloshAmp;
      waveCtrl1Y = surfaceY + math.sin(_animTime * 3.5 + 1.2) * sloshAmp;
      waveCtrl2Y = surfaceY - math.sin(_animTime * 3.5 + 1.2) * sloshAmp;
      waveRightY = surfaceY - math.sin(_animTime * 3.5) * sloshAmp;
    }

    final waterPath = Path()
      ..moveTo(0, waveLeftY)
      ..cubicTo(
        w * 0.34,
        waveCtrl1Y,
        w * 0.66,
        waveCtrl2Y,
        w,
        waveRightY,
      )
      ..lineTo(w, baseY + 10)
      ..lineTo(0, baseY + 10)
      ..close();

    canvas.drawPath(
      waterPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.15, surfaceY),
          Offset(w * 0.85, baseY),
          [
            Colors.white.withValues(alpha: 0.95),
            lightWater.withValues(alpha: 0.94),
            midWater.withValues(alpha: 0.92),
            bodyWater.withValues(alpha: 0.92),
            deepWater.withValues(alpha: 0.95),
          ],
          const [0.0, 0.12, 0.38, 0.72, 1.0],
        ),
    );

    // Subtle bottom bounce light inside the liquid
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.82),
        width: w * 0.72,
        height: h * 0.11,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.5, h * 0.76),
          Offset(w * 0.5, h * 0.87),
          [
            _style.topBright.withValues(alpha: 0.0),
            lightWater.withValues(alpha: 0.52),
          ],
        ),
    );

    // 3. 3D Elliptical Meniscus Surface (`mat nuoc` in `play_4.png`) & Sweeping S-Wave Ribbon (`play_0.png`)
    final meniscusBandH = isPouring ? h * 0.056 : h * 0.040;
    final meniscusRibbon = Path()
      ..moveTo(0, waveLeftY)
      ..cubicTo(
        w * 0.34,
        waveCtrl1Y,
        w * 0.66,
        waveCtrl2Y,
        w,
        waveRightY,
      )
      ..lineTo(w, waveRightY + meniscusBandH)
      ..cubicTo(
        w * 0.66,
        waveCtrl2Y + meniscusBandH * 1.18,
        w * 0.34,
        waveCtrl1Y + meniscusBandH * 1.18,
        0,
        waveLeftY + meniscusBandH,
      )
      ..close();

    canvas.drawPath(
      meniscusRibbon,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.15, surfaceY - meniscusBandH * 0.5),
          Offset(w * 0.85, surfaceY + meniscusBandH * 1.4),
          [
            Colors.white.withValues(alpha: 0.88),
            meniscusColor.withValues(alpha: 0.92),
            midWater.withValues(alpha: 0.18),
          ],
          const [0.0, 0.48, 1.0],
        ),
    );

    // Crisp white-tinted meniscus wave crest stroke (`play_0.png` S-wave highlight)
    final crestPath = Path()
      ..moveTo(w * 0.06, waveLeftY)
      ..cubicTo(
        w * 0.34,
        waveCtrl1Y,
        w * 0.66,
        waveCtrl2Y,
        w * 0.94,
        waveRightY,
      );
    canvas.drawPath(
      crestPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (w * 0.026).clamp(1.5, 3.2)
        ..color = Colors.white.withValues(alpha: 0.94),
    );

    // 4. Living Effervescent Water Bubbles rising inside the liquid (`play_0.png`)
    final bubbleCount = isPouring ? 20 : 12;
    for (int i = 0; i < bubbleCount; i++) {
      final seed = (i * 137.5) % 1.0;
      final bx = (w * 0.5) +
          (seed - 0.5) * w * 0.62 +
          math.sin(_animTime * 2.8 + i * 1.4) * w * 0.024;
      final speed = 0.18 + 0.07 * (i % 3);
      final bubbleT = ((_animTime * speed + i * (1.0 / bubbleCount)) % 1.0);
      final by = ui.lerpDouble(baseY - 4.0, surfaceY + 6.0, bubbleT)!;
      if (by < surfaceY + 2.0 || by > baseY) continue;
      final r = 1.8 + (i % 4) * 0.75;
      canvas.drawCircle(
        Offset(bx, by),
        r,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.52),
      );
      canvas.drawCircle(
        Offset(bx - r * 0.32, by - r * 0.32),
        r * 0.38,
        Paint()..color = Colors.white.withValues(alpha: 0.88),
      );
    }

    // 5. Twinkling Water Sparkles / Caustics (`play_0.png`)
    for (int k = 0; k < 4; k++) {
      final sx = (w * 0.28) + (k * 0.16) * w;
      final sy = ui.lerpDouble(surfaceY + 8.0, baseY - 8.0, (k + 1) * 0.20)!;
      final pulse =
          (0.5 + 0.5 * math.sin(_animTime * 4.5 + k * 1.8)).clamp(0.0, 1.0);
      final starR = 2.0 + 1.8 * pulse;
      final starPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.75 * pulse);
      canvas.drawLine(
        Offset(sx - starR, sy),
        Offset(sx + starR, sy),
        starPaint..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(sx, sy - starR),
        Offset(sx, sy + starR),
        starPaint..strokeWidth = 1.0,
      );
    }

    canvas.restore();

    // --- PART B: Continuous Plunging Water Stream, Flared Funnel Base & 3D Teardrop Splashes (`play_0.png`) ---
    // Clipped to `_buildPotNeckAndBellyClipPath` so the stream starts right at the open mouth (`h * 0.125`),
    // passes seamlessly through the bottle neck (`0.125..0.255 * h`), and plunges into `surfaceY`!
    if (isPouring && fillFraction < 0.97) {
      final streamFade = ((0.97 - fillFraction) / 0.09).clamp(0.0, 1.0);
      // As the external stream tail finishes entering the mouth (`fillFraction > 0.86`),
      // the top of the interior stream drops smoothly from the mouth (`h * 0.125`) into `surfaceY`.
      final tailDropT = ((fillFraction - 0.86) / 0.11).clamp(0.0, 1.0);
      final streamTopY = ui.lerpDouble(h * 0.155, surfaceY, tailDropT)!;
      final streamBotY = surfaceY + h * 0.018;

      if (streamBotY > streamTopY + 3.0) {
        canvas.save();
        canvas.clipPath(_buildPotNeckAndBellyClipPath(w, h));

        final cx = w * 0.5;
        final breathe = 1.0 + 0.035 * math.sin(_animTime * 18.0);
        // Smooth laminar stream width matching `BoardSandStreamToJarVfx` at the mouth (`w * 0.088`),
        // narrowing slightly in the upper belly (`w * 0.066`), and flaring into a wide curved liquid
        // trumpet/funnel base (`w * 0.215`) where it meets the water surface (`play_0.png`)!
        final topHalfW = w * 0.088 * breathe;
        final waistHalfW = w * 0.065 * breathe;
        final funnelHalfW = w * (0.215 + 0.020 * math.cos(_animTime * 16.0));
        final waistY = ui.lerpDouble(streamTopY, streamBotY, 0.54)!;
        final funnelStartY = ui.lerpDouble(streamTopY, streamBotY, 0.76)!;

        // 1. Plunging Stream + Flared Funnel Silhouette (`play_0.png`)
        final streamFunnelPath = Path()
          ..moveTo(cx - topHalfW, streamTopY)
          ..cubicTo(
            cx - topHalfW * 0.92,
            ui.lerpDouble(streamTopY, waistY, 0.5)!,
            cx - waistHalfW,
            waistY,
            cx - waistHalfW * 1.12,
            funnelStartY,
          )
          ..quadraticBezierTo(
            cx - waistHalfW * 1.35,
            streamBotY - h * 0.010,
            cx - funnelHalfW,
            streamBotY,
          )
          ..quadraticBezierTo(
            cx,
            streamBotY + h * 0.042,
            cx + funnelHalfW,
            streamBotY,
          )
          ..quadraticBezierTo(
            cx + waistHalfW * 1.35,
            streamBotY - h * 0.010,
            cx + waistHalfW * 1.12,
            funnelStartY,
          )
          ..cubicTo(
            cx + waistHalfW,
            waistY,
            cx + topHalfW * 0.92,
            ui.lerpDouble(streamTopY, waistY, 0.5)!,
            cx + topHalfW,
            streamTopY,
          )
          ..close();

        canvas.drawPath(
          streamFunnelPath,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(cx - funnelHalfW * 0.85, streamTopY),
              Offset(cx + funnelHalfW * 0.85, streamBotY),
              [
                deepWater.withValues(alpha: 0.94 * streamFade),
                midWater.withValues(alpha: 0.98 * streamFade),
                lightWater.withValues(alpha: 0.98 * streamFade),
                midWater.withValues(alpha: 0.96 * streamFade),
                deepWater.withValues(alpha: 0.92 * streamFade),
              ],
              const [0.0, 0.22, 0.48, 0.78, 1.0],
            ),
        );

        // 2. Continuous Vertical White Specular Highlight Ribbon down the stream into the Flared Funnel (`play_0.png`)
        final specLeftTop = cx - topHalfW * 0.34;
        final specRightTop = cx - topHalfW * 0.04;
        final specLeftWaist = cx - waistHalfW * 0.32;
        final specRightWaist = cx - waistHalfW * 0.02;
        final specFunnelLeft = cx - funnelHalfW * 0.52;
        final specFunnelRight = cx + funnelHalfW * 0.12;

        final streamSpecPath = Path()
          ..moveTo(specLeftTop, streamTopY)
          ..lineTo(specLeftWaist, funnelStartY)
          ..quadraticBezierTo(
            cx - waistHalfW * 0.65,
            streamBotY - h * 0.005,
            specFunnelLeft,
            streamBotY + h * 0.004,
          )
          ..quadraticBezierTo(
            cx - funnelHalfW * 0.18,
            streamBotY + h * 0.028,
            specFunnelRight,
            streamBotY + h * 0.006,
          )
          ..quadraticBezierTo(
            cx - waistHalfW * 0.10,
            streamBotY - h * 0.008,
            specRightWaist,
            funnelStartY,
          )
          ..lineTo(specRightTop, streamTopY)
          ..close();

        canvas.drawPath(
          streamSpecPath,
          Paint()..color = Colors.white.withValues(alpha: 0.88 * streamFade),
        );

        // 3. Concentric White Crescent Impact Ripple at the Funnel Base (`toaa` / `tron` in `play_0.png`)
        final ripplePhase = (_animTime * 3.2) % 1.0;
        final rippleW = funnelHalfW * (1.05 + 0.55 * ripplePhase);
        final rippleH = h * (0.028 + 0.018 * ripplePhase);
        final rippleAlpha =
            (math.sin(ripplePhase * math.pi) * 0.78 * streamFade).clamp(0.0, 1.0);
        if (rippleAlpha > 0.02) {
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx, streamBotY + h * 0.008),
              width: rippleW * 2.0,
              height: rippleH * 2.0,
            ),
            Paint()
              ..style = ui.PaintingStyle.stroke
              ..strokeWidth = (w * 0.022).clamp(1.2, 2.8)
              ..color = Colors.white.withValues(alpha: rippleAlpha),
          );
        }

        // 4. Glossy 3D Teardrop Splash Droplets (`wtd01`, `wtd02` in `play_0.png`)
        // Only show when there is headroom above `surfaceY` inside the bottle belly (`surfaceY > h * 0.40`).
        final splashRoom = ((surfaceY - h * 0.36) / (h * 0.16)).clamp(0.0, 1.0);
        final dropAlpha = streamFade * splashRoom;
        if (dropAlpha > 0.04) {
          final pulseL = 0.88 + 0.16 * math.sin(_animTime * 14.0);
          final pulseR = 0.88 + 0.16 * math.cos(_animTime * 14.0 + 0.8);

          // Left 3D Teardrop Splash (`play_0.png` left droplet)
          _drawGlossyTeardropSplash(
            canvas,
            tailPt: Offset(cx - w * 0.14, surfaceY - h * 0.042 * pulseL),
            headCenter: Offset(cx - w * 0.21, surfaceY - h * 0.095 * pulseL),
            headRadius: w * 0.044,
            lightColor: lightWater,
            midColor: midWater,
            deepColor: deepWater,
            alpha: dropAlpha,
          );

          // Left Curling Wave Splash Tongue (`play_0.png` far-left wave lip)
          _drawGlossyTeardropSplash(
            canvas,
            tailPt: Offset(cx - w * 0.18, surfaceY + h * 0.005),
            headCenter: Offset(cx - w * 0.31, surfaceY - h * 0.055 * pulseL),
            headRadius: w * 0.036,
            lightColor: lightWater,
            midColor: midWater,
            deepColor: deepWater,
            alpha: dropAlpha * 0.92,
          );

          // Right Large 3D Teardrop Splash (`play_0.png` right droplet)
          _drawGlossyTeardropSplash(
            canvas,
            tailPt: Offset(cx + w * 0.11, surfaceY - h * 0.048 * pulseR),
            headCenter: Offset(cx + w * 0.185, surfaceY - h * 0.112 * pulseR),
            headRadius: w * 0.052,
            lightColor: lightWater,
            midColor: midWater,
            deepColor: deepWater,
            alpha: dropAlpha,
          );

          // Right Secondary Round Splash Bead (`play_0.png` lower-right droplet)
          final beadCenter =
              Offset(cx + w * 0.255, surfaceY - h * 0.038 * pulseR);
          final beadR = w * 0.026;
          canvas.drawCircle(
            beadCenter,
            beadR,
            Paint()..color = midWater.withValues(alpha: dropAlpha),
          );
          canvas.drawCircle(
            Offset(beadCenter.dx - beadR * 0.25, beadCenter.dy - beadR * 0.28),
            beadR * 0.42,
            Paint()..color = Colors.white.withValues(alpha: 0.85 * dropAlpha),
          );
        }

        canvas.restore();
      }
    }
  }

  /// Combined Neck + Belly clip path starting from the open bottle mouth (`y = 0.120 * h`)
  /// so the interior pouring stream flows continuously through the glass neck into the belly!
  Path _buildPotNeckAndBellyClipPath(double w, double h) {
    final cx = w * 0.5;
    final neckHalfW = w * 0.20;
    final shoulderHalfW = w * 0.26;
    final bellyHalfW = w * 0.44;
    final baseHalfW = w * 0.33;

    final neckTopY = h * 0.155;
    final neckBotY = h * 0.260;
    final shoulderBotY = h * 0.360;
    final bellyMidY = h * 0.580;
    final baseY = h * 0.880;

    return Path()
      ..moveTo(cx - neckHalfW, neckTopY)
      ..lineTo(cx + neckHalfW, neckTopY)
      ..lineTo(cx + neckHalfW, neckBotY)
      ..quadraticBezierTo(
        cx + shoulderHalfW,
        (neckBotY + shoulderBotY) * 0.5,
        cx + bellyHalfW,
        shoulderBotY,
      )
      ..cubicTo(
        cx + bellyHalfW * 1.02,
        bellyMidY * 0.85,
        cx + bellyHalfW * 1.02,
        bellyMidY * 1.15,
        cx + baseHalfW,
        baseY,
      )
      ..quadraticBezierTo(
        cx,
        baseY + h * 0.025,
        cx - baseHalfW,
        baseY,
      )
      ..cubicTo(
        cx - bellyHalfW * 1.02,
        bellyMidY * 1.15,
        cx - bellyHalfW * 1.02,
        bellyMidY * 0.85,
        cx - bellyHalfW,
        shoulderBotY,
      )
      ..quadraticBezierTo(
        cx - shoulderHalfW,
        (neckBotY + shoulderBotY) * 0.5,
        cx - neckHalfW,
        neckBotY,
      )
      ..close();
  }

  Path _buildPotBellyPath(double w, double h) {
    return _buildPotNeckAndBellyClipPath(w, h);
  }

  /// Draws the embossed 3D Faceted Golden 4-Pointed Star Emblem on the front of the bottle
  /// (and ascending when the bottle opens).
  void _draw3DFacetedGoldStarEmblem(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required double glowBoost,
  }) {
    final outerR = radius;
    final innerR = radius * 0.42;

    final topPt = Offset(center.dx, center.dy - outerR);
    final rightPt = Offset(center.dx + outerR * 1.04, center.dy);
    final botPt = Offset(center.dx, center.dy + outerR);
    final leftPt = Offset(center.dx - outerR * 1.04, center.dy);

    final trIn = Offset(center.dx + innerR, center.dy - innerR);
    final brIn = Offset(center.dx + innerR, center.dy + innerR);
    final blIn = Offset(center.dx - innerR, center.dy + innerR);
    final tlIn = Offset(center.dx - innerR, center.dy - innerR);

    final starOutline = Path()
      ..moveTo(topPt.dx, topPt.dy)
      ..lineTo(trIn.dx, trIn.dy)
      ..lineTo(rightPt.dx, rightPt.dy)
      ..lineTo(brIn.dx, brIn.dy)
      ..lineTo(botPt.dx, botPt.dy)
      ..lineTo(blIn.dx, blIn.dy)
      ..lineTo(leftPt.dx, leftPt.dy)
      ..lineTo(tlIn.dx, tlIn.dy)
      ..close();

    // Recessed drop shadow on the glass belly under the golden star
    canvas.drawPath(
      starOutline.shift(Offset(0, radius * 0.10)),
      Paint()..color = const Color(0x55000000),
    );

    // 4 3D beveled quadrants around `center` for crisp metallic gold look
    final topLeftQuad = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(leftPt.dx, leftPt.dy)
      ..lineTo(tlIn.dx, tlIn.dy)
      ..lineTo(topPt.dx, topPt.dy)
      ..close();
    final topRightQuad = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(topPt.dx, topPt.dy)
      ..lineTo(trIn.dx, trIn.dy)
      ..lineTo(rightPt.dx, rightPt.dy)
      ..close();
    final botRightQuad = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(rightPt.dx, rightPt.dy)
      ..lineTo(brIn.dx, brIn.dy)
      ..lineTo(botPt.dx, botPt.dy)
      ..close();
    final botLeftQuad = Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(botPt.dx, botPt.dy)
      ..lineTo(blIn.dx, blIn.dy)
      ..lineTo(leftPt.dx, leftPt.dy)
      ..close();

    final facetPaint = Paint()..style = ui.PaintingStyle.fill;
    facetPaint.color = const Color(0xFFFFF59D);
    canvas.drawPath(topLeftQuad, facetPaint);
    facetPaint.color = const Color(0xFFFFD53D);
    canvas.drawPath(topRightQuad, facetPaint);
    facetPaint.color = const Color(0xFFF09D18);
    canvas.drawPath(botLeftQuad, facetPaint);
    facetPaint.color = const Color(0xFFC67106);
    canvas.drawPath(botRightQuad, facetPaint);

    // Subtle warm bronze outer rim around the golden star
    canvas.drawPath(
      starOutline,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (radius * 0.10).clamp(1.0, 2.2)
        ..strokeJoin = ui.StrokeJoin.round
        ..color = const Color(0xFF8C4800),
    );

    if (glowBoost > 0.02) {
      canvas.drawCircle(
        center,
        radius * (1.1 + 0.4 * glowBoost),
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..color = const Color(0xFFFFEE58)
              .withValues(alpha: (0.48 * glowBoost).clamp(0.0, 0.85)),
      );
    }
  }

  /// Draws the rising sloshing liquid column (`WaterUpController` + `FakeWater`)
  /// inside the crystal-clear glass bottle as `fill` (`0..1`) increases (`play_0.png` style):
  /// 1. Back rolled glass collar & recessed mouth cavity (drawn BEHIND the pouring stream!)
  /// 2. Rising water column, 3D meniscus, S-wave crest, plunging water stream funnel & 3D teardrop splashes
  /// 3. Foreground glass tube reflections & translucent front glass collar lip!
  void _drawRisingConicalSandMound(
    Canvas canvas,
    double w,
    double h,
    double fill,
  ) {
    final easedFill = Curves.easeOutCubic.transform(fill.clamp(0.0, 1.0));
    final effectiveFill = easedFill.clamp(0.0, 1.0);
    final bellyPath = _buildPotBellyPath(w, h);

    final brightTop = Color.lerp(_style.topBright, Colors.white, 0.34)!;
    final midColor = _style.topMid;
    final deepShade = Color.lerp(_style.bottomLip, const Color(0xFF061028), 0.48)!;
    final glassRimLight = Color.lerp(_style.rimHighlight, const Color(0xFFD8F6FF), 0.55)!;
    final darkOutline = Color.lerp(_style.bottomLip, const Color(0xFF040B1E), 0.52)!;

    // 1. Draw the rolled collar & recessed mouth cavity BEHIND the pouring water stream
    _drawBottleCollarAndMouth(
      canvas,
      w: w,
      h: h,
      brightTop: brightTop,
      midColor: midColor,
      deepShade: deepShade,
      glassRimLight: glassRimLight,
      darkOutline: darkOutline,
    );

    // 2. Draw the rising sloshing water column, S-wave crest, plunging stream funnel & 3D teardrop splashes
    _drawBottleLiquidColumn(
      canvas,
      w: w,
      h: h,
      bellyPath: bellyPath,
      fillFraction: effectiveFill,
      isPouring: true,
    );

    // 3. Overlay the foreground glass bottle reflections & translucent front glass collar lip
    _drawGlassReflectionsCollarAndEmblem(
      canvas,
      w: w,
      h: h,
      bellyPath: bellyPath,
      brightTop: brightTop,
      midColor: midColor,
      deepShade: deepShade,
      glassRimLight: glassRimLight,
      darkOutline: darkOutline,
      isPouring: true,
      fillFraction: effectiveFill,
    );

    // 4. Luminous liquid glow inside the glass belly as water fills up
    final bellyGlowAlpha = (0.38 * easedFill + 0.28 * _glowIntensity).clamp(0.0, 0.68);
    if (bellyGlowAlpha > 0.01) {
      canvas.drawCircle(
        Offset(w * 0.5, h * 0.56),
        w * 0.36,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset(w * 0.5, h * 0.56),
            w * 0.36,
            [
              _style.rimHighlight.withValues(alpha: bellyGlowAlpha),
              _style.topBright.withValues(alpha: 0.0),
            ],
          ),
      );
    }
  }

  void _drawOuterAuraAndGodRays(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.5, h * 0.52);
    final popAura = (_appearProgress > 0.01 && _appearProgress < 1.0)
        ? math.sin(_appearProgress * math.pi) * 0.65
        : 0.0;
    final auraIntensity =
        math.max(math.max(_glowIntensity, _openProgress), popAura).clamp(0.0, 1.0);
    final auraRadius = w * (0.62 + 0.38 * auraIntensity + 0.26 * _openProgress);

    canvas.drawCircle(
      center,
      auraRadius,
      Paint()
        ..blendMode = ui.BlendMode.plus
        ..shader = ui.Gradient.radial(
          center,
          auraRadius,
          [
            _style.rimHighlight.withValues(alpha: 0.72 * auraIntensity),
            _style.topBright.withValues(alpha: 0.42 * auraIntensity),
            _style.accent.withValues(alpha: 0.0),
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
            _style.topBright.withValues(alpha: 0.65 * auraIntensity),
            ui.BlendMode.modulate,
          ),
      );
    }

    if (_glowIntensity > 0.35 || _openProgress > 0.01) {
      final rayAlpha =
          ((_glowIntensity - 0.35) / 0.65 + _openProgress).clamp(0.0, 1.0);
      final mouthCenter = Offset(w * 0.5, h * 0.155);
      final rayOrigin = _openProgress > 0.05 ? mouthCenter : center;
      const rayCount = 8;
      final rayLen = w * (0.55 + 0.45 * _openProgress);
      final halfW = w * 0.068;
      final rayPaint = Paint()
        ..blendMode = ui.BlendMode.plus
        ..color = _style.rimHighlight.withValues(alpha: 0.48 * rayAlpha);

      _scratchPath
        ..reset()
        ..moveTo(0, 0)
        ..lineTo(-halfW, -rayLen)
        ..lineTo(halfW, -rayLen)
        ..close();

      for (int i = 0; i < rayCount; i++) {
        final angle = _animTime * 1.8 + (i * math.pi * 2.0 / rayCount);
        canvas.save();
        canvas.translate(rayOrigin.dx, rayOrigin.dy);
        canvas.rotate(angle);
        canvas.drawPath(_scratchPath, rayPaint);
        canvas.restore();
      }
    }
  }
}

/// Step 1 VFX (`1. merge thành công số cuối cùng. Tile cuối phát sáng, scale lớn nhẹ và tạo hiệu ứng nổ ánh sáng`):
/// Expanding shockwave halo, rotating light rays, and radial burst of glowing particles from the final tile.
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

    // 1. Expanding radial light flash & shockwave ring
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
            style.topBright.withValues(alpha: 0.55 * fade),
            style.accent.withValues(alpha: 0.0),
          ],
          const [0.0, 0.45, 1.0],
        ),
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
            style.rimHighlight.withValues(alpha: 0.85 * fade),
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
            style.topBright.withValues(alpha: 0.72 * fade),
            ui.BlendMode.modulate,
          ),
      );
    }

    // 2. Hardware-batched radial light sparks
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

        final c = useAccent ? style.rimHighlight : style.topBright;
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

/// Step 2 VFX (`com.chaos.drink.sort` Single Continuous Pouring Water Stream `WaterSteam` / `play_0.png` to Bottle):
/// - Strictly ONE single smooth, glossy, laminar stream of water (`1 dòng nước thôi`)!
/// - Rises smoothly from `finalTileCenter`, arches over an apex above the bottle mouth, and POURS
///   STRAIGHT DOWN vertically (`đổ nước`) into the open bottle mouth (`targetMouth`), seamlessly joining
///   the interior plunging water stream and flared funnel splash inside the bottle!
class BoardSandStreamToJarVfx extends PositionComponent {
  final Vector2 finalTileCenter;
  final BlockColorStyle style;
  final Vector2 Function() targetMouthProvider;
  final double cellSize;
  double _elapsed = 0.0;
  final double _totalDuration = 1.36;
  late final double _archSideSign;

  final Path _outerStreamPath = Path();
  final Path _coreStreamPath = Path();
  final Path _specularStripePath = Path();

  BoardSandStreamToJarVfx({
    required this.finalTileCenter,
    required List<Vector2> boardOrigins,
    required this.targetMouthProvider,
    required this.style,
    required this.cellSize,
  }) : super(priority: 125) {
    assert(boardOrigins.isNotEmpty || finalTileCenter.length >= 0);
    final target = targetMouthProvider();
    final dxToMouth = finalTileCenter.x - target.x;
    _archSideSign = dxToMouth.abs() > cellSize * 0.20
        ? (dxToMouth >= 0 ? 1.0 : -1.0)
        : -1.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt.clamp(0.0, 0.05);
    if (_elapsed >= _totalDuration) {
      removeFromParent();
    }
  }

  /// Evaluates a point and unit normal on the cubic Bezier pouring arc at parameter `u` (`0..1`).
  /// Uses a clean, sleek laminar trajectory that arches above `end` (`targetMouth`) and enters
  /// `end` vertically downward (`dx = 0, dy > 0`) just like `play_0.png`!
  (Offset pos, Offset normal) _sampleLaminarPourCurve({
    required Vector2 start,
    required Vector2 ctrl1,
    required Vector2 ctrl2,
    required Vector2 end,
    required double u,
  }) {
    final c = u.clamp(0.0, 1.0);
    final om = 1.0 - c;
    final om2 = om * om;
    final om3 = om2 * om;
    final c2 = c * c;
    final c3 = c2 * c;

    final bx = om3 * start.x +
        3.0 * om2 * c * ctrl1.x +
        3.0 * om * c2 * ctrl2.x +
        c3 * end.x;
    final by = om3 * start.y +
        3.0 * om2 * c * ctrl1.y +
        3.0 * om * c2 * ctrl2.y +
        c3 * end.y;

    // Derivative for tangent & unit normal
    final tx = 3.0 * om2 * (ctrl1.x - start.x) +
        6.0 * om * c * (ctrl2.x - ctrl1.x) +
        3.0 * c2 * (end.x - ctrl2.x);
    final ty = 3.0 * om2 * (ctrl1.y - start.y) +
        6.0 * om * c * (ctrl2.y - ctrl1.y) +
        3.0 * c2 * (end.y - ctrl2.y);
    final tLen = math.max(1e-3, math.sqrt(tx * tx + ty * ty));
    final nx = -ty / tLen;
    final ny = tx / tLen;

    // Subtle laminar flow breathing (zero high-frequency wriggling)
    final archEnv = math.sin(c * math.pi) * (1.0 - c * 0.65);
    final gentleSway =
        math.sin(c * 5.0 - _elapsed * 14.0) * cellSize * 0.012 * archEnv;

    return (
      Offset(bx + nx * gentleSway, by + ny * gentleSway),
      Offset(nx, ny),
    );
  }

  void _drawSingleLaminarPourStream({
    required Canvas canvas,
    required Vector2 start,
    required Vector2 ctrl1,
    required Vector2 ctrl2,
    required Vector2 end,
    required double tailT,
    required double headT,
  }) {
    final span = headT - tailT;
    if (span <= 0.015) return;

    const int steps = 40;
    final leftOuter = <Offset>[];
    final rightOuter = <Offset>[];
    final leftCore = <Offset>[];
    final rightCore = <Offset>[];
    final leftSpec = <Offset>[];
    final rightSpec = <Offset>[];

    for (int i = 0; i <= steps; i++) {
      final localFrac = i / steps;
      final u = tailT + span * localFrac;

      final (pt, norm) = _sampleLaminarPourCurve(
        start: start,
        ctrl1: ctrl1,
        ctrl2: ctrl2,
        end: end,
        u: u,
      );

      final headTaper = (headT < 0.96 && localFrac > 0.84)
          ? math.sin(((1.0 - localFrac) / 0.16) * (math.pi * 0.5)).clamp(0.18, 1.0)
          : 1.0;
      final tailTaper = (tailT > 0.02 && localFrac < 0.20)
          ? math.sin((localFrac / 0.20) * (math.pi * 0.5)).clamp(0.12, 1.0)
          : 1.0;
      final endEnvelope = headTaper * tailTaper;

      // Rayleigh undulating waves along the stream
      final waveBreathe = 1.0 + 0.035 * math.sin(u * 10.0 - _elapsed * 20.0);

      // Base width at block is wide (to), smoothly tapering down to slender stream (nhỏ dần)
      // at the jar mouth as in user sketch media_1793872153515.png!
      final baseHalfW = cellSize * 0.45;
      final mouthHalfW = cellSize * 0.082;
      final taperU = math.pow(u.clamp(0.0, 1.0), 0.68).toDouble();
      final halfW = ui.lerpDouble(baseHalfW, mouthHalfW, taperU)! *
          waveBreathe *
          endEnvelope;

      final outerW = halfW * 1.15;
      leftOuter.add(pt + norm * outerW);
      rightOuter.add(pt - norm * outerW);

      leftCore.add(pt + norm * (halfW * 0.86));
      rightCore.add(pt - norm * (halfW * 0.86));

      // Specular highlight stripe along the upper crest of the water arc
      final specCenter = pt + norm * (halfW * 0.35);
      final specHalfW = halfW * 0.18;
      leftSpec.add(specCenter + norm * specHalfW);
      rightSpec.add(specCenter - norm * specHalfW);
    }

    void buildRibbonPath(Path path, List<Offset> leftPts, List<Offset> rightPts) {
      path.reset();
      if (leftPts.isEmpty) return;
      path.moveTo(leftPts.first.dx, leftPts.first.dy);
      for (int i = 1; i < leftPts.length; i++) {
        path.lineTo(leftPts[i].dx, leftPts[i].dy);
      }
      for (int i = rightPts.length - 1; i >= 0; i--) {
        path.lineTo(rightPts[i].dx, rightPts[i].dy);
      }
      path.close();
    }

    buildRibbonPath(_outerStreamPath, leftOuter, rightOuter);
    buildRibbonPath(_coreStreamPath, leftCore, rightCore);
    buildRibbonPath(_specularStripePath, leftSpec, rightSpec);

    final brightLiquid = Color.lerp(style.topBright, Colors.white, 0.42)!;

    // 1. Refractive outer fluid glow envelope (soft blurred translucency)
    canvas.drawPath(
      _outerStreamPath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..color = style.topMid.withValues(alpha: 0.50)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, (cellSize * 0.035).clamp(1.5, 4.2)),
    );

    // 2. Saturated translucent liquid stream body (`play_0.png`)
    canvas.drawPath(
      _coreStreamPath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..shader = ui.Gradient.linear(
          Offset(start.x, start.y),
          Offset(end.x, end.y),
          [
            style.topBright.withValues(alpha: 0.88),
            brightLiquid.withValues(alpha: 0.94),
            style.topMid.withValues(alpha: 0.90),
            style.bottomLip.withValues(alpha: 0.85),
          ],
          const [0.0, 0.40, 0.75, 1.0],
        ),
    );

    // 3. Continuous glossy white specular reflection ribbon along the stream
    canvas.drawPath(
      _specularStripePath,
      Paint()
        ..style = ui.PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    // 4. Shimmering traveling caustic light beads zipping along the stream toward the bottle mouth!
    for (int k = 0; k < 4; k++) {
      final beadFrac = ((_elapsed * 2.2 + k * 0.25) % 1.0);
      final u = tailT + span * beadFrac;
      if (u <= tailT + 0.03 || u >= headT - 0.03) continue;
      final (pt, norm) = _sampleLaminarPourCurve(
        start: start,
        ctrl1: ctrl1,
        ctrl2: ctrl2,
        end: end,
        u: u,
      );
      final beadPos = pt + norm * (cellSize * 0.02);
      final beadW = (cellSize * 0.08).clamp(2.5, 9.0);
      final beadH = (cellSize * 0.035).clamp(1.5, 4.5);
      final beadAlpha = (math.sin(beadFrac * math.pi) * 0.88).clamp(0.0, 1.0);
      canvas.drawOval(
        Rect.fromCenter(center: beadPos, width: beadW, height: beadH),
        Paint()..color = Colors.white.withValues(alpha: beadAlpha),
      );
    }
  }

  /// Draws 10 glossy water droplets flying along the trajectory alongside the stream (`play_0.png`).
  void _drawFlyingWaterDroplets({
    required Canvas canvas,
    required Vector2 start,
    required Vector2 ctrl1,
    required Vector2 ctrl2,
    required Vector2 end,
    required double tailT,
    required double headT,
  }) {
    final span = headT - tailT;
    if (span <= 0.05) return;

    const int dropletCount = 10;
    final brightLiquid = Color.lerp(style.topBright, Colors.white, 0.42)!;

    for (int i = 0; i < dropletCount; i++) {
      final speed = 1.35 + 0.25 * (i % 3);
      final phase = ((_elapsed * speed + i * (1.0 / dropletCount)) % 1.0);
      final u = tailT + span * phase;
      if (u <= tailT + 0.02 || u >= headT - 0.02) continue;

      final (pt, norm) = _sampleLaminarPourCurve(
        start: start,
        ctrl1: ctrl1,
        ctrl2: ctrl2,
        end: end,
        u: u,
      );

      final sideSign = (i % 2 == 0) ? 1.0 : -1.0;
      final localStreamW = ui.lerpDouble(cellSize * 0.45, cellSize * 0.082, math.pow(u, 0.68).toDouble())!;
      final lateralDist = localStreamW + cellSize * (0.024 + 0.016 * ((i * 7) % 3));
      final dropCenter = pt + norm * (sideSign * lateralDist);

      final r = (ui.lerpDouble(cellSize * 0.038, cellSize * 0.018, u)! * (0.85 + 0.30 * (i % 3))).clamp(1.6, 5.5);
      final alpha = (math.sin(phase * math.pi) * 0.92).clamp(0.0, 1.0);

      canvas.drawCircle(
        dropCenter,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            dropCenter,
            r,
            [
              brightLiquid.withValues(alpha: alpha * 0.95),
              style.topBright.withValues(alpha: alpha * 0.90),
              style.bottomLip.withValues(alpha: alpha * 0.70),
            ],
            const [0.0, 0.65, 1.0],
          ),
      );
      canvas.drawCircle(
        Offset(dropCenter.dx - r * 0.32, dropCenter.dy - r * 0.32),
        r * 0.38,
        Paint()..color = Colors.white.withValues(alpha: alpha * 0.94),
      );
    }
  }

  /// Draws the liquid pool and upward water eruption vortex at `finalTileCenter` while draining.
  void _drawSourceBlockLiquidPool(Canvas canvas, double tailT) {
    if (tailT >= 0.75) return;
    final env = ((0.75 - tailT) / 0.75).clamp(0.0, 1.0);
    final rx = cellSize * (0.35 + 0.15 * env);
    final ry = rx * 0.62;
    final poolRect = Rect.fromCenter(
      center: Offset(finalTileCenter.x, finalTileCenter.y),
      width: rx * 2.0,
      height: ry * 2.0,
    );

    final brightWater = Color.lerp(style.topBright, Colors.white, 0.45)!;

    // 1. Concentric water ripples
    canvas.drawOval(
      poolRect,
      Paint()
        ..shader = ui.Gradient.radial(
          poolRect.center,
          rx,
          [
            brightWater.withValues(alpha: 0.85 * env),
            style.topBright.withValues(alpha: 0.75 * env),
            style.bottomLip.withValues(alpha: 0.0),
          ],
          const [0.0, 0.62, 1.0],
        ),
    );
    canvas.drawOval(
      poolRect.deflate(rx * 0.18),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.032 * env).clamp(1.2, 3.0)
        ..color = Colors.white.withValues(alpha: 0.82 * env),
    );
    // Outer ripple ring
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(finalTileCenter.x, finalTileCenter.y),
        width: rx * 2.6,
        height: ry * 2.6,
      ),
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.020 * env).clamp(1.0, 2.2)
        ..color = style.rimHighlight.withValues(alpha: 0.60 * env),
    );

    // 2. Upward water spout cone lifting off the block into the stream
    final spoutTopY = finalTileCenter.y - cellSize * 0.32 * env;
    final spoutHalfW = cellSize * 0.42 * env;
    final spoutPath = Path()
      ..moveTo(finalTileCenter.x - rx * 0.85, finalTileCenter.y)
      ..quadraticBezierTo(
        finalTileCenter.x - rx * 0.45,
        finalTileCenter.y - cellSize * 0.16 * env,
        finalTileCenter.x - spoutHalfW,
        spoutTopY,
      )
      ..lineTo(finalTileCenter.x + spoutHalfW, spoutTopY)
      ..quadraticBezierTo(
        finalTileCenter.x + rx * 0.45,
        finalTileCenter.y - cellSize * 0.16 * env,
        finalTileCenter.x + rx * 0.85,
        finalTileCenter.y,
      )
      ..close();

    canvas.drawPath(
      spoutPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(finalTileCenter.x, finalTileCenter.y),
          Offset(finalTileCenter.x, spoutTopY),
          [
            style.topMid.withValues(alpha: 0.75 * env),
            brightWater.withValues(alpha: 0.90 * env),
          ],
        ),
    );

    // 3. Splash droplets bursting upward from the source block
    for (int s = 0; s < 5; s++) {
      final angle = -math.pi * 0.5 + (s - 2) * 0.38;
      final dist = cellSize * (0.14 + 0.16 * math.sin(_elapsed * 12.0 + s).abs()) * env;
      final sx = finalTileCenter.x + math.cos(angle) * dist;
      final sy = finalTileCenter.y + math.sin(angle) * dist - cellSize * 0.10 * env;
      final sr = (cellSize * 0.032 * env).clamp(1.5, 4.0);
      canvas.drawCircle(
        Offset(sx, sy),
        sr,
        Paint()..color = brightWater.withValues(alpha: 0.88 * env),
      );
      canvas.drawCircle(
        Offset(sx - sr * 0.3, sy - sr * 0.3),
        sr * 0.4,
        Paint()..color = Colors.white.withValues(alpha: 0.95 * env),
      );
    }
  }

  /// Draws the subtle translucent front glass lip arc of the bottle mouth over the stream entry point
  /// (`targetMouth`) so the single pouring stream visibly goes INSIDE the bottle mouth behind the front glass lip!
  void _drawBottleMouthFrontGlassLip(
    Canvas canvas,
    Vector2 targetMouth,
    double headT,
    double tailT,
  ) {
    if (headT < 0.88 || tailT >= 0.98) return;
    final fadeIn = ((headT - 0.88) / 0.12).clamp(0.0, 1.0);
    final fadeOut = ((0.98 - tailT) / 0.12).clamp(0.0, 1.0);
    final env = math.min(fadeIn, fadeOut);
    if (env <= 0.02) return;

    final spanX = cellSize * 0.34;
    final lipY = targetMouth.y + cellSize * 0.070;
    final lipArc = Path()
      ..moveTo(targetMouth.x - spanX, targetMouth.y + cellSize * 0.015)
      ..quadraticBezierTo(
        targetMouth.x,
        lipY,
        targetMouth.x + spanX,
        targetMouth.y + cellSize * 0.015,
      );

    canvas.drawPath(
      lipArc,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (cellSize * 0.034).clamp(1.4, 3.0)
        ..color = Colors.white.withValues(alpha: 0.82 * env),
    );
  }

  @override
  void render(Canvas canvas) {
    final targetMouth = targetMouthProvider();

    // Progressive stream head (`0 -> 1` in first 0.26s) and tail (`0 -> 1` from 0.62s..1.30s)
    final headT =
        Curves.easeOutCubic.transform((_elapsed / 0.26).clamp(0.0, 1.0));
    final tailT = _elapsed <= 0.62
        ? 0.0
        : Curves.easeInOutCubic.transform(
            ((_elapsed - 0.62) / (_totalDuration - 0.68)).clamp(0.0, 1.0),
          );

    final spanY =
        (finalTileCenter.y - targetMouth.y).abs().clamp(cellSize * 1.6, cellSize * 10.0);

    // Control points that arch smoothly above `targetMouth` and enter `targetMouth`
    // vertically downward (`ctrl2.x == targetMouth.x`, `ctrl2.y < targetMouth.y`)!
    final ctrl1 = Vector2(
      ui.lerpDouble(finalTileCenter.x, targetMouth.x, 0.48)! +
          _archSideSign * cellSize * 0.22,
      math.min(
        finalTileCenter.y - spanY * 0.65,
        targetMouth.y - cellSize * 0.60,
      ),
    );
    final ctrl2 = Vector2(
      targetMouth.x,
      targetMouth.y - cellSize * 1.25,
    );

    _drawSourceBlockLiquidPool(canvas, tailT);

    // Strictly ONE single smooth laminar pouring water stream (`1 dòng nước thôi`)
    _drawSingleLaminarPourStream(
      canvas: canvas,
      start: finalTileCenter,
      ctrl1: ctrl1,
      ctrl2: ctrl2,
      end: targetMouth,
      tailT: tailT,
      headT: headT,
    );

    // Flying water droplets along the curve!
    _drawFlyingWaterDroplets(
      canvas: canvas,
      start: finalTileCenter,
      ctrl1: ctrl1,
      ctrl2: ctrl2,
      end: targetMouth,
      tailT: tailT,
      headT: headT,
    );

    _drawBottleMouthFrontGlassLip(canvas, targetMouth, headT, tailT);
  }
}

/// Step 3 & Step 4 VFX (`3. Sau đó bình mở ra bằng hiệu ứng ánh sáng. 4. Hiệu ứng ánh sáng lan ra toàn màn hình, hiện pop up next level`):
/// Renders the fountain of light when the jar opens, followed by a luminous radial light wave expanding across the entire screen!
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
    this.totalDuration = 1.05,
  }) : super(priority: 150) {
    if (Flame.images.containsKey('Explosion_Halo.png')) {
      _haloImg = Flame.images.fromCache('Explosion_Halo.png');
    }
    if (Flame.images.containsKey('Glow_Ring.png')) {
      _ringImg = Flame.images.fromCache('Glow_Ring.png');
    }
  }

  double get currentFullscreenFlashIntensity {
    if (_elapsed < 0.20) return 0.0;
    if (_elapsed <= 0.62) {
      return ((_elapsed - 0.20) / 0.42).clamp(0.0, 1.0);
    }
    return (1.0 - (_elapsed - 0.62) / math.max(0.05, totalDuration - 0.62))
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

    // 1. Step 3: Jar Mouth Opening Light Burst (`0.0 -> 0.55`)
    if (t < 0.75) {
      final burstT = (t / 0.75).clamp(0.0, 1.0);
      final burstFade = (1.0 - burstT).clamp(0.0, 1.0);
      final burstR = cellSize * (0.6 + 3.2 * Curves.easeOutCubic.transform(burstT));

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
              style.topBright.withValues(alpha: 0.85 * burstFade),
              ui.BlendMode.modulate,
            ),
        );
      }
    }

    // 2. Step 4: Fullscreen Expanding Light Wave (`t >= 0.16`)
    final flash = currentFullscreenFlashIntensity;
    if (flash > 0.01) {
      final expandT = ((_elapsed - 0.14) / (totalDuration - 0.14)).clamp(0.0, 1.0);
      final maxRadius = cellSize * (2.5 + 18.0 * Curves.easeInOutCubic.transform(expandT));

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
              style.rimHighlight.withValues(alpha: (0.82 * flash).clamp(0.0, 1.0)),
              style.topBright.withValues(alpha: (0.55 * flash).clamp(0.0, 1.0)),
              style.topBright.withValues(alpha: 0.0),
            ],
            const [0.0, 0.35, 0.72, 1.0],
          ),
      );
    }
  }
}
