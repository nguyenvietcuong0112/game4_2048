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
  double _bakePadding = 0.0;

  Set<GridCell>? highlightedCells;
  Color highlightColor = Colors.white;

  BoardComponent({
    required this.level,
    required this.cellSize,
    required Vector2 position,
  }) : super(
          position: position,
          size: Vector2(level.cols * cellSize, level.rows * cellSize),
          priority: 1,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await _bakeBoardToGpuImage();
  }

  @override
  void onRemove() {
    _bakedImage?.dispose();
    _bakedImage = null;
    super.onRemove();
  }

  Future<void> _bakeBoardToGpuImage() async {
    final playable = level.playableCells;
    if (playable.isEmpty) return;

    final sideClearance = cellSize * 0.095;
    final bottomPerspectiveExt = cellSize * 0.245;
    _bakePadding = sideClearance + bottomPerspectiveExt + cellSize * 0.28;

    final imgW = (size.x + _bakePadding * 2).ceil().clamp(1, 4096);
    final imgH = (size.y + _bakePadding * 2).ceil().clamp(1, 4096);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(_bakePadding, _bakePadding);

    // 1. Build 2.5D Perspective Cavity Cutout:
    // Top/sides have tight `0.095 * cellSize` clearance, while bottom edges extend by
    // `+0.245 * cellSize` so the 3D vertical walls & glossy floor reflections sit inside the cavity!
    final baseCutout = PolyominoPathBuilder.buildRoundedPath(
      cells: playable,
      cellSize: cellSize,
      inset: -sideClearance,
      cornerRadius: cellSize * 0.20,
      concaveRadius: cellSize * 0.14,
    );
    final cavityPath = Path.combine(
      PathOperation.union,
      baseCutout,
      baseCutout.shift(Offset(0, bottomPerspectiveExt)),
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

    // Recessed floor plane shifted down by the inner top table cliff wall (`0.18 * cellSize`)
    final cliffDrop = cellSize * 0.18;
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
    canvas.drawPath(
      cavityPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.042).clamp(1.6, 3.2)
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

    final picture = recorder.endRecording();
    _bakedImage = await picture.toImage(imgW, imgH);
    picture.dispose();
  }

  @override
  void render(Canvas canvas) {
    final img = _bakedImage;
    if (img != null) {
      canvas.drawImage(img, Offset(-_bakePadding, -_bakePadding), Paint());
    }

    // Dynamic Landing Placement Highlight under the dragged piece
    final hl = highlightedCells;
    if (hl != null && hl.isNotEmpty) {
      final hlPath = PolyominoPathBuilder.buildRoundedPath(
        cells: hl,
        cellSize: cellSize,
        inset: cellSize * 0.025,
        cornerRadius: cellSize * 0.15,
      ).shift(Offset(0, cellSize * 0.14));
      canvas.drawPath(
        hlPath,
        Paint()
          ..color = highlightColor.withValues(alpha: 0.20)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        hlPath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
    }
  }
}
