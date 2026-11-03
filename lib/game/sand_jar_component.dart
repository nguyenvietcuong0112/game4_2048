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
        MaskFilter,
        Offset,
        Paint,
        Path,
        RRect,
        Radius,
        Rect;
import '../models/palette.dart';

/// Above-board Magic Sand Jar (`Note: cái bình sẽ đặt ở trên board và bình trùng màu với màu của số lớn nhất trong level đấy`).
///
/// Implements the 4-layer dynamic ColorRamp re-coloring algorithm so that for ANY level's
/// final target number (`16, 32, 64, ..., 2048, 4096, 8192`), the jar, swirling sand,
/// and revealed hidden object/texture automatically adopt the exact 3D palette of that number:
/// 1. 3D Base Ramp Shader (`style.bottomLip` -> `style.topMid` -> `style.topBright`)
/// 2. Translucent Inner Cavity & Unrevealed Hidden Object Silhouette
/// 3. Dynamic Wave-Clipped Swirling Sand Fill (`fillProgress: 0..1`) + Progressive Hidden Object Reveal
/// 4. Color-Invariant Glass Specular Reflections & Pop-Off Stopper Lid (`openProgress: 0..1`)
class MagicSandJarComponent extends PositionComponent {
  BlockColorStyle _style;
  final int levelNumber;

  double _fillProgress = 0.0;
  double _glowIntensity = 0.0;
  double _openProgress = 0.0;
  double _shakeIntensity = 0.0;
  double _animTime = 0.0;
  bool _isOpened = false;

  ui.Image? _haloImg;
  ui.Image? _crystalTexImg;

  // Pre-computed swirling sand grain seeds inside the jar cavity
  static final List<(double xFrac, double ySeed, double radiusFrac, double speed)>
      _innerGrainSeeds = List.generate(32, (i) {
    final rng = math.Random(701 + i * 37);
    return (
      0.12 + rng.nextDouble() * 0.76,
      rng.nextDouble(),
      0.016 + rng.nextDouble() * 0.022,
      0.65 + rng.nextDouble() * 0.85,
    );
  });

  MagicSandJarComponent({
    required BlockColorStyle style,
    required this.levelNumber,
    required Vector2 centerPosition,
    required double jarWidth,
    required double jarHeight,
  })  : _style = style,
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
    if (Flame.images.containsKey('IceBlocks.png')) {
      try {
        _crystalTexImg = Flame.images.fromCache('IceBlocks.png');
      } catch (_) {}
    }
  }

  BlockColorStyle get style => _style;
  double get fillProgress => _fillProgress;
  double get glowIntensity => _glowIntensity;
  double get shakeIntensity => _shakeIntensity;
  double get openProgress => _openProgress;
  bool get isOpened => _isOpened;

  bool get isAnimating =>
      _shakeIntensity > 0.001 ||
      _glowIntensity > 0.001 ||
      (_fillProgress > 0.001 && !_isOpened) ||
      (_isOpened && _openProgress < 1.0);

  /// World-space coordinates of the jar's mouth (target for flying sand streams).
  Vector2 get mouthWorldPos => Vector2(
        position.x,
        position.y - size.y * 0.34,
      );

  void updateStyle(BlockColorStyle newStyle) {
    _style = newStyle;
  }

  void resetJarState() {
    _fillProgress = 0.0;
    _glowIntensity = 0.0;
    _openProgress = 0.0;
    _shakeIntensity = 0.0;
    _isOpened = false;
  }

  void setWinSequenceState({
    required double fillProgress,
    required double glowIntensity,
    required double shakeIntensity,
    required double openProgress,
  }) {
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
    if (isAnimating) {
      _animTime += dt.clamp(0.0, 0.05);
    }
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    if (w <= 4 || h <= 4) return;

    canvas.save();

    // Apply rhythmic shake & scale throb during Steps 2 & 3
    final cx = w * 0.5;
    final cy = h * 0.54;
    if (_shakeIntensity > 0.001 || _glowIntensity > 0.001) {
      final wobbleAngle =
          math.sin(_animTime * 38.0) * 0.095 * _shakeIntensity;
      final throbScale = 1.0 +
          0.12 * _glowIntensity +
          0.048 * math.sin(_animTime * 26.0).abs() * _shakeIntensity;
      final jitterX = math.cos(_animTime * 46.0) * w * 0.022 * _shakeIntensity;
      final jitterY = math.sin(_animTime * 52.0) * h * 0.016 * _shakeIntensity;
      canvas.translate(cx + jitterX, cy + jitterY);
      canvas.scale(throbScale, throbScale);
      canvas.rotate(wobbleAngle);
      canvas.translate(-cx, -cy);
    }

    // 0. Outer Ambient Halo & Opening God-Rays (`Step 3 & Step 4`)
    if (_glowIntensity > 0.01 || _openProgress > 0.01) {
      _drawOuterAuraAndGodRays(canvas, w, h);
    }

    // 1. Soft Ground Drop Shadow beneath Pedestal
    final shadowRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.945),
      width: w * 0.76,
      height: h * 0.11,
    );
    canvas.drawOval(
      shadowRect,
      Paint()
        ..color = const Color(0x6601061D)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.045),
    );

    // Build Jar Outer Body Path & Inner Glass Cavity Path
    final outerBodyPath = _buildJarBodyPath(w, h, inset: 0.0);
    final innerCavityPath = _buildJarCavityPath(w, h);

    // 2. Layer 1 — 3D Colored Jar Body (`style.bottomLip` -> `style.topMid` -> `style.topBright`)
    final bodyBounds = Rect.fromLTWH(w * 0.06, h * 0.18, w * 0.88, h * 0.74);
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(bodyBounds.left, bodyBounds.top),
        Offset(bodyBounds.right, bodyBounds.bottom),
        [
          _style.topBright,
          _style.topMid,
          _style.bottomLip,
        ],
        const [0.0, 0.52, 1.0],
      );
    canvas.drawPath(outerBodyPath, bodyPaint);

    // 3D Bottom Lip / Pedestal Rim
    final pedestalRRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.91),
        width: w * 0.60,
        height: h * 0.075,
      ),
      Radius.circular(h * 0.038),
    );
    canvas.drawRRect(
      pedestalRRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.20, h * 0.91),
          Offset(w * 0.80, h * 0.91),
          [
            _style.bottomLip,
            _style.topMid,
            _style.topBright,
            _style.topMid,
            _style.bottomLip,
          ],
          const [0.0, 0.25, 0.50, 0.75, 1.0],
        ),
    );

    // 3. Layer 2 — Inner Translucent Glass Cavity & Unrevealed Mystery Texture Silhouette
    final cavityBounds = Rect.fromLTWH(w * 0.11, h * 0.24, w * 0.78, h * 0.64);
    canvas.save();
    canvas.clipPath(innerCavityPath);

    canvas.drawRect(
      cavityBounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.45, h * 0.52),
          w * 0.48,
          [
            Color.lerp(_style.bottomLip, const Color(0xFF0A1642), 0.48)!,
            Color.lerp(_style.numberStrokeOuter, const Color(0xFF050A24), 0.68)!,
          ],
        ),
    );

    // Faint frosted mystery lattice & silhouette inside the empty glass before sand fills
    _drawHiddenSandArtTexture(
      canvas,
      cavityBounds,
      isRevealed: false,
      glowBoost: 0.0,
    );
    if (_fillProgress < 0.99) {
      _drawHiddenObject(
        canvas,
        center: Offset(w * 0.5, h * 0.57),
        radius: w * 0.265,
        isRevealed: false,
      );
    }

    // 4. Layer 3 — Rising Swirling Colored Sand & Progressive Hidden Texture + Object Reveal!
    if (_fillProgress > 0.005) {
      final sandWavePath = _buildSandWaveClipPath(cavityBounds, _fillProgress);
      canvas.save();
      canvas.clipPath(sandWavePath);

      // Rich multi-layered Hidden Sand-Art Texture (strata waves + diamond mosaic + crystal grain)
      _drawHiddenSandArtTexture(
        canvas,
        cavityBounds,
        isRevealed: true,
        glowBoost: _glowIntensity,
      );

      // Swirling sparkling sand grains inside the rising sand volume
      final sandTopY =
          ui.lerpDouble(cavityBounds.bottom, cavityBounds.top, _fillProgress)!;
      final grainPaint = Paint()..blendMode = ui.BlendMode.plus;
      for (int i = 0; i < _innerGrainSeeds.length; i++) {
        final (xFrac, ySeed, rFrac, spd) = _innerGrainSeeds[i];
        final localYFrac = (ySeed - _animTime * spd * 0.55) % 1.0;
        final wrappedY = localYFrac < 0 ? localYFrac + 1.0 : localYFrac;
        final gx = cavityBounds.left +
            cavityBounds.width *
                (xFrac + 0.05 * math.sin(_animTime * 5.0 + i)).clamp(0.06, 0.94);
        final gy = sandTopY + (cavityBounds.bottom - sandTopY) * wrappedY;
        final pulse = 0.45 + 0.55 * math.sin(_animTime * 9.0 + i * 1.7).abs();
        grainPaint.color = (i.isEven ? _style.rimHighlight : _style.accent)
            .withValues(alpha: (0.48 + 0.45 * pulse).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(gx, gy), w * rFrac, grainPaint);
      }

      // Revealed 3D Faceted Hidden Object inside the rising sand (progressively uncovered bottom-to-top!)
      if (_openProgress < 0.35) {
        final revealPop =
            1.0 + 0.08 * math.sin(_fillProgress * math.pi) + 0.10 * _openProgress;
        _drawHiddenObject(
          canvas,
          center: Offset(w * 0.5, h * 0.57 - h * 0.05 * _openProgress),
          radius: w * 0.265 * revealPop,
          isRevealed: true,
        );
      }

      canvas.restore();

      // Bright glowing wave crest ribbon along the top surface of the rising sand
      _drawSandWaveCrestStroke(canvas, cavityBounds, _fillProgress);
    }

    canvas.restore(); // End innerCavityPath clip

    // 5. Layer 4 — Color-Invariant 3D Glass Specular Reflections, Neck Collar & Contour
    canvas.drawPath(
      outerBodyPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.024).clamp(1.6, 4.0)
        ..color = Color.lerp(_style.rimHighlight, Colors.white, 0.38)!
            .withValues(alpha: 0.92),
    );

    // Left curved glass highlight ribbon
    final leftSpecPath = Path()
      ..moveTo(w * 0.19, h * 0.32)
      ..quadraticBezierTo(w * 0.12, h * 0.56, w * 0.21, h * 0.80)
      ..quadraticBezierTo(w * 0.17, h * 0.56, w * 0.24, h * 0.33)
      ..close();
    canvas.drawPath(
      leftSpecPath,
      Paint()..color = Colors.white.withValues(alpha: 0.50),
    );

    // Right secondary rim reflection
    final rightSpecPath = Path()
      ..moveTo(w * 0.82, h * 0.36)
      ..quadraticBezierTo(w * 0.87, h * 0.57, w * 0.80, h * 0.78);
    canvas.drawPath(
      rightSpecPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = w * 0.028
        ..color = _style.rimHighlight.withValues(alpha: 0.45),
    );

    // Neck Collar & Flared Mouth Rim
    final neckRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.185),
        width: w * 0.52,
        height: h * 0.074,
      ),
      Radius.circular(h * 0.037),
    );
    canvas.drawRRect(
      neckRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(w * 0.24, h * 0.185),
          Offset(w * 0.76, h * 0.185),
          [
            _style.bottomLip,
            _style.topBright,
            _style.rimHighlight,
            _style.topBright,
            _style.bottomLip,
          ],
          const [0.0, 0.25, 0.50, 0.75, 1.0],
        ),
    );
    canvas.drawRRect(
      neckRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (w * 0.016).clamp(1.2, 2.8)
        ..color = Colors.white.withValues(alpha: 0.72),
    );

    // 6. When Jar Opens (`_openProgress >= 0.35`), the Revealed Hidden Object emerges & shines above the jar!
    if (_openProgress >= 0.35) {
      final emergeT = ((_openProgress - 0.35) / 0.65).clamp(0.0, 1.0);
      final eased = 1.0 - math.pow(1.0 - emergeT, 3).toDouble();
      final objY = ui.lerpDouble(h * 0.54, h * 0.30, eased)!;
      final objScale = ui.lerpDouble(1.08, 1.34, eased)!;

      // Brilliant halo behind emerging hidden object
      canvas.drawCircle(
        Offset(w * 0.5, objY),
        w * 0.38 * objScale,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset(w * 0.5, objY),
            w * 0.38 * objScale,
            [
              Colors.white.withValues(alpha: 0.92),
              _style.topBright.withValues(alpha: 0.65),
              _style.accent.withValues(alpha: 0.0),
            ],
            const [0.0, 0.48, 1.0],
          ),
      );

      _drawHiddenObject(
        canvas,
        center: Offset(w * 0.5, objY),
        radius: w * 0.265 * objScale,
        isRevealed: true,
      );
    }

    // 7. Cork / Stopper Lid (sits on mouth, then pops open with light beam in Step 3!)
    _drawJarLid(canvas, w, h);

    canvas.restore();
  }

  void _drawOuterAuraAndGodRays(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.5, h * 0.52);
    final auraIntensity = math.max(_glowIntensity, _openProgress).clamp(0.0, 1.0);
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

    // Rotating light beams when jar is near full or opening
    if (_glowIntensity > 0.35 || _openProgress > 0.01) {
      final rayAlpha =
          ((_glowIntensity - 0.35) / 0.65 + _openProgress).clamp(0.0, 1.0);
      final mouthCenter = Offset(w * 0.5, h * 0.185);
      final rayOrigin = _openProgress > 0.05 ? mouthCenter : center;
      const rayCount = 8;
      final rayPaint = Paint()
        ..blendMode = ui.BlendMode.plus
        ..color = _style.rimHighlight.withValues(alpha: 0.48 * rayAlpha);

      for (int i = 0; i < rayCount; i++) {
        final angle = _animTime * 1.8 + (i * math.pi * 2.0 / rayCount);
        final rayLen = w * (0.55 + 0.45 * _openProgress);
        final halfW = w * 0.068;
        canvas.save();
        canvas.translate(rayOrigin.dx, rayOrigin.dy);
        canvas.rotate(angle);
        final rayPath = Path()
          ..moveTo(0, 0)
          ..lineTo(-halfW, -rayLen)
          ..lineTo(halfW, -rayLen)
          ..close();
        canvas.drawPath(rayPath, rayPaint);
        canvas.restore();
      }
    }
  }

  void _drawJarLid(Canvas canvas, double w, double h) {
    final openT = _openProgress.clamp(0.0, 1.0);
    final lidAlpha = (1.0 - (openT - 0.55) / 0.45).clamp(0.0, 1.0);
    if (lidAlpha <= 0.01) return;

    final liftY = -h * 0.48 * openT;
    final driftX = w * 0.18 * openT;
    final tiltAngle = 0.85 * openT;

    canvas.save();
    canvas.translate(w * 0.5 + driftX, h * 0.115 + liftY);
    canvas.rotate(tiltAngle);

    // Stopper jewel / cap
    final capRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: w * 0.36,
        height: h * 0.095,
      ),
      Radius.circular(h * 0.036),
    );
    canvas.drawRRect(
      capRect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-w * 0.18, -h * 0.045),
          Offset(w * 0.18, h * 0.045),
          [
            _style.rimHighlight.withValues(alpha: lidAlpha),
            _style.topBright.withValues(alpha: lidAlpha),
            _style.bottomLip.withValues(alpha: lidAlpha),
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
    canvas.drawRRect(
      capRect,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = Colors.white.withValues(alpha: 0.78 * lidAlpha),
    );

    // Top crown gem on stopper
    canvas.drawCircle(
      Offset(0, -h * 0.055),
      w * 0.072,
      Paint()..color = _style.rimHighlight.withValues(alpha: lidAlpha),
    );

    canvas.restore();
  }

  Path _buildJarBodyPath(double w, double h, {required double inset}) {
    final l = w * 0.5;
    final neckHalfW = w * 0.21 - inset;
    final bellyHalfW = w * 0.435 - inset;
    final baseHalfW = w * 0.275 - inset;

    final neckTopY = h * 0.185 + inset;
    final shoulderY = h * 0.27 + inset * 0.5;
    final bellyMidY = h * 0.56;
    final baseBottomY = h * 0.895 - inset;

    return Path()
      ..moveTo(l - neckHalfW, neckTopY)
      ..lineTo(l + neckHalfW, neckTopY)
      ..quadraticBezierTo(
        l + neckHalfW,
        shoulderY,
        l + bellyHalfW * 0.88,
        shoulderY + h * 0.07,
      )
      ..cubicTo(
        l + bellyHalfW * 1.07,
        bellyMidY - h * 0.11,
        l + bellyHalfW * 1.05,
        bellyMidY + h * 0.17,
        l + baseHalfW,
        baseBottomY,
      )
      ..quadraticBezierTo(
        l,
        baseBottomY + h * 0.032,
        l - baseHalfW,
        baseBottomY,
      )
      ..cubicTo(
        l - bellyHalfW * 1.05,
        bellyMidY + h * 0.17,
        l - bellyHalfW * 1.07,
        bellyMidY - h * 0.11,
        l - bellyHalfW * 0.88,
        shoulderY + h * 0.07,
      )
      ..quadraticBezierTo(
        l - neckHalfW,
        shoulderY,
        l - neckHalfW,
        neckTopY,
      )
      ..close();
  }

  Path _buildJarCavityPath(double w, double h) {
    return _buildJarBodyPath(w, h, inset: w * 0.044);
  }

  Path _buildSandWaveClipPath(Rect bounds, double fill) {
    final topY = ui.lerpDouble(bounds.bottom, bounds.top, fill)!;
    final waveAmp =
        bounds.height * 0.042 * math.sin(fill * math.pi).clamp(0.18, 1.0);
    final path = Path()..moveTo(bounds.left - 4, bounds.bottom + 4);
    path.lineTo(bounds.left - 4, topY);

    const steps = 16;
    for (int i = 0; i <= steps; i++) {
      final frac = i / steps;
      final x = bounds.left + bounds.width * frac;
      final w1 = math.sin(frac * math.pi * 2.5 + _animTime * 9.5) * waveAmp;
      final w2 =
          math.cos(frac * math.pi * 4.0 - _animTime * 6.2) * (waveAmp * 0.45);
      path.lineTo(x, topY + w1 + w2);
    }

    path
      ..lineTo(bounds.right + 4, bounds.bottom + 4)
      ..close();
    return path;
  }

  void _drawSandWaveCrestStroke(Canvas canvas, Rect bounds, double fill) {
    if (fill <= 0.02 || fill >= 0.99) return;
    final topY = ui.lerpDouble(bounds.bottom, bounds.top, fill)!;
    final waveAmp =
        bounds.height * 0.042 * math.sin(fill * math.pi).clamp(0.18, 1.0);
    final crestPath = Path();
    const steps = 16;
    for (int i = 0; i <= steps; i++) {
      final frac = i / steps;
      final x = bounds.left + bounds.width * frac;
      final w1 = math.sin(frac * math.pi * 2.5 + _animTime * 9.5) * waveAmp;
      final w2 =
          math.cos(frac * math.pi * 4.0 - _animTime * 6.2) * (waveAmp * 0.45);
      if (i == 0) {
        crestPath.moveTo(x, topY + w1 + w2);
      } else {
        crestPath.lineTo(x, topY + w1 + w2);
      }
    }
    canvas.drawPath(
      crestPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  /// Renders the multi-layered Hidden Sand-Art Texture inside the jar (`+ có texture hidden`):
  /// - When `isRevealed == false`, draws a subtle frosted glass lattice inside the empty cavity.
  /// - When `isRevealed == true` (inside the rising `sandWavePath` clip), reveals:
  ///   1. 6 undulating horizontal Sand-Art Strata Bands (`rimHighlight`, `topBright`, warm gold, `accent`, `topMid`, `bottomLip`).
  ///   2. Real crystalline facet texture overlay (`IceBlocks.png`) modulated across the sand volume.
  ///   3. Geometric Diamond Argyle Mosaic & golden beaded filigree bands across the upper and lower jar belly.
  void _drawHiddenSandArtTexture(
    Canvas canvas,
    Rect bounds, {
    required bool isRevealed,
    required double glowBoost,
  }) {
    if (!isRevealed) {
      // Subtle frosted mystery diamond lattice in empty glass cavity
      final faintStroke = Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _style.topBright.withValues(alpha: 0.14);
      const cols = 6;
      final cellW = bounds.width / cols;
      for (final yFrac in const [0.22, 0.78]) {
        final cy = bounds.top + bounds.height * yFrac;
        final dh = bounds.height * 0.065;
        for (int c = 0; c < cols; c++) {
          final cx = bounds.left + (c + 0.5) * cellW;
          final dPath = Path()
            ..moveTo(cx, cy - dh)
            ..lineTo(cx + cellW * 0.45, cy)
            ..lineTo(cx, cy + dh)
            ..lineTo(cx - cellW * 0.45, cy)
            ..close();
          canvas.drawPath(dPath, faintStroke);
        }
      }
      return;
    }

    // 1. Base Sand-Art Gradient + 6 Undulating Layered Sand-Art Strata Bands
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top),
          Offset(bounds.center.dx, bounds.bottom),
          [
            _style.rimHighlight,
            _style.topBright,
            _style.topMid,
            _style.bottomLip,
          ],
          const [0.0, 0.25, 0.68, 1.0],
        ),
    );

    final goldSand = Color.lerp(_style.rimHighlight, const Color(0xFFFFE57F), 0.60)!;
    final bandColors = <Color>[
      _style.rimHighlight.withValues(alpha: 0.42),
      goldSand.withValues(alpha: 0.38),
      _style.accent.withValues(alpha: 0.40),
      _style.bottomLip.withValues(alpha: 0.45),
      goldSand.withValues(alpha: 0.36),
    ];
    for (int b = 0; b < bandColors.length; b++) {
      final yTopFrac = 0.12 + b * 0.16;
      final yBotFrac = yTopFrac + 0.095;
      final yTop = bounds.top + bounds.height * yTopFrac;
      final yBot = bounds.top + bounds.height * yBotFrac;
      final amp = bounds.height * 0.028;
      final phase = b * 1.35 + levelNumber * 0.7;

      final strataPath = Path()..moveTo(bounds.left - 2, yTop);
      const segs = 12;
      for (int i = 0; i <= segs; i++) {
        final t = i / segs;
        final x = bounds.left + bounds.width * t;
        final dy = math.sin(t * math.pi * 3.0 + phase) * amp;
        strataPath.lineTo(x, yTop + dy);
      }
      for (int i = segs; i >= 0; i--) {
        final t = i / segs;
        final x = bounds.left + bounds.width * t;
        final dy = math.cos(t * math.pi * 3.0 - phase) * amp;
        strataPath.lineTo(x, yBot + dy);
      }
      strataPath.close();
      canvas.drawPath(strataPath, Paint()..color = bandColors[b]);
    }

    // 2. Real Crystalline Facet Texture Overlay (`IceBlocks.png`) inside the sand volume
    if (_crystalTexImg != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        _crystalTexImg!.width.toDouble(),
        _crystalTexImg!.height.toDouble(),
      );
      canvas.drawImageRect(
        _crystalTexImg!,
        src,
        bounds,
        Paint()
          ..blendMode = ui.BlendMode.plus
          ..colorFilter = ui.ColorFilter.mode(
            _style.rimHighlight.withValues(
              alpha: (0.24 + 0.16 * glowBoost).clamp(0.0, 0.48),
            ),
            ui.BlendMode.modulate,
          ),
      );
    }

    // 3. Geometric Diamond Mosaic & Beaded Golden Filigree Bands (Upper & Lower Jar Belly)
    const cols = 6;
    final cellW = bounds.width / cols;
    final mosaicFillPaint = Paint()..style = ui.PaintingStyle.fill;
    final mosaicStrokePaint = Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.62 + 0.25 * glowBoost);

    for (final yFrac in const [0.20, 0.80]) {
      final cy = bounds.top + bounds.height * yFrac;
      final dh = bounds.height * 0.068;

      // Horizontal framing lines
      final linePaint = Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = goldSand.withValues(alpha: 0.72);
      canvas.drawLine(
        Offset(bounds.left, cy - dh * 1.18),
        Offset(bounds.right, cy - dh * 1.18),
        linePaint,
      );
      canvas.drawLine(
        Offset(bounds.left, cy + dh * 1.18),
        Offset(bounds.right, cy + dh * 1.18),
        linePaint,
      );

      for (int c = 0; c < cols; c++) {
        final cx = bounds.left + (c + 0.5) * cellW;
        final dPath = Path()
          ..moveTo(cx, cy - dh)
          ..lineTo(cx + cellW * 0.44, cy)
          ..lineTo(cx, cy + dh)
          ..lineTo(cx - cellW * 0.44, cy)
          ..close();

        mosaicFillPaint.color = (c.isEven ? goldSand : _style.rimHighlight)
            .withValues(alpha: 0.48 + 0.22 * glowBoost);
        canvas.drawPath(dPath, mosaicFillPaint);
        canvas.drawPath(dPath, mosaicStrokePaint);

        // Center jewel dot inside each mosaic diamond
        canvas.drawCircle(
          Offset(cx, cy),
          cellW * 0.09,
          Paint()..color = Colors.white.withValues(alpha: 0.85),
        );
      }
    }
  }

  /// Draws the Hidden Object / Treasure inside the jar (`Crown`, `Faceted Gem`, `Star Emblem`, `Crystal Heart`):
  /// - When `isRevealed == false`, renders a subtle mystery silhouette inside the empty glass cavity.
  /// - When `isRevealed == true`, renders a multi-faceted, glowing 3D emblem with internal gem facet lines!
  void _drawHiddenObject(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required bool isRevealed,
  }) {
    final shapeType = levelNumber % 4;
    final path = Path();
    final facetPath = Path();

    if (shapeType == 1) {
      // Royal 3-Peak Crown with internal jewel facets
      final w = radius * 1.18;
      final h = radius * 0.94;
      path
        ..moveTo(center.dx - w * 0.78, center.dy + h * 0.65)
        ..lineTo(center.dx - w * 0.95, center.dy - h * 0.35)
        ..lineTo(center.dx - w * 0.42, center.dy + h * 0.12)
        ..lineTo(center.dx, center.dy - h * 0.78)
        ..lineTo(center.dx + w * 0.42, center.dy + h * 0.12)
        ..lineTo(center.dx + w * 0.95, center.dy - h * 0.35)
        ..lineTo(center.dx + w * 0.78, center.dy + h * 0.65)
        ..close();

      facetPath
        ..moveTo(center.dx - w * 0.80, center.dy + h * 0.38)
        ..lineTo(center.dx + w * 0.80, center.dy + h * 0.38)
        ..moveTo(center.dx, center.dy - h * 0.78)
        ..lineTo(center.dx, center.dy + h * 0.65)
        ..moveTo(center.dx - w * 0.42, center.dy + h * 0.12)
        ..lineTo(center.dx - w * 0.35, center.dy + h * 0.65)
        ..moveTo(center.dx + w * 0.42, center.dy + h * 0.12)
        ..lineTo(center.dx + w * 0.35, center.dy + h * 0.65);
    } else if (shapeType == 2) {
      // Brilliant Cut Diamond with crown/table/pavilion facet lines
      final w = radius * 1.08;
      final h = radius * 1.08;
      final topY = center.dy - h * 0.68;
      final girdleY = center.dy - h * 0.18;
      final botY = center.dy + h * 0.88;
      path
        ..moveTo(center.dx - w * 0.55, topY)
        ..lineTo(center.dx + w * 0.55, topY)
        ..lineTo(center.dx + w, girdleY)
        ..lineTo(center.dx, botY)
        ..lineTo(center.dx - w, girdleY)
        ..close();

      facetPath
        ..moveTo(center.dx - w, girdleY)
        ..lineTo(center.dx + w, girdleY)
        ..moveTo(center.dx - w * 0.55, topY)
        ..lineTo(center.dx - w * 0.38, girdleY)
        ..lineTo(center.dx, botY)
        ..moveTo(center.dx + w * 0.55, topY)
        ..lineTo(center.dx + w * 0.38, girdleY)
        ..lineTo(center.dx, botY)
        ..moveTo(center.dx - w * 0.38, girdleY)
        ..lineTo(center.dx, topY)
        ..lineTo(center.dx + w * 0.38, girdleY);
    } else if (shapeType == 3) {
      // Faceted Crystal Heart
      final r = radius * 0.98;
      path
        ..moveTo(center.dx, center.dy + r * 0.90)
        ..cubicTo(
          center.dx - r * 1.28,
          center.dy + r * 0.15,
          center.dx - r * 0.98,
          center.dy - r * 0.98,
          center.dx,
          center.dy - r * 0.32,
        )
        ..cubicTo(
          center.dx + r * 0.98,
          center.dy - r * 0.98,
          center.dx + r * 1.28,
          center.dy + r * 0.15,
          center.dx,
          center.dy + r * 0.90,
        )
        ..close();

      facetPath
        ..moveTo(center.dx, center.dy - r * 0.32)
        ..lineTo(center.dx, center.dy + r * 0.90)
        ..moveTo(center.dx - r * 0.55, center.dy - r * 0.52)
        ..lineTo(center.dx, center.dy + r * 0.22)
        ..lineTo(center.dx + r * 0.55, center.dy - r * 0.52)
        ..moveTo(center.dx - r * 0.85, center.dy + r * 0.05)
        ..lineTo(center.dx, center.dy + r * 0.22)
        ..lineTo(center.dx + r * 0.85, center.dy + r * 0.05);
    } else {
      // 5-Pointed Celestial Star Emblem with 3D ridge facets
      const points = 5;
      final outerR = radius * 1.12;
      final innerR = radius * 0.50;
      for (int i = 0; i < points * 2; i++) {
        final r = i.isEven ? outerR : innerR;
        final a = -math.pi * 0.5 + i * (math.pi / points);
        final px = center.dx + math.cos(a) * r;
        final py = center.dy + math.sin(a) * r;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
        facetPath
          ..moveTo(center.dx, center.dy)
          ..lineTo(px, py);
      }
      path.close();
    }

    if (!isRevealed) {
      canvas.drawPath(
        path,
        Paint()..color = _style.bottomLip.withValues(alpha: 0.42),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _style.topBright.withValues(alpha: 0.28),
      );
      return;
    }

    // Outer dark contrast rim so the revealed emblem pops crisply against the sand-art texture
    canvas.drawPath(
      path,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeJoin = ui.StrokeJoin.round
        ..color = _style.numberStrokeOuter.withValues(alpha: 0.65),
    );

    // Revealed state: luminous 3D golden + target-color gradient with internal gem facets!
    final goldTint =
        Color.lerp(_style.rimHighlight, const Color(0xFFFFE57F), 0.62)!;
    final coreDark =
        Color.lerp(_style.bottomLip, const Color(0xFFD47B00), 0.48)!;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - radius, center.dy - radius),
          Offset(center.dx + radius, center.dy + radius),
          [
            Colors.white,
            goldTint,
            _style.topBright,
            coreDark,
          ],
          const [0.0, 0.30, 0.70, 1.0],
        ),
    );

    // Draw internal 3D gem facet ridges
    canvas.drawPath(
      facetPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: 0.68),
    );

    // Crisp outer specular bevel
    canvas.drawPath(
      path,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = ui.StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.95),
    );

    // Specular star glint on upper-left facet
    canvas.drawCircle(
      Offset(center.dx - radius * 0.22, center.dy - radius * 0.22),
      radius * 0.16,
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );
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

class _SandStreamGrain {
  final Vector2 startPos;
  final Vector2 ctrlPos1;
  final Vector2 ctrlPos2;
  final double delay;
  final double flightDuration;
  final double sizeScale;
  final int colorVariant;

  const _SandStreamGrain({
    required this.startPos,
    required this.ctrlPos1,
    required this.ctrlPos2,
    required this.delay,
    required this.flightDuration,
    required this.sizeScale,
    required this.colorVariant,
  });
}

/// Step 2 VFX (`2. cát bắt đầu chuyển động từ khu vực board bay lên phía chiếc bình`):
/// Streams 56 glowing, colored sand grains from the final tile & playable board area
/// along swirling cubic Bezier trajectories directly into the mouth of `MagicSandJarComponent`.
class BoardSandStreamToJarVfx extends PositionComponent {
  final BlockColorStyle style;
  final Vector2 Function() targetMouthProvider;
  final double cellSize;
  final List<_SandStreamGrain> _grains = [];
  double _elapsed = 0.0;
  double _totalDuration = 1.48;

  ui.Image? _sparkleImg;
  late final Float32List _rstTransforms;
  late final Float32List _texRects;
  late final Int32List _colors;
  final Paint _atlasPaint = Paint()
    ..blendMode = ui.BlendMode.plus
    ..filterQuality = ui.FilterQuality.low;

  BoardSandStreamToJarVfx({
    required Vector2 finalTileCenter,
    required List<Vector2> boardOrigins,
    required this.targetMouthProvider,
    required this.style,
    required this.cellSize,
  }) : super(priority: 125) {
    if (Flame.images.containsKey('Sparkle_01.png')) {
      _sparkleImg = Flame.images.fromCache('Sparkle_01.png');
    }

    const grainCount = 56;
    final rng = math.Random(1337);
    final target = targetMouthProvider();
    double maxEnd = 0.0;

    for (int i = 0; i < grainCount; i++) {
      // 65% of sand grains erupt from the glowing final tile, 35% rise from across the board area
      final fromTile = i < (grainCount * 0.65) || boardOrigins.isEmpty;
      final baseOrigin = fromTile
          ? finalTileCenter
          : boardOrigins[i % boardOrigins.length];
      final jitterAngle = rng.nextDouble() * math.pi * 2.0;
      final jitterRadius =
          cellSize * (fromTile ? 0.55 : 0.42) * rng.nextDouble();
      final start = Vector2(
        baseOrigin.x + math.cos(jitterAngle) * jitterRadius,
        baseOrigin.y + math.sin(jitterAngle) * jitterRadius,
      );

      final sideSign = (i.isEven ? 1.0 : -1.0) * (0.45 + rng.nextDouble() * 0.95);
      final spanY = (start.y - target.y).abs().clamp(cellSize, cellSize * 10.0);
      final ctrl1 = Vector2(
        start.x + sideSign * cellSize * 1.45,
        start.y - spanY * 0.25,
      );
      final ctrl2 = Vector2(
        target.x - sideSign * cellSize * 0.85,
        target.y + spanY * 0.32,
      );

      final delay = (i / grainCount) * 0.58 + rng.nextDouble() * 0.08;
      final flightDur = 0.62 + rng.nextDouble() * 0.22;
      if (delay + flightDur > maxEnd) {
        maxEnd = delay + flightDur;
      }

      _grains.add(
        _SandStreamGrain(
          startPos: start,
          ctrlPos1: ctrl1,
          ctrlPos2: ctrl2,
          delay: delay,
          flightDuration: flightDur,
          sizeScale: 0.45 + rng.nextDouble() * 0.55,
          colorVariant: i % 3,
        ),
      );
    }

    _totalDuration = maxEnd + 0.05;
    _rstTransforms = Float32List(grainCount * 4);
    _texRects = Float32List(grainCount * 4);
    _colors = Int32List(grainCount);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt.clamp(0.0, 0.05);
    if (_elapsed >= _totalDuration) {
      removeFromParent();
    }
  }

  Vector2 _evalCubicBezier(
    Vector2 p0,
    Vector2 p1,
    Vector2 p2,
    Vector2 p3,
    double t,
  ) {
    final u = 1.0 - t;
    final tt = t * t;
    final uu = u * u;
    final uuu = uu * u;
    final ttt = tt * t;
    return Vector2(
      uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x,
      uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y,
    );
  }

  @override
  void render(Canvas canvas) {
    final targetMouth = targetMouthProvider();
    final spImg = _sparkleImg;
    final sandCorePaint = Paint()..style = ui.PaintingStyle.fill;
    final sandGlowPaint = Paint()..blendMode = ui.BlendMode.plus;

    int activeCount = 0;
    final sw = spImg?.width.toDouble() ?? 32.0;
    final sh = spImg?.height.toDouble() ?? 32.0;
    final hx = sw * 0.5;
    final hy = sh * 0.5;
    final baseAtlasSize = cellSize * 0.36;

    for (int i = 0; i < _grains.length; i++) {
      final g = _grains[i];
      final localT = (_elapsed - g.delay) / g.flightDuration;
      if (localT <= 0.0 || localT >= 1.0) continue;

      final eased = Curves.easeInOutCubic.transform(localT.clamp(0.0, 1.0));
      final pos = _evalCubicBezier(
        g.startPos,
        g.ctrlPos1,
        g.ctrlPos2,
        targetMouth,
        eased,
      );

      final env = math.sin(localT * math.pi).clamp(0.0, 1.0);
      final grainR = cellSize * 0.095 * g.sizeScale * (0.65 + 0.45 * env);

      final grainColor = g.colorVariant == 0
          ? style.rimHighlight
          : (g.colorVariant == 1 ? style.topBright : style.accent);

      // Draw crisp glowing sand droplet + short motion tail
      final prevT = (eased - 0.06).clamp(0.0, 1.0);
      final prevPos = _evalCubicBezier(
        g.startPos,
        g.ctrlPos1,
        g.ctrlPos2,
        targetMouth,
        prevT,
      );
      canvas.drawLine(
        Offset(prevPos.x, prevPos.y),
        Offset(pos.x, pos.y),
        sandGlowPaint
          ..strokeWidth = grainR * 1.45
          ..strokeCap = ui.StrokeCap.round
          ..color = style.topBright.withValues(alpha: 0.52 * env),
      );

      sandCorePaint.color =
          grainColor.withValues(alpha: (0.85 * env + 0.15).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(pos.x, pos.y), grainR, sandCorePaint);

      if (spImg != null) {
        final targetSz = baseAtlasSize * g.sizeScale * (0.7 + 0.4 * env);
        final scaleFactor = targetSz / math.max(1.0, sw);
        final rot = _elapsed * 6.0 + i;
        final scos = scaleFactor * math.cos(rot);
        final ssin = scaleFactor * math.sin(rot);

        final idx4 = activeCount * 4;
        _rstTransforms[idx4] = scos;
        _rstTransforms[idx4 + 1] = ssin;
        _rstTransforms[idx4 + 2] = pos.x - scos * hx + ssin * hy;
        _rstTransforms[idx4 + 3] = pos.y - ssin * hx - scos * hy;
        _texRects[idx4] = 0.0;
        _texRects[idx4 + 1] = 0.0;
        _texRects[idx4 + 2] = sw;
        _texRects[idx4 + 3] = sh;
        _colors[activeCount] =
            grainColor.withValues(alpha: (0.82 * env).clamp(0.0, 1.0)).toARGB32();
        activeCount++;
      }
    }

    if (spImg != null && activeCount > 0) {
      canvas.drawRawAtlas(
        spImg,
        Float32List.sublistView(_rstTransforms, 0, activeCount * 4),
        Float32List.sublistView(_texRects, 0, activeCount * 4),
        Int32List.sublistView(_colors, 0, activeCount),
        ui.BlendMode.modulate,
        null,
        _atlasPaint,
      );
    }
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
