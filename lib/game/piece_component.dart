import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart' hide Matrix4;
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import '../geometry/polyomino_path_builder.dart';
import '../models/level_models.dart';
import '../models/palette.dart';
import '../models/unity_curve.dart';

class PieceComponent extends PositionComponent {
  final PieceModel model;
  final double cellSize;
  final BlockOrderPalette palette;
  final PieceVisualSettings visualSettings;
  final Vector2 boardOrigin;

  late Path _topPath;
  late Path _wallPath;
  late Path _innerHighlightPath;
  late Rect _localBounds;
  late Offset _labelOffset;
  late List<Offset> _screwOffsets;
  late double _lipDepth;

  // Smooth spring & drag visual state
  Vector2 _visualGridPos;
  Vector2 _dragTargetPos;
  bool isDragging = false;
  double _dragLift = 0.0; // 0 -> 1
  Offset _jellySkew = Offset.zero;
  Offset _jellyVel = Offset.zero;
  Vector2 _prevPos = Vector2.zero();

  // Micro-juice animation timers
  double _tapTimer = -1.0;
  double _shakeTimer = -1.0;
  Offset _shakeAxis = const Offset(1, 0);

  // Merge candidate heartbeat & preview
  bool isMergeCandidate = false;
  int? previewMergedNumber;
  double _candidatePulseTime = 0.0;

  // Level-Up cyan target aura (`LevelUpVisualConfig.json`: `GlowColor: #00BFFF`)
  double levelUpTargetGlow = 0.0;

  // Radial ink-spread color transition on merge
  BlockColorStyle? _previousStyleBeforeMerge;
  Offset _mergeContactLocal = Offset.zero;
  double _mergeTransitionTimer = -1.0;
  double _numberBounceTimer = -1.0;
  double _survivorPulseTimer = -1.0;

  // Swallowed / Level-Up flight override
  bool isFlyingOrSwallowed = false;
  double visualScale = 1.0;
  double visualOpacity = 1.0;

  ui.Image? _iceLockImg;
  ui.Image? _iceBlocksTex;
  ui.Image? _screwImg;
  ui.Image? _arrowShadowImg;
  ui.Image? _arrowOutlineImg;
  ui.Image? _arrowTopImg;
  ui.Image? _arrowHorizFallbackImg;
  ui.Image? _arrowVertFallbackImg;
  ui.Image? _glowImg;

  PieceComponent({
    required this.model,
    required this.cellSize,
    required this.palette,
    required this.visualSettings,
    required this.boardOrigin,
  })  : _visualGridPos = Vector2(model.col.toDouble(), model.row.toDouble()),
        _dragTargetPos = Vector2(
          boardOrigin.x + model.col * cellSize,
          boardOrigin.y + model.row * cellSize,
        ),
        super(
          position: Vector2(
            boardOrigin.x + model.col * cellSize,
            boardOrigin.y + model.row * cellSize,
          ),
          size: Vector2(
            model.widthCols * cellSize,
            model.heightRows * cellSize,
          ),
          priority: 10 + (model.row + model.heightRows - 1) * 2,
        ) {
    _prevPos = position.clone();
    _rebuildCachedGeometry();
    _cacheSprites();
  }

  void _cacheSprites() {
    ui.Image? tryGet(String key) {
      if (!Flame.images.containsKey(key)) return null;
      try {
        return Flame.images.fromCache(key);
      } catch (_) {
        return null;
      }
    }

    _iceLockImg = tryGet('IceLock.png');
    _iceBlocksTex = tryGet('IceBlocks.png');
    _screwImg = tryGet('Screw_Greyscale_01.png');
    _arrowShadowImg = tryGet('Movement_Single-Horizontal_Shadow.png');
    _arrowOutlineImg = tryGet('Movement_Single-Horizontal_Stroke.png');
    _arrowTopImg = tryGet('Movement_Single-Horizontal_Top.png');
    _arrowHorizFallbackImg = tryGet('Movement_Double_Horizontal.png');
    _arrowVertFallbackImg = tryGet('Movement_Double_Vertical.png');
    _glowImg = tryGet('Glow_02.png');
  }

  void _rebuildCachedGeometry() {
    final localSet = model.localCells.toSet();
    // Exact snug Unity packing (`~1.3%` per side = ~2.2px total seam on 1080px screen)
    final gapInset = cellSize * 0.013;
    _lipDepth = cellSize * 0.235;

    _topPath = PolyominoPathBuilder.buildRoundedPath(
      cells: localSet,
      cellSize: cellSize,
      inset: gapInset,
      cornerRadius: cellSize * 0.148,
      concaveRadius: cellSize * 0.096,
    );

    // Build seamless extruded 3D vertical wall path without scalloped corner gaps
    Path extruded = _topPath.shift(Offset(0, _lipDepth));
    for (final frac in const [0.22, 0.45, 0.68, 0.86]) {
      extruded = Path.combine(
        PathOperation.union,
        extruded,
        _topPath.shift(Offset(0, _lipDepth * frac)),
      );
    }
    _wallPath = extruded;

    // Molded inner chamfer rim path (`ref_gameplay.png`)
    final bevelInset = gapInset + (cellSize * 0.052).clamp(1.8, 5.2);
    _innerHighlightPath = PolyominoPathBuilder.buildRoundedPath(
      cells: localSet,
      cellSize: cellSize,
      inset: bevelInset,
      cornerRadius: cellSize * 0.115,
      concaveRadius: cellSize * 0.078,
    );

    _localBounds = Rect.fromLTWH(
      0,
      0,
      model.widthCols * cellSize,
      model.heightRows * cellSize,
    );
    final (cx, cy) = model.computeLabelCenterInCells();
    _labelOffset = Offset(cx * cellSize, cy * cellSize);
    _screwOffsets = PolyominoPathBuilder.computePinnedScrewOffsets(
      cells: localSet,
      cellSize: cellSize,
    );
  }

  Vector2 get worldCenter => Vector2(
        position.x + _labelOffset.dx,
        position.y + _labelOffset.dy,
      );

  Vector2 targetWorldOriginForGrid(int col, int row) => Vector2(
        boardOrigin.x + col * cellSize,
        boardOrigin.y + row * cellSize,
      );

  void setDragTargetWorld(Vector2 worldOrigin) {
    _dragTargetPos = worldOrigin.clone();
  }

  void snapDragTargetToModelGrid() {
    _dragTargetPos = targetWorldOriginForGrid(model.col, model.row);
  }

  void triggerTapSquish() {
    _tapTimer = 0.0;
  }

  void triggerBlockedShake([Offset axis = const Offset(1, 0)]) {
    _shakeTimer = 0.0;
    _shakeAxis =
        axis.distance > 0.01 ? axis / axis.distance : const Offset(1, 0);
  }

  void triggerMergeAbsorb({
    required BlockColorStyle oldStyle,
    required Vector2 worldContactPoint,
  }) {
    _previousStyleBeforeMerge = oldStyle;
    _mergeContactLocal = Offset(
      worldContactPoint.x - position.x,
      worldContactPoint.y - position.y,
    );
    _mergeTransitionTimer = 0.0;
    _numberBounceTimer = 0.0;
    _survivorPulseTimer = 0.0;
    isMergeCandidate = false;
    previewMergedNumber = null;
    _screwOffsets = PolyominoPathBuilder.computePinnedScrewOffsets(
      cells: model.localCells.toSet(),
      cellSize: cellSize,
    );
  }

  void triggerIceUnfroze() {
    _numberBounceTimer = 0.0;
    _survivorPulseTimer = 0.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final clampedDt = dt.clamp(0.0, 0.05);

    if (!isFlyingOrSwallowed) {
      final targetPos = isDragging
          ? _dragTargetPos
          : targetWorldOriginForGrid(model.col, model.row);
      final smoothing = isDragging
          ? visualSettings.followSmoothing
          : visualSettings.settleSmoothing;
      final alpha = 1.0 - math.exp(-smoothing * clampedDt);
      position.lerp(targetPos, alpha);

      _visualGridPos = Vector2(
        (position.x - boardOrigin.x) / cellSize,
        (position.y - boardOrigin.y) / cellSize,
      );
      // Sort by bottom-most visual row so lower blocks always cleanly occlude upper blocks' 3D front walls!
      final bottomRow =
          (_visualGridPos.y + model.heightRows - 1.0).round().clamp(0, 30);
      priority = isDragging ? 95 : (10 + bottomRow * 2);
    }

    // Lift transition
    final targetLift = (isDragging || isFlyingOrSwallowed) ? 1.0 : 0.0;
    _dragLift += (targetLift - _dragLift) * (1.0 - math.exp(-22.0 * clampedDt));

    if (levelUpTargetGlow > 0) {
      levelUpTargetGlow = math.max(0.0, levelUpTargetGlow - clampedDt * 1.4);
    }

    // Velocity-driven Jelly spring deformation (`PieceJellyDeformer`)
    if (clampedDt > 1e-4) {
      final vel = (position - _prevPos) / clampedDt;
      _prevPos = position.clone();

      final maxLean = visualSettings.jellyLeanMax;
      final targetSkew = Offset(
        (-vel.x / (cellSize * 18.0)).clamp(-maxLean, maxLean),
        (-vel.y / (cellSize * 18.0)).clamp(-maxLean, maxLean),
      );
      final k = visualSettings.jellyStiffness;
      final damp = 2.0 * math.sqrt(k) * (0.35 + visualSettings.jellyDamping);
      final ax = (targetSkew.dx - _jellySkew.dx) * k - _jellyVel.dx * damp;
      final ay = (targetSkew.dy - _jellySkew.dy) * k - _jellyVel.dy * damp;
      _jellyVel = Offset(
        _jellyVel.dx + ax * clampedDt,
        _jellyVel.dy + ay * clampedDt,
      );
      _jellySkew = Offset(
        (_jellySkew.dx + _jellyVel.dx * clampedDt)
            .clamp(-maxLean * 1.4, maxLean * 1.4),
        (_jellySkew.dy + _jellyVel.dy * clampedDt)
            .clamp(-maxLean * 1.4, maxLean * 1.4),
      );
    }

    // Advance micro-juice timers
    if (_tapTimer >= 0) {
      _tapTimer += clampedDt;
      if (_tapTimer >= visualSettings.tapDuration) _tapTimer = -1.0;
    }
    if (_shakeTimer >= 0) {
      _shakeTimer += clampedDt;
      if (_shakeTimer >= visualSettings.shakeDuration) _shakeTimer = -1.0;
    }
    if (isMergeCandidate) {
      _candidatePulseTime = (_candidatePulseTime + clampedDt) %
          visualSettings.mergeCandidatePulseDuration;
    } else {
      _candidatePulseTime = 0.0;
    }
    if (_mergeTransitionTimer >= 0) {
      _mergeTransitionTimer += clampedDt;
      if (_mergeTransitionTimer >=
          visualSettings.mergeTransitionExpandDuration) {
        _mergeTransitionTimer = -1.0;
        _previousStyleBeforeMerge = null;
      }
    }
    if (_numberBounceTimer >= 0) {
      _numberBounceTimer += clampedDt;
      if (_numberBounceTimer >= visualSettings.mergeNumberSettleDuration) {
        _numberBounceTimer = -1.0;
      }
    }
    if (_survivorPulseTimer >= 0) {
      _survivorPulseTimer += clampedDt;
      if (_survivorPulseTimer >= visualSettings.mergeSurvivorMovesDuration) {
        _survivorPulseTimer = -1.0;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (visualOpacity <= 0.01) return;

    final currentStyle = palette.styleFor(
      number: model.number,
      isFrozen: model.isFrozen,
    );

    double scaleX = visualScale;
    double scaleY = visualScale;

    if (_tapTimer >= 0) {
      final t = (_tapTimer / visualSettings.tapDuration).clamp(0.0, 1.0);
      final inflate = visualSettings.tapInflate.evaluate(t);
      scaleX *= (1.0 + inflate * 1.25);
      scaleY *= (1.0 + inflate * 0.88);
    }

    if (isMergeCandidate) {
      final t = (_candidatePulseTime /
              visualSettings.mergeCandidatePulseDuration)
          .clamp(0.0, 1.0);
      final pulseZ = visualSettings.mergeCandidatePulseScale.evaluate(t);
      final s = 1.0 + (pulseZ - 1.0) * 0.13;
      scaleX *= s;
      scaleY *= s;
    }

    if (_survivorPulseTimer >= 0) {
      final t = (_survivorPulseTimer / visualSettings.mergeSurvivorMovesDuration)
          .clamp(0.0, 1.0);
      final p = visualSettings.mergeSurvivorMovesPulseCurve.evaluate(t);
      final s = 1.0 + (visualSettings.mergeSurvivorMovesPulseScale - 1.0) * p;
      scaleX *= s;
      scaleY *= s;
    }

    Offset shakeOffset = Offset.zero;
    if (_shakeTimer >= 0) {
      final t = (_shakeTimer / visualSettings.shakeDuration).clamp(0.0, 1.0);
      final amp = cellSize * 0.085 * (1.0 - t);
      final wave = math.sin(t * math.pi * 6.0);
      shakeOffset = _shakeAxis * (amp * wave);
    }

    final liftPx =
        _dragLift * cellSize * visualSettings.offsetWhileDragging * 1.30;

    canvas.save();
    if (visualOpacity < 0.999) {
      canvas.saveLayer(
        _localBounds.inflate(cellSize * 0.8),
        Paint()..color = Colors.white.withValues(alpha: visualOpacity),
      );
    }

    // Center pivot for jelly skew & pulse scaling
    final cx = _localBounds.width * 0.5;
    final cy = _localBounds.height * 0.5;
    canvas.translate(cx + shakeOffset.dx, cy + shakeOffset.dy);
    canvas.scale(scaleX, scaleY);
    if (_jellySkew.dx.abs() > 1e-4 || _jellySkew.dy.abs() > 1e-4) {
      final m = Matrix4.identity()
        ..setEntry(0, 1, _jellySkew.dx)
        ..setEntry(1, 0, _jellySkew.dy);
      canvas.transform(m.storage);
    }
    canvas.translate(-cx, -cy);

    // 0. Optional Cyan `LevelUpVisualConfig` Target Aura (`GlowColor: #00BFFF`)
    if (levelUpTargetGlow > 0.01 && _glowImg != null) {
      final auraRect = _localBounds.inflate(cellSize * 0.55);
      canvas.drawImageRect(
        _glowImg!,
        Rect.fromLTWH(
          0,
          0,
          _glowImg!.width.toDouble(),
          _glowImg!.height.toDouble(),
        ),
        auraRect,
        Paint()
          ..blendMode = BlendMode.plus
          ..colorFilter = ColorFilter.mode(
            const Color(0xFF00BFFF)
                .withValues(alpha: (levelUpTargetGlow * 0.75).clamp(0.0, 1.0)),
            BlendMode.modulate,
          ),
      );
    }

    // 1. Glossy Floor Reflection (`ShowReflection: 1`, `ReflectionAlpha: 0.197`) & Ambient Drop Shadow
    final shadowDrop = _lipDepth + cellSize * 0.055 + liftPx * 1.35;
    canvas.drawPath(
      _topPath.shift(Offset(0, shadowDrop)),
      Paint()
        ..color = Color.fromRGBO(2, 7, 26, 0.36 + _dragLift * 0.18)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          cellSize * (0.055 + _dragLift * 0.085),
        ),
    );

    if (_dragLift < 0.35) {
      final reflAlpha =
          (visualSettings.reflectionAlpha * 1.15 * (1.0 - _dragLift / 0.35))
              .clamp(0.0, 0.30);
      final reflTop = _localBounds.bottom + _lipDepth * 0.90;
      final reflBottom = _localBounds.bottom + _lipDepth * 1.95;
      final reflPath = _topPath.shift(Offset(0, _lipDepth * 1.55));
      canvas.drawPath(
        reflPath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, reflTop),
            Offset(cx, reflBottom),
            [
              currentStyle.topMid.withValues(alpha: reflAlpha),
              currentStyle.bottomLip.withValues(alpha: 0.0),
            ],
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.035),
      );
    }

    // Shift piece upward when lifted during drag
    canvas.translate(0, -liftPx);

    // 2. Chunky 2.5D Vertical Front Extrusion Wall (`_wallPath`, `0.235 * cellSize`)
    final activeBaseStyle = _previousStyleBeforeMerge ?? currentStyle;
    _drawExtrudedFrontWall(canvas, activeBaseStyle);

    if (_previousStyleBeforeMerge != null && _mergeTransitionTimer >= 0) {
      final t = (_mergeTransitionTimer /
              visualSettings.mergeTransitionExpandDuration)
          .clamp(0.0, 1.0);
      final prog = visualSettings.mergeTransitionExpandCurve.evaluate(t);
      final maxR = _localBounds.longestSide * 1.45;
      canvas.save();
      canvas.clipPath(_wallPath);
      canvas.drawCircle(
        _mergeContactLocal + Offset(0, _lipDepth * 0.5),
        maxR * prog,
        Paint()..color = currentStyle.bottomLip,
      );
      canvas.restore();
    }

    // 3. Top Beveled Face + Radial Ink-Spread Merge Color Transition
    _drawTopFaceGradient(canvas, activeBaseStyle);

    if (_previousStyleBeforeMerge != null && _mergeTransitionTimer >= 0) {
      final t = (_mergeTransitionTimer /
              visualSettings.mergeTransitionExpandDuration)
          .clamp(0.0, 1.0);
      final prog = visualSettings.mergeTransitionExpandCurve.evaluate(t);
      final maxR = _localBounds.longestSide * 1.45;
      final radius = (maxR * prog).clamp(1.0, maxR * 1.5);

      canvas.save();
      canvas.clipPath(_topPath);
      final spreadClip = Path()
        ..addOval(Rect.fromCircle(center: _mergeContactLocal, radius: radius));
      canvas.clipPath(spreadClip);
      _drawTopFaceGradient(canvas, currentStyle);
      canvas.restore();
    }

    // 4. Frosted `IceBlocks.png` Texture & Specular Diagonal Sheen for Ice Blocks
    if (model.isFrozen) {
      _drawIceFrostAndSheen(canvas);
    }

    // 5. Molded 3D Inner Chamfer Bevel Frame + Crisp Outer Seam Contour (`ref_gameplay.png`)
    final rimStrokeW = (cellSize * 0.044).clamp(1.6, 3.6);
    final softRimEnd =
        Color.lerp(currentStyle.topBright, currentStyle.rimHighlight, 0.50)!;
    canvas.drawPath(
      _innerHighlightPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimStrokeW
        ..strokeJoin = StrokeJoin.round
        ..shader = ui.Gradient.linear(
          _localBounds.topLeft,
          _localBounds.bottomRight,
          [
            currentStyle.rimHighlight
                .withValues(alpha: model.isFrozen ? 0.88 : 0.68),
            softRimEnd.withValues(alpha: model.isFrozen ? 0.62 : 0.36),
          ],
        ),
    );

    // Crisp 1.1px outer edge contour so adjacent light/same-color blocks have razor-sharp seams
    final outerContourColor = model.isFrozen
        ? const Color(0xFF2882ED)
        : Color.lerp(currentStyle.topMid, currentStyle.bottomLip, 0.58)!;
    canvas.drawPath(
      _topPath,
      Paint()
        ..color = outerContourColor.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15,
    );

    // Candidate glowing aura rim
    if (isMergeCandidate) {
      canvas.drawPath(
        _topPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }

    // 6. Stationary/Pinned Tinted Corner Screws (`Screw_Greyscale_01.png`)
    if (model.movement.isPinned && !model.isFrozen) {
      _drawPinnedScrews(canvas, currentStyle);
    }

    // 7. Authentic 3-Layer Directional Restriction Arrows (`horizontal` / `vertical`)
    if (!model.isFrozen &&
        (model.movement == MovementConstraint.horizontalOnly ||
            model.movement == MovementConstraint.verticalOnly)) {
      _drawMovementArrows(canvas, currentStyle);
    }

    // 8. Center `PoetsenOne` Number or Frozen `IceLock.png` Padlock Badge
    if (model.isFrozen) {
      _drawFrozenLockBadge(canvas, model.iceTarget ?? 2);
    } else if (!model.isDud && model.number != null) {
      _drawBlockNumber(canvas, currentStyle);
    }

    if (visualOpacity < 0.999) {
      canvas.restore();
    }
    canvas.restore();
  }

  void _drawExtrudedFrontWall(Canvas canvas, BlockColorStyle style) {
    final topCrease = Color.lerp(style.bottomLip, Colors.black, 0.08)!;
    final baseShade = Color.lerp(style.bottomLip, Colors.black, 0.14)!;
    final wallShader = ui.Gradient.linear(
      Offset(_localBounds.left, _localBounds.bottom - cellSize * 0.15),
      Offset(_localBounds.left, _localBounds.bottom + _lipDepth),
      model.isFrozen
          ? const [Color(0xFF2B8CFA), Color(0xFF1876EE), Color(0xFF105EC8)]
          : [topCrease, style.bottomLip, baseShade],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawPath(_wallPath, Paint()..shader = wallShader);

    // Subtle dark base outline on bottom of 3D wall
    canvas.drawPath(
      _topPath.shift(Offset(0, _lipDepth)),
      Paint()
        ..color = baseShade.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawTopFaceGradient(Canvas canvas, BlockColorStyle style) {
    final shader = ui.Gradient.linear(
      Offset(_localBounds.left, _localBounds.top),
      Offset(_localBounds.right * 0.78, _localBounds.bottom),
      [style.topBright, style.topMid],
    );
    canvas.drawPath(_topPath, Paint()..shader = shader);
  }

  void _drawIceFrostAndSheen(Canvas canvas) {
    canvas.save();
    canvas.clipPath(_topPath);

    if (_iceBlocksTex != null) {
      canvas.drawImageRect(
        _iceBlocksTex!,
        Rect.fromLTWH(
          0,
          0,
          _iceBlocksTex!.width.toDouble(),
          _iceBlocksTex!.height.toDouble(),
        ),
        _localBounds.inflate(cellSize * 0.1),
        Paint()
          ..blendMode = BlendMode.softLight
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: 0.30),
            BlendMode.modulate,
          ),
      );
    }

    final w = _localBounds.width;
    final h = _localBounds.height;
    final sheenPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final stripe1 = Path()
      ..moveTo(-h * 0.28, h)
      ..lineTo(w * 0.46, 0)
      ..lineTo(w * 0.68, 0)
      ..lineTo(-h * 0.06, h)
      ..close();
    final stripe2 = Path()
      ..moveTo(w * 0.36, h)
      ..lineTo(w + h * 0.22, 0)
      ..lineTo(w + h * 0.34, 0)
      ..lineTo(w * 0.48, h)
      ..close();

    canvas.drawPath(stripe1, sheenPaint);
    canvas.drawPath(stripe2, sheenPaint);
    canvas.restore();
  }

  void _drawPinnedScrews(Canvas canvas, BlockColorStyle style) {
    final screwDiam = (cellSize * 0.195).clamp(6.0, 16.0);
    final r = screwDiam * 0.5;

    for (final pt in _screwOffsets) {
      // Dark socket shadow
      canvas.drawCircle(
        pt + Offset(0, r * 0.24),
        r * 1.05,
        Paint()..color = style.screwDark.withValues(alpha: 0.82),
      );

      if (_screwImg != null) {
        final tint = Color.lerp(Colors.white, style.screwBright, 0.42)!;
        canvas.drawImageRect(
          _screwImg!,
          Rect.fromLTWH(
            0,
            0,
            _screwImg!.width.toDouble(),
            _screwImg!.height.toDouble(),
          ),
          Rect.fromCenter(center: pt, width: screwDiam, height: screwDiam),
          Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate),
        );
      } else {
        canvas.drawCircle(pt, r, Paint()..color = const Color(0xFFE7EEF8));
      }
    }
  }

  void _drawMovementArrows(Canvas canvas, BlockColorStyle style) {
    final isHoriz = model.movement == MovementConstraint.horizontalOnly;
    final center = _labelOffset;
    final offsetCenter = isHoriz
        ? Offset(center.dx, center.dy + (model.isDud ? 0 : cellSize * 0.30))
        : Offset(center.dx + (model.isDud ? 0 : cellSize * 0.30), center.dy);

    // Authentic 3-Layer Unity `Movement_Single-Horizontal_*` composition
    if (_arrowShadowImg != null &&
        _arrowOutlineImg != null &&
        _arrowTopImg != null) {
      final w = cellSize * 0.64;
      final h = w * (_arrowTopImg!.height / _arrowTopImg!.width);
      final src = Rect.fromLTWH(
        0,
        0,
        _arrowTopImg!.width.toDouble(),
        _arrowTopImg!.height.toDouble(),
      );
      final dst = Rect.fromCenter(center: Offset.zero, width: w, height: h);

      canvas.save();
      canvas.translate(offsetCenter.dx, offsetCenter.dy);
      if (!isHoriz) {
        canvas.rotate(math.pi * 0.5);
      }

      canvas.drawImageRect(
        _arrowShadowImg!,
        src,
        dst.shift(Offset(0, cellSize * 0.025)),
        Paint()
          ..colorFilter = ColorFilter.mode(
            style.arrowShadow.withValues(alpha: 0.78),
            BlendMode.modulate,
          ),
      );
      canvas.drawImageRect(
        _arrowOutlineImg!,
        src,
        dst,
        Paint()
          ..colorFilter =
              ColorFilter.mode(style.arrowStroke, BlendMode.modulate),
      );
      canvas.drawImageRect(_arrowTopImg!, src, dst, Paint());
      canvas.restore();
      return;
    }

    final fallback = isHoriz ? _arrowHorizFallbackImg : _arrowVertFallbackImg;
    if (fallback != null) {
      final targetSize = cellSize * 0.72;
      final dst = isHoriz
          ? Rect.fromCenter(
              center: offsetCenter,
              width: targetSize,
              height: targetSize * (fallback.height / fallback.width),
            )
          : Rect.fromCenter(
              center: offsetCenter,
              width: targetSize * (fallback.width / fallback.height),
              height: targetSize,
            );
      canvas.drawImageRect(
        fallback,
        Rect.fromLTWH(
          0,
          0,
          fallback.width.toDouble(),
          fallback.height.toDouble(),
        ),
        dst,
        Paint()..color = Colors.white.withValues(alpha: 0.90),
      );
    }
  }

  /// Authentic `IceCountBadge`: `IceLock.png` + `PoetsenOne` `#1E3587` fill & `#C6DCFF` stroke.
  void _drawFrozenLockBadge(Canvas canvas, int targetNum) {
    final badgeH = cellSize * 0.74;
    final badgeW = badgeH * 0.84;
    final dst = Rect.fromCenter(
      center: _labelOffset,
      width: badgeW,
      height: badgeH,
    );

    if (_iceLockImg != null) {
      canvas.drawImageRect(
        _iceLockImg!,
        Rect.fromLTWH(
          0,
          0,
          _iceLockImg!.width.toDouble(),
          _iceLockImg!.height.toDouble(),
        ),
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    final textStr = '$targetNum';
    final digits = textStr.length;
    final fontSize = cellSize *
        (digits <= 2
            ? 0.245
            : digits == 3
                ? 0.195
                : 0.158);

    final strokeTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: fontSize,
          height: 1.0,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (fontSize * 0.18).clamp(1.2, 3.0)
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFC8DEFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final fillTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: fontSize,
          color: const Color(0xFF1E3587),
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textPos = Offset(
      _labelOffset.dx - fillTp.width * 0.5,
      _labelOffset.dy + badgeH * 0.105 - fillTp.height * 0.5,
    );
    strokeTp.paint(canvas, textPos);
    fillTp.paint(canvas, textPos);
  }

  /// Authentic `NumberComponentView`: `PoetsenOne` font + 3 concentric palette strokes + `#FFFFFF` face.
  void _drawBlockNumber(Canvas canvas, BlockColorStyle style) {
    final displayNum = (isMergeCandidate && previewMergedNumber != null)
        ? previewMergedNumber!
        : model.number!;
    final textStr = '$displayNum';
    final digits = textStr.length;

    double numScale = 1.0;
    if (_numberBounceTimer >= 0) {
      final t = (_numberBounceTimer / visualSettings.mergeNumberSettleDuration)
          .clamp(0.0, 1.0);
      numScale = visualSettings.mergeNumberSettleSize.evaluate(t);
    } else if (isMergeCandidate && previewMergedNumber != null) {
      numScale = 1.12;
    }

    final multiCellBoost =
        (model.widthCols >= 2 && model.heightRows >= 2) ? 1.32 : 1.0;
    final baseFontSize = cellSize *
        multiCellBoost *
        (digits == 1
            ? 0.375
            : digits == 2
                ? 0.335
                : digits == 3
                    ? 0.285
                    : 0.245);

    canvas.save();
    canvas.translate(_labelOffset.dx, _labelOffset.dy);
    canvas.scale(numScale, numScale);

    // 1. Outer Dark Shadow Stroke (`numberStrokeOuter`) + subtle 3D drop
    final outerSw = (baseFontSize * 0.20).clamp(2.2, 6.4);
    final outerTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontSize,
          height: 1.0,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = outerSw
            ..strokeJoin = StrokeJoin.round
            ..color = style.numberStrokeOuter,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(-outerTp.width * 0.5, -outerTp.height * 0.5);
    outerTp.paint(canvas, offset + Offset(0, baseFontSize * 0.055));
    outerTp.paint(canvas, offset);

    // 2. Mid Colored Rim Stroke (`numberStrokeMid`)
    final midSw = (baseFontSize * 0.115).clamp(1.3, 4.0);
    final midTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontSize,
          height: 1.0,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = midSw
            ..strokeJoin = StrokeJoin.round
            ..color = style.numberStrokeMid,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    midTp.paint(canvas, offset);

    // 3. Crisp Pure-White Face (`#FFFFFF`)
    final fillTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontSize,
          height: 1.0,
          color: isMergeCandidate && previewMergedNumber != null
              ? const Color(0xFFFFFAC2)
              : Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    fillTp.paint(canvas, offset);

    canvas.restore();
  }
}
