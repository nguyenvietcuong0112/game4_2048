import 'package:block_order_2048/geometry/polyomino_path_builder.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/ui/unity_ui_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MovementConstraint.resolveMergedWith combines movement axes accurately', () {
    expect(
      MovementConstraint.pinned.resolveMergedWith(MovementConstraint.free),
      MovementConstraint.free,
    );
    expect(
      MovementConstraint.horizontalOnly
          .resolveMergedWith(MovementConstraint.verticalOnly),
      MovementConstraint.free,
    );
    expect(
      MovementConstraint.horizontalOnly
          .resolveMergedWith(MovementConstraint.pinned),
      MovementConstraint.horizontalOnly,
    );
    expect(
      MovementConstraint.pinned.resolveMergedWith(MovementConstraint.pinned),
      MovementConstraint.pinned,
    );
  });

  test('PieceModel.computeLabelCenterInCells centers rectangles and L-elbows', () {
    final rectPiece = PieceModel(
      id: 1,
      key: 'R',
      col: 0,
      row: 0,
      localCells: const [
        (0, 0),
        (1, 0),
        (2, 0),
        (0, 1),
        (1, 1),
        (2, 1),
      ],
      number: 4096,
    );
    expect(rectPiece.computeLabelCenterInCells(), (1.5, 1.0));

    final lPiece = PieceModel(
      id: 2,
      key: 'L',
      col: 0,
      row: 0,
      localCells: const [
        (1, 0),
        (0, 1),
        (1, 1),
      ],
      number: 16,
    );
    // Elbow cell is (1, 1) -> center (1.5, 1.5)
    expect(lPiece.computeLabelCenterInCells(), (1.5, 1.5));
  });

  test('PolyominoPathBuilder builds valid closed path for L-shaped polyomino', () {
    final path = PolyominoPathBuilder.buildRoundedPath(
      cells: const {(1, 0), (0, 1), (1, 1)},
      cellSize: 60.0,
      inset: 2.5,
      cornerRadius: 12.0,
    );
    final bounds = path.getBounds();
    expect(bounds.width, greaterThan(110.0));
    expect(bounds.height, greaterThan(110.0));
    expect(path.contains(const Offset(90, 90)), isTrue);
    expect(path.contains(const Offset(20, 20)), isFalse);
  });

  test('LevelRepository & Palette load all 122 campaign levels (+1 prepended Level 1 Spotlight Tutorial) and 25 bonus levels',
      () async {
    final repo = await LevelRepository.loadFromAssets();
    final palette = await BlockOrderPalette.loadFromAssets();

    expect(repo.campaignLevels.length, 122);
    expect(repo.bonusLevels.length, 25);

    // New Level 1: 4x6 Spotlight Tutorial with 4 2x2 blocks (2, 2, 4, 8)
    final lv1 = repo.getCampaignLevel(1);
    expect(lv1.number, 1);
    expect((lv1.cols, lv1.rows), (4, 6));
    expect(lv1.timerDisabled, isTrue);
    expect(lv1.initialPieces.length, 4);
    expect(
      lv1.initialPieces.map((p) => p.number).toList()..sort(),
      [2, 2, 4, 8],
    );

    // Old Level 1 shifted intact to Level 2 (6x10)
    final lv2 = repo.getCampaignLevel(2);
    expect(lv2.number, 2);
    expect((lv2.cols, lv2.rows), (6, 10));

    // Old Level 20 shifted intact to Level 21 (Ice + Dud)
    final lv21 = repo.getCampaignLevel(21);
    expect(lv21.number, 21);
    expect(lv21.hasIce, isTrue);
    expect(lv21.hasDud, isTrue);

    final style2048 = palette.styleFor(number: 2048, isFrozen: false);
    expect(style2048.number, 2048);
  });

  test('UnitySpriteRegistry preloads all 25 sliced Unity UI sprites cleanly',
      () async {
    double lastProgress = 0.0;
    await UnitySpriteRegistry.preloadAll(
      onProgress: (p) => lastProgress = p,
    );
    expect(lastProgress, 1.0);
    for (final spriteName in UnitySpriteRegistry.slices.keys) {
      expect(
        UnitySpriteRegistry.get(spriteName),
        isNotNull,
        reason: 'Expected $spriteName to be decoded into GPU ui.Image cache',
      );
    }
  });
}
