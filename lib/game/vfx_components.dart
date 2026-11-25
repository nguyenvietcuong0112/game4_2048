import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart'
    show
        BlendMode,
        Canvas,
        Color,
        ColorFilter,
        Colors,
        Curves,
        FilterQuality,
        FontWeight,
        Offset,
        PaintingStyle,
        RRect,
        Radius,
        Rect,
        StrokeCap,
        StrokeJoin,
        TextDirection,
        TextPainter,
        TextSpan,
        TextStyle;

ui.Image? _safeFlameImage(String key) {
  if (!Flame.images.containsKey(key)) return null;
  try {
    return Flame.images.fromCache(key);
  } catch (_) {
    return null;
  }
}

/// GPU 5x4 color-matrix filters for Unity channel-packed additive/alpha mask textures
/// (`Explosion_Halo.png`, `IceBlocks.png`, `Glow_01.png` = R8 on opaque black;
///  `Sparkle_01.png`, `Glow_Ring.png` = RG8 white-core + tinted-bloom on opaque black).
class UnityChannelMaskFilters {
  const UnityChannelMaskFilters._();

  /// Maps an opaque-black `R8` mask (`R` = intensity, `A = 255`) to `color` with
  /// clean proportional alpha (`R = 0` -> `RGBA(0,0,0,0)`).
  static ColorFilter redChannelTint(Color color, {double opacity = 1.0}) {
    final a = (color.a * opacity).clamp(0.0, 1.0);
    return ColorFilter.matrix(<double>[
      color.r, 0, 0, 0, 0,
      color.g, 0, 0, 0, 0,
      color.b, 0, 0, 0, 0,
      a, 0, 0, 0, 0,
    ]);
  }

  /// Maps an opaque-black `R8` mask (`R` = intensity `0..255`, `A = 255`, such as
  /// `Frost_Gradient.png`) to a luminous unpremultiplied `color` whose alpha is
  /// driven purely by `R` (`R = 0` at center -> `A = 0` 100% transparent; `R > 0`
  /// at edges -> bright `color` without dark RGB premultiplication).
  static ColorFilter redChannelAlphaTint(
    Color color, {
    double opacity = 1.0,
    double alphaScale = 1.0,
  }) {
    final a = (color.a * opacity * alphaScale).clamp(0.0, 2.5);
    return ColorFilter.matrix(<double>[
      0, 0, 0, 0, color.r * 255.0,
      0, 0, 0, 0, color.g * 255.0,
      0, 0, 0, 0, color.b * 255.0,
      a, 0, 0, 0, 0,
    ]);
  }

  /// Maps an opaque-black `RG8` dual-channel Unity particle mask (`R` = hot white core,
  /// `G` = outer colored bloom, `B = 0`, `A = 255`) to a white-cored glowing sprite
  /// with zero black-box or red/green channel artifacts.
  static ColorFilter rgDualChannelStar(
    Color bloomColor, {
    double opacity = 1.0,
    double coreWhite = 1.0,
  }) {
    final a = (bloomColor.a * opacity).clamp(0.0, 1.0);
    return ColorFilter.matrix(<double>[
      coreWhite, bloomColor.r, 0, 0, 0,
      coreWhite, bloomColor.g, 0, 0, 0,
      coreWhite, bloomColor.b, 0, 0, 0,
      a, a * 0.88, 0, 0, 0,
    ]);
  }
}

/// Pre-bakes a clean `64x64` RGBA white star sprite from Unity's `RG8` `Sparkle_01.png`
/// once at startup so all sparkle particle systems render in a SINGLE `Canvas.drawAtlas`
/// GPU batch with zero per-frame `toImageSync` or `ColorFilter.matrix` allocations!
class SparkleAtlas {
  SparkleAtlas._();

  static const double tileSize = 64.0;
  static const ui.Rect tileRect = ui.Rect.fromLTWH(0, 0, tileSize, tileSize);
  static const ui.Rect whiteTileRect = tileRect;
  static const ui.Rect tintedTileRect = tileRect;

  static ui.Image? _starImage;

  static ui.Image? get starImage {
    if (_starImage != null) return _starImage;
    final raw = _safeFlameImage('Sparkle_01.png');
    if (raw == null) return null;
    return _bakeWhiteStar(raw);
  }

  static Future<void> ensureLoaded() async {
    if (_starImage != null) return;
    final raw = _safeFlameImage('Sparkle_01.png');
    if (raw == null) return;
    _starImage = _bakeWhiteStar(raw);
  }

  static ui.Image? _bakeWhiteStar(ui.Image rawSparkle) {
    try {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final src = ui.Rect.fromLTWH(
        0,
        0,
        rawSparkle.width.toDouble(),
        rawSparkle.height.toDouble(),
      );
      canvas.drawImageRect(
        rawSparkle,
        src,
        tileRect,
        ui.Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = UnityChannelMaskFilters.rgDualChannelStar(
            Colors.white,
            opacity: 1.0,
          ),
      );
      final pic = recorder.endRecording();
      final baked = pic.toImageSync(tileSize.toInt(), tileSize.toInt());
      pic.dispose();
      _starImage = baked;
      return baked;
    } catch (_) {
      return null;
    }
  }

  /// Backward-compatible access that returns the pre-baked white star texture immediately
  /// with ZERO synchronous GPU stalls during gameplay!
  static ui.Image? getOrBake(ui.Image? rawSparkle, [Color? _]) {
    if (_starImage != null) return _starImage;
    if (rawSparkle == null) return null;
    return _bakeWhiteStar(rawSparkle);
  }
}

/// Flood-fills exterior opaque white (`RGBA = 255,255,255,255`) pixels outside the
/// hexagonal bolt in `Screw_Greyscale_01/02/03.png` into clean antialiased alpha once at startup.
class ScrewTextureCleaner {
  static final List<ui.Image> cleanedScrews = <ui.Image>[];
  static bool _loaded = false;

  static Future<void> ensureCleanedScrewsLoaded() async {
    if (_loaded && cleanedScrews.isNotEmpty) return;
    cleanedScrews.clear();
    const keys = <String>[
      'Screw_Greyscale_01.png',
      'Screw_Greyscale_02.png',
      'Screw_Greyscale_03.png',
    ];
    for (final key in keys) {
      final raw = _safeFlameImage(key);
      if (raw == null) continue;
      final cleaned = await _cleanExteriorWhite(raw);
      if (cleaned != null) {
        cleanedScrews.add(cleaned);
      }
    }
    _loaded = cleanedScrews.isNotEmpty;
  }

  static Future<ui.Image?> _cleanExteriorWhite(ui.Image src) async {
    final byteData = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return src;
    final w = src.width;
    final h = src.height;
    final pixels = Uint8List.fromList(byteData.buffer.asUint8List());
    final total = w * h;
    // Reworked circular screws already ship with clean transparent alpha outside the bolt.
    if (pixels[3] == 0 &&
        pixels[(w - 1) * 4 + 3] == 0 &&
        pixels[((h - 1) * w) * 4 + 3] == 0 &&
        pixels[(total - 1) * 4 + 3] == 0) {
      return src;
    }
    final visited = Uint8List(total);
    final queue = ListQueue<int>();

    int lumAt(int idx) {
      final o = idx * 4;
      return (pixels[o] + pixels[o + 1] + pixels[o + 2]) ~/ 3;
    }

    void tryEnqueue(int idx) {
      if (visited[idx] != 0) return;
      if (lumAt(idx) >= 242) {
        visited[idx] = 1;
        queue.addLast(idx);
      }
    }

    for (int x = 0; x < w; x++) {
      tryEnqueue(x);
      tryEnqueue((h - 1) * w + x);
    }
    for (int y = 0; y < h; y++) {
      tryEnqueue(y * w);
      tryEnqueue(y * w + (w - 1));
    }

    while (queue.isNotEmpty) {
      final idx = queue.removeFirst();
      final o = idx * 4;
      pixels[o + 3] = 0;

      final x = idx % w;
      final y = idx ~/ w;
      if (x > 0) tryEnqueue(idx - 1);
      if (x + 1 < w) tryEnqueue(idx + 1);
      if (y > 0) tryEnqueue(idx - w);
      if (y + 1 < h) tryEnqueue(idx + w);
    }

    // Softly feather 1px anti-aliased white fringe bordering the exterior flood-fill
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        if (visited[idx] != 0) continue;
        final touchesExterior = visited[idx - 1] != 0 ||
            visited[idx + 1] != 0 ||
            visited[idx - w] != 0 ||
            visited[idx + w] != 0;
        if (!touchesExterior) continue;
        final lum = lumAt(idx);
        if (lum >= 224) {
          final alphaFrac = ((246 - lum) / 22.0).clamp(0.0, 1.0);
          final o = idx * 4;
          final clampedGrey = math.min(lum, 212);
          pixels[o] = clampedGrey;
          pixels[o + 1] = clampedGrey;
          pixels[o + 2] = clampedGrey;
          pixels[o + 3] = (alphaFrac * 255).round();
        }
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

class _VfxParticle {
  ui.Offset pos;
  ui.Offset vel;
  double size;
  double life;
  final double maxLife;
  final Color color;
  final double gravity;
  double rotation;
  final double angularVel;
  final int spriteVariant;

  _VfxParticle({
    required this.pos,
    required this.vel,
    required this.size,
    required this.maxLife,
    required this.color,
    this.gravity = 0.0,
    this.rotation = 0.0,
    this.angularVel = 0.0,
    this.spriteVariant = 0,
  }) : life = maxLife;
}

/// Contiguous touching seam edge segment computed by `BoardView.OutlineEdgesTouching`
/// and passed into `MergeSplashVfx.Play`.
class MergeSplashEdge {
  final Vector2 center;
  final ui.Offset outwardDir;
  final int cells;

  const MergeSplashEdge({
    required this.center,
    required this.outwardDir,
    this.cells = 1,
  });
}

/// Computes the progressive escalation tier for `mergedNumber >= 32`:
/// - `mergedNumber < 32` (`2..16`): `0`
/// - `32 -> 1`, `64 -> 2`, `128 -> 3`, `256 -> 4`, `512 -> 5`, `1024 -> 6`, `2048 -> 7`, `4096+ -> 8`
int mergeEscalationTierForNumber(int mergedNumber) {
  if (mergedNumber < 32) return 0;
  int tier = 0;
  int v = mergedNumber;
  while (v >= 32 && tier < 8) {
    tier++;
    v ~/= 2;
  }
  return tier;
}

/// Authentic Unity `MergeSplash` (`BoardView.PlayMergeSplash` + `Glow_Ring.png`,
/// `Explosion_Halo.png`, `ParticleFlare.png`, and `Sparkle_01.png`), with progressive
/// tier escalation for `mergedNumber >= 32` (`Kiểu nổ to hơn, anim đã hơn`):
/// - Spawns outward cone/radial droplets & sparkles whose count, speed, and scale grow with `_tier`.
/// - For `mergedNumber >= 32` (`_tier = 1..8`), adds:
///   1. Bigger primary shockwave ring + secondary/tertiary supersonic shockwaves.
///   2. Rotating starburst god-rays radiating from the merge center.
///   3. High-energy fountain burst of 3D colored sand beads & diamond glints (`♦`) in the merged number's color.
class MergeSplashVfx extends PositionComponent {
  final Color primaryColor;
  final Color accentColor;
  final Color ringColor;
  final double cellSize;
  final int mergedNumber;
  late final int _tier;
  late final double _duration;
  final List<_VfxParticle> _particles = [];
  double _elapsed = 0.0;
  static const double _coneHalfAngleRad = 36.73 * math.pi / 360.0;

  ui.Image? _ringImg;
  ui.Image? _haloImg;
  ui.Image? _flareImg;

  MergeSplashVfx({
    required Vector2 centerPos,
    required this.primaryColor,
    required this.accentColor,
    Color? ringColor,
    ui.Offset pushDir = ui.Offset.zero,
    List<MergeSplashEdge>? edges,
    required this.cellSize,
    this.mergedNumber = 4,
  })  : ringColor = ringColor ?? accentColor,
        super(position: centerPos, priority: 200) {
    _tier = mergeEscalationTierForNumber(mergedNumber);
    _duration = 0.56 + 0.055 * _tier;

    _ringImg = _safeFlameImage('Glow_Ring.png');
    _haloImg = _safeFlameImage('Explosion_Halo.png');
    _flareImg = _safeFlameImage('ParticleFlare.png');

    final speedScale = 1.0 + 0.16 * _tier;
    final sizeScale = 1.0 + 0.11 * _tier;
    final lifeBoost = 0.035 * _tier;

    final rng = math.Random();
    if (edges != null && edges.isNotEmpty) {
      for (final edge in edges) {
        final outLen = edge.outwardDir.distance;
        final normOut = outLen > 1e-3
            ? edge.outwardDir / outLen
            : const ui.Offset(0.0, -1.0);
        final tangent = ui.Offset(-normOut.dy, normOut.dx);
        final baseAngle = math.atan2(normOut.dy, normOut.dx);
        final localEdgeCenter = ui.Offset(
          edge.center.x - centerPos.x,
          edge.center.y - centerPos.y,
        );
        final spanLength = math.max(1, edge.cells) * cellSize * 0.78;
        final dropletCount =
            ((4 + rng.nextInt(3) + _tier) * math.max(1, edge.cells)).clamp(4, 16);

        for (int i = 0; i < dropletCount; i++) {
          final alongOffset = (rng.nextDouble() - 0.5) * spanLength;
          final angle =
              baseAngle + (rng.nextDouble() * 2.0 - 1.0) * _coneHalfAngleRad;
          final dir = ui.Offset(math.cos(angle), math.sin(angle));
          final speed = cellSize * (2.0 + rng.nextDouble() * 1.6) * speedScale;
          final isBright = i % 4 == 0;
          _particles.add(
            _VfxParticle(
              pos: localEdgeCenter + tangent * alongOffset,
              vel: dir * speed,
              size: cellSize * (0.14 + rng.nextDouble() * 0.18) * sizeScale,
              maxLife: 0.28 + rng.nextDouble() * 0.17 + lifeBoost,
              color: isBright ? Colors.white : accentColor,
              gravity: 0.0,
              rotation: rng.nextDouble() * math.pi * 2,
              angularVel: (rng.nextDouble() - 0.5) * (6.0 + _tier * 1.5),
            ),
          );
        }
      }
    } else {
      final hasPush = pushDir.distance > 0.05;
      final normPush = hasPush ? pushDir / pushDir.distance : ui.Offset.zero;
      final tangent = ui.Offset(-normPush.dy, normPush.dx);

      final count = (14 + 3 * _tier).clamp(14, 22);
      for (int i = 0; i < count; i++) {
        final angle =
            (i / count) * math.pi * 2 + (rng.nextDouble() - 0.5) * 0.34;
        final dir = ui.Offset(math.cos(angle), math.sin(angle));
        final speed = cellSize * (2.0 + rng.nextDouble() * 1.6) * speedScale;
        final isBright = i % 4 == 0;
        final spawnOffset = hasPush
            ? tangent * ((rng.nextDouble() - 0.5) * cellSize * 0.52)
            : ui.Offset(
                (rng.nextDouble() - 0.5) * cellSize * 0.32,
                (rng.nextDouble() - 0.5) * cellSize * 0.32,
              );
        _particles.add(
          _VfxParticle(
            pos: spawnOffset,
            vel: dir * speed,
            size: cellSize * (0.14 + rng.nextDouble() * 0.18) * sizeScale,
            maxLife: 0.28 + rng.nextDouble() * 0.17 + lifeBoost,
            color: isBright ? Colors.white : accentColor,
            gravity: 0.0,
            rotation: rng.nextDouble() * math.pi * 2,
            angularVel: (rng.nextDouble() - 0.5) * (6.0 + _tier * 1.5),
          ),
        );
      }
    }
  }

  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _rayPaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _ringStrokePaint = ui.Paint()
    ..blendMode = BlendMode.plus
    ..style = ui.PaintingStyle.stroke;
  final ui.Paint _liquidWavePaint = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  final ui.Path _scratchPath = ui.Path();
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    final damp = math.pow(0.91, dt * 60.0).toDouble();
    for (final p in _particles) {
      p.life -= dt;
      p.vel = ui.Offset(p.vel.dx * damp, p.vel.dy * damp + p.gravity * dt);
      p.pos += p.vel * dt;
      p.rotation += p.angularVel * dt;
    }
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final radiusScale = 1.0 + 0.24 * _tier;

    // 0. Rotating starburst god-rays for `mergedNumber >= 32` (`_tier >= 1`)
    if (_tier >= 1) {
      final rayDur = 0.34 + 0.03 * _tier;
      final rayT = (_elapsed / rayDur).clamp(0.0, 1.0);
      if (rayT < 1.0) {
        final rayFade = (1.0 - rayT).clamp(0.0, 1.0);
        final rayCount = (5 + _tier).clamp(5, 8);
        final rayLen =
            cellSize * (0.75 + (0.95 + 0.22 * _tier) * math.sqrt(rayT));
        final rayHalfW = cellSize * (0.055 + 0.008 * _tier) * rayFade;
        _rayPaint.color = ringColor.withValues(
          alpha: (0.42 + 0.05 * _tier).clamp(0.0, 0.78) * rayFade,
        );
        _scratchPath.reset();
        for (int i = 0; i < rayCount; i++) {
          final ang = (i * math.pi * 2.0 / rayCount);
          final cosA = math.cos(ang);
          final sinA = math.sin(ang);
          final perpX = -sinA * rayHalfW;
          final perpY = cosA * rayHalfW;
          final tipX = cosA * rayLen;
          final tipY = sinA * rayLen;
          _scratchPath
            ..moveTo(perpX, perpY)
            ..lineTo(tipX, tipY)
            ..lineTo(-perpX, -perpY)
            ..close();
        }
        canvas.save();
        canvas.rotate(_elapsed * 2.6);
        canvas.drawPath(_scratchPath, _rayPaint);
        canvas.restore();
      }
    }

    // 1. Crisp `Glow_Ring.png` RG8 primary shockwave ring (scaled up progressively by `radiusScale`)
    final ringDur = 0.30 + 0.025 * _tier;
    final crispRingT = (_elapsed / ringDur).clamp(0.0, 1.0);
    if (crispRingT < 1.0) {
      final eased = 1.0 - math.pow(1.0 - crispRingT, 2.4).toDouble();
      final ringAlpha =
          ((1.0 - crispRingT) * (0.88 + 0.02 * _tier)).clamp(0.0, 1.0);
      final ringRadius = cellSize * (0.30 + eased * 1.18 * radiusScale);
      if (_ringImg != null) {
        _additivePaint.colorFilter = UnityChannelMaskFilters.rgDualChannelStar(
          ringColor,
          opacity: ringAlpha,
          coreWhite: 0.88,
        );
        canvas.drawImageRect(
          _ringImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _ringImg!.width.toDouble(),
            _ringImg!.height.toDouble(),
          ),
          ui.Rect.fromCircle(center: ui.Offset.zero, radius: ringRadius),
          _additivePaint,
        );
      }
    }

    // 1B. Secondary & Tertiary Supersonic Shockwave Rings for `mergedNumber >= 32` (`_tier >= 1`)
    if (_tier >= 1 && _elapsed >= 0.05) {
      final secDur = 0.36 + 0.035 * _tier;
      final secT = ((_elapsed - 0.05) / secDur).clamp(0.0, 1.0);
      if (secT < 1.0) {
        final eased2 = 1.0 - math.pow(1.0 - secT, 2.8).toDouble();
        final secR = cellSize * (0.42 + eased2 * (1.48 + 0.34 * _tier));
        final secAlpha = ((1.0 - secT) * 0.78).clamp(0.0, 1.0);
        _ringStrokePaint
          ..strokeWidth =
              (cellSize * (0.055 + 0.010 * _tier) * (1.0 - secT * 0.65))
                  .clamp(1.5, 9.0)
          ..color = ringColor.withValues(alpha: secAlpha);
        canvas.drawCircle(ui.Offset.zero, secR, _ringStrokePaint);
      }
    }
    if (_tier >= 3 && _elapsed >= 0.11) {
      final triDur = 0.38 + 0.03 * _tier;
      final triT = ((_elapsed - 0.11) / triDur).clamp(0.0, 1.0);
      if (triT < 1.0) {
        final eased3 = 1.0 - math.pow(1.0 - triT, 3.0).toDouble();
        final triR = cellSize * (0.55 + eased3 * (1.85 + 0.38 * _tier));
        final triAlpha = ((1.0 - triT) * 0.68).clamp(0.0, 1.0);
        _ringStrokePaint
          ..strokeWidth =
              (cellSize * 0.045 * (1.0 - triT * 0.7)).clamp(1.2, 7.0)
          ..color = Colors.white.withValues(alpha: triAlpha);
        canvas.drawCircle(ui.Offset.zero, triR, _ringStrokePaint);
      }
    }

    // 2. Soft `Explosion_Halo.png` R8 radial bloom
    final haloDur = 0.36 + 0.03 * _tier;
    final haloT = (_elapsed / haloDur).clamp(0.0, 1.0);
    if (haloT < 1.0) {
      final haloAlpha =
          ((1.0 - haloT) * (0.76 + 0.03 * _tier)).clamp(0.0, 1.0);
      final haloRadius =
          cellSize * (0.42 + haloT * 1.32 * (1.0 + 0.26 * _tier));
      if (_haloImg != null) {
        _additivePaint.colorFilter = UnityChannelMaskFilters.redChannelTint(
          accentColor,
          opacity: haloAlpha,
        );
        canvas.drawImageRect(
          _haloImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _haloImg!.width.toDouble(),
            _haloImg!.height.toDouble(),
          ),
          ui.Rect.fromCircle(center: ui.Offset.zero, radius: haloRadius),
          _additivePaint,
        );
      } else {
        _ringStrokePaint
          ..color = accentColor.withValues(alpha: haloAlpha)
          ..strokeWidth = cellSize * 0.12 * (1.0 - haloT * 0.7);
        canvas.drawCircle(ui.Offset.zero, haloRadius, _ringStrokePaint);
      }
    }

    // 3. Central `ParticleFlare.png` white-hot star flash at contact point
    final flareDur = 0.22 + 0.025 * _tier;
    final flareT = (_elapsed / flareDur).clamp(0.0, 1.0);
    if (flareT < 1.0 && _flareImg != null) {
      final r = cellSize * (0.58 + flareT * 0.68) * (1.0 + 0.26 * _tier);
      _additivePaint.colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: ((1.0 - flareT) * 0.92).clamp(0.0, 1.0)),
        BlendMode.modulate,
      );
      canvas.drawImageRect(
        _flareImg!,
        ui.Rect.fromLTWH(
          0,
          0,
          _flareImg!.width.toDouble(),
          _flareImg!.height.toDouble(),
        ),
        ui.Rect.fromCircle(center: ui.Offset.zero, radius: r),
        _additivePaint,
      );
    }

    // 4. Radial `Sparkle_01.png` RG8 dual-channel particles batched in 1 GPU `drawAtlas` call!
    final starImg = SparkleAtlas.starImage;
    if (starImg != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = SparkleAtlas.tileSize * 0.5;
      for (int i = 0; i < _particles.length; i++) {
        final p = _particles[i];
        if (p.life <= 0) continue;
        final t = (p.life / p.maxLife).clamp(0.0, 1.0);
        final s = p.size * (0.38 + 0.62 * t);
        if (s <= 0.3) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: p.rotation * 0.35,
            scale: s / SparkleAtlas.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: p.pos.dx,
            translateY: p.pos.dy,
          ),
        );
        _scratchRects.add(SparkleAtlas.tileRect);
        _scratchColors.add(p.color.withValues(alpha: t));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          starImg,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _additivePaint,
        );
      }
    } else {
      _additivePaint.colorFilter = null;
      for (final p in _particles) {
        if (p.life <= 0) continue;
        final t = (p.life / p.maxLife).clamp(0.0, 1.0);
        final s = p.size * (0.38 + 0.62 * t);
        _additivePaint.color = p.color.withValues(alpha: t);
        canvas.drawCircle(p.pos, s * 0.35, _additivePaint);
      }
    }

    // 5. Expanding Sloshing Liquid Wave Rings & Glossy Water Teardrop Splashes (`media_1794007349252.png` Panel 1)
    final waveDur = 0.42 + 0.03 * _tier;
    final waveT = (_elapsed / waveDur).clamp(0.0, 1.0);
    if (waveT < 1.0) {
      final easeOut = 1.0 - math.pow(1.0 - waveT, 2.2).toDouble();
      final fade = (1.0 - waveT).clamp(0.0, 1.0);
      final brightWave = Color.lerp(ringColor, Colors.white, 0.45)!;

      for (int wIdx = 0; wIdx < 2; wIdx++) {
        final rBase =
            cellSize * ((0.22 + wIdx * 0.14) + easeOut * (0.85 + 0.22 * _tier));
        _liquidWavePaint
          ..strokeWidth =
              (cellSize * (wIdx == 0 ? 0.052 : 0.032) * fade).clamp(1.2, 5.2)
          ..color = (wIdx == 0 ? brightWave : Colors.white)
              .withValues(alpha: (0.82 * fade).clamp(0.0, 1.0));
        canvas.drawCircle(ui.Offset.zero, rBase, _liquidWavePaint);
      }

      // Glossy 3D liquid droplets splashing radially outward (zero matrix push/pop)
      final dropCount = (6 + _tier).clamp(6, 12);
      final dropFillPaint = ui.Paint()..style = PaintingStyle.fill;
      final specPaint = ui.Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: (0.90 * fade).clamp(0.0, 1.0));

      for (int d = 0; d < dropCount; d++) {
        final ang = (d / dropCount) * math.pi * 2.0 + (d.isEven ? 0.18 : -0.14);
        final dist =
            cellSize * (0.30 + easeOut * (0.92 + 0.18 * (d % 3) + 0.16 * _tier));
        final r = (cellSize * (0.048 + 0.014 * (d % 2)) * (0.55 + 0.45 * fade))
            .clamp(1.4, 5.8);
        final dx = math.cos(ang) * dist;
        final dy = math.sin(ang) * dist + cellSize * 0.10 * waveT * waveT;
        final center = ui.Offset(dx, dy);

        dropFillPaint.color = (d % 3 == 0 ? brightWave : accentColor)
            .withValues(alpha: (0.88 * fade).clamp(0.0, 1.0));
        canvas.drawCircle(center, r, dropFillPaint);
        canvas.drawCircle(center + ui.Offset(r * 0.26, -r * 0.26), r * 0.38, specPaint);
      }
    }
  }
}

/// Crystalline ice shards bursting outward from `Ice_Shards.png` (3x2 6-shard atlas) +
/// `Explosion_Halo.png` frost shockwave when an `iceTarget` block shatters free.
class IceShatterVfx extends PositionComponent {
  final double cellSize;
  final List<_VfxParticle> _shards = [];
  final List<_VfxParticle> _frostMotes = [];
  double _elapsed = 0.0;
  static const double _duration = 0.74;

  ui.Image? _shardsAtlas;
  ui.Image? _haloImg;
  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _shardPaint = ui.Paint()..filterQuality = FilterQuality.low;

  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];

  IceShatterVfx({
    required Vector2 centerPos,
    required this.cellSize,
    List<Vector2>? worldCellCenters,
  }) : super(position: centerPos, priority: 210) {
    _shardsAtlas = _safeFlameImage('Ice_Shards.png');
    _haloImg = _safeFlameImage('Explosion_Halo.png');

    final localCenters = (worldCellCenters != null && worldCellCenters.isNotEmpty)
        ? worldCellCenters
            .map((w) => ui.Offset(w.x - centerPos.x, w.y - centerPos.y))
            .toList()
        : const <ui.Offset>[ui.Offset.zero];

    final rng = math.Random();
    final shardCount = math.min(34, 14 + localCenters.length * 4);
    for (int i = 0; i < shardCount; i++) {
      final origin = localCenters[i % localCenters.length];
      final angle = -math.pi * 0.92 + rng.nextDouble() * math.pi * 1.84;
      final speed = cellSize * (1.65 + rng.nextDouble() * 3.35);
      _shards.add(
        _VfxParticle(
          pos: origin +
              ui.Offset(
                (rng.nextDouble() - 0.5) * cellSize * 0.62,
                (rng.nextDouble() - 0.5) * cellSize * 0.62,
              ),
          vel: ui.Offset(
            math.cos(angle) * speed,
            math.sin(angle) * speed - cellSize * 1.25,
          ),
          size: cellSize * (0.28 + rng.nextDouble() * 0.25),
          maxLife: 0.42 + rng.nextDouble() * 0.28,
          color: i % 3 == 0 ? Colors.white : const Color(0xFFB3EEFF),
          gravity: cellSize * 8.8,
          rotation: rng.nextDouble() * math.pi * 2,
          angularVel: (rng.nextDouble() - 0.5) * 14.0,
          spriteVariant: i % 6,
        ),
      );
    }

    for (int i = 0; i < 10; i++) {
      final origin = localCenters[i % localCenters.length];
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = cellSize * (0.9 + rng.nextDouble() * 2.1);
      _frostMotes.add(
        _VfxParticle(
          pos: origin,
          vel: ui.Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          size: cellSize * (0.22 + rng.nextDouble() * 0.20),
          maxLife: 0.26 + rng.nextDouble() * 0.20,
          color: const Color(0xFF9BE8FF),
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    final shardDamp = math.pow(0.96, dt * 60.0).toDouble();
    final moteDamp = math.pow(0.92, dt * 60.0).toDouble();
    for (final s in _shards) {
      s.life -= dt;
      s.vel = ui.Offset(s.vel.dx * shardDamp, s.vel.dy + s.gravity * dt);
      s.pos += s.vel * dt;
      s.rotation += s.angularVel * dt;
    }
    for (final m in _frostMotes) {
      m.life -= dt;
      m.vel = m.vel * moteDamp;
      m.pos += m.vel * dt;
    }
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final flashT = (_elapsed / 0.28).clamp(0.0, 1.0);
    if (flashT < 1.0) {
      final r = cellSize * (0.48 + flashT * 1.20);
      if (_haloImg != null) {
        _additivePaint.colorFilter = UnityChannelMaskFilters.redChannelTint(
          const Color(0xFFC4F3FF),
          opacity: (1.0 - flashT) * 0.85,
        );
        canvas.drawImageRect(
          _haloImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _haloImg!.width.toDouble(),
            _haloImg!.height.toDouble(),
          ),
          ui.Rect.fromCircle(center: ui.Offset.zero, radius: r),
          _additivePaint,
        );
      } else {
        final haloCenterGlow = ui.Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            ui.Offset.zero,
            r * 1.15,
            [
              const Color(0xFFBDF0FF).withValues(alpha: (1.0 - flashT) * 0.58),
              const Color(0xFFBDF0FF).withValues(alpha: 0.0),
            ],
          );
        canvas.drawCircle(ui.Offset.zero, r * 1.15, haloCenterGlow);
      }
    }

    final moteAtlas = SparkleAtlas.starImage;
    if (moteAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = SparkleAtlas.tileSize * 0.5;
      for (int i = 0; i < _frostMotes.length; i++) {
        final m = _frostMotes[i];
        if (m.life <= 0) continue;
        final t = (m.life / m.maxLife).clamp(0.0, 1.0);
        final sz = m.size * (0.4 + 0.6 * t);
        if (sz <= 0.3) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: 0.0,
            scale: sz / SparkleAtlas.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: m.pos.dx,
            translateY: m.pos.dy,
          ),
        );
        _scratchRects.add(SparkleAtlas.tileRect);
        _scratchColors.add(m.color.withValues(alpha: t * 0.9));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          moteAtlas,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _additivePaint,
        );
      }
    }

    final atlas = _shardsAtlas;
    if (atlas != null) {
      // `Ice_Shards.png` is a 3 columns x 2 rows (6-shard) sprite sheet: batch all 34 shards in 1 GPU call!
      final tileW = atlas.width / 3.0;
      final tileH = atlas.height / 2.0;
      final avgTile = (tileW + tileH) * 0.5;
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      for (int i = 0; i < _shards.length; i++) {
        final s = _shards[i];
        if (s.life <= 0) continue;
        final t = (s.life / s.maxLife).clamp(0.0, 1.0);
        final sz = s.size * (0.55 + 0.45 * t);
        if (sz <= 0.3) continue;
        final col = s.spriteVariant % 3;
        final row = (s.spriteVariant ~/ 3) % 2;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: s.rotation,
            scale: sz / avgTile,
            anchorX: tileW * 0.5,
            anchorY: tileH * 0.5,
            translateX: s.pos.dx,
            translateY: s.pos.dy,
          ),
        );
        _scratchRects.add(ui.Rect.fromLTWH(col * tileW, row * tileH, tileW, tileH));
        _scratchColors.add(s.color.withValues(alpha: t * 0.95));
      }
      if (_scratchTransforms.isNotEmpty) {
        _shardPaint.colorFilter = null;
        canvas.drawAtlas(
          atlas,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _shardPaint,
        );
      }
    } else {
      for (final s in _shards) {
        if (s.life <= 0) continue;
        final t = (s.life / s.maxLife).clamp(0.0, 1.0);
        final sz = s.size * (0.55 + 0.45 * t);
        final r = sz * 0.45;
        canvas.save();
        canvas.translate(s.pos.dx, s.pos.dy);
        canvas.rotate(s.rotation);
        final shardPath = ui.Path()
          ..moveTo(0, -r)
          ..lineTo(r * 0.75, 0)
          ..lineTo(0, r * 1.1)
          ..lineTo(-r * 0.65, r * 0.15)
          ..close();
        canvas.drawPath(
          shardPath,
          ui.Paint()..color = s.color.withValues(alpha: t * 0.92),
        );
        canvas.restore();
      }
    }
  }
}

/// Subtle frost chip burst (`sfx_ice_break_small.wav`) when tapping or nudging a frozen block.
class IceChipVfx extends PositionComponent {
  final double cellSize;
  final List<_VfxParticle> _chips = [];
  double _elapsed = 0.0;
  static const double _duration = 0.42;
  ui.Image? _shardsAtlas;
  final ui.Paint _chipPaint = ui.Paint()..filterQuality = FilterQuality.low;
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];

  IceChipVfx({
    required Vector2 centerPos,
    required this.cellSize,
  }) : super(position: centerPos, priority: 208) {
    _shardsAtlas = _safeFlameImage('Ice_Shards.png');
    final rng = math.Random();
    for (int i = 0; i < 5; i++) {
      final angle = -math.pi * 0.85 + rng.nextDouble() * math.pi * 0.70;
      final speed = cellSize * (0.85 + rng.nextDouble() * 1.35);
      _chips.add(
        _VfxParticle(
          pos: ui.Offset(
            (rng.nextDouble() - 0.5) * cellSize * 0.45,
            (rng.nextDouble() - 0.5) * cellSize * 0.35,
          ),
          vel: ui.Offset(
            math.cos(angle) * speed,
            math.sin(angle) * speed - cellSize * 0.65,
          ),
          size: cellSize * (0.16 + rng.nextDouble() * 0.11),
          maxLife: 0.26 + rng.nextDouble() * 0.14,
          color: i.isEven ? Colors.white : const Color(0xFFC2F2FF),
          gravity: cellSize * 7.2,
          rotation: rng.nextDouble() * math.pi * 2,
          angularVel: (rng.nextDouble() - 0.5) * 12.0,
          spriteVariant: rng.nextInt(6),
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    final damp = math.pow(0.95, dt * 60.0).toDouble();
    for (final c in _chips) {
      c.life -= dt;
      c.vel = ui.Offset(c.vel.dx * damp, c.vel.dy + c.gravity * dt);
      c.pos += c.vel * dt;
      c.rotation += c.angularVel * dt;
    }
    if (_elapsed >= _duration) removeFromParent();
  }

  @override
  void render(ui.Canvas canvas) {
    final atlas = _shardsAtlas;
    if (atlas != null) {
      final tileW = atlas.width / 3.0;
      final tileH = atlas.height / 2.0;
      final avgTile = (tileW + tileH) * 0.5;
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      for (int i = 0; i < _chips.length; i++) {
        final c = _chips[i];
        if (c.life <= 0) continue;
        final t = (c.life / c.maxLife).clamp(0.0, 1.0);
        final sz = c.size * (0.5 + 0.5 * t);
        if (sz <= 0.3) continue;
        final col = c.spriteVariant % 3;
        final row = (c.spriteVariant ~/ 3) % 2;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: c.rotation,
            scale: sz / avgTile,
            anchorX: tileW * 0.5,
            anchorY: tileH * 0.5,
            translateX: c.pos.dx,
            translateY: c.pos.dy,
          ),
        );
        _scratchRects.add(ui.Rect.fromLTWH(col * tileW, row * tileH, tileW, tileH));
        _scratchColors.add(c.color.withValues(alpha: t * 0.90));
      }
      if (_scratchTransforms.isNotEmpty) {
        _chipPaint.colorFilter = null;
        canvas.drawAtlas(
          atlas,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _chipPaint,
        );
      }
      return;
    }

    for (final c in _chips) {
      if (c.life <= 0) continue;
      final t = (c.life / c.maxLife).clamp(0.0, 1.0);
      final sz = c.size * (0.5 + 0.5 * t);
      canvas.drawCircle(
        c.pos,
        sz * 0.35,
        ui.Paint()..color = c.color.withValues(alpha: t * 0.85),
      );
    }
  }
}

/// Trailing `Sparkle_01.png` RG8 burst during `Level Up` power-up block flight.
class LevelUpSparksVfx extends PositionComponent {
  final Color color;
  final double cellSize;
  final List<_VfxParticle> _sparks = [];
  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];

  LevelUpSparksVfx({
    required Vector2 pos,
    required this.color,
    required this.cellSize,
  }) : super(position: pos, priority: 205) {
    final rng = math.Random();
    for (int i = 0; i < 8; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final sp = cellSize * (0.6 + rng.nextDouble() * 1.5);
      _sparks.add(
        _VfxParticle(
          pos: ui.Offset.zero,
          vel: ui.Offset(math.cos(a) * sp, math.sin(a) * sp),
          size: cellSize * (0.20 + rng.nextDouble() * 0.18),
          maxLife: 0.26 + rng.nextDouble() * 0.16,
          color: i.isEven ? Colors.white : color,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    bool anyAlive = false;
    for (final s in _sparks) {
      s.life -= dt;
      if (s.life > 0) {
        anyAlive = true;
        s.pos += s.vel * dt;
      }
    }
    if (!anyAlive) removeFromParent();
  }

  @override
  void render(ui.Canvas canvas) {
    final starAtlas = SparkleAtlas.starImage;
    if (starAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = SparkleAtlas.tileSize * 0.5;
      for (int i = 0; i < _sparks.length; i++) {
        final s = _sparks[i];
        if (s.life <= 0) continue;
        final t = (s.life / s.maxLife).clamp(0.0, 1.0);
        final sz = s.size * t;
        if (sz <= 0.3) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: 0.0,
            scale: sz / SparkleAtlas.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: s.pos.dx,
            translateY: s.pos.dy,
          ),
        );
        _scratchRects.add(SparkleAtlas.tileRect);
        _scratchColors.add(s.color.withValues(alpha: t));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          starAtlas,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _additivePaint,
        );
      }
      return;
    }

    _additivePaint.colorFilter = null;
    for (final s in _sparks) {
      if (s.life <= 0) continue;
      final t = (s.life / s.maxLife).clamp(0.0, 1.0);
      final sz = s.size * t;
      _additivePaint.color = s.color.withValues(alpha: t);
      canvas.drawCircle(s.pos, sz * 0.35, _additivePaint);
    }
  }
}

/// Floating `PowerUp_Icon_Arrow.png` reveal indicator over the target block
/// when `Level Up` power-up activates (`sfx_powerup_levelup_arrow.wav`).
class LevelUpRevealArrowVfx extends PositionComponent {
  final double cellSize;
  final double duration;
  double _elapsed = 0.0;
  ui.Image? _arrowImg;
  final ui.Paint _arrowPaint = ui.Paint()..filterQuality = FilterQuality.medium;

  LevelUpRevealArrowVfx({
    required Vector2 targetCenter,
    required this.cellSize,
    this.duration = 0.72,
  }) : super(position: targetCenter, priority: 215) {
    _arrowImg = _safeFlameImage('PowerUp_Icon_Arrow.png');
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= duration) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final img = _arrowImg;
    if (img == null) return;
    final t = (_elapsed / duration).clamp(0.0, 1.0);
    final pop = t < 0.24
        ? (0.45 + 0.70 * (t / 0.24))
        : (1.15 - 0.15 * ((t - 0.24) / 0.76));
    final rise = -cellSize * (0.42 + 0.45 * math.sin(t * math.pi * 0.85));
    final alpha = t > 0.72 ? ((1.0 - t) / 0.28).clamp(0.0, 1.0) : 1.0;

    final h = cellSize * 0.72 * pop;
    final w = h * (img.width / img.height);
    _arrowPaint.color = Colors.white.withValues(alpha: alpha);
    canvas.save();
    canvas.translate(0, rise);
    canvas.rotate(math.pi);
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromCenter(center: ui.Offset.zero, width: w, height: h),
      _arrowPaint,
    );
    canvas.restore();
  }
}

/// Authentic `VFX_MergeSparks` (`BoardView.PlayMergeSparksAsync` + `SpawnSparksOnBlocks`):
/// Waits `mergeSparksDelay` (`0.10s`) after merge commit, then spawns upward-accelerating
/// (`gravityModifier = -10.0`) `Sparkle_01.png` RG8 sparks across every block cell of the
/// merged survivor (`box = (0.80, 0.70) * cs`, `downOffset = 0.15 * cs`, `life = 0.20..0.30s`).
class MergeBlockSparksVfx extends PositionComponent {
  final List<Vector2> Function() cellCentersProvider;
  final Color accentColor;
  final double cellSize;
  final double downOffsetCells;
  final double liftCells;
  final int mergedNumber;
  double _delayRemaining;
  bool _spawned = false;
  final List<_VfxParticle> _sparks = [];
  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];

  MergeBlockSparksVfx({
    required this.cellCentersProvider,
    required this.accentColor,
    required this.cellSize,
    double delaySeconds = 0.10,
    this.downOffsetCells = 0.15,
    this.liftCells = 0.15,
    this.mergedNumber = 4,
  })  : _delayRemaining = delaySeconds,
        super(position: Vector2.zero(), priority: 206) {
    if (_delayRemaining <= 0.0) {
      _spawnNow();
    }
  }

  void _spawnNow() {
    if (_spawned) return;
    _spawned = true;
    final centers = cellCentersProvider();
    if (centers.isEmpty) {
      removeFromParent();
      return;
    }

    final rng = math.Random();
    final tier = mergeEscalationTierForNumber(mergedNumber);
    final sparksPerBlock = 6 + 3 * tier;
    final sizeScale = 1.0 + 0.12 * tier;
    final velScale = 1.0 + 0.12 * tier;
    final lifeBoost = 0.025 * tier;

    for (final c in centers) {
      final baseOffset = ui.Offset(
        c.x,
        c.y + (downOffsetCells - liftCells * 0.5) * cellSize,
      );
      for (int i = 0; i < sparksPerBlock; i++) {
        final boxOffset = ui.Offset(
          (rng.nextDouble() - 0.5) * (0.80 + 0.05 * tier) * cellSize,
          (rng.nextDouble() - 0.5) * (0.70 + 0.04 * tier) * cellSize,
        );
        final initVel = ui.Offset(
          (rng.nextDouble() - 0.5) * 0.65 * cellSize * velScale,
          -(0.45 + rng.nextDouble() * 0.75) * cellSize * velScale,
        );
        _sparks.add(
          _VfxParticle(
            pos: baseOffset + boxOffset,
            vel: initVel,
            size: cellSize * (0.14 + rng.nextDouble() * 0.08) * sizeScale,
            maxLife: 0.20 + rng.nextDouble() * 0.10 + lifeBoost,
            color: i % 3 == 0 ? Colors.white : accentColor,
            gravity: -10.0 * cellSize * velScale,
            rotation: rng.nextDouble() * math.pi * 2,
            angularVel: (rng.nextDouble() - 0.5) * (5.0 + 0.8 * tier),
          ),
        );
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_spawned) {
      _delayRemaining -= dt;
      if (_delayRemaining <= 0.0) {
        _spawnNow();
      }
      return;
    }

    final damp = math.pow(0.96, dt * 60.0).toDouble();
    bool anyAlive = false;
    for (final s in _sparks) {
      s.life -= dt;
      if (s.life > 0) {
        anyAlive = true;
        s.vel = ui.Offset(s.vel.dx * damp, s.vel.dy + s.gravity * dt);
        s.pos += s.vel * dt;
        s.rotation += s.angularVel * dt;
      }
    }
    if (!anyAlive) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    if (!_spawned) return;
    final starAtlas = SparkleAtlas.starImage;
    if (starAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = SparkleAtlas.tileSize * 0.5;
      for (int i = 0; i < _sparks.length; i++) {
        final s = _sparks[i];
        if (s.life <= 0) continue;
        final remFrac = (s.life / s.maxLife).clamp(0.0, 1.0);
        final ageFrac = 1.0 - remFrac;
        final sizeCurve = ageFrac < 0.25
            ? (0.45 + 0.55 * (ageFrac / 0.25))
            : ((1.0 - ageFrac) / 0.75).clamp(0.0, 1.0);
        final sz = s.size * (0.45 + 0.85 * sizeCurve);
        if (sz <= 0.4) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: s.rotation * 0.25,
            scale: sz / SparkleAtlas.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: s.pos.dx,
            translateY: s.pos.dy,
          ),
        );
        _scratchRects.add(SparkleAtlas.tileRect);
        _scratchColors.add(s.color.withValues(alpha: remFrac));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          starAtlas,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _additivePaint,
        );
      }
      return;
    }

    _additivePaint.colorFilter = null;
    for (final s in _sparks) {
      if (s.life <= 0) continue;
      final remFrac = (s.life / s.maxLife).clamp(0.0, 1.0);
      final ageFrac = 1.0 - remFrac;
      final sizeCurve = ageFrac < 0.25
          ? (0.45 + 0.55 * (ageFrac / 0.25))
          : ((1.0 - ageFrac) / 0.75).clamp(0.0, 1.0);
      final sz = s.size * (0.45 + 0.85 * sizeCurve);
      if (sz <= 0.4) continue;
      _additivePaint.color = s.color.withValues(alpha: remFrac);
      canvas.drawCircle(s.pos, sz * 0.35, _additivePaint);
    }
  }
}

/// Visual & text configuration for a consecutive merge combo tier (`x1, x2, x3...`).
class ComboPraiseTier {
  final int comboCount;
  final String comboLabel;
  final String? praiseText;
  final Color primaryColor;
  final Color secondaryColor;
  final Color strokeColor;
  final double scaleBoost;

  const ComboPraiseTier({
    required this.comboCount,
    required this.comboLabel,
    required this.praiseText,
    required this.primaryColor,
    required this.secondaryColor,
    required this.strokeColor,
    required this.scaleBoost,
  });

  static ComboPraiseTier forCombo(int comboCount) {
    final c = math.max(1, comboCount);
    switch (c) {
      case 1:
        return const ComboPraiseTier(
          comboCount: 1,
          comboLabel: 'X1',
          praiseText: null,
          primaryColor: Color(0xFF48E5FF),
          secondaryColor: Color(0xFFAAFAFF),
          strokeColor: Color(0xFF0A2E46),
          scaleBoost: 0.92,
        );
      case 2:
        return const ComboPraiseTier(
          comboCount: 2,
          comboLabel: 'X2',
          praiseText: 'NICE!',
          primaryColor: Color(0xFF2AF598),
          secondaryColor: Color(0xFFB8FFDF),
          strokeColor: Color(0xFF093824),
          scaleBoost: 0.99,
        );
      case 3:
        return const ComboPraiseTier(
          comboCount: 3,
          comboLabel: 'X3',
          praiseText: 'GREAT!',
          primaryColor: Color(0xFFFFD200),
          secondaryColor: Color(0xFFFFF3A1),
          strokeColor: Color(0xFF4A2500),
          scaleBoost: 1.06,
        );
      case 4:
        return const ComboPraiseTier(
          comboCount: 4,
          comboLabel: 'X4',
          praiseText: 'AWESOME!',
          primaryColor: Color(0xFFFF7A00),
          secondaryColor: Color(0xFFFFD08A),
          strokeColor: Color(0xFF4A1200),
          scaleBoost: 1.12,
        );
      case 5:
        return const ComboPraiseTier(
          comboCount: 5,
          comboLabel: 'X5',
          praiseText: 'AMAZING!',
          primaryColor: Color(0xFFFF2A85),
          secondaryColor: Color(0xFFFFB2D6),
          strokeColor: Color(0xFF480624),
          scaleBoost: 1.18,
        );
      case 6:
        return const ComboPraiseTier(
          comboCount: 6,
          comboLabel: 'X6',
          praiseText: 'BRILLIANT!',
          primaryColor: Color(0xFFB721FF),
          secondaryColor: Color(0xFFEAC2FF),
          strokeColor: Color(0xFF2B0548),
          scaleBoost: 1.18,
        );
      case 7:
        return const ComboPraiseTier(
          comboCount: 7,
          comboLabel: 'X7',
          praiseText: 'EXCELLENT!',
          primaryColor: Color(0xFF00E5FF),
          secondaryColor: Color(0xFFC4FBFF),
          strokeColor: Color(0xFF003847),
          scaleBoost: 1.18,
        );
      case 8:
        return const ComboPraiseTier(
          comboCount: 8,
          comboLabel: 'X8',
          praiseText: 'FLAWLESS!',
          primaryColor: Color(0xFFFF2B58),
          secondaryColor: Color(0xFFFFB5C8),
          strokeColor: Color(0xFF4D0014),
          scaleBoost: 1.18,
        );
      case 9:
        return const ComboPraiseTier(
          comboCount: 9,
          comboLabel: 'X9',
          praiseText: 'LEGENDARY!',
          primaryColor: Color(0xFFFFD700),
          secondaryColor: Color(0xFFFFF8DC),
          strokeColor: Color(0xFF4A2800),
          scaleBoost: 1.18,
        );
      default:
        return ComboPraiseTier(
          comboCount: c,
          comboLabel: 'X$c',
          praiseText: 'INCREDIBLE!',
          primaryColor: const Color(0xFFFFEE55),
          secondaryColor: const Color(0xFFFFFFFF),
          strokeColor: const Color(0xFF4D0A00),
          scaleBoost: 1.18,
        );
    }
  }
}

/// Cached CPU vector layout for the 3D stroked `X1, X2, X3...` pill + praise callout.
/// Layout is computed once in CPU memory per combo count and cell size with ZERO GPU texture
/// allocation or synchronous `toImageSync` blocking!
class _ComboBadgeLayout {
  final ui.Image? bakedImage;
  final ui.Rect srcRect;
  final TextPainter comboFillTp;
  final TextPainter comboStrokeTp;
  final TextPainter? praiseFillTp;
  final TextPainter? praiseStrokeTp;
  final ui.RRect pillRRect;
  final ui.Offset comboOffset;
  final ui.Offset? praiseOffset;
  final ui.Rect bounds;

  const _ComboBadgeLayout({
    this.bakedImage,
    required this.srcRect,
    required this.comboFillTp,
    required this.comboStrokeTp,
    this.praiseFillTp,
    this.praiseStrokeTp,
    required this.pillRRect,
    required this.comboOffset,
    this.praiseOffset,
    required this.bounds,
  });
}

class _ComboBadgeLayoutCache {
  _ComboBadgeLayoutCache._();

  static final Map<int, _ComboBadgeLayout> _cache = <int, _ComboBadgeLayout>{};

  static _ComboBadgeLayout? getOrCreate(
    ComboPraiseTier tier,
    double cellSize,
  ) {
    final sizeBucket = (cellSize * 2.0).round().clamp(40, 440);
    final key = (tier.comboCount << 16) | sizeBucket;
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    try {
      final comboFontSize =
          (cellSize * 0.36 * tier.scaleBoost).clamp(18.0, 40.0);
      final comboStrokeTp = _layoutText(
        text: tier.comboLabel,
        fontSize: comboFontSize,
        foreground: ui.Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (comboFontSize * 0.24).clamp(3.5, 7.5)
          ..strokeJoin = StrokeJoin.round
          ..color = tier.strokeColor,
      );
      final comboFillTp = _layoutText(
        text: tier.comboLabel,
        fontSize: comboFontSize,
        foreground: ui.Paint()..color = Colors.white,
      );

      TextPainter? praiseStrokeTp;
      TextPainter? praiseFillTp;
      if (tier.praiseText != null) {
        final praiseFontSize =
            (cellSize * 0.46 * tier.scaleBoost).clamp(22.0, 52.0);
        praiseStrokeTp = _layoutText(
          text: tier.praiseText!,
          fontSize: praiseFontSize,
          foreground: ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (praiseFontSize * 0.25).clamp(4.5, 9.5)
            ..strokeJoin = StrokeJoin.round
            ..color = tier.strokeColor,
        );
        praiseFillTp = _layoutText(
          text: tier.praiseText!,
          fontSize: praiseFontSize,
          foreground: ui.Paint()..color = tier.primaryColor,
        );
      }

      final hasPraise = praiseStrokeTp != null && praiseFillTp != null;
      final pillW = comboFillTp.width + cellSize * 0.34;
      final pillH = comboFillTp.height + cellSize * 0.10;
      final maxW = math.max(pillW, praiseFillTp?.width ?? 0.0) + 28.0;
      final totalH = pillH + (hasPraise ? praiseFillTp.height + 20.0 : 16.0);

      final topY = hasPraise
          ? -comboFillTp.height * 0.95
          : -comboFillTp.height * 0.5;
      final pillRRect = ui.RRect.fromRectAndRadius(
        ui.Rect.fromCenter(
          center: ui.Offset(0.0, topY + comboFillTp.height * 0.5),
          width: pillW,
          height: pillH,
        ),
        ui.Radius.circular(pillH * 0.5),
      );

      final comboOffset = ui.Offset(-comboFillTp.width * 0.5, topY);
      final praiseOffset = hasPraise
          ? ui.Offset(
              -praiseFillTp.width * 0.5,
              topY + comboFillTp.height * 0.88,
            )
          : null;

      final bounds = ui.Rect.fromCenter(
        center: ui.Offset(0.0, topY + comboFillTp.height * 0.5),
        width: maxW,
        height: totalH,
      );

      ui.Image? bakedImg;
      ui.Rect srcRect = ui.Rect.zero;
      try {
        const ss = 2.0;
        final imgW = (bounds.width * ss).ceil().clamp(4, 1024);
        final imgH = (bounds.height * ss).ceil().clamp(4, 1024);
        final rec = ui.PictureRecorder();
        final rc = ui.Canvas(rec);
        rc.scale(imgW / bounds.width, imgH / bounds.height);
        rc.translate(-bounds.left, -bounds.top);

        rc.drawRRect(
          pillRRect,
          ui.Paint()
            ..style = PaintingStyle.fill
            ..color = tier.strokeColor.withValues(alpha: 0.88),
        );
        rc.drawRRect(
          pillRRect,
          ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = tier.primaryColor,
        );
        comboStrokeTp.paint(rc, comboOffset + const ui.Offset(0.0, 1.5));
        comboStrokeTp.paint(rc, comboOffset);
        comboFillTp.paint(rc, comboOffset);
        if (hasPraise && praiseOffset != null) {
          praiseStrokeTp.paint(rc, praiseOffset + const ui.Offset(0.0, 2.8));
          praiseStrokeTp.paint(rc, praiseOffset);
          praiseFillTp.paint(rc, praiseOffset);
        }
        final pic = rec.endRecording();
        bakedImg = pic.toImageSync(imgW, imgH);
        pic.dispose();
        srcRect = ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble());
      } catch (_) {
        bakedImg = null;
      }

      final layout = _ComboBadgeLayout(
        bakedImage: bakedImg,
        srcRect: srcRect,
        comboFillTp: comboFillTp,
        comboStrokeTp: comboStrokeTp,
        praiseFillTp: praiseFillTp,
        praiseStrokeTp: praiseStrokeTp,
        pillRRect: pillRRect,
        comboOffset: comboOffset,
        praiseOffset: praiseOffset,
        bounds: bounds,
      );

      if (_cache.length >= 32) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = layout;
      return layout;
    } catch (_) {
      return null;
    }
  }

  static TextPainter _layoutText({
    required String text,
    required double fontSize,
    required ui.Paint foreground,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Baloo2',
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          height: 1.0,
          letterSpacing: 0.6,
          foreground: foreground,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }
}

/// Floating 3D combo badge (`COMBO x2, x3...`) and praise callout (`NICE!`, `GREAT!`,
/// `AWESOME!`, `AMAZING!`, `BRILLIANT!`, `EXCELLENT!`, `FLAWLESS!`, `LEGENDARY!`, `INCREDIBLE!`)
/// spawned above the merged piece.
class ComboPraiseCalloutVfx extends PositionComponent {
  final ComboPraiseTier tier;
  final double cellSize;
  final double duration;
  double _elapsed = 0.0;

  _ComboBadgeLayout? _badgeLayout;

  @visibleForTesting
  String? get debugRenderedComboLabel =>
      _badgeLayout?.comboFillTp.text?.toPlainText();

  final List<_VfxParticle> _burstParticles = <_VfxParticle>[];
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];
  ui.Image? _ringImg;
  final ui.Paint _ringPaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _sparkPaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _pillFillPaint = ui.Paint()..style = PaintingStyle.fill;
  final ui.Paint _pillBorderPaint = ui.Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  final ui.Paint _fadePaint = ui.Paint();

  ComboPraiseCalloutVfx({
    required Vector2 anchorWorld,
    required int comboCount,
    required this.cellSize,
    double? minWorldX,
    double? maxWorldX,
    double? minWorldY,
  })  : tier = ComboPraiseTier.forCombo(comboCount),
        duration = comboCount <= 1 ? 0.68 : 0.92,
        super(
          position: Vector2(
            minWorldX != null && maxWorldX != null && minWorldX <= maxWorldX
                ? anchorWorld.x.clamp(minWorldX, maxWorldX)
                : anchorWorld.x,
            minWorldY != null
                ? math.max(anchorWorld.y - cellSize * 0.42, minWorldY)
                : (anchorWorld.y - cellSize * 0.42),
          ),
          priority: 240,
        ) {
    _ringImg = _safeFlameImage('Glow_Ring.png');
    _badgeLayout = _ComboBadgeLayoutCache.getOrCreate(tier, cellSize);

    if (tier.comboCount >= 2) {
      final rng = math.Random(tier.comboCount * 997);
      final count = (8 + tier.comboCount.clamp(1, 5) * 2).clamp(10, 18);
      for (int i = 0; i < count; i++) {
        final angle =
            (i / count) * math.pi * 2 + (rng.nextDouble() - 0.5) * 0.35;
        final speed =
            cellSize * (0.95 + rng.nextDouble() * 1.45) * tier.scaleBoost;
        _burstParticles.add(
          _VfxParticle(
            pos: ui.Offset.zero,
            vel: ui.Offset(math.cos(angle) * speed, math.sin(angle) * speed),
            size: cellSize * (0.14 + rng.nextDouble() * 0.12) * tier.scaleBoost,
            maxLife: 0.36 + rng.nextDouble() * 0.24,
            color: i.isEven ? Colors.white : tier.primaryColor,
            gravity: cellSize * 1.6,
            rotation: rng.nextDouble() * math.pi * 2,
            angularVel: (rng.nextDouble() - 0.5) * 7.0,
          ),
        );
      }
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= duration) {
      removeFromParent();
      return;
    }

    final drag = math.pow(0.90, dt * 60.0).toDouble();
    for (final p in _burstParticles) {
      p.life -= dt;
      if (p.life > 0) {
        p.vel = ui.Offset(p.vel.dx * drag, p.vel.dy * drag + p.gravity * dt);
        p.pos += p.vel * dt;
        p.rotation += p.angularVel * dt;
      }
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final t = (_elapsed / duration).clamp(0.0, 1.0);

    // 3-stage pop -> hold -> float-fade curve
    final double scale;
    final double tiltRad;
    if (t < 0.20) {
      final u = (t / 0.20).clamp(0.0, 1.0);
      final ease = Curves.easeOutBack.transform(u);
      scale = 0.25 + 0.90 * ease;
      tiltRad = (1.0 - u) * -0.09;
    } else if (t < 0.65) {
      final u = ((t - 0.20) / 0.45).clamp(0.0, 1.0);
      scale = 1.15 - 0.15 * Curves.easeOut.transform(u);
      tiltRad = math.sin(u * math.pi) * 0.025;
    } else {
      final u = ((t - 0.65) / 0.35).clamp(0.0, 1.0);
      scale = 1.0 + 0.08 * u;
      tiltRad = 0.0;
    }

    final double alpha = t < 0.10
        ? (t / 0.10).clamp(0.0, 1.0)
        : (t > 0.68 ? ((1.0 - t) / 0.32).clamp(0.0, 1.0) : 1.0);
    if (alpha <= 0.01) return;

    final riseY = -cellSize * (0.18 + 0.58 * Curves.easeOutCubic.transform(t));

    // 1. Expanding RG8 halo ring for combo >= 3
    if (tier.comboCount >= 3 && t < 0.52) {
      final ringU = (t / 0.52).clamp(0.0, 1.0);
      final ringRadius = cellSize *
          (0.35 + 1.35 * Curves.easeOutCubic.transform(ringU)) *
          tier.scaleBoost;
      final ringAlpha = (1.0 - ringU) * 0.55 * alpha;
      final ringImg = _ringImg;
      if (ringImg != null) {
        _ringPaint.colorFilter = UnityChannelMaskFilters.rgDualChannelStar(
          tier.primaryColor,
          opacity: ringAlpha,
          coreWhite: 0.88,
        );
        canvas.drawImageRect(
          ringImg,
          ui.Rect.fromLTWH(
            0,
            0,
            ringImg.width.toDouble(),
            ringImg.height.toDouble(),
          ),
          ui.Rect.fromCenter(
            center: ui.Offset(0, riseY),
            width: ringRadius * 2.0,
            height: ringRadius * 2.0,
          ),
          _ringPaint,
        );
      }
    }

    // 2. Burst sparkles batched into a single `Canvas.drawAtlas` GPU call
    final starAtlas = SparkleAtlas.starImage;
    if (starAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = SparkleAtlas.tileSize * 0.5;
      for (int i = 0; i < _burstParticles.length; i++) {
        final p = _burstParticles[i];
        if (p.life <= 0) continue;
        final rem = (p.life / p.maxLife).clamp(0.0, 1.0);
        final sz = p.size * rem;
        if (sz <= 0.5) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: p.rotation * 0.35,
            scale: sz / SparkleAtlas.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: p.pos.dx,
            translateY: p.pos.dy + riseY * 0.5,
          ),
        );
        _scratchRects.add(SparkleAtlas.tileRect);
        _scratchColors.add(p.color.withValues(alpha: rem * alpha));
      }
      if (_scratchTransforms.isNotEmpty) {
        _sparkPaint.colorFilter = null;
        canvas.drawAtlas(
          starAtlas,
          _scratchTransforms,
          _scratchRects,
          _scratchColors,
          BlendMode.modulate,
          null,
          _sparkPaint,
        );
      }
    } else {
      _sparkPaint.colorFilter = null;
      for (final p in _burstParticles) {
        if (p.life <= 0) continue;
        final rem = (p.life / p.maxLife).clamp(0.0, 1.0);
        final sz = p.size * rem;
        if (sz <= 0.5) continue;
        final pos = ui.Offset(p.pos.dx, p.pos.dy + riseY * 0.5);
        _sparkPaint.color = p.color.withValues(alpha: rem * alpha);
        canvas.drawCircle(pos, sz * 0.35, _sparkPaint);
      }
    }

    // 3. Pre-composited badge sprite rendering (zero saveLayer & zero per-frame text layout/paint!)
    final layout = _badgeLayout;
    if (layout != null) {
      canvas.save();
      canvas.translate(0.0, riseY);
      canvas.rotate(tiltRad);
      canvas.scale(scale, scale);

      final bakedImg = layout.bakedImage;
      if (bakedImg != null) {
        _fadePaint
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, alpha);
        canvas.drawImageRect(
          bakedImg,
          layout.srcRect,
          layout.bounds,
          _fadePaint,
        );
      } else {
        final bool hasFade = alpha < 0.98;
        if (hasFade) {
          _fadePaint.color = Color.fromRGBO(255, 255, 255, alpha);
          canvas.saveLayer(layout.bounds, _fadePaint);
        }

        _pillFillPaint.color = tier.strokeColor.withValues(alpha: 0.88);
        canvas.drawRRect(layout.pillRRect, _pillFillPaint);

        _pillBorderPaint.color = tier.primaryColor;
        canvas.drawRRect(layout.pillRRect, _pillBorderPaint);

        layout.comboStrokeTp.paint(
          canvas,
          layout.comboOffset + const ui.Offset(0.0, 1.5),
        );
        layout.comboStrokeTp.paint(canvas, layout.comboOffset);
        layout.comboFillTp.paint(canvas, layout.comboOffset);

        if (layout.praiseFillTp != null && layout.praiseStrokeTp != null) {
          final praiseOffset = layout.praiseOffset!;
          layout.praiseStrokeTp!.paint(
            canvas,
            praiseOffset + const ui.Offset(0.0, 2.8),
          );
          layout.praiseStrokeTp!.paint(canvas, praiseOffset);
          layout.praiseFillTp!.paint(canvas, praiseOffset);
        }

        if (hasFade) {
          canvas.restore();
        }
      }
      canvas.restore();
    }
  }
}

/// Swirling cyan/gold sparkle burst spawned over every block transformed by the `Shuffle` booster.
class ShuffleSparkVfx extends PositionComponent {
  final Color accentColor;
  final double cellSize;
  final List<_VfxParticle> _particles = [];
  double _elapsed = 0.0;
  static const double _duration = 0.52;

  ui.Image? _haloImg;
  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _ringPaint = ui.Paint()..style = PaintingStyle.stroke;

  ShuffleSparkVfx({
    required Vector2 centerPos,
    required this.accentColor,
    required this.cellSize,
  }) : super(position: centerPos, priority: 212) {
    _haloImg = _safeFlameImage('Explosion_Halo.png');
    final rng = math.Random();
    for (int i = 0; i < 10; i++) {
      final angle = (i / 10.0) * math.pi * 2.0 + rng.nextDouble() * 0.4;
      final speed = cellSize * (1.2 + rng.nextDouble() * 1.9);
      _particles.add(
        _VfxParticle(
          pos: ui.Offset(
            math.cos(angle) * cellSize * 0.16,
            math.sin(angle) * cellSize * 0.16,
          ),
          vel: ui.Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          size: cellSize * (0.18 + rng.nextDouble() * 0.16),
          maxLife: 0.30 + rng.nextDouble() * 0.20,
          color: i % 3 == 0
              ? Colors.white
              : (i % 2 == 0 ? const Color(0xFF47F0FF) : accentColor),
          angularVel: (rng.nextDouble() - 0.5) * 9.0,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    final damp = math.pow(0.92, dt * 60.0).toDouble();
    for (final p in _particles) {
      p.life -= dt;
      p.vel = p.vel * damp;
      p.pos += p.vel * dt;
      p.rotation += p.angularVel * dt;
    }
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final ringT = (_elapsed / 0.32).clamp(0.0, 1.0);
    if (ringT < 1.0) {
      final ease = 1.0 - math.pow(1.0 - ringT, 2.4).toDouble();
      final r = cellSize * (0.30 + ease * 0.78);
      final fade = (1.0 - ringT).clamp(0.0, 1.0);
      if (_haloImg != null) {
        _additivePaint.colorFilter = UnityChannelMaskFilters.redChannelTint(
          accentColor,
          opacity: fade * 0.72,
        );
        canvas.drawImageRect(
          _haloImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _haloImg!.width.toDouble(),
            _haloImg!.height.toDouble(),
          ),
          ui.Rect.fromCircle(center: ui.Offset.zero, radius: r),
          _additivePaint,
        );
      }
      _ringPaint
        ..color = Colors.white.withValues(alpha: fade * 0.80)
        ..strokeWidth = (cellSize * 0.05 * fade).clamp(1.2, 4.0);
      canvas.drawCircle(ui.Offset.zero, r * 0.85, _ringPaint);
    }

    final starImg = SparkleAtlas.starImage;
    if (starImg != null) {
      final transforms = <ui.RSTransform>[];
      final rects = <ui.Rect>[];
      final colors = <Color>[];
      const halfTile = SparkleAtlas.tileSize * 0.5;
      for (final p in _particles) {
        if (p.life <= 0) continue;
        final t = (p.life / p.maxLife).clamp(0.0, 1.0);
        final sz = p.size * (0.45 + 0.55 * t);
        if (sz <= 0.3) continue;
        transforms.add(
          ui.RSTransform.fromComponents(
            rotation: p.rotation,
            scale: sz / SparkleAtlas.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: p.pos.dx,
            translateY: p.pos.dy,
          ),
        );
        rects.add(SparkleAtlas.tileRect);
        colors.add(p.color.withValues(alpha: t * 0.92));
      }
      if (transforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          starImg,
          transforms,
          rects,
          colors,
          BlendMode.modulate,
          null,
          _additivePaint,
        );
      }
    }
  }
}

/// Animated 3D Hammer (`PowerUp_Hammer.png`) booster VFX:
/// - Optional Beat 1 (`startPos != null`): flies along an upward arc from the bottom Hammer HUD button
/// - Beat 2: lifts high & cocks back with a golden glint
/// - Beat 3: high-speed downward slam (`resolvedImpactTime`) triggering shockwave + split shatter
/// - Beat 4: elastic recoil bounce & graceful fade out
class HammerSwingSmashVfx extends PositionComponent {
  final double cellSize;
  final Color debrisPrimary;
  final Color debrisSecondary;
  final Vector2? startPos;
  final List<_VfxParticle> _debris = [];
  double _elapsed = 0.0;
  bool _impactSpawned = false;

  static const double impactTime = 0.22;
  static const double _flyDurWithStart = 0.26;
  static const double _windUpDurWithStart = 0.20;
  static const double _slamDurWithStart = 0.10;
  static const double _windUpDurLocal = 0.14;
  static const double _slamDurLocal = 0.08;
  static const double _reboundDur = 0.34;

  double get _flyDur => startPos != null ? _flyDurWithStart : 0.0;
  double get _windUpDur =>
      startPos != null ? _windUpDurWithStart : _windUpDurLocal;
  double get _slamDur => startPos != null ? _slamDurWithStart : _slamDurLocal;
  double get windUpStartTime => _flyDur;
  double get resolvedImpactTime => _flyDur + _windUpDur + _slamDur;
  double get _totalDuration => resolvedImpactTime + 0.50;

  ui.Image? _haloImg;
  ui.Image? _hammerImg;
  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;

  HammerSwingSmashVfx({
    required Vector2 centerPos,
    required this.cellSize,
    this.startPos,
    this.debrisPrimary = const Color(0xFFFFCA3A),
    this.debrisSecondary = const Color(0xFF8C9BCE),
  }) : super(position: centerPos, priority: 225) {
    _haloImg = _safeFlameImage('Explosion_Halo.png');
    _hammerImg = _safeFlameImage('PowerUp_Hammer.png');
  }

  void _spawnImpactDebris() {
    final rng = math.Random();
    for (int i = 0; i < 16; i++) {
      final angle = -math.pi * 0.92 + rng.nextDouble() * math.pi * 1.84;
      final speed = cellSize * (1.7 + rng.nextDouble() * 3.1);
      _debris.add(
        _VfxParticle(
          pos: ui.Offset(
            (rng.nextDouble() - 0.5) * cellSize * 0.42,
            (rng.nextDouble() - 0.5) * cellSize * 0.42,
          ),
          vel: ui.Offset(
            math.cos(angle) * speed,
            math.sin(angle) * speed - cellSize * 1.25,
          ),
          size: cellSize * (0.14 + rng.nextDouble() * 0.16),
          maxLife: 0.32 + rng.nextDouble() * 0.18,
          color: i % 3 == 0
              ? Colors.white
              : (i.isEven ? debrisPrimary : debrisSecondary),
          gravity: cellSize * 8.8,
          rotation: rng.nextDouble() * math.pi * 2.0,
          angularVel: (rng.nextDouble() - 0.5) * 14.0,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (!_impactSpawned && _elapsed >= resolvedImpactTime) {
      _impactSpawned = true;
      _spawnImpactDebris();
    }
    if (_impactSpawned) {
      final damp = math.pow(0.95, dt * 60.0).toDouble();
      for (final d in _debris) {
        d.life -= dt;
        d.vel = ui.Offset(d.vel.dx * damp, d.vel.dy + d.gravity * dt);
        d.pos += d.vel * dt;
        d.rotation += d.angularVel * dt;
      }
    }
    if (_elapsed >= _totalDuration) {
      removeFromParent();
    }
  }

  void _drawFourPointGlint(ui.Canvas canvas, ui.Offset c, double r, double alpha) {
    if (r <= 0.5 || alpha <= 0.01) return;
    final p = ui.Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.20, c.dy - r * 0.20, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.20, c.dy + r * 0.20, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.20, c.dy + r * 0.20, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.20, c.dy - r * 0.20, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(
      p,
      ui.Paint()..color = const Color(0xFFFFF7C2).withValues(alpha: alpha),
    );
  }

  @override
  void render(ui.Canvas canvas) {
    final impactT = resolvedImpactTime;
    final flyDur = _flyDur;
    final windUpEnd = flyDur + _windUpDur;

    // 1. Shockwave halo & debris after impact
    if (_elapsed >= impactT) {
      final postT = ((_elapsed - impactT) / 0.30).clamp(0.0, 1.0);
      if (postT < 1.0) {
        final r = cellSize * (0.42 + postT * 1.40);
        final fade = (1.0 - postT).clamp(0.0, 1.0);
        if (_haloImg != null) {
          _additivePaint.colorFilter = UnityChannelMaskFilters.redChannelTint(
            debrisPrimary,
            opacity: fade * 0.88,
          );
          canvas.drawImageRect(
            _haloImg!,
            ui.Rect.fromLTWH(
              0,
              0,
              _haloImg!.width.toDouble(),
              _haloImg!.height.toDouble(),
            ),
            ui.Rect.fromCircle(center: ui.Offset.zero, radius: r),
            _additivePaint,
          );
        }
        final ringPaint = ui.Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (cellSize * 0.072 * fade).clamp(1.5, 5.5)
          ..color = Colors.white.withValues(alpha: fade * 0.86);
        canvas.drawCircle(ui.Offset.zero, r * 0.80, ringPaint);
      }

      for (final d in _debris) {
        if (d.life <= 0) continue;
        final t = (d.life / d.maxLife).clamp(0.0, 1.0);
        final r = d.size * (0.45 + 0.55 * t) * 0.5;
        canvas.save();
        canvas.translate(d.pos.dx, d.pos.dy);
        canvas.rotate(d.rotation);
        final rect = ui.RRect.fromRectAndRadius(
          ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: r * 2.0,
            height: r * 1.45,
          ),
          ui.Radius.circular(r * 0.3),
        );
        canvas.drawRRect(
          rect,
          ui.Paint()..color = d.color.withValues(alpha: t * 0.92),
        );
        canvas.restore();
      }
    }

    // 2. Animated 3D Mallet: Fly-up arc -> Wind-up lift -> High-speed slam -> Rebound & fade
    if (_elapsed <= impactT + _reboundDur) {
      final strikePivot = ui.Offset(cellSize * 0.60, cellSize * 0.38);
      ui.Offset curPivot = strikePivot;
      double angleRad;
      double alpha = 1.0;
      double scale = 1.0;
      double liftGlint = 0.0;

      if (flyDur > 0.0 && _elapsed < flyDur) {
        // Beat 1: Fly up cleanly from bottom Hammer HUD button to strike perch!
        final rawU = (_elapsed / flyDur).clamp(0.0, 1.0);
        final u = Curves.easeOutCubic.transform(rawU);
        final startLocal = ui.Offset(
          startPos!.x - position.x,
          startPos!.y - position.y,
        );
        final ctrl = ui.Offset(
          ui.lerpDouble(startLocal.dx, strikePivot.dx, 0.52)! + cellSize * 0.95,
          math.min(startLocal.dy, strikePivot.dy) - cellSize * 1.05,
        );
        final om = 1.0 - u;
        curPivot = ui.Offset(
          om * om * startLocal.dx + 2 * om * u * ctrl.dx + u * u * strikePivot.dx,
          om * om * startLocal.dy + 2 * om * u * ctrl.dy + u * u * strikePivot.dy,
        );
        angleRad = ui.lerpDouble(-0.45, 0.32, u)!;
        scale = ui.lerpDouble(0.58, 1.15, u)!;

        // Soft luminous flight trail dots along the upward curve
        for (int k = 1; k <= 4; k++) {
          final tu = (rawU - k * 0.055).clamp(0.0, 1.0);
          if (tu <= 0.01) continue;
          final eu = Curves.easeOutCubic.transform(tu);
          final omu = 1.0 - eu;
          final tp = ui.Offset(
            omu * omu * startLocal.dx +
                2 * omu * eu * ctrl.dx +
                eu * eu * strikePivot.dx,
            omu * omu * startLocal.dy +
                2 * omu * eu * ctrl.dy +
                eu * eu * strikePivot.dy,
          );
          final trailAlpha = ((1.0 - k / 5.0) * 0.42 * (1.0 - rawU * 0.35))
              .clamp(0.0, 1.0);
          canvas.drawCircle(
            tp + ui.Offset(-cellSize * 0.14, -cellSize * 0.42),
            (cellSize * (0.13 - k * 0.02)).clamp(2.0, 12.0),
            ui.Paint()
              ..color = const Color(0xFF7AF5FF).withValues(alpha: trailAlpha)
              ..maskFilter = ui.MaskFilter.blur(
                ui.BlurStyle.normal,
                (cellSize * 0.06).clamp(1.5, 5.0),
              ),
          );
        }
      } else if (_elapsed < windUpEnd) {
        // Beat 2: Dramatic lift UP & cock back with anticipation swell + golden head glint
        final u = ((_elapsed - flyDur) / _windUpDur).clamp(0.0, 1.0);
        final ease = Curves.easeOutCubic.transform(u);
        curPivot = strikePivot + ui.Offset(cellSize * 0.14 * ease, -cellSize * 0.38 * ease);
        angleRad = ui.lerpDouble(0.32, 1.14, ease)!;
        scale = ui.lerpDouble(1.15, 1.32, ease)!;
        liftGlint = math.sin(u * math.pi).clamp(0.0, 1.0);
      } else if (_elapsed < impactT) {
        // Beat 3: High-speed slam straight down onto block center!
        final u = ((_elapsed - windUpEnd) / _slamDur).clamp(0.0, 1.0);
        final ease = Curves.easeInExpo.transform(u);
        curPivot = strikePivot +
            ui.Offset(
              ui.lerpDouble(cellSize * 0.14, -cellSize * 0.04, ease)!,
              ui.lerpDouble(-cellSize * 0.38, cellSize * 0.08, ease)!,
            );
        angleRad = ui.lerpDouble(1.14, -0.52, ease)!;
        scale = ui.lerpDouble(1.32, 1.18, ease)!;
      } else {
        // Beat 4: Elastic recoil bounce & graceful fade out
        final u = ((_elapsed - impactT) / _reboundDur).clamp(0.0, 1.0);
        final bounce = Curves.easeOutBack.transform(u);
        curPivot = strikePivot +
            ui.Offset(
              ui.lerpDouble(-cellSize * 0.04, cellSize * 0.12, u)!,
              ui.lerpDouble(cellSize * 0.08, -cellSize * 0.14, u)!,
            );
        angleRad = ui.lerpDouble(-0.52, 0.16, bounce)!;
        scale = ui.lerpDouble(1.18, 0.88, u)!;
        alpha = (1.0 -
                Curves.easeIn.transform(((u - 0.36) / 0.64).clamp(0.0, 1.0)))
            .clamp(0.0, 1.0);
      }

      canvas.save();
      if (alpha < 0.99) {
        canvas.saveLayer(
          ui.Rect.fromCircle(center: curPivot, radius: cellSize * 2.4),
          ui.Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
        );
      }
      canvas.translate(curPivot.dx, curPivot.dy);
      canvas.rotate(angleRad);
      canvas.scale(scale, scale);

      final s = cellSize * 0.98;
      if (_hammerImg != null) {
        final img = _hammerImg!;
        canvas.save();
        canvas.translate(-s * 0.20, -s * 0.64);
        canvas.scale(-1.0, 1.0);
        canvas.rotate(0.45);
        final drawSize = s * 1.40;
        canvas.drawImageRect(
          img,
          ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: drawSize,
            height: drawSize,
          ),
          ui.Paint()..filterQuality = FilterQuality.high,
        );
        canvas.restore();
      } else {
        final handleRect = ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(-s * 0.11, -s * 0.85, s * 0.22, s * 0.98),
          ui.Radius.circular(s * 0.10),
        );
        canvas.drawRRect(
          handleRect,
          ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset(-s * 0.11, 0),
              ui.Offset(s * 0.11, 0),
              const [Color(0xFF9C4F19), Color(0xFFE6943E), Color(0xFF7B380D)],
              const [0.0, 0.45, 1.0],
            ),
        );
        canvas.drawRRect(
          handleRect,
          ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (s * 0.045).clamp(1.5, 4.0)
            ..color = const Color(0xFF451E05),
        );

        final headRect = ui.RRect.fromRectAndRadius(
          ui.Rect.fromCenter(
            center: ui.Offset(-s * 0.05, -s * 0.90),
            width: s * 0.86,
            height: s * 0.46,
          ),
          ui.Radius.circular(s * 0.14),
        );
        canvas.drawRRect(
          headRect,
          ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset(0, -s * 1.13),
              ui.Offset(0, -s * 0.67),
              const [Color(0xFFFFE066), Color(0xFFFF8811), Color(0xFFD63218)],
              const [0.0, 0.42, 1.0],
            ),
        );
        canvas.drawRRect(
          headRect,
          ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (s * 0.05).clamp(1.8, 4.5)
            ..color = const Color(0xFF5A1606),
        );
      }

      if (liftGlint > 0.05) {
        _drawFourPointGlint(
          canvas,
          ui.Offset(-s * 0.24, -s * 1.04),
          s * 0.26 * liftGlint,
          liftGlint * 0.92,
        );
      }

      if (alpha < 0.99) {
        canvas.restore();
      }
      canvas.restore();
    }
  }
}

/// Visual split-in-half crack & shatter VFX spawned at the exact instant the Hammer
/// smashes a block into two `1x1` halves:
/// - Bright cleavage crack line slicing through the block center
/// - Two colored glass-liquid shell halves physically cracking open & separating outward
/// - Translucent water droplets & crystal glass shards bursting from the seam
class HammerSplitCrackVfx extends PositionComponent {
  final double blockWidth;
  final double blockHeight;
  final double cellSize;
  final bool splitHorizontal;
  final Color topBright;
  final Color bottomLip;
  final Color rimHighlight;

  final List<_VfxParticle> _shards = [];
  double _elapsed = 0.0;
  static const double _duration = 0.48;

  HammerSplitCrackVfx({
    required Vector2 centerPos,
    required this.blockWidth,
    required this.blockHeight,
    required this.cellSize,
    required this.splitHorizontal,
    required this.topBright,
    required this.bottomLip,
    required this.rimHighlight,
  }) : super(position: centerPos, priority: 222) {
    final rng = math.Random();
    for (int i = 0; i < 16; i++) {
      final isGlass = i % 3 == 0;
      final baseAngle = splitHorizontal
          ? (i.isEven ? 0.0 : math.pi) + (rng.nextDouble() - 0.5) * 1.35
          : (i.isEven ? math.pi * 0.5 : -math.pi * 0.5) +
              (rng.nextDouble() - 0.5) * 1.35;
      final speed = cellSize * (1.4 + rng.nextDouble() * 2.6);
      _shards.add(
        _VfxParticle(
          pos: ui.Offset(
            (rng.nextDouble() - 0.5) * (splitHorizontal ? cellSize * 0.18 : blockWidth * 0.5),
            (rng.nextDouble() - 0.5) * (splitHorizontal ? blockHeight * 0.5 : cellSize * 0.18),
          ),
          vel: ui.Offset(
            math.cos(baseAngle) * speed,
            math.sin(baseAngle) * speed - cellSize * 0.85,
          ),
          size: cellSize * (isGlass ? (0.14 + rng.nextDouble() * 0.14) : (0.10 + rng.nextDouble() * 0.10)),
          maxLife: 0.28 + rng.nextDouble() * 0.18,
          color: isGlass ? Colors.white : (i % 2 == 0 ? topBright : rimHighlight),
          gravity: cellSize * 7.5,
          rotation: rng.nextDouble() * math.pi * 2.0,
          angularVel: (rng.nextDouble() - 0.5) * 15.0,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    final damp = math.pow(0.94, dt * 60.0).toDouble();
    for (final s in _shards) {
      s.life -= dt;
      s.vel = ui.Offset(s.vel.dx * damp, s.vel.dy + s.gravity * dt);
      s.pos += s.vel * dt;
      s.rotation += s.angularVel * dt;
    }
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  ui.Path _buildJaggedHalfPath({required bool firstHalf}) {
    final hw = math.max(cellSize * 0.44, blockWidth * 0.46);
    final hh = math.max(cellSize * 0.44, blockHeight * 0.46);
    final jag = cellSize * 0.085;
    final p = ui.Path();
    if (splitHorizontal) {
      final outerX = firstHalf ? -hw : hw;
      p.moveTo(0, -hh);
      p.lineTo(jag * 0.8, -hh * 0.50);
      p.lineTo(-jag * 0.9, 0);
      p.lineTo(jag * 0.7, hh * 0.50);
      p.lineTo(0, hh);
      p.lineTo(outerX, hh);
      p.lineTo(outerX, -hh);
      p.close();
    } else {
      final outerY = firstHalf ? -hh : hh;
      p.moveTo(-hw, 0);
      p.lineTo(-hw * 0.50, jag * 0.8);
      p.lineTo(0, -jag * 0.9);
      p.lineTo(hw * 0.50, jag * 0.7);
      p.lineTo(hw, 0);
      p.lineTo(hw, outerY);
      p.lineTo(-hw, outerY);
      p.close();
    }
    return p;
  }

  @override
  void render(ui.Canvas canvas) {
    final t = (_elapsed / _duration).clamp(0.0, 1.0);

    // 1. Two glass-liquid block halves physically cracking open & separating outward
    final halfT = (_elapsed / 0.34).clamp(0.0, 1.0);
    if (halfT < 1.0) {
      final ease = Curves.easeOutCubic.transform(halfT);
      final alpha = (1.0 - Curves.easeIn.transform(halfT)).clamp(0.0, 1.0);
      final sep = cellSize * 0.52 * ease;
      final rot = 0.28 * ease;
      final sc = ui.lerpDouble(1.0, 0.74, ease)!;
      final halfW = math.max(cellSize * 0.44, blockWidth * 0.46);
      final halfH = math.max(cellSize * 0.44, blockHeight * 0.46);

      for (final firstHalf in [true, false]) {
        final sign = firstHalf ? -1.0 : 1.0;
        final shift = splitHorizontal
            ? ui.Offset(sign * sep, -cellSize * 0.06 * math.sin(halfT * math.pi))
            : ui.Offset(0, sign * sep);
        final halfPath = _buildJaggedHalfPath(firstHalf: firstHalf);

        canvas.save();
        canvas.translate(shift.dx, shift.dy);
        canvas.rotate(sign * rot);
        canvas.scale(sc, sc);
        canvas.drawPath(
          halfPath,
          ui.Paint()
            ..shader = ui.Gradient.linear(
              ui.Offset(0, -halfH),
              ui.Offset(0, halfH),
              [
                topBright.withValues(alpha: alpha * 0.82),
                bottomLip.withValues(alpha: alpha * 0.86),
              ],
            ),
        );
        canvas.drawPath(
          halfPath,
          ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = (cellSize * 0.045).clamp(1.6, 3.8)
            ..color = Colors.white.withValues(alpha: alpha * 0.85),
        );
        canvas.restore();
      }

      // 2. Luminous white-gold fracture crack seam flash right down the center
      final crackT = (_elapsed / 0.18).clamp(0.0, 1.0);
      if (crackT < 1.0) {
        final crackAlpha = (1.0 - crackT).clamp(0.0, 1.0);
        final jag = cellSize * 0.085;
        final seam = ui.Path();
        if (splitHorizontal) {
          seam
            ..moveTo(0, -halfH * 1.08)
            ..lineTo(jag * 0.8, -halfH * 0.50)
            ..lineTo(-jag * 0.9, 0)
            ..lineTo(jag * 0.7, halfH * 0.50)
            ..lineTo(0, halfH * 1.08);
        } else {
          seam
            ..moveTo(-halfW * 1.08, 0)
            ..lineTo(-halfW * 0.50, jag * 0.8)
            ..lineTo(0, -jag * 0.9)
            ..lineTo(halfW * 0.50, jag * 0.7)
            ..lineTo(halfW * 1.08, 0);
        }
        canvas.drawPath(
          seam,
          ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = (cellSize * 0.14 * crackAlpha).clamp(2.5, 11.0)
            ..color = const Color(0xFFFFE57F).withValues(alpha: crackAlpha * 0.78)
            ..maskFilter = ui.MaskFilter.blur(
              ui.BlurStyle.normal,
              (cellSize * 0.06).clamp(1.5, 5.0),
            ),
        );
        canvas.drawPath(
          seam,
          ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = (cellSize * 0.055 * crackAlpha).clamp(1.4, 4.5)
            ..color = Colors.white.withValues(alpha: crackAlpha),
        );
      }
    }

    // 3. Translucent liquid droplets & triangular crystal glass shards
    for (int i = 0; i < _shards.length; i++) {
      final s = _shards[i];
      if (s.life <= 0) continue;
      final st = (s.life / s.maxLife).clamp(0.0, 1.0);
      final r = s.size * (0.45 + 0.55 * st) * 0.5;
      canvas.save();
      canvas.translate(s.pos.dx, s.pos.dy);
      canvas.rotate(s.rotation);
      if (i % 3 == 0) {
        final tri = ui.Path()
          ..moveTo(0, -r * 1.2)
          ..lineTo(r * 0.95, r * 0.85)
          ..lineTo(-r * 0.85, r * 0.65)
          ..close();
        canvas.drawPath(
          tri,
          ui.Paint()..color = Colors.white.withValues(alpha: st * 0.88),
        );
      } else {
        canvas.drawCircle(
          ui.Offset.zero,
          r,
          ui.Paint()..color = s.color.withValues(alpha: st * 0.88),
        );
        canvas.drawCircle(
          ui.Offset(-r * 0.28, -r * 0.28),
          r * 0.30,
          ui.Paint()..color = Colors.white.withValues(alpha: st * 0.75),
        );
      }
      canvas.restore();
    }

    if (t < 0.75) {
      final rt = (t / 0.75).clamp(0.0, 1.0);
      final ringR = cellSize * (0.35 + rt * 1.05);
      canvas.drawCircle(
        ui.Offset.zero,
        ringR,
        ui.Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (cellSize * 0.042 * (1.0 - rt)).clamp(1.0, 3.6)
          ..color = topBright.withValues(alpha: (1.0 - rt) * 0.55),
      );
    }
  }
}

/// Shared visual color palette for `Key & Lock` blocks (`gold`, `ruby`, `emerald`).
({Color bright, Color mid, Color dark, Color outline}) keyLockColorsFor(
  String? colorName,
) {
  switch ((colorName ?? 'gold').toLowerCase()) {
    case 'ruby':
    case 'red':
      return (
        bright: const Color(0xFFFF7A93),
        mid: const Color(0xFFE8254B),
        dark: const Color(0xFF940D2A),
        outline: const Color(0xFF3E0512),
      );
    case 'emerald':
    case 'green':
      return (
        bright: const Color(0xFF64FFB0),
        mid: const Color(0xFF10B96B),
        dark: const Color(0xFF066E3E),
        outline: const Color(0xFF042D1A),
      );
    case 'gold':
    default:
      return (
        bright: const Color(0xFFFFF08A),
        mid: const Color(0xFFFFB818),
        dark: const Color(0xFFB36B00),
        outline: const Color(0xFF452400),
      );
  }
}

/// Floating emerald `+Ns` bonus time callout spawned when a Clock Bonus Block merges.
class ClockBonusCalloutVfx extends PositionComponent {
  final int bonusSeconds;
  final double cellSize;
  double _elapsed = 0.0;
  static const double _duration = 0.95;

  ClockBonusCalloutVfx({
    required Vector2 anchorWorld,
    required this.bonusSeconds,
    required this.cellSize,
  }) : super(
          position: anchorWorld.clone(),
          priority: 126,
        );

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _duration).clamp(0.0, 1.0);
    final rise = Curves.easeOutCubic.transform(t) * cellSize * 0.95;
    final popScale = t < 0.16
        ? Curves.easeOutBack.transform((t / 0.16).clamp(0.0, 1.0))
        : 1.0;
    final alpha = t > 0.72 ? (1.0 - (t - 0.72) / 0.28).clamp(0.0, 1.0) : 1.0;
    if (alpha <= 0.01) return;

    canvas.save();
    canvas.translate(0, -rise);
    canvas.scale(popScale, popScale);

    final label = '+${bonusSeconds}s';
    final fontSize = (cellSize * 0.42).clamp(16.0, 42.0);
    final strokeW = (fontSize * 0.24).clamp(2.5, 8.5);
    final watchDiam = (cellSize * 0.68).clamp(26.0, 68.0);
    final baseStyle = TextStyle(
      fontFamily: 'PoetsenOne',
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      height: 1.0,
      letterSpacing: -fontSize * 0.02,
    );

    final tpOutline = TextPainter(
      text: TextSpan(
        text: label,
        style: baseStyle.copyWith(
          foreground: ui.Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeW
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF033426),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tpFill = TextPainter(
      text: TextSpan(
        text: label,
        style: baseStyle.copyWith(
          foreground: ui.Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(0, fontSize),
              const [Color(0xFFFFFFFF), Color(0xFFA7F3D0)],
            ),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final gap = watchDiam * 0.08;
    final totalW = watchDiam + gap + tpFill.width;
    final left = -totalW * 0.5;

    if (alpha < 0.995) {
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: totalW + watchDiam,
          height: watchDiam * 2.0,
        ),
        ui.Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }

    drawEmeraldStopwatchIcon(
      canvas,
      Offset(left + watchDiam * 0.5, -watchDiam * 0.03),
      watchDiam,
    );
    final textOrigin = Offset(left + watchDiam + gap, -tpFill.height * 0.48);
    tpOutline.paint(canvas, textOrigin + Offset(0, fontSize * 0.06));
    tpOutline.paint(canvas, textOrigin);
    tpFill.paint(canvas, textOrigin);

    if (alpha < 0.995) {
      canvas.restore();
    }
    canvas.restore();
  }
}

/// Mystic sparkle burst spawned when a `?` Mystery Block flips open after an adjacent merge.
class MysteryRevealVfx extends PositionComponent {
  final Color accentColor;
  final double cellSize;
  double _elapsed = 0.0;
  static const double _duration = 0.46;

  MysteryRevealVfx({
    required Vector2 centerPos,
    required this.accentColor,
    required this.cellSize,
  }) : super(
          position: centerPos.clone(),
          priority: 120,
        );

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _duration).clamp(0.0, 1.0);
    final ease = Curves.easeOutCubic.transform(t);
    final alpha = (1.0 - t).clamp(0.0, 1.0);
    if (alpha <= 0.01) return;

    final ringR = cellSize * (0.24 + 0.68 * ease);
    canvas.drawCircle(
      Offset.zero,
      ringR,
      ui.Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.08 * (1.0 - t * 0.65)).clamp(1.5, 8.0)
        ..color = const Color(0xFFD8B4FE).withValues(alpha: alpha * 0.9),
    );

    for (int i = 0; i < 8; i++) {
      final angle = (math.pi * 2.0 * i) / 8.0 + t * 0.8;
      final dist = cellSize * (0.18 + 0.62 * ease);
      final pos = Offset(math.cos(angle) * dist, math.sin(angle) * dist);
      final r = cellSize * 0.075 * (1.0 - t * 0.6);
      canvas.drawCircle(
        pos,
        r,
        ui.Paint()
          ..color = (i.isEven ? accentColor : const Color(0xFFFFF08A))
              .withValues(alpha: alpha),
      );
    }
  }
}

/// Animated colored Key flying along a curved arc from a merged Key Block to its
/// matching locked block, bursting into unlock sparks upon impact!
class FlyingKeyUnlockVfx extends PositionComponent {
  final Vector2 startWorld;
  final Vector2 endWorld;
  final String keyColor;
  final double cellSize;
  double _elapsed = 0.0;
  static const double _flightDur = 0.34;
  static const double _burstDur = 0.24;

  FlyingKeyUnlockVfx({
    required this.startWorld,
    required this.endWorld,
    required this.keyColor,
    required this.cellSize,
  }) : super(priority: 125);

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _flightDur + _burstDur) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = keyLockColorsFor(keyColor);
    if (_elapsed <= _flightDur) {
      final t = (_elapsed / _flightDur).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(t);
      final mid = (startWorld + endWorld) * 0.5 + Vector2(0, -cellSize * 0.95);
      final om = 1.0 - eased;
      final pos =
          startWorld * (om * om) + mid * (2.0 * om * eased) + endWorld * (eased * eased);

      // Trail glow dots
      for (int i = 1; i <= 3; i++) {
        final tt = (eased - i * 0.06).clamp(0.0, 1.0);
        final omm = 1.0 - tt;
        final tp =
            startWorld * (omm * omm) + mid * (2.0 * omm * tt) + endWorld * (tt * tt);
        canvas.drawCircle(
          Offset(tp.x, tp.y),
          cellSize * (0.11 - i * 0.02),
          ui.Paint()..color = c.bright.withValues(alpha: 0.45 - i * 0.1),
        );
      }

      canvas.save();
      canvas.translate(pos.x, pos.y);
      canvas.rotate(-0.4 + eased * math.pi * 2.0);
      final kScale = 1.0 + math.sin(eased * math.pi) * 0.38;
      canvas.scale(kScale, kScale);
      drawVectorKeyIcon(canvas, Offset.zero, cellSize * 0.46, keyColor);
      canvas.restore();
    } else {
      final bt = ((_elapsed - _flightDur) / _burstDur).clamp(0.0, 1.0);
      final ease = Curves.easeOutCubic.transform(bt);
      final alpha = (1.0 - bt).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(endWorld.x, endWorld.y);
      canvas.drawCircle(
        Offset.zero,
        cellSize * (0.20 + 0.65 * ease),
        ui.Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (cellSize * 0.09 * (1.0 - bt * 0.6)).clamp(1.6, 8.0)
          ..color = c.bright.withValues(alpha: alpha),
      );
      for (int i = 0; i < 8; i++) {
        final ang = (math.pi * 2.0 * i) / 8.0;
        final dist = cellSize * (0.16 + 0.58 * ease);
        canvas.drawCircle(
          Offset(math.cos(ang) * dist, math.sin(ang) * dist),
          cellSize * 0.075 * (1.0 - bt * 0.5),
          ui.Paint()..color = (i.isEven ? c.bright : Colors.white).withValues(alpha: alpha),
        );
      }
      canvas.restore();
    }
  }
}

/// Shared crisp glossy vector Key icon used on Key Blocks, FlyingKeyUnlockVfx, and Unlock Dialog.
void drawVectorKeyIcon(
  Canvas canvas,
  Offset center,
  double size,
  String? colorName,
) {
  final c = keyLockColorsFor(colorName);
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(-0.45);

  final bowR = size * 0.25;
  final bowCenter = Offset(-size * 0.22, 0);
  final shaftStart = Offset(-size * 0.02, 0);
  final shaftEnd = Offset(size * 0.38, 0);
  final strokeW = (size * 0.14).clamp(2.0, 14.0);
  final outlineW = strokeW + (size * 0.10).clamp(1.8, 10.0);

  void paintKey(ui.Paint p, {bool fillBow = false}) {
    canvas.drawCircle(bowCenter, bowR, p);
    canvas.drawLine(shaftStart, shaftEnd, p);
    canvas.drawLine(
      Offset(size * 0.18, 0),
      Offset(size * 0.18, size * 0.16),
      p,
    );
    canvas.drawLine(
      Offset(size * 0.34, 0),
      Offset(size * 0.34, size * 0.20),
      p,
    );
    if (fillBow) {
      canvas.drawCircle(
        bowCenter,
        bowR * 0.44,
        ui.Paint()..color = c.outline,
      );
    }
  }

  // Dark outline
  paintKey(
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = outlineW
      ..color = c.outline,
  );
  // Metallic colored body
  paintKey(
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeW
      ..color = c.mid,
  );
  // Top-left bright specular highlight
  canvas.drawCircle(
    bowCenter + Offset(-bowR * 0.25, -bowR * 0.25),
    bowR * 0.28,
    ui.Paint()..color = c.bright,
  );
  canvas.drawLine(
    shaftStart + Offset(0, -strokeW * 0.22),
    shaftEnd + Offset(0, -strokeW * 0.22),
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (strokeW * 0.32).clamp(1.0, 4.0)
      ..color = c.bright,
  );
  canvas.restore();
}

/// Draws a lush 3D glossy emerald-and-ivory Stopwatch charm matching the game's
/// crystal-candy art style (`Icon_Clock.png` / `IceLock.png`), shared across
/// `PieceComponent`, `MechanicUnlockDialog`, and `ClockBonusFlyVfx`.
void drawEmeraldStopwatchIcon(
  Canvas canvas,
  Offset center,
  double diameter, {
  bool drawDropShadow = true,
}) {
  if (diameter <= 2.0) return;
  final r = diameter * 0.42;
  // Slightly lower dial center so the top plunger crown fits snugly inside `diameter`
  final dialC = Offset(center.dx, center.dy + diameter * 0.065);
  final outlineW = (r * 0.16).clamp(1.1, 4.2);

  canvas.save();

  // 1. Soft grounded drop shadow underneath the stopwatch body
  if (drawDropShadow) {
    canvas.drawCircle(
      dialC + Offset(0, r * 0.16),
      r * 1.04,
      ui.Paint()
        ..color = const Color(0x6602241B)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          (r * 0.18).clamp(1.0, 5.0),
        ),
    );
  }

  // 2. Angled side stopwatch pusher (at ~42 deg clockwise from 12 o'clock)
  canvas.save();
  canvas.translate(dialC.dx, dialC.dy);
  canvas.rotate(0.74);
  final lugRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(0, -r * 1.08),
      width: r * 0.34,
      height: r * 0.28,
    ),
    Radius.circular(r * 0.09),
  );
  canvas.drawRRect(
    lugRect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset(-r * 0.18, -r * 1.22),
        Offset(r * 0.18, -r * 0.94),
        const [Color(0xFFFDE68A), Color(0xFF10B981), Color(0xFF047857)],
        const [0.0, 0.45, 1.0],
      ),
  );
  canvas.drawRRect(
    lugRect,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outlineW * 0.78).clamp(0.9, 3.0)
      ..color = const Color(0xFF032D23),
  );
  canvas.restore();

  // 3. Top crown stem + plump rounded plunger button
  final stemRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(dialC.dx, dialC.dy - r * 1.03),
      width: r * 0.32,
      height: r * 0.30,
    ),
    Radius.circular(r * 0.06),
  );
  canvas.drawRRect(
    stemRect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset(dialC.dx - r * 0.16, dialC.dy - r * 1.15),
        Offset(dialC.dx + r * 0.16, dialC.dy - r * 1.15),
        const [Color(0xFF6EE7B7), Color(0xFF059669), Color(0xFF064E3B)],
        const [0.0, 0.55, 1.0],
      ),
  );
  canvas.drawRRect(
    stemRect,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outlineW * 0.78).clamp(0.9, 3.0)
      ..color = const Color(0xFF032D23),
  );

  final capRect = RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: Offset(dialC.dx, dialC.dy - r * 1.24),
      width: r * 0.62,
      height: r * 0.28,
    ),
    Radius.circular(r * 0.14),
  );
  canvas.drawRRect(
    capRect,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset(dialC.dx, capRect.top),
        Offset(dialC.dx, capRect.bottom),
        const [Color(0xFFFEF08A), Color(0xFFF59E0B)],
      ),
  );
  // Specular glint on golden top crown button
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(dialC.dx - r * 0.06, dialC.dy - r * 1.29),
        width: r * 0.34,
        height: r * 0.08,
      ),
      Radius.circular(r * 0.04),
    ),
    ui.Paint()..color = const Color(0xCCFFFFFF),
  );
  canvas.drawRRect(
    capRect,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outlineW * 0.82).clamp(0.9, 3.2)
      ..color = const Color(0xFF032D23),
  );

  // 4. Sculpted 3D emerald bezel casing
  canvas.drawCircle(
    dialC,
    r,
    ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset(dialC.dx - r * 0.35, dialC.dy - r),
        Offset(dialC.dx + r * 0.35, dialC.dy + r),
        const [
          Color(0xFFA7F3D0),
          Color(0xFF22E59B),
          Color(0xFF059669),
          Color(0xFF046347),
        ],
        const [0.0, 0.28, 0.72, 1.0],
      ),
  );

  // Glossy top-left outer rim specular highlight arc
  canvas.drawArc(
    Rect.fromCircle(center: dialC, radius: r * 0.90),
    -math.pi * 0.86,
    math.pi * 0.56,
    false,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (r * 0.11).clamp(0.9, 3.0)
      ..color = const Color(0xB8FFFFFF),
  );

  // Crisp deep-emerald outer contour
  canvas.drawCircle(
    dialC,
    r,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = outlineW
      ..color = const Color(0xFF032D23),
  );

  // 5. Recessed luminous warm-ivory dial face (high contrast even on green blocks!)
  final dialR = r * 0.73;
  canvas.drawCircle(
    dialC,
    dialR,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        Offset(dialC.dx - dialR * 0.18, dialC.dy - dialR * 0.22),
        dialR * 1.25,
        const [Color(0xFFFFFFFF), Color(0xFFF2FDF8), Color(0xFFCAEFE0)],
        const [0.0, 0.65, 1.0],
      ),
  );

  // Subtle inner bezel cast shadow around top edge of dial
  canvas.drawArc(
    Rect.fromCircle(center: dialC, radius: dialR * 0.94),
    -math.pi * 0.92,
    math.pi * 0.84,
    false,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (dialR * 0.14).clamp(0.8, 3.0)
      ..color = const Color(0x3304523D),
  );

  // Vibrant emerald 15-second bonus wedge (12 o'clock -> 3 o'clock)
  final wedgePath = ui.Path()
    ..moveTo(dialC.dx, dialC.dy)
    ..arcTo(
      Rect.fromCircle(center: dialC, radius: dialR * 0.82),
      -math.pi * 0.5,
      math.pi * 0.52,
      false,
    )
    ..close();
  canvas.drawPath(
    wedgePath,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        dialC,
        dialR * 0.85,
        const [Color(0xBB34D399), Color(0xDD10B981)],
      ),
  );

  // Crisp cardinal dial tick dots (12, 3, 6, 9)
  final tickR = (dialR * 0.085).clamp(0.7, 2.2);
  final tickDist = dialR * 0.77;
  final tickPaint = ui.Paint()..color = const Color(0xFF0F766E);
  for (int i = 0; i < 4; i++) {
    final a = i * math.pi * 0.5;
    canvas.drawCircle(
      dialC + Offset(math.cos(a) * tickDist, math.sin(a) * tickDist),
      tickR,
      tickPaint,
    );
  }

  // Bold rounded clock hands (12 o'clock & ~3 o'clock)
  final handPaint = ui.Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = (dialR * 0.19).clamp(1.1, 3.8)
    ..color = const Color(0xFF043B2E);
  canvas.drawLine(dialC, dialC + Offset(0, -dialR * 0.56), handPaint);
  canvas.drawLine(
    dialC,
    dialC + Offset(dialR * 0.45, -dialR * 0.06),
    handPaint..strokeWidth = (dialR * 0.16).clamp(1.0, 3.2),
  );

  // Golden center pin dot
  canvas.drawCircle(
    dialC,
    (dialR * 0.16).clamp(1.1, 3.4),
    ui.Paint()..color = const Color(0xFF043B2E),
  );
  canvas.drawCircle(
    dialC,
    (dialR * 0.10).clamp(0.7, 2.2),
    ui.Paint()..color = const Color(0xFFFDE047),
  );

  // Inner dial crisp ring
  canvas.drawCircle(
    dialC,
    dialR,
    ui.Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outlineW * 0.52).clamp(0.7, 2.0)
      ..color = const Color(0xAA04523D),
  );

  // Glossy curved crystal-glass dome sheen across top-left of watch face
  canvas.save();
  canvas.clipPath(ui.Path()..addOval(Rect.fromCircle(center: dialC, radius: dialR * 0.96)));
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(dialC.dx - dialR * 0.12, dialC.dy - dialR * 0.52),
      width: dialR * 1.48,
      height: dialR * 0.78,
    ),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        Offset(dialC.dx, dialC.dy - dialR * 0.92),
        Offset(dialC.dx, dialC.dy - dialR * 0.10),
        const [Color(0x99FFFFFF), Color(0x00FFFFFF)],
      ),
  );
  canvas.restore();

  canvas.restore();
}

/// Renders live magnetic field arcs, inward-pulling luminous droplets, and a seam
/// ionization glow between two nearby mergeable blocks (`cảm giác tự hút lại như nam châm`).
class MagneticBridgeVfxComponent extends PositionComponent {
  double _clock = 0.0;
  double _targetStrength = 0.0;
  double _strength = 0.0;

  final Vector2 _fromWorld = Vector2.zero();
  final Vector2 _toWorld = Vector2.zero();
  double _spanLength = 40.0;
  double _cellSize = 60.0;
  Color _primaryColor = const Color(0xFF66E3FF);
  Color _targetColor = const Color(0xFFFFFFFF);

  final ui.Paint _glowPaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _haloStrokePaint = ui.Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final ui.Paint _coreStrokePaint = ui.Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final ui.Paint _motePaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Path _arcPath = ui.Path();

  MagneticBridgeVfxComponent({super.priority = 139});

  void updateTarget({
    required Vector2 fromEdgeWorld,
    required Vector2 toEdgeWorld,
    required double spanLength,
    required double cellSize,
    required double strength,
    required Color primaryColor,
    required Color targetColor,
  }) {
    _fromWorld.setFrom(fromEdgeWorld);
    _toWorld.setFrom(toEdgeWorld);
    _spanLength = math.max(cellSize * 0.65, spanLength);
    _cellSize = cellSize;
    _targetStrength = strength.clamp(0.0, 1.0);
    _primaryColor = primaryColor;
    _targetColor = targetColor;
  }

  void clear({bool immediate = false}) {
    _targetStrength = 0.0;
    if (immediate) {
      _strength = 0.0;
    }
  }

  double get debugStrength => _strength;

  @override
  void update(double dt) {
    super.update(dt);
    final clampedDt = dt.clamp(0.0, 0.05);
    _clock = (_clock + clampedDt) % 1000.0;
    final rate = _targetStrength > _strength ? 26.0 : 18.0;
    final alpha = (1.0 - math.exp(-rate * clampedDt)).clamp(0.0, 1.0);
    _strength = ui.lerpDouble(_strength, _targetStrength, alpha)!;
    if (_targetStrength <= 1e-4 && _strength <= 0.005) {
      _strength = 0.0;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_strength <= 0.01 || _cellSize <= 1.0) return;

    final dx = _toWorld.x - _fromWorld.x;
    final dy = _toWorld.y - _fromWorld.y;
    final dist = math.sqrt(dx * dx + dy * dy);
    // Keep axis stable even when the blocks touch or slightly overlap (`dist ~= 0`)
    final nx = dist > 1e-3 ? dx / dist : 1.0;
    final ny = dist > 1e-3 ? dy / dist : 0.0;
    final tx = -ny;
    final ty = nx;

    final midX = (_fromWorld.x + _toWorld.x) * 0.5;
    final midY = (_fromWorld.y + _toWorld.y) * 0.5;
    final reach = math.max(dist * 0.5, _cellSize * 0.20);
    final startA = Offset(midX - nx * reach, midY - ny * reach);
    final startB = Offset(midX + nx * reach, midY + ny * reach);
    final mid = Offset(midX, midY);

    final pulse = 0.85 + 0.15 * math.sin(_clock * 14.0);
    final blendColor =
        Color.lerp(_primaryColor, _targetColor, 0.55) ?? _targetColor;
    final seamAuraRadius = _cellSize * (0.34 + 0.18 * _strength);

    // 1. Central Magnetic Seam Glow
    _glowPaint.shader = ui.Gradient.radial(
      mid,
      seamAuraRadius,
      [
        Colors.white.withValues(alpha: (0.48 * _strength * pulse).clamp(0.0, 1.0)),
        blendColor.withValues(alpha: (0.36 * _strength * pulse).clamp(0.0, 1.0)),
        blendColor.withValues(alpha: 0.0),
      ],
      const [0.0, 0.42, 1.0],
    );
    canvas.drawCircle(mid, seamAuraRadius, _glowPaint);
    _glowPaint.shader = null;

    // 2. Pulsing Seam Line Hugging the Shared Boundary
    final edgeHalf = _spanLength * (0.34 + 0.10 * _strength);
    final seamP1 = Offset(midX - tx * edgeHalf, midY - ty * edgeHalf);
    final seamP2 = Offset(midX + tx * edgeHalf, midY + ty * edgeHalf);
    _haloStrokePaint
      ..strokeWidth = (_cellSize * (0.14 + 0.06 * _strength)).clamp(4.0, 14.0)
      ..maskFilter = ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        (_cellSize * 0.08).clamp(2.5, 8.0),
      )
      ..color =
          blendColor.withValues(alpha: (0.55 * _strength * pulse).clamp(0.0, 1.0));
    canvas.drawLine(seamP1, seamP2, _haloStrokePaint);

    _coreStrokePaint
      ..strokeWidth = (_cellSize * (0.045 + 0.025 * _strength)).clamp(1.8, 5.0)
      ..color = Colors.white.withValues(
        alpha: (0.82 * _strength * pulse).clamp(0.0, 1.0),
      );
    canvas.drawLine(seamP1, seamP2, _coreStrokePaint);

    // 3. Three Hourglass Magnetic Flux Arcs pulling inward from both faces
    final maxLateral = _spanLength * 0.29;
    final pinch = 1.0 - 0.58 * _strength;
    for (int lane = -1; lane <= 1; lane++) {
      final offsetEnd = lane * maxLateral;
      final wave =
          math.sin(_clock * 11.0 + lane * 1.9) * _cellSize * 0.032 * _strength;
      final p0 = Offset(startA.dx + tx * offsetEnd, startA.dy + ty * offsetEnd);
      final p2 = Offset(startB.dx + tx * offsetEnd, startB.dy + ty * offsetEnd);
      final ctrl = Offset(
        midX + tx * (offsetEnd * pinch * 0.35 + wave),
        midY + ty * (offsetEnd * pinch * 0.35 + wave),
      );

      _arcPath
        ..reset()
        ..moveTo(p0.dx, p0.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, p2.dx, p2.dy);

      final laneWeight = lane == 0 ? 1.0 : 0.78;
      _haloStrokePaint
        ..strokeWidth = (_cellSize * 0.085 * laneWeight).clamp(2.5, 8.5)
        ..maskFilter = ui.MaskFilter.blur(
          ui.BlurStyle.normal,
          (_cellSize * 0.055).clamp(1.5, 5.5),
        )
        ..color = blendColor.withValues(
          alpha: (0.58 * _strength * laneWeight).clamp(0.0, 1.0),
        );
      canvas.drawPath(_arcPath, _haloStrokePaint);

      _coreStrokePaint
        ..strokeWidth = (_cellSize * 0.032 * laneWeight).clamp(1.2, 3.4)
        ..color = Colors.white.withValues(
          alpha: (0.85 * _strength * laneWeight).clamp(0.0, 1.0),
        );
      canvas.drawPath(_arcPath, _coreStrokePaint);
    }

    // 4. Inward-Sucking Energy Droplets racing from each block into the center seam
    final edgeTravel = math.max(reach * 1.18, _cellSize * 0.24);
    for (int i = 0; i < 8; i++) {
      final fromSideA = i.isEven;
      final laneFrac = ((i ~/ 2) - 1.5) / 1.5; // -1..+1 across contact edge
      final phase = ((_clock * (2.2 + 0.35 * (i % 3)) + i * 0.21) % 1.0);
      final inwardProgress = phase * phase; // Ease-in acceleration toward magnet core
      final sign = fromSideA ? -1.0 : 1.0;
      final distFromMid = edgeTravel * (1.0 - inwardProgress);
      final lateral = laneFrac * maxLateral * (1.0 - inwardProgress * 0.72);

      final mx = midX + nx * sign * distFromMid + tx * lateral;
      final my = midY + ny * sign * distFromMid + ty * lateral;
      final moteR =
          (_cellSize * (0.028 + 0.022 * _strength) * (0.65 + 0.55 * phase))
              .clamp(1.4, 5.5);
      final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);

      _motePaint.color = blendColor.withValues(
        alpha: (0.68 * _strength * fade).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(mx, my), moteR * 1.65, _motePaint);

      _motePaint.color = Colors.white.withValues(
        alpha: (0.95 * _strength * fade).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(mx, my), moteR, _motePaint);
    }
  }
}





