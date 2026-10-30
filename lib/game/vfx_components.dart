import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/material.dart' show BlendMode, Color, ColorFilter, Colors, MaskFilter, BlurStyle;

ui.Image? _safeFlameImage(String key) {
  if (!Flame.images.containsKey(key)) return null;
  try {
    return Flame.images.fromCache(key);
  } catch (_) {
    return null;
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

/// Authentic Unity sprite-driven merge burst using `Explosion_Halo.png`,
/// `ParticleFlare.png`, and `Sparkle_01.png` with additive GPU blending.
class MergeSplashVfx extends PositionComponent {
  final Color primaryColor;
  final Color accentColor;
  final double cellSize;
  final List<_VfxParticle> _particles = [];
  double _elapsed = 0.0;
  static const double _duration = 0.56;

  ui.Image? _haloImg;
  ui.Image? _flareImg;
  ui.Image? _sparkleImg;

  MergeSplashVfx({
    required Vector2 centerPos,
    required this.primaryColor,
    required this.accentColor,
    required this.cellSize,
  }) : super(position: centerPos, priority: 200) {
    _haloImg = _safeFlameImage('Explosion_Halo.png');
    _flareImg = _safeFlameImage('ParticleFlare.png');
    _sparkleImg = _safeFlameImage('Sparkle_01.png');

    final rng = math.Random();
    const count = 20;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2 + (rng.nextDouble() - 0.5) * 0.35;
      final speed = cellSize * (1.7 + rng.nextDouble() * 3.5);
      final isBright = i % 3 == 0;
      _particles.add(
        _VfxParticle(
          pos: ui.Offset(
            (rng.nextDouble() - 0.5) * cellSize * 0.32,
            (rng.nextDouble() - 0.5) * cellSize * 0.32,
          ),
          vel: ui.Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          size: cellSize * (0.24 + rng.nextDouble() * 0.26),
          maxLife: 0.28 + rng.nextDouble() * 0.24,
          color: isBright ? Colors.white : (i.isEven ? accentColor : primaryColor),
          gravity: cellSize * 2.0,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    for (final p in _particles) {
      p.life -= dt;
      p.vel = ui.Offset(p.vel.dx * 0.91, p.vel.dy * 0.91 + p.gravity * dt);
      p.pos += p.vel * dt;
    }
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    // 1. Expanding `Explosion_Halo.png` shockwave ring
    final ringT = (_elapsed / 0.34).clamp(0.0, 1.0);
    if (ringT < 1.0) {
      final ringAlpha = (1.0 - ringT) * 0.78;
      final ringRadius = cellSize * (0.40 + ringT * 1.35);
      if (_haloImg != null) {
        final dst = ui.Rect.fromCircle(center: ui.Offset.zero, radius: ringRadius);
        canvas.drawImageRect(
          _haloImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _haloImg!.width.toDouble(),
            _haloImg!.height.toDouble(),
          ),
          dst,
          ui.Paint()
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.mode(
              accentColor.withValues(alpha: ringAlpha),
              BlendMode.modulate,
            ),
        );
      } else {
        canvas.drawCircle(
          ui.Offset.zero,
          ringRadius,
          ui.Paint()
            ..color = accentColor.withValues(alpha: ringAlpha)
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = cellSize * 0.12 * (1.0 - ringT * 0.7)
            ..blendMode = BlendMode.plus,
        );
      }
    }

    // 2. Central `ParticleFlare.png` star flash
    final flareT = (_elapsed / 0.22).clamp(0.0, 1.0);
    if (flareT < 1.0 && _flareImg != null) {
      final r = cellSize * (0.55 + flareT * 0.65);
      canvas.drawImageRect(
        _flareImg!,
        ui.Rect.fromLTWH(
          0,
          0,
          _flareImg!.width.toDouble(),
          _flareImg!.height.toDouble(),
        ),
        ui.Rect.fromCircle(center: ui.Offset.zero, radius: r),
        ui.Paint()
          ..blendMode = BlendMode.plus
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: (1.0 - flareT) * 0.85),
            BlendMode.modulate,
          ),
      );
    }

    // 3. Radial `Sparkle_01.png` particles
    for (final p in _particles) {
      if (p.life <= 0) continue;
      final t = (p.life / p.maxLife).clamp(0.0, 1.0);
      final s = p.size * (0.4 + 0.6 * t);
      if (_sparkleImg != null) {
        canvas.drawImageRect(
          _sparkleImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _sparkleImg!.width.toDouble(),
            _sparkleImg!.height.toDouble(),
          ),
          ui.Rect.fromCenter(center: p.pos, width: s, height: s),
          ui.Paint()
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.mode(
              p.color.withValues(alpha: t),
              BlendMode.modulate,
            ),
        );
      } else {
        canvas.drawCircle(
          p.pos,
          s * 0.35,
          ui.Paint()
            ..color = p.color.withValues(alpha: t)
            ..blendMode = BlendMode.plus,
        );
      }
    }
  }
}

/// Crystalline ice shards bursting outward from `Ice_Shards.png` (2x2 atlas) +
/// `Explosion_Halo.png` frost shockwave when an `iceTarget` block shatters free.
class IceShatterVfx extends PositionComponent {
  final double cellSize;
  final List<_VfxParticle> _shards = [];
  double _elapsed = 0.0;
  static const double _duration = 0.72;

  ui.Image? _shardsAtlas;
  ui.Image? _haloImg;

  IceShatterVfx({
    required Vector2 centerPos,
    required this.cellSize,
  }) : super(position: centerPos, priority: 210) {
    _shardsAtlas = _safeFlameImage('Ice_Shards.png');
    _haloImg = _safeFlameImage('Explosion_Halo.png');

    final rng = math.Random();
    for (int i = 0; i < 18; i++) {
      final angle = -math.pi * 0.90 + rng.nextDouble() * math.pi * 1.8;
      final speed = cellSize * (1.7 + rng.nextDouble() * 3.4);
      _shards.add(
        _VfxParticle(
          pos: ui.Offset(
            (rng.nextDouble() - 0.5) * cellSize * 0.65,
            (rng.nextDouble() - 0.5) * cellSize * 0.65,
          ),
          vel: ui.Offset(
            math.cos(angle) * speed,
            math.sin(angle) * speed - cellSize * 1.2,
          ),
          size: cellSize * (0.28 + rng.nextDouble() * 0.24),
          maxLife: 0.42 + rng.nextDouble() * 0.28,
          color: i % 3 == 0 ? Colors.white : const Color(0xFFB3EEFF),
          gravity: cellSize * 8.8,
          rotation: rng.nextDouble() * math.pi * 2,
          angularVel: (rng.nextDouble() - 0.5) * 14.0,
          spriteVariant: i % 4,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    for (final s in _shards) {
      s.life -= dt;
      s.vel = ui.Offset(s.vel.dx * 0.96, s.vel.dy + s.gravity * dt);
      s.pos += s.vel * dt;
      s.rotation += s.angularVel * dt;
    }
    if (_elapsed >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(ui.Canvas canvas) {
    final flashT = (_elapsed / 0.26).clamp(0.0, 1.0);
    if (flashT < 1.0) {
      final r = cellSize * (0.45 + flashT * 1.15);
      if (_haloImg != null) {
        canvas.drawImageRect(
          _haloImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _haloImg!.width.toDouble(),
            _haloImg!.height.toDouble(),
          ),
          ui.Rect.fromCircle(center: ui.Offset.zero, radius: r),
          ui.Paint()
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.mode(
              const Color(0xFFC4F3FF).withValues(alpha: (1.0 - flashT) * 0.8),
              BlendMode.modulate,
            ),
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

    final atlas = _shardsAtlas;
    final halfW = atlas != null ? atlas.width * 0.5 : 0.0;
    final halfH = atlas != null ? atlas.height * 0.5 : 0.0;

    for (final s in _shards) {
      if (s.life <= 0) continue;
      final t = (s.life / s.maxLife).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(s.pos.dx, s.pos.dy);
      canvas.rotate(s.rotation);
      final sz = s.size * (0.55 + 0.45 * t);

      if (atlas != null) {
        final col = s.spriteVariant % 2;
        final row = s.spriteVariant ~/ 2;
        canvas.drawImageRect(
          atlas,
          ui.Rect.fromLTWH(col * halfW, row * halfH, halfW, halfH),
          ui.Rect.fromCenter(center: ui.Offset.zero, width: sz, height: sz),
          ui.Paint()
            ..colorFilter = ColorFilter.mode(
              s.color.withValues(alpha: t * 0.95),
              BlendMode.modulate,
            ),
        );
      } else {
        final r = sz * 0.45;
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
      }
      canvas.restore();
    }
  }
}

/// Trailing `Sparkle_01.png` + `ParticleFlare.png` burst during `Level Up` power-up block flight.
class LevelUpSparksVfx extends PositionComponent {
  final Color color;
  final double cellSize;
  final List<_VfxParticle> _sparks = [];
  ui.Image? _sparkleImg;

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
    for (final s in _sparks) {
      if (s.life <= 0) continue;
      final t = (s.life / s.maxLife).clamp(0.0, 1.0);
      final sz = s.size * t;
      if (_sparkleImg != null) {
        canvas.drawImageRect(
          _sparkleImg!,
          ui.Rect.fromLTWH(
            0,
            0,
            _sparkleImg!.width.toDouble(),
            _sparkleImg!.height.toDouble(),
          ),
          ui.Rect.fromCenter(center: s.pos, width: sz, height: sz),
          ui.Paint()
            ..blendMode = BlendMode.plus
            ..colorFilter = ColorFilter.mode(
              s.color.withValues(alpha: t),
              BlendMode.modulate,
            ),
        );
      } else {
        canvas.drawCircle(
          s.pos,
          sz * 0.35,
          ui.Paint()
            ..color = s.color.withValues(alpha: t)
            ..blendMode = BlendMode.plus,
        );
      }
    }
  }
}
