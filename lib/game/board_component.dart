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

  @override
  Future<void> onLoad() async {
    await super.onLoad();
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

    final sideClearance = cellSize * 0.095;
    final topPerspectiveShift = cellSize * 0.080;
    final bottomPerspectiveShift = cellSize * 0.145;
    _bakePadding = sideClearance + bottomPerspectiveShift + cellSize * 0.28;

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

    // 1. Build 2.5D Perspective Cavity Cutout:
    // Shifting top edges by `+0.080 * cs` (`-0.015 * cs` at row 0) and bottom edges by
    // `+0.145 * cs` (`rows + 0.240 * cs` at bottom row) aligns the cavity with the `+0.15 * cs`
    // perspective floor plane AND keeps enclosed inner wall pillars (`L5`, `L17`, `L20`, `L27`...)
    // at full `0.81 * cs × 0.745 * cs` 3D royal-blue pillar proportions centered on the 2.5D grid!
    final baseCutout = PolyominoPathBuilder.buildRoundedPath(
      cells: playable,
      cellSize: cellSize,
      inset: -sideClearance,
      cornerRadius: cellSize * 0.20,
      concaveRadius: cellSize * 0.14,
    );
    final cavityPath = Path.combine(
      PathOperation.union,
      baseCutout.shift(Offset(0, topPerspectiveShift)),
      baseCutout.shift(Offset(0, bottomPerspectiveShift)),
    );

    // Subtle outer table ambient shadow around the cutout
    canvas.drawPath(
      cavityPath.shift(Offset(0, cellSize * 0.03)),
      Paint()
        ..color = const Color(0x6601092B)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.09),
    );

    // Deep abyssal recessed cavity base (`#040A24`)
    canvas.drawPath(
      cavityPath,
      Paint()..color = const Color(0xFF040A24),
    );

    // 2. Clipped Interior: Recessed Floor Plane + `TileMaterial_A` / `TileMaterial_B` Pedestals
    canvas.save();
    canvas.clipPath(cavityPath);

    // Recessed floor plane shifted down by the inner top table cliff wall (`0.165 * cellSize`)
    final cliffDrop = cellSize * 0.165;
    canvas.drawPath(
      cavityPath.shift(Offset(0, cliffDrop)),
      Paint()..color = const Color(0xFF07133B),
    );

    // Subtle dark-navy 3D floor tile pedestals (`TileMaterial_A: #0D1E4C`, `TileMaterial_B: #0C225C`)
    // shifted down slightly in perspective so empty slots show rounded dark-blue pedestals (`ref_gameplay.png`)
    final tileYShift = cellSize * 0.15;
    final tileInset = cellSize * 0.032;
    final tileRadius = Radius.circular(cellSize * 0.13);

    for (final (c, r) in playable) {
      final isAlt = ((c + r) & 1) == 1;
      final topColor = isAlt ? const Color(0xFF0D235F) : const Color(0xFF0C1E50);
      final wallColor = isAlt ? const Color(0xFF081642) : const Color(0xFF07133A);

      final tileRect = Rect.fromLTWH(
        c * cellSize + tileInset,
        r * cellSize + tileYShift + tileInset,
        cellSize - tileInset * 2,
        cellSize - tileInset * 2,
      );
      final rrect = RRect.fromRectAndRadius(tileRect, tileRadius);

      // Subtle pedestal front lip
      canvas.drawRRect(
        rrect.shift(Offset(0, cellSize * 0.09)),
        Paint()..color = wallColor,
      );
      // Pedestal top face
      canvas.drawRRect(
        rrect,
        Paint()..color = topColor,
      );
      // Crisp subtle top bevel highlight on empty floor pedestals
      canvas.drawRRect(
        rrect.deflate(0.8),
        Paint()
          ..color = const Color(0xFF143284).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }

    // Soft inner shadow cast downward from the top table cliff edges into the cavity
    final innerShadowDiff = Path.combine(
      PathOperation.difference,
      cavityPath,
      cavityPath.shift(Offset(0, cellSize * 0.11)),
    );
    canvas.drawPath(
      innerShadowDiff,
      Paint()
        ..color = const Color(0xAA020618)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.04),
    );

    canvas.restore();

    // 3. Crisp Electric-Blue Table Cutout Rim Bevel (`#064AE8` on bottom/sides, `#032690` on top)
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
            Color(0xFF03238A),
            Color(0xFF0542D4),
            Color(0xFF0A54FF),
          ],
          const [0.0, 0.55, 1.0],
        ),
    );

    // 4. Highlight enclosed inner wall islands (`L5`, `L17`, `L20`, `L27`, `L33`...) as raised 3D
    // `#0330AC` royal-blue table pillars with top rim highlight so inner obstacles read clearly.
    final enclosedWalls = _findEnclosedWallCells(playable);
    if (enclosedWalls.isNotEmpty) {
      final rawIsland = PolyominoPathBuilder.buildRoundedPath(
        cells: enclosedWalls,
        cellSize: cellSize,
        inset: sideClearance,
        cornerRadius: cellSize * 0.14,
        concaveRadius: cellSize * 0.14,
      );
      final islandTopPath = Path.combine(
        PathOperation.intersect,
        rawIsland.shift(Offset(0, topPerspectiveShift)),
        rawIsland.shift(Offset(0, bottomPerspectiveShift)),
      );
      canvas.drawPath(
        islandTopPath,
        Paint()..color = const Color(0xFF0330AC),
      );
      canvas.drawPath(
        islandTopPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rimStrokeW
          ..color = const Color(0xFF084EE8),
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
    final img = _bakedImage;
    if (img != null) {
      canvas.drawImageRect(img, _bakedSrcRect, _bakedDstRect, _imagePaint);
    }
  }
}
