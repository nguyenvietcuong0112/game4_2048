import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../geometry/polyomino_path_builder.dart';
import '../models/level_models.dart';

/// Authentic 2.5D Carved Recessed Board Cavity (`BackdropBuilder` + `TileMaterial_A/B`)
/// matching `ref_gameplay.png` and `ref_settings.png` pixel-for-pixel:
/// - Recessed cutout sunk into the `#0330AC` royal-blue table with extra bottom perspective
///   depth (`0.235 * cellSize`) to house bottom-row block 3D front walls & floor reflections
/// - Top inner vertical table cliff shadow (`#03081D`)
/// - Subtle dark-navy 3D checkerboard floor pedestals (`#0D1E4C` & `#0C235E` from `TileMaterial_A/B`)
/// - Crisp electric-blue outer table cutout lip highlight (`#064AE8`)
class BoardComponent extends PositionComponent {
  final LevelDefinition level;
  final double cellSize;

  ui.Image? _bakedImage;
  Rect _bakedSrcRect = Rect.zero;
  Rect _bakedDstRect = Rect.zero;
  double _bakePadding = 0.0;
  bool isSuperseded = false;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  static const double _cellTrailFadeSeconds = 0.20;
  static const double _wakeFadeSeconds = 0.13;
  static const int _maxWakeStamps = 8;

  late final int _gridCols;
  late final int _gridRows;
  late final Float32List _cellTrailAge;
  late final Uint8List _cellTrailHold;
  late final List<Color> _cellTrailColor;

  final Float32List _wakeCx = Float32List(_maxWakeStamps);
  final Float32List _wakeCy = Float32List(_maxWakeStamps);
  final Float32List _wakeW = Float32List(_maxWakeStamps);
  final Float32List _wakeH = Float32List(_maxWakeStamps);
  final Float32List _wakeAge = Float32List(_maxWakeStamps);
  final List<Color> _wakeColor = List<Color>.filled(
    _maxWakeStamps,
    Colors.transparent,
  );
  int _wakeCursor = 0;
  double _holdPulseClock = 0.0;
  bool _hasActiveTrails = false;

  final Paint _trailFillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _trailRimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  BoardComponent({
    required this.level,
    required this.cellSize,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2(level.cols * cellSize, level.rows * cellSize),
          priority: 1,
        ) {
    _gridCols = math.max(1, level.cols);
    _gridRows = math.max(1, level.rows);
    final totalCells = _gridCols * _gridRows;
    _cellTrailAge = Float32List(totalCells)..fillRange(0, totalCells, -1.0);
    _cellTrailHold = Uint8List(totalCells);
    _cellTrailColor = List<Color>.filled(totalCells, Colors.transparent);
    _wakeAge.fillRange(0, _maxWakeStamps, -1.0);
    _bakeBoardToGpuImageSync();
  }

  @visibleForTesting
  int get debugActiveTrailCellCount {
    int count = 0;
    for (int i = 0; i < _cellTrailAge.length; i++) {
      if (_cellTrailHold[i] != 0 || _cellTrailAge[i] > 0.0) count++;
    }
    return count;
  }

  @visibleForTesting
  double debugTrailAgeAt(int col, int row) {
    if (col < 0 || col >= _gridCols || row < 0 || row >= _gridRows) {
      return -1.0;
    }
    return _cellTrailAge[row * _gridCols + col];
  }

  /// Lights up the board grid slots underneath a dragged block; vacated cells
  /// remain lit and smoothly animate & contract into a colorful fading trail.
  void updateActiveDragFootprint(
    int baseCol,
    int baseRow,
    List<GridCell> localCells,
    Color accentColor,
  ) {
    if (isSuperseded) return;
    _cellTrailHold.fillRange(0, _cellTrailHold.length, 0);
    for (int i = 0; i < localCells.length; i++) {
      final lc = localCells[i];
      final c = baseCol + lc.$1;
      final r = baseRow + lc.$2;
      if (c < 0 || c >= _gridCols || r < 0 || r >= _gridRows) continue;
      final idx = r * _gridCols + c;
      _cellTrailHold[idx] = 1;
      _cellTrailAge[idx] = 1.0;
      _cellTrailColor[idx] = accentColor;
    }
    _hasActiveTrails = true;
  }

  /// Releases hold lock so the last touched cells animate smoothly to fade out.
  void clearActiveDragFootprint() {
    _cellTrailHold.fillRange(0, _cellTrailHold.length, 0);
  }

  /// Emits a lightweight motion-wake stamp behind the sliding block footprint.
  void emitDragWakeStamp({
    required double cx,
    required double cy,
    required double width,
    required double height,
    required Color color,
  }) {
    if (isSuperseded) return;
    _wakeCx[_wakeCursor] = cx;
    _wakeCy[_wakeCursor] = cy;
    _wakeW[_wakeCursor] = width;
    _wakeH[_wakeCursor] = height;
    _wakeAge[_wakeCursor] = 1.0;
    _wakeColor[_wakeCursor] = color;
    _wakeCursor = (_wakeCursor + 1) % _maxWakeStamps;
    _hasActiveTrails = true;
  }

  void clearTrailsImmediate() {
    _cellTrailHold.fillRange(0, _cellTrailHold.length, 0);
    _cellTrailAge.fillRange(0, _cellTrailAge.length, -1.0);
    _wakeAge.fillRange(0, _maxWakeStamps, -1.0);
    _hasActiveTrails = false;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isSuperseded || !_hasActiveTrails) return;

    final clampedDt = dt.clamp(0.0, 0.05);
    _holdPulseClock = (_holdPulseClock + clampedDt * 6.5) % (math.pi * 200.0);

    bool anyAlive = false;
    final cellDecay = clampedDt / _cellTrailFadeSeconds;
    for (int i = 0; i < _cellTrailAge.length; i++) {
      if (_cellTrailHold[i] != 0) {
        _cellTrailAge[i] = 1.0;
        anyAlive = true;
      } else if (_cellTrailAge[i] > 0.0) {
        final next = _cellTrailAge[i] - cellDecay;
        _cellTrailAge[i] = next > 0.004 ? next : -1.0;
        if (_cellTrailAge[i] > 0.0) anyAlive = true;
      }
    }

    final wakeDecay = clampedDt / _wakeFadeSeconds;
    for (int i = 0; i < _maxWakeStamps; i++) {
      final age = _wakeAge[i];
      if (age > 0.0) {
        final next = age - wakeDecay;
        _wakeAge[i] = next > 0.004 ? next : -1.0;
        if (_wakeAge[i] > 0.0) anyAlive = true;
      }
    }

    _hasActiveTrails = anyAlive;
  }

  void markSupersededAndDispose() {
    isSuperseded = true;
    _bakedImage?.dispose();
    _bakedImage = null;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (isSuperseded) {
      _bakedImage?.dispose();
      _bakedImage = null;
      removeFromParent();
      return;
    }
    if (_bakedImage == null) {
      _bakeBoardToGpuImageSync();
    }
  }

  @override
  void onRemove() {
    _bakedImage?.dispose();
    _bakedImage = null;
    super.onRemove();
  }

  void _bakeBoardToGpuImageSync() {
    final playable = level.playableCells;
    if (playable.isEmpty) return;

    final sideClearance = cellSize * 0.085;
    final bottomShadowClearance = cellSize * 0.015;
    _bakePadding = sideClearance + bottomShadowClearance + cellSize * 0.24;

    final logicalW = (size.x + _bakePadding * 2).clamp(1.0, 4096.0);
    final logicalH = (size.y + _bakePadding * 2).clamp(1.0, 4096.0);
    final dpr = (ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
            2.0)
        .clamp(1.5, 2.25);
    final imgW = (logicalW * dpr).ceil().clamp(2, 4096);
    final imgH = (logicalH * dpr).ceil().clamp(2, 4096);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(imgW / logicalW, imgH / logicalH);
    canvas.translate(_bakePadding, _bakePadding);

    // 1. Build Recessed Cavity Cutout aligned 1:1 with `[0 .. cols * cs] x [0 .. rows * cs]`
    // so every block at `(c * cs, r * cs)` sits dead-center inside its corresponding grid cell!
    final baseCutout = PolyominoPathBuilder.buildRoundedPath(
      cells: playable,
      cellSize: cellSize,
      inset: -sideClearance,
      cornerRadius: cellSize * 0.19,
      concaveRadius: cellSize * 0.13,
    );
    final cavityPath = Path.combine(
      PathOperation.union,
      baseCutout,
      baseCutout.shift(Offset(0, bottomShadowClearance)),
    );

    // Subtle outer table ambient shadow around the cutout
    canvas.drawPath(
      cavityPath.shift(Offset(0, cellSize * 0.025)),
      Paint()
        ..color = const Color(0x6601092B)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.08),
    );

    // Deep abyssal recessed cavity base (`#040A24`)
    canvas.drawPath(
      cavityPath,
      Paint()..color = const Color(0xFF040A24),
    );

    // 2. Clipped Interior: Recessed Floor Plane + 1:1 Aligned Grid Slots
    canvas.save();
    canvas.clipPath(cavityPath);

    // Subtle recessed top cliff wall kept within `sideClearance` so it never cuts across row-0 glass blocks
    final cliffDrop = cellSize * 0.055;
    canvas.drawPath(
      cavityPath.shift(Offset(0, cliffDrop)),
      Paint()..color = const Color(0xFF07133B),
    );

    // Dark-navy 3D floor tile slots centered 1:1 on `(c * cellSize, r * cellSize)` (`tileYShift = 0`)
    final tileInset = cellSize * 0.028;
    final tileRadius = Radius.circular(cellSize * 0.135);

    for (final (c, r) in playable) {
      final isAlt = ((c + r) & 1) == 1;
      final topColor = isAlt ? const Color(0xFF0D235F) : const Color(0xFF0C1E50);
      final wallColor = isAlt ? const Color(0xFF081642) : const Color(0xFF07133A);

      final tileRect = Rect.fromLTWH(
        c * cellSize + tileInset,
        r * cellSize + tileInset,
        cellSize - tileInset * 2,
        cellSize - tileInset * 2,
      );
      final rrect = RRect.fromRectAndRadius(tileRect, tileRadius);

      // Compact pedestal front lip staying within the cell groove
      canvas.drawRRect(
        rrect.shift(Offset(0, cellSize * 0.024)),
        Paint()..color = wallColor,
      );
      // Pedestal top face aligned 1:1 with `(c * cellSize, r * cellSize)`
      canvas.drawRRect(
        rrect,
        Paint()..color = topColor,
      );
      // Crisp subtle top bevel highlight on empty floor slots
      canvas.drawRRect(
        rrect.deflate(0.8),
        Paint()
          ..color = const Color(0xFF16368C).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }

    // Soft inner shadow cast downward from the top table cliff edges into the recessed frame margin
    final innerShadowDiff = Path.combine(
      PathOperation.difference,
      cavityPath,
      cavityPath.shift(Offset(0, cellSize * 0.065)),
    );
    canvas.drawPath(
      innerShadowDiff,
      Paint()
        ..color = const Color(0x99020618)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.035),
    );

    canvas.restore();

    // 3. Subtle Purple-Indigo Table Cutout Rim Bevel harmonizing with `Background_Core.png`
    final bounds = cavityPath.getBounds();
    final rimStrokeW = (cellSize * 0.042).clamp(1.6, 3.2);
    canvas.drawPath(
      cavityPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimStrokeW
        ..shader = ui.Gradient.linear(
          Offset(bounds.center.dx, bounds.top),
          Offset(bounds.center.dx, bounds.bottom),
          const [
            Color(0xFF1F1254),
            Color(0xFF392184),
            Color(0xFF5232AE),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    // 4. Highlight enclosed inner wall islands (`L5`, `L17`, `L20`, `L27`, `L33`...) centered 1:1
    // on `(c * cellSize, r * cellSize)` so inner obstacles align symmetrically with adjacent blocks.
    final enclosedWalls = _findEnclosedWallCells(playable);
    if (enclosedWalls.isNotEmpty) {
      final islandTopPath = PolyominoPathBuilder.buildRoundedPath(
        cells: enclosedWalls,
        cellSize: cellSize,
        inset: sideClearance,
        cornerRadius: cellSize * 0.14,
        concaveRadius: cellSize * 0.14,
      );
      canvas.drawPath(
        islandTopPath,
        Paint()..color = const Color(0xFF462899),
      );
      canvas.drawPath(
        islandTopPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimStrokeW
          ..color = const Color(0xFF5C39BC),
      );
    }

    final picture = recorder.endRecording();
    try {
      _bakedImage = picture.toImageSync(imgW, imgH);
      _bakedSrcRect = Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble());
      _bakedDstRect = Rect.fromLTWH(
        -_bakePadding,
        -_bakePadding,
        logicalW,
        logicalH,
      );
    } finally {
      picture.dispose();
    }
  }

  /// Finds wall cells that are disconnected from the exterior border (enclosed inner islands).
  Set<GridCell> _findEnclosedWallCells(Set<GridCell> playable) {
    final allWalls = <GridCell>{};
    for (int r = 0; r < level.rows; r++) {
      for (int c = 0; c < level.cols; c++) {
        if (!playable.contains((c, r))) {
          allWalls.add((c, r));
        }
      }
    }
    if (allWalls.isEmpty) return const <GridCell>{};

    final exteriorConnected = <GridCell>{};
    final queue = <GridCell>[];
    for (final (c, r) in allWalls) {
      if (c == 0 || c == level.cols - 1 || r == 0 || r == level.rows - 1) {
        if (exteriorConnected.add((c, r))) {
          queue.add((c, r));
        }
      }
    }
    var head = 0;
    while (head < queue.length) {
      final (cx, cy) = queue[head++];
      for (final (nx, ny) in [
        (cx + 1, cy),
        (cx - 1, cy),
        (cx, cy + 1),
        (cx, cy - 1),
      ]) {
        if (allWalls.contains((nx, ny)) && exteriorConnected.add((nx, ny))) {
          queue.add((nx, ny));
        }
      }
    }
    return allWalls.difference(exteriorConnected);
  }

  @override
  void render(Canvas canvas) {
    if (isSuperseded) return;
    final img = _bakedImage;
    if (img != null) {
      canvas.drawImageRect(img, _bakedSrcRect, _bakedDstRect, _imagePaint);
    }
    if (_hasActiveTrails) {
      _drawBoardCellTrailsAndWake(canvas);
    }
  }

  void _drawBoardCellTrailsAndWake(Canvas canvas) {
    final tileInset = cellSize * 0.028;
    final baseTileSpan = cellSize - tileInset * 2.0;
    final baseTileRadius = cellSize * 0.135;

    // 1. Animated board grid slot highlights under & trailing the dragged block
    for (int i = 0; i < _cellTrailAge.length; i++) {
      final rawAge = _cellTrailAge[i];
      if (rawAge <= 0.0) continue;

      final c = i % _gridCols;
      final r = i ~/ _gridCols;
      final baseColor = _cellTrailColor[i];
      final cx = c * cellSize + cellSize * 0.5;
      final cy = r * cellSize + cellSize * 0.5;

      final bool isHeld = _cellTrailHold[i] != 0;
      final double scale;
      final double fillAlpha;
      final double rimAlpha;
      if (isHeld) {
        final pulse = 0.5 + 0.5 * math.sin(_holdPulseClock);
        scale = 0.96 + 0.025 * pulse;
        fillAlpha = 0.20 + 0.05 * pulse;
        rimAlpha = 0.42 + 0.08 * pulse;
      } else {
        final u = rawAge.clamp(0.0, 1.0);
        final fade = u * u;
        final popBump = u > 0.72
            ? ((1.0 - (u - 0.72) / 0.28).clamp(0.0, 1.0) * 0.035)
            : 0.0;
        scale = (0.62 + 0.36 * u + popBump).clamp(0.4, 1.04);
        fillAlpha = 0.32 * fade;
        rimAlpha = 0.48 * fade;
      }

      final span = baseTileSpan * scale;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: span, height: span),
        Radius.circular(baseTileRadius * scale),
      );

      _trailFillPaint.color = baseColor.withValues(alpha: fillAlpha);
      canvas.drawRRect(rrect, _trailFillPaint);

      _trailRimPaint.color = Color.lerp(baseColor, Colors.white, 0.48)!
          .withValues(alpha: rimAlpha);
      canvas.drawRRect(rrect, _trailRimPaint);
    }

    // 2. Soft continuous motion wake stamps trailing the sliding block body
    final wakeRadius = cellSize * 0.14;
    for (int offset = 0; offset < _maxWakeStamps; offset++) {
      final idx = (_wakeCursor + offset) % _maxWakeStamps;
      final rawAge = _wakeAge[idx];
      if (rawAge <= 0.0) continue;

      final u = rawAge.clamp(0.0, 1.0);
      final scale = 0.74 + 0.22 * u;
      final alpha = 0.10 * u * u;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(_wakeCx[idx], _wakeCy[idx]),
          width: _wakeW[idx] * scale,
          height: _wakeH[idx] * scale,
        ),
        Radius.circular(wakeRadius * scale),
      );
      _trailFillPaint.color =
          Color.lerp(_wakeColor[idx], Colors.white, 0.22)!
              .withValues(alpha: alpha);
      canvas.drawRRect(rrect, _trailFillPaint);
    }
  }
}
