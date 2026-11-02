import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart'
    show BlendMode, BlurStyle, Color, ColorFilter, Colors, FilterQuality, MaskFilter;

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

/// Authentic Unity `MergeSplash` (`BoardView.PlayMergeSplash` + `Glow_Ring.png`,
/// `Explosion_Halo.png`, `ParticleFlare.png`, and `Sparkle_01.png`):
/// Spawns `5..8` droplets per contiguous touching edge in a `36.73°` outward cone
/// (`speed = 2.0..3.6 * cs`, `size = 0.14..0.32 * cs`, `life = 0.28..0.45s`, `gravity = 0`)
/// tinted with `accentColor`, plus crisp additive seam flash at `centerPos`.
class MergeSplashVfx extends PositionComponent {
  final Color primaryColor;
  final Color accentColor;
  final Color ringColor;
  final double cellSize;
  final List<_VfxParticle> _particles = [];
  double _elapsed = 0.0;
  static const double _duration = 0.56;
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
  })  : ringColor = ringColor ?? accentColor,
        super(position: centerPos, priority: 200) {
    _ringImg = _safeFlameImage('Glow_Ring.png');
    _haloImg = _safeFlameImage('Explosion_Halo.png');
    _flareImg = _safeFlameImage('ParticleFlare.png');
    _sparkleImg = _safeFlameImage('Sparkle_01.png');

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
        final dropletCount = (5 + rng.nextInt(4)) * math.max(1, edge.cells);

        for (int i = 0; i < dropletCount; i++) {
          final alongOffset = (rng.nextDouble() - 0.5) * spanLength;
          final angle =
              baseAngle + (rng.nextDouble() * 2.0 - 1.0) * _coneHalfAngleRad;
          final dir = ui.Offset(math.cos(angle), math.sin(angle));
          final speed = cellSize * (2.0 + rng.nextDouble() * 1.6);
          final isBright = i % 5 == 0;
          _particles.add(
            _VfxParticle(
              pos: localEdgeCenter + tangent * alongOffset,
              vel: dir * speed,
              size: cellSize * (0.14 + rng.nextDouble() * 0.18),
              maxLife: 0.28 + rng.nextDouble() * 0.17,
              color: isBright ? Colors.white : accentColor,
              gravity: 0.0,
              rotation: rng.nextDouble() * math.pi * 2,
              angularVel: (rng.nextDouble() - 0.5) * 6.0,
            ),
          );
        }
      }
    } else {
      final hasPush = pushDir.distance > 0.05;
      final normPush = hasPush ? pushDir / pushDir.distance : ui.Offset.zero;
      final tangent = ui.Offset(-normPush.dy, normPush.dx);

      const count = 20;
      for (int i = 0; i < count; i++) {
        final angle =
            (i / count) * math.pi * 2 + (rng.nextDouble() - 0.5) * 0.34;
        final dir = ui.Offset(math.cos(angle), math.sin(angle));
        final speed = cellSize * (2.0 + rng.nextDouble() * 1.6);
        final isBright = i % 5 == 0;
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
            size: cellSize * (0.14 + rng.nextDouble() * 0.18),
            maxLife: 0.28 + rng.nextDouble() * 0.17,
            color: isBright ? Colors.white : accentColor,
            gravity: 0.0,
            rotation: rng.nextDouble() * math.pi * 2,
            angularVel: (rng.nextDouble() - 0.5) * 6.0,
          ),
        );
      }
    }
  }

  final ui.Paint _additivePaint = ui.Paint()..blendMode = BlendMode.plus;

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
    // 1. Crisp `Glow_Ring.png` RG8 shockwave ring
    final crispRingT = (_elapsed / 0.30).clamp(0.0, 1.0);
    if (crispRingT < 1.0) {
      final eased = 1.0 - math.pow(1.0 - crispRingT, 2.4).toDouble();
      final ringAlpha = (1.0 - crispRingT) * 0.88;
      final ringRadius = cellSize * (0.30 + eased * 1.18);
      if (_ringImg != null) {
        _additivePaint.colorFilter = UnityChannelMaskFilters.rgDualChannelStar(
          ringColor,
          opacity: ringAlpha,
          coreWhite: 0.85,
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

    // 2. Soft `Explosion_Halo.png` R8 radial bloom
    final haloT = (_elapsed / 0.36).clamp(0.0, 1.0);
    if (haloT < 1.0) {
      final haloAlpha = (1.0 - haloT) * 0.76;
      final haloRadius = cellSize * (0.42 + haloT * 1.32);
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
        canvas.drawCircle(
          ui.Offset.zero,
          haloRadius,
          ui.Paint()
            ..color = accentColor.withValues(alpha: haloAlpha)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = cellSize * 0.12 * (1.0 - haloT * 0.7)
            ..blendMode = BlendMode.plus,
        );
      }
    }

    // 3. Central `ParticleFlare.png` white-hot star flash at contact point
    final flareT = (_elapsed / 0.22).clamp(0.0, 1.0);
    if (flareT < 1.0 && _flareImg != null) {
      final r = cellSize * (0.58 + flareT * 0.68);
      _additivePaint.colorFilter = ColorFilter.mode(
        Colors.white.withValues(alpha: (1.0 - flareT) * 0.90),
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
      final transforms = <ui.RSTransform>[];
      final rects = <ui.Rect>[];
      final colors = <Color>[];
      const halfTile = _SparkleDualAtlasCache.tileSize * 0.5;
      for (int i = 0; i < _particles.length; i++) {
        final p = _particles[i];
        if (p.life <= 0) continue;
        final t = (p.life / p.maxLife).clamp(0.0, 1.0);
        final s = p.size * (0.38 + 0.62 * t);
        if (s <= 0.3) continue;
        transforms.add(
          ui.RSTransform.fromComponents(
            rotation: p.rotation * 0.35,
            scale: s / _SparkleDualAtlasCache.tileSize,
            anchorX: halfTile,
            anchorY: halfTile,
            translateX: p.pos.dx,
            translateY: p.pos.dy,
          ),
        );
        rects.add(
          p.color == Colors.white
              ? _SparkleDualAtlasCache.whiteTileRect
              : _SparkleDualAtlasCache.tintedTileRect,
        );
        colors.add(Color.fromRGBO(255, 255, 255, t));
      }
      if (transforms.isNotEmpty) {
        _additivePaint.colorFilter = null;
        canvas.drawAtlas(
          dualAtlas,
          transforms,
          rects,
          colors,
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
    for (final c in centers) {
      final baseOffset = ui.Offset(
        c.x,
        c.y + (downOffsetCells - liftCells * 0.5) * cellSize,
      );
      const sparksPerBlock = 6;
      for (int i = 0; i < sparksPerBlock; i++) {
        final boxOffset = ui.Offset(
          (rng.nextDouble() - 0.5) * 0.80 * cellSize,
          (rng.nextDouble() - 0.5) * 0.70 * cellSize,
        );
        final initVel = ui.Offset(
          (rng.nextDouble() - 0.5) * 0.65 * cellSize,
          -(0.45 + rng.nextDouble() * 0.75) * cellSize,
        );
        _sparks.add(
          _VfxParticle(
            pos: baseOffset + boxOffset,
            vel: initVel,
            size: cellSize * (0.14 + rng.nextDouble() * 0.08),
            maxLife: 0.20 + rng.nextDouble() * 0.10,
            color: i % 3 == 0 ? Colors.white : accentColor,
            gravity: -10.0 * cellSize,
            rotation: rng.nextDouble() * math.pi * 2,
            angularVel: (rng.nextDouble() - 0.5) * 5.0,
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

