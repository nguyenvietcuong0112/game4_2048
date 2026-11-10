import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:flame/flame.dart';
import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/game/vfx_components.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';

class _NoOpAudioService extends AudioHapticsService {
  @override
  void playPut() {}
  @override
  void playMerge() {}
}

Future<void> _mountAndLoadGame(
  WidgetTester tester,
  BlockOrderGame game,
) async {
  await tester.runAsync(() async {
    const sprites = [
      'IceLock.png',
      'IceBlocks.png',
      'Ice_Shards.png',
      'Screw_Greyscale_01.png',
      'Screw_Greyscale_02.png',
      'Screw_Greyscale_03.png',
      'Movement_Single-Horizontal_Shadow.png',
      'Movement_Single-Horizontal_Stroke.png',
      'Movement_Single-Horizontal_Top.png',
      'Movement_Double_Horizontal.png',
      'Movement_Double_Vertical.png',
      'Sparkle_01.png',
      'ParticleFlare.png',
      'Explosion_Halo.png',
      'Glow_Ring.png',
      'Glow_02.png',
      'PowerUp_Icon_Arrow.png',
      'Hand_01.png',
    ];
    for (final s in sprites) {
      await Flame.images.load(s);
    }
    await ScrewTextureCleaner.ensureCleanedScrewsLoaded();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 540,
          height: 960,
          child: GameWidget(game: game),
        ),
      ),
    ),
  );
  for (int i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 32));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Level 5: Dragging piece with overhanging arm into Cross (+) 512 in narrow well merges and wins',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });

      // Exact board layout from Level 5:
      // Narrow 3-column well at cols 2, 3, 4 with walls at (4, 7), (5, 7), (6, 7), etc.
      final walls = <GridCell>{
        (0, 0), (3, 0), (6, 0),
        (0, 1), (3, 1), (6, 1),
        (0, 2), (6, 2),
        (0, 3), (3, 3), (6, 3),
        (0, 4), (6, 4),
        (0, 7), (1, 7), (2, 7), (4, 7), (5, 7), (6, 7),
        (0, 8), (1, 8), (5, 8), (6, 8),
        (0, 9), (1, 9), (4, 9), (5, 9), (6, 9),
      };

      // Piece C: Cross (+) 512 at col 2, row 7
      // local cells: (1, 0), (0, 1), (1, 1), (2, 1), (1, 2)
      // World cells: (3, 7), (2, 8), (3, 8), (4, 8), (3, 9)
      final pieceC = PieceModel(
        id: 1,
        key: 'C',
        col: 2,
        row: 7,
        localCells: const [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
        number: 512,
      );

      // Top piece from screenshot: 512 piece at col 2, row 5
      // with right arm at col 4, row 6 (local cell (2, 1))
      // When dragged down (pushDir = (0, 1)), local cell (2, 1) steps to (4, 7), which is a wall!
      final topPiece = PieceModel(
        id: 2,
        key: 'Top512',
        col: 2,
        row: 5,
        localCells: const [(1, 0), (1, 1), (2, 1)],
        number: 512,
      );

      final level = LevelDefinition(
        number: 5,
        title: 'Level 5 Well Test',
        cols: 7,
        rows: 10,
        timeSeconds: 180,
        timerDisabled: true,
        walls: walls,
        initialPieces: [pieceC, topPiece],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: _NoOpAudioService(),
        onLevelWon: () {},
        onTimeExpired: () {},
      );

      await _mountAndLoadGame(tester, game);

      // Verify pieces are loaded
      expect(game.debugPieces.length, 2);

      // Drag topPiece at cell (3, 6) down towards pieceC at (3, 7)
      final from = game.debugCellCenterCanvas(3, 6);
      final to = game.debugCellCenterCanvas(3, 7);

      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(to);
      await tester.pump(const Duration(milliseconds: 32));

      // Must successfully detect merge candidate!
      final topComp = game.debugPieces.firstWhere((p) => p.model.id == 2);
      final bottomComp = game.debugPieces.firstWhere((p) => p.model.id == 1);
      expect(topComp.isMergeCandidate, isTrue);
      expect(bottomComp.isMergeCandidate, isTrue);

      // Release to commit merge
      await gesture.up();
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      // Level won! Final merge triggers win sequence!
      expect(game.isWinSequenceActiveNotifier.value, isTrue);
    },
  );
}
