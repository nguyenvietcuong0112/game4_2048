import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart'
    show
        BlendMode,
        BlurStyle,
        Color,
        ColorFilter,
        Colors,
        Curves,
        FilterQuality,
        FontWeight,
        MaskFilter,
        PaintingStyle,
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

/// Pre-bakes a `128x64` 2-tile RGBA sprite (`[0..64] = hot white star`, `[64..128] = white-cored tinted star`)
/// from Unity's `RG8` `Sparkle_01.png` once per palette accent color so all sparkle particle systems
/// render in a SINGLE `Canvas.drawAtlas` GPU batch with zero per-particle `ColorFilter.matrix` allocations!
class _SparkleDualAtlasCache {
  _SparkleDualAtlasCache._();

  static const double tileSize = 64.0;
  static const ui.Rect whiteTileRect = ui.Rect.fromLTWH(0, 0, tileSize, tileSize);
  static const ui.Rect tintedTileRect =
      ui.Rect.fromLTWH(tileSize, 0, tileSize, tileSize);

  static ui.Image? _lastSource;
  static final Map<int, ui.Image> _cache = <int, ui.Image>{};

  static ui.Image? getOrBake(ui.Image? rawSparkle, Color accentColor) {
    if (rawSparkle == null) return null;
    if (!identical(_lastSource, rawSparkle)) {
      for (final img in _cache.values) {
        img.dispose();
      }
      _cache.clear();
      _lastSource = rawSparkle;
    }
    final key = accentColor.toARGB32();
    final existing = _cache[key];
    if (existing != null) return existing;

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
        whiteTileRect,
        ui.Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = UnityChannelMaskFilters.rgDualChannelStar(
            Colors.white,
            opacity: 1.0,
          ),
      );
      canvas.drawImageRect(
        rawSparkle,
        src,
        tintedTileRect,
        ui.Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = UnityChannelMaskFilters.rgDualChannelStar(
            accentColor,
            opacity: 1.0,
          ),
      );
      final pic = recorder.endRecording();
      final baked = pic.toImageSync((tileSize * 2).toInt(), tileSize.toInt());
      pic.dispose();
      if (_cache.length >= 32) {
        final oldest = _cache.remove(_cache.keys.first);
        oldest?.dispose();
      }
      _cache[key] = baked;
      return baked;
    } catch (_) {
      return null;
    }
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
  ui.Image? _sparkleImg;

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
    _sparkleImg = _safeFlameImage('Sparkle_01.png');

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
            (5 + rng.nextInt(4) + 3 * _tier) * math.max(1, edge.cells);

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

      final count = 20 + 7 * _tier;
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
        final rayCount = 6 + _tier * 2;
        final rayLen =
            cellSize * (0.75 + (0.95 + 0.22 * _tier) * math.sqrt(rayT));
        final rayHalfW = cellSize * (0.055 + 0.008 * _tier) * rayFade;
        _rayPaint.color = ringColor.withValues(
          alpha: (0.42 + 0.05 * _tier).clamp(0.0, 0.78) * rayFade,
        );
        _scratchPath
          ..reset()
          ..moveTo(0, 0)
          ..lineTo(-rayHalfW, -rayLen)
          ..lineTo(rayHalfW, -rayLen)
          ..close();
        for (int i = 0; i < rayCount; i++) {
          final ang = _elapsed * 2.6 + (i * math.pi * 2.0 / rayCount);
          canvas.save();
          canvas.rotate(ang);
          canvas.drawPath(_scratchPath, _rayPaint);
          canvas.restore();
        }
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
    final dualAtlas = _SparkleDualAtlasCache.getOrBake(_sparkleImg, accentColor);
    if (dualAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = _SparkleDualAtlasCache.tileSize * 0.5;
      for (int i = 0; i < _particles.length; i++) {
        final p = _particles[i];
        if (p.life <= 0) continue;
        final t = (p.life / p.maxLife).clamp(0.0, 1.0);
        final s = p.size * (0.38 + 0.62 * t);
        if (s <= 0.3) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: p.rotation * 0.35,
            scale: s / _SparkleDualAtlasCache.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: p.pos.dx,
            translateY: p.pos.dy,
          ),
        );
        _scratchRects.add(
          p.color == Colors.white
              ? _SparkleDualAtlasCache.whiteTileRect
              : _SparkleDualAtlasCache.tintedTileRect,
        );
        _scratchColors.add(Color.fromRGBO(255, 255, 255, t));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          dualAtlas,
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
        final wobbleAmp = cellSize * 0.065 * fade;
        _scratchPath.reset();
        const int segs = 32;
        for (int s = 0; s <= segs; s++) {
          final ang = (s / segs) * math.pi * 2.0;
          final r = rBase +
              math.sin(ang * 4.0 + _elapsed * 18.0 + wIdx * 1.6) * wobbleAmp;
          final px = math.cos(ang) * r;
          final py = math.sin(ang) * r;
          if (s == 0) {
            _scratchPath.moveTo(px, py);
          } else {
            _scratchPath.lineTo(px, py);
          }
        }
        _scratchPath.close();

        _liquidWavePaint
          ..strokeWidth =
              (cellSize * (wIdx == 0 ? 0.052 : 0.032) * fade).clamp(1.2, 5.2)
          ..color = (wIdx == 0 ? brightWave : Colors.white)
              .withValues(alpha: (0.82 * fade).clamp(0.0, 1.0));
        canvas.drawPath(_scratchPath, _liquidWavePaint);
      }

      // Glossy 3D liquid teardrops splashing radially outward
      final dropCount = 8 + _tier * 2;
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

        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(ang);
        dropFillPaint.color = (d % 3 == 0 ? brightWave : accentColor)
            .withValues(alpha: (0.88 * fade).clamp(0.0, 1.0));
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: ui.Offset.zero,
            width: r * 2.4,
            height: r * 1.55,
          ),
          dropFillPaint,
        );
        canvas.drawOval(
          ui.Rect.fromCenter(
            center: ui.Offset(r * 0.28, -r * 0.24),
            width: r * 0.92,
            height: r * 0.48,
          ),
          specPaint,
        );
        canvas.restore();
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
  ui.Image? _sparkleImg;
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
    _sparkleImg = _safeFlameImage('Sparkle_01.png');

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
        canvas.drawCircle(
          ui.Offset.zero,
          r,
          ui.Paint()
            ..color =
                const Color(0xFFBDF0FF).withValues(alpha: (1.0 - flashT) * 0.55)
            ..blendMode = BlendMode.plus
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }
    }

    final moteAtlas =
        _SparkleDualAtlasCache.getOrBake(_sparkleImg, const Color(0xFF9BE8FF));
    if (moteAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = _SparkleDualAtlasCache.tileSize * 0.5;
      for (int i = 0; i < _frostMotes.length; i++) {
        final m = _frostMotes[i];
        if (m.life <= 0) continue;
        final t = (m.life / m.maxLife).clamp(0.0, 1.0);
        final sz = m.size * (0.4 + 0.6 * t);
        if (sz <= 0.3) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: 0.0,
            scale: sz / _SparkleDualAtlasCache.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: m.pos.dx,
            translateY: m.pos.dy,
          ),
        );
        _scratchRects.add(_SparkleDualAtlasCache.tintedTileRect);
        _scratchColors.add(Color.fromRGBO(255, 255, 255, t * 0.9));
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
  ui.Image? _sparkleImg;
  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];

  LevelUpSparksVfx({
    required Vector2 pos,
    required this.color,
    required this.cellSize,
  }) : super(position: pos, priority: 205) {
    _sparkleImg = _safeFlameImage('Sparkle_01.png');
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
    final dualAtlas = _SparkleDualAtlasCache.getOrBake(_sparkleImg, color);
    if (dualAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = _SparkleDualAtlasCache.tileSize * 0.5;
      for (int i = 0; i < _sparks.length; i++) {
        final s = _sparks[i];
        if (s.life <= 0) continue;
        final t = (s.life / s.maxLife).clamp(0.0, 1.0);
        final sz = s.size * t;
        if (sz <= 0.3) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: 0.0,
            scale: sz / _SparkleDualAtlasCache.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: s.pos.dx,
            translateY: s.pos.dy,
          ),
        );
        _scratchRects.add(
          s.color == Colors.white
              ? _SparkleDualAtlasCache.whiteTileRect
              : _SparkleDualAtlasCache.tintedTileRect,
        );
        _scratchColors.add(Color.fromRGBO(255, 255, 255, t));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          dualAtlas,
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
  ui.Image? _sparkleImg;
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
    _sparkleImg = _safeFlameImage('Sparkle_01.png');
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
    final dualAtlas = _SparkleDualAtlasCache.getOrBake(_sparkleImg, accentColor);
    if (dualAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = _SparkleDualAtlasCache.tileSize * 0.5;
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
            scale: sz / _SparkleDualAtlasCache.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: s.pos.dx,
            translateY: s.pos.dy,
          ),
        );
        _scratchRects.add(
          s.color == Colors.white
              ? _SparkleDualAtlasCache.whiteTileRect
              : _SparkleDualAtlasCache.tintedTileRect,
        );
        _scratchColors.add(Color.fromRGBO(255, 255, 255, remFrac));
      }
      if (_scratchTransforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          dualAtlas,
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
          scaleBoost: 0.94,
        );
      case 2:
        return const ComboPraiseTier(
          comboCount: 2,
          comboLabel: 'X2',
          praiseText: 'NICE!',
          primaryColor: Color(0xFF2AF598),
          secondaryColor: Color(0xFFB8FFDF),
          strokeColor: Color(0xFF093824),
          scaleBoost: 1.02,
        );
      case 3:
        return const ComboPraiseTier(
          comboCount: 3,
          comboLabel: 'X3',
          praiseText: 'GREAT!',
          primaryColor: Color(0xFFFFD200),
          secondaryColor: Color(0xFFFFF3A1),
          strokeColor: Color(0xFF4A2500),
          scaleBoost: 1.10,
        );
      case 4:
        return const ComboPraiseTier(
          comboCount: 4,
          comboLabel: 'X4',
          praiseText: 'PERFECT!',
          primaryColor: Color(0xFFFF6B00),
          secondaryColor: Color(0xFFFFD08A),
          strokeColor: Color(0xFF4A1200),
          scaleBoost: 1.18,
        );
      case 5:
        return const ComboPraiseTier(
          comboCount: 5,
          comboLabel: 'X5',
          praiseText: 'WOW!',
          primaryColor: Color(0xFFFF2A85),
          secondaryColor: Color(0xFFFFB2D6),
          strokeColor: Color(0xFF480624),
          scaleBoost: 1.26,
        );
      case 6:
        return const ComboPraiseTier(
          comboCount: 6,
          comboLabel: 'X6',
          praiseText: 'AMAZING!',
          primaryColor: Color(0xFFB721FF),
          secondaryColor: Color(0xFFEAC2FF),
          strokeColor: Color(0xFF2B0548),
          scaleBoost: 1.34,
        );
      default:
        return ComboPraiseTier(
          comboCount: c,
          comboLabel: 'X$c',
          praiseText: 'UNSTOPPABLE!',
          primaryColor: const Color(0xFFFFEE55),
          secondaryColor: const Color(0xFFFFFFFF),
          strokeColor: const Color(0xFF4D1A00),
          scaleBoost: (1.38 + (c - 7) * 0.04).clamp(1.38, 1.54),
        );
    }
  }
}

/// Pre-bakes the 3D stroked `X1, X2, X3...` pill + `NICE! / PERFECT! / WOW!` callout into a single
/// RGBA `ui.Image` cached by `(comboCount, cellSizeBucket)` so `ComboPraiseCalloutVfx.render`
/// executes in 1 GPU `drawImageRect` call with zero `saveLayer` or repeated `TextPainter.layout()`.
class _ComboBadgeImageCache {
  _ComboBadgeImageCache._();

  static final Map<int, (ui.Image, double, double)> _cache =
      <int, (ui.Image, double, double)>{};

  static (ui.Image, double, double)? getOrBake(
    ComboPraiseTier tier,
    double cellSize,
  ) {
    final sizeBucket = (cellSize * 2.0).round().clamp(40, 440);
    final key = (math.min(tier.comboCount, 12) << 16) ^ sizeBucket;
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      const double dpr = 2.0;
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
      final maxW = math.max(pillW, praiseFillTp?.width ?? 0.0) + 24.0;
      final totalH = pillH + (hasPraise ? praiseFillTp.height + 16.0 : 12.0);

      final pxW = (maxW * dpr).ceil().clamp(16, 1024);
      final pxH = (totalH * dpr).ceil().clamp(16, 512);
      final logicalW = pxW / dpr;
      final logicalH = pxH / dpr;

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(dpr, dpr);
      canvas.translate(logicalW * 0.5, logicalH * 0.5);

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
      canvas.drawRRect(
        pillRRect,
        ui.Paint()..color = tier.strokeColor.withValues(alpha: 0.88),
      );
      canvas.drawRRect(
        pillRRect,
        ui.Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = tier.primaryColor,
      );

      final comboOffset = ui.Offset(-comboFillTp.width * 0.5, topY);
      comboStrokeTp.paint(canvas, comboOffset + const ui.Offset(0.0, 1.5));
      comboStrokeTp.paint(canvas, comboOffset);
      comboFillTp.paint(canvas, comboOffset);

      if (hasPraise) {
        final praiseOffset = ui.Offset(
          -praiseFillTp.width * 0.5,
          topY + comboFillTp.height * 0.88,
        );
        praiseStrokeTp.paint(canvas, praiseOffset + const ui.Offset(0.0, 2.8));
        praiseStrokeTp.paint(canvas, praiseOffset);
        praiseFillTp.paint(canvas, praiseOffset);
      }

      final pic = recorder.endRecording();
      final img = pic.toImageSync(pxW, pxH);
      pic.dispose();

      if (_cache.length >= 24) {
        final oldest = _cache.remove(_cache.keys.first);
        oldest?.$1.dispose();
      }
      final entry = (img, logicalW, logicalH);
      _cache[key] = entry;
      return entry;
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
/// `PERFECT!`, `WOW!`, `AMAZING!`, `UNSTOPPABLE!`) spawned above the merged piece.
class ComboPraiseCalloutVfx extends PositionComponent {
  final ComboPraiseTier tier;
  final double cellSize;
  final double duration;
  double _elapsed = 0.0;

  (ui.Image, double, double)? _bakedBadge;
  final List<_VfxParticle> _burstParticles = <_VfxParticle>[];
  final List<ui.RSTransform> _scratchTransforms = <ui.RSTransform>[];
  final List<ui.Rect> _scratchRects = <ui.Rect>[];
  final List<Color> _scratchColors = <Color>[];
  ui.Image? _sparkleImg;
  ui.Image? _ringImg;
  final ui.Paint _ringPaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _sparkPaint = ui.Paint()..blendMode = BlendMode.plus;
  final ui.Paint _badgePaint = ui.Paint()..filterQuality = FilterQuality.low;

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
    _sparkleImg = _safeFlameImage('Sparkle_01.png');
    _ringImg = _safeFlameImage('Glow_Ring.png');
    _bakedBadge = _ComboBadgeImageCache.getOrBake(tier, cellSize);

    if (tier.comboCount >= 2) {
      final rng = math.Random(tier.comboCount * 997);
      final count = (8 + tier.comboCount * 2).clamp(10, 22);
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
    final dualAtlas =
        _SparkleDualAtlasCache.getOrBake(_sparkleImg, tier.primaryColor);
    if (dualAtlas != null) {
      _scratchTransforms.clear();
      _scratchRects.clear();
      _scratchColors.clear();
      const halfTile = _SparkleDualAtlasCache.tileSize * 0.5;
      for (int i = 0; i < _burstParticles.length; i++) {
        final p = _burstParticles[i];
        if (p.life <= 0) continue;
        final rem = (p.life / p.maxLife).clamp(0.0, 1.0);
        final sz = p.size * rem;
        if (sz <= 0.5) continue;
        _scratchTransforms.add(
          ui.RSTransform.fromComponents(
            rotation: p.rotation * 0.35,
            scale: sz / _SparkleDualAtlasCache.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: p.pos.dx,
            translateY: p.pos.dy + riseY * 0.5,
          ),
        );
        _scratchRects.add(
          p.color == Colors.white
              ? _SparkleDualAtlasCache.whiteTileRect
              : _SparkleDualAtlasCache.tintedTileRect,
        );
        _scratchColors.add(Color.fromRGBO(255, 255, 255, rem * alpha));
      }
      if (_scratchTransforms.isNotEmpty) {
        _sparkPaint.colorFilter = null;
        canvas.drawAtlas(
          dualAtlas,
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

    // 3. Draw pre-baked 3D stroked `COMBO xN` pill + `NICE! / PERFECT! / WOW!` badge in 1 draw call (zero saveLayer!)
    final badge = _bakedBadge;
    if (badge != null) {
      final (img, logicalW, logicalH) = badge;
      _badgePaint.color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.save();
      canvas.translate(0.0, riseY);
      canvas.rotate(tiltRad);
      canvas.scale(scale, scale);
      canvas.drawImageRect(
        img,
        ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        ui.Rect.fromCenter(
          center: ui.Offset.zero,
          width: logicalW,
          height: logicalH,
        ),
        _badgePaint,
      );
      canvas.restore();
    }
  }
}


