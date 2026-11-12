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

  BoardComponent({
    required this.level,
    required this.cellSize,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2(level.cols * cellSize, level.rows * cellSize),
          priority: 1,
        ) {
    _bakeBoardToGpuImageSync();
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
  }
}
