import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';

class _SilentAudioService extends AudioHapticsService {
  @override
  void playGrab() {}

  @override
  void playPut() {}

  @override
  void playAttract() {}

  @override
  void playMerge({int tier = 0}) {}

  @override
  void hapticDrop() {}

  @override
  void hapticMergeImpact({int tier = 0}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LevelDefinition buildMagnetLevel() {
    return LevelDefinition(
      number: 2,
      title: 'Level 2',
      cols: 4,
      rows: 3,
      timeSeconds: 60,
      timerDisabled: false,
      walls: const {},
      initialPieces: [
        PieceModel(
          id: 1,
          key: 'p1',
          col: 0,
          row: 1,
          number: 2,
          localCells: const [(0, 0)],
          movement: MovementConstraint.free,
        ),
        PieceModel(
          id: 2,
          key: 'p2',
          col: 2,
          row: 1,
          number: 2,
          localCells: const [(0, 0)],
          movement: MovementConstraint.free,
        ),
        PieceModel(
          id: 3,
          key: 'p3',
          col: 0,
          row: 2,
          number: 4,
          localCells: const [(0, 0)],
          movement: MovementConstraint.free,
        ),
      ],
    );
  }

  testWidgets(
    'magnetic attraction pulls mergeable blocks toward each other, resets on release, and commits merge cleanly',
    (tester) async {
      late BlockOrderGame game;
      late BlockOrderPalette palette;
      late PieceVisualSettings visualSettings;

      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        visualSettings = await PieceVisualSettings.loadFromAssets();
      });

      game = BlockOrderGame(
        initialLevel: buildMagnetLevel(),
        palette: palette,
        visualSettings: visualSettings,
        audio: _SilentAudioService(),
        onLevelWon: () {},
        onTimeExpired: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 412,
            height: 892,
            child: GameWidget(game: game),
          ),
        ),
      );
      for (int i = 0; i < 40 && game.debugPieces.length < 3; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 350));

      final pieceA = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final pieceB = game.debugPieces.firstWhere((p) => p.model.id == 2);
      final pieceMismatch = game.debugPieces.firstWhere((p) => p.model.id == 3);
      final stage = game.children.whereType<PositionComponent>().first;

      Offset worldToCanvas(Vector2 worldPos) {
        final p = stage.position + worldPos * stage.scale.x;
        return Offset(p.x, p.y);
      }

      // 1. Drag mismatched `4` piece toward `2` -> zero magnet attraction
      final mismatchStart = worldToCanvas(pieceMismatch.worldCenter);
      final mismatchUp = worldToCanvas(
        pieceMismatch.worldCenter - Vector2(0, game.debugCellSize * 0.35),
      );
      final gMismatch = await tester.startGesture(mismatchStart);
      await gMismatch.moveTo(mismatchUp);
      await tester.pump(const Duration(milliseconds: 60));
      expect(game.debugMagnetPartner, isNull);
      expect(game.debugMagnetBridgeStrength, 0.0);
      await gMismatch.up();
      await tester.pump(const Duration(milliseconds: 120));

      // 2. Drag matching `2` (`pieceA` at col 0) right toward `pieceB` at col 2:
      // Magnetic assist pulls `pieceA` into col 1 (`0.45 + assist > 0.55`),
      // arms `_magnetPartner = pieceB`, pulls BOTH `pieceA` (+x) & `pieceB` (-x), and lights up VFX!
      final aCenter = worldToCanvas(pieceA.worldCenter);
      final g = await tester.startGesture(aCenter);
      await g.moveBy(
        Offset(game.debugCellSize * 0.45 * stage.scale.x, 0),
      );
      await tester.pump(const Duration(milliseconds: 90));

      expect(pieceA.model.col, 1);
      expect(game.debugMagnetPartner, pieceB);
      expect(game.debugMagnetBridgeStrength, greaterThan(0.15));
      expect(pieceA.debugMagnetAttractStrength, greaterThan(0.2));
      expect(pieceB.debugMagnetAttractStrength, greaterThan(0.2));
      expect(pieceA.debugMagnetPullOffsetPx.dx, greaterThan(0.5));
      expect(pieceB.debugMagnetPullOffsetPx.dx, lessThan(-0.5));

      // Release early before arming merge -> magnet resets smoothly cleanly without merging
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(game.debugMagnetPartner, isNull);
      expect(pieceB.debugMagnetAttractStrength, 0.0);
      expect(pieceB.debugMagnetPullOffsetPx.dx.abs(), lessThan(0.5));
      expect(pieceB.model.number, 2);

      // 3. Grab `pieceA` (now at col 1, adjacent to `pieceB` at col 2) and push into merge:
      final aNextCenter = worldToCanvas(pieceA.worldCenter);
      final gMerge = await tester.startGesture(aNextCenter);
      await gMerge.moveBy(
        Offset(game.debugCellSize * 0.25 * stage.scale.x, 0),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(pieceA.debugMagnetAttractStrength, greaterThanOrEqualTo(0.62));
      expect(pieceB.debugMagnetAttractStrength, greaterThanOrEqualTo(0.62));

      await gMerge.moveBy(
        Offset(game.debugCellSize * 0.22 * stage.scale.x, 0),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(pieceA.debugMagnetAttractStrength, greaterThan(0.75));
      expect(pieceB.debugMagnetAttractStrength, greaterThan(0.75));

      await gMerge.up();
      await tester.pump(const Duration(milliseconds: 350));

      expect(game.debugMagnetPartner, isNull);
      expect(pieceB.model.number, 4);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
