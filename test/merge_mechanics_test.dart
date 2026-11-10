import 'dart:ui' as ui;
import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/game/vfx_components.dart';
import 'package:block_order_2048/geometry/polyomino_path_builder.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/ads_manager.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/exit_gameplay_popup.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/lose_overlay.dart';
import 'package:block_order_2048/ui/mechanic_unlock_dialog.dart';
import 'package:block_order_2048/ui/powerup_buy_popup.dart';
import 'package:block_order_2048/ui/unity_ui_kit.dart';
import 'package:block_order_2048/ui/win_overlay.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudioHapticsService extends AudioHapticsService {
  int putCount = 0;
  int attractCount = 0;
  int mergeCount = 0;
  int iceBreakCount = 0;
  int dropHapticCount = 0;
  int mergeImpactHapticCount = 0;

  @override
  void playClick() {}

  @override
  void playPowerUpSelect() {}

  @override
  void playGrab() {}

  @override
  void playPut() {
    putCount++;
  }

  @override
  void playAttract() {
    attractCount++;
  }

  @override
  void playMerge() {
    mergeCount++;
  }

  @override
  void playIceBreakSmall() {}

  @override
  void playIceBreak() {
    iceBreakCount++;
  }

  @override
  void playLevelUpArrow() {}

  @override
  void playLevelUpFly() {}

  @override
  void playLevelUpMerge() {}

  @override
  void playTimeFreeze() {}

  int waterStreamFlowCount = 0;

  @override
  void playWaterStreamFlow() {
    waterStreamFlowCount++;
  }

  @override
  void playWinComplete() {}

  @override
  void playWinAmazing() {}

  @override
  void playCoinCollect() {}

  @override
  void playOutOfTime() {}

  @override
  void playLevelFailed() {}

  @override
  void hapticBlocked() {}

  @override
  void hapticDrop() {
    dropHapticCount++;
  }

  final List<int> comboPraises = <int>[];

  @override
  void hapticMergeImpact() {
    mergeImpactHapticCount++;
  }

  @override
  void playComboPraise(int comboCount) {
    if (comboCount >= 2) {
      comboPraises.add(comboCount);
    }
  }
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

  setUp(() {
    AdsManager.mockRewardResult = true;
    AdsManager.enableAds = false;
  });

  test(
    'PieceVisualSettings parses all authentic Unity curves, geometry helpers & ScrewTextureCleaner',
    () async {
      final settings = await PieceVisualSettings.loadFromAssets();

      expect(settings.jellyLeanPerLagCell, closeTo(1.35, 1e-3));
      expect(settings.jellyLeanSizeFalloff, closeTo(0.50, 1e-3));
      expect(settings.jellyStiffness, closeTo(300.0, 1e-3));
      expect(settings.jellyDamping, closeTo(0.20, 1e-3));
      expect(settings.mergeCandidatePulseScale.evaluate(1.0), closeTo(1.370, 1e-2));
      expect(settings.mergeCandidateReleaseCurve.evaluate(0.0), closeTo(1.370, 1e-2));
      expect(settings.mergeCandidateReleaseCurve.evaluate(1.0), closeTo(1.0, 1e-2));
      expect(settings.mergeJoinStrength.evaluate(0.0), closeTo(0.0, 1e-2));
      expect(settings.mergeJoinStrength.evaluate(1.0), closeTo(1.0, 1e-2));
      expect(settings.mergePreviewNumberSize.evaluate(0.0), closeTo(0.0, 1e-2));
      expect(settings.mergePreviewNumberSize.evaluate(1.0), closeTo(1.0, 1e-2));
      expect(settings.mergePartnerNumberSize.evaluate(0.0), closeTo(1.0, 1e-2));
      expect(settings.mergePartnerNumberSize.evaluate(1.0), closeTo(0.75, 1e-2));
      expect(settings.mergeSurvivorStaysPulseScale, closeTo(1.20, 1e-3));
      expect(settings.mergeSurvivorMovesPulseScale, closeTo(1.12, 1e-3));
      expect(settings.mergeTransitionSoftness, closeTo(0.60, 1e-3));

      // Verify StationaryBlocksParts 1x1 vs multi-block corner screw placements
      final singlePins = PolyominoPathBuilder.computePinnedScrewAnchors(
        cells: const {(0, 0)},
        cellSize: 100.0,
      );
      expect(singlePins.length, 4);
      expect(singlePins.first.baseScale, closeTo(0.65, 1e-4));
      expect(singlePins.first.restPos.dx, closeTo(20.0, 1e-3)); // 0.50 - 0.30 = 0.20

      final multiPins = PolyominoPathBuilder.computePinnedScrewAnchors(
        cells: const {(0, 0), (1, 0)},
        cellSize: 100.0,
      );
      expect(multiPins.length, 4);
      expect(multiPins.first.baseScale, closeTo(1.0, 1e-4));

      // Verify L-shape horizontal movement resolves non-compact arrow gap on roomiest row (row 1)
      final lPiece = PieceModel(
        id: 10,
        key: 'L',
        col: 0,
        row: 0,
        localCells: const [(0, 0), (0, 1), (1, 1)],
        number: 4,
        movement: MovementConstraint.horizontalOnly,
      );
      final arrowLayout = PolyominoPathBuilder.resolveMovementArrows(
        model: lPiece,
        cellSize: 100.0,
      );
      expect(arrowLayout, isNotNull);
      expect(arrowLayout!.hasArrowGap, isTrue);
      final gapCenter = (arrowLayout.negRestPos + arrowLayout.posRestPos) * 0.5;
      expect(gapCenter.dx, closeTo(100.0, 1e-3));
      expect(gapCenter.dy, closeTo(150.0, 1e-3));

      await Flame.images.load('Screw_Greyscale_01.png');
      await Flame.images.load('Screw_Greyscale_02.png');
      await Flame.images.load('Screw_Greyscale_03.png');
      await ScrewTextureCleaner.ensureCleanedScrewsLoaded();
      expect(ScrewTextureCleaner.cleanedScrews.length, 3);

      final screwBytes = await ScrewTextureCleaner.cleanedScrews.first
          .toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(screwBytes, isNotNull);
      final rgba = screwBytes!.buffer.asUint8List();
      expect(rgba[3], 0);
      final centerAlphaIdx = (128 * 256 + 128) * 4 + 3;
      expect(rgba[centerAlphaIdx], 255);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Hold-to-Preview runs 5-stage MergeColorTransition & MergeNumberPreview, smoothly retracts on cancel, and commits ONLY on release',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 2,
        title: 'Test Hold Release',
        cols: 4,
        rows: 3,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'a',
            col: 0,
            row: 1,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 2,
            key: 'b',
            col: 2,
            row: 1,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 3,
            key: 'c',
            col: 3,
            row: 2,
            localCells: const [(0, 0)],
            number: 8,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );

      await _mountAndLoadGame(tester, game);
      expect(game.debugPieces.length, 3);

      // 1. Drag Piece 1 from (0,1) deep into Piece 2 at (2,1) while holding finger DOWN
      final startPt = game.debugCellCenterCanvas(0, 1);
      final targetPt = game.debugCellCenterCanvas(2, 1);
      final gesture = await tester.startGesture(startPt);
      await tester.pump(const Duration(milliseconds: 16));

      await gesture.moveTo(targetPt);
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      // MUST NOT have merged mid-drag even after holding > 1.2s!
      expect(game.debugPieces.length, 3);
      expect(audio.mergeCount, 0);
      expect(audio.attractCount, 1);

      final p1 = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final p2 = game.debugPieces.firstWhere((p) => p.model.id == 2);
      expect(p1.model.col, 1);
      expect(p1.isPartnerCandidate, isTrue);
      expect(p2.isSurvivorCandidate, isTrue);
      expect(p2.previewMergedNumber, 4);

      // Verify `_MergeCylinder`, `_MergeOverlap`, and `MergeNumberPreview` active on BOTH blocks during hold!
      expect(p1.debugMergeCylinderRadius, greaterThan(0.0));
      expect(p2.debugMergeCylinderRadius, greaterThan(0.0));
      expect(p1.debugMergeOverlapStrength, greaterThan(0.5));
      expect(p2.debugMergeOverlapStrength, greaterThan(0.5));
      expect(p2.debugPreviewNumberScaleFactor, closeTo(1.0, 0.05));
      expect(p2.debugNormalNumberScaleFactor, closeTo(0.0, 0.05));
      expect(p1.debugNormalNumberScaleFactor, closeTo(0.75, 0.05));

      // 2. Pull finger back to (0, 1) WITHOUT lifting -> 0.20s smooth ShrinkAway & cylinder retraction!
      await gesture.moveTo(startPt);
      await tester.pump(const Duration(milliseconds: 32));
      expect(p1.isPartnerCandidate, isFalse);
      expect(p2.isSurvivorCandidate, isFalse);
      expect(p2.debugIsPreviewShrinkingAway, isTrue);
      expect(p2.debugMergeCylinderRadius, greaterThan(0.0));

      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(game.debugPieces.length, 3);
      expect(audio.mergeCount, 0);
      expect(p2.previewMergedNumber, isNull);
      expect(p2.debugIsPreviewShrinkingAway, isFalse);
      expect(p2.debugMergeCylinderRadius, 0.0);
      expect(p2.debugNormalNumberScaleFactor, closeTo(1.0, 1e-3));

      // 3. Push back into Piece 2 at (2, 1) and RELEASE finger -> MUST commit merge & expand cylinder!
      await gesture.moveTo(targetPt);
      await tester.pump(const Duration(milliseconds: 32));
      expect(p2.isSurvivorCandidate, isTrue);
      expect(p2.previewMergedNumber, 4);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 32));
      // Mid-expansion (`0.032s < 0.30s`): radial cylinder is actively sweeping across survivor!
      expect(p2.debugMergeCylinderRadius, greaterThan(0.0));

      for (int i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(audio.mergeCount, 1);
      expect(game.debugPieces.length, 2);
      expect(p2.model.number, 4);
      expect(p2.debugMergeCylinderRadius, 0.0);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Larger polyomino dragged into smaller matching piece shows preview on larger piece and steps forward on release',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 5,
        title: 'Test Polyomino Survivor',
        cols: 4,
        rows: 3,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'big',
            col: 0,
            row: 1,
            localCells: const [(0, 0), (1, 0)],
            number: 4,
          ),
          PieceModel(
            id: 2,
            key: 'small_pinned',
            col: 2,
            row: 1,
            localCells: const [(0, 0)],
            number: 4,
            movement: MovementConstraint.pinned,
          ),
          PieceModel(
            id: 3,
            key: 'other',
            col: 3,
            row: 2,
            localCells: const [(0, 0)],
            number: 16,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );

      await _mountAndLoadGame(tester, game);

      final bigPiece = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final smallPiece = game.debugPieces.firstWhere((p) => p.model.id == 2);

      final grabPt = game.debugCellCenterCanvas(1, 1);
      final pushPt = game.debugCellCenterCanvas(2, 1);
      final gesture = await tester.startGesture(grabPt);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(pushPt);
      await tester.pump(const Duration(milliseconds: 32));

      expect(bigPiece.isSurvivorCandidate, isTrue);
      expect(bigPiece.previewMergedNumber, 8);
      expect(smallPiece.isPartnerCandidate, isTrue);
      expect(smallPiece.previewMergedNumber, isNull);

      await gesture.up();
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(game.debugPieces.length, 2);
      expect(bigPiece.model.number, 8);
      expect(bigPiece.model.col, 1);
      expect(bigPiece.model.movement, MovementConstraint.free);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Exact IceComponent target == mergedNumber unlock with 0.3833s badge Pop & 1-curve pinned screw shrink',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 7,
        title: 'Test Ice Exact Match & Pin Shrink',
        cols: 4,
        rows: 4,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          // Horizontal 1x1 #4 at (0, 1) -> merges into Pinned 2x1 #4 at (1, 1)..(2, 1)
          PieceModel(
            id: 1,
            key: 'h4',
            col: 0,
            row: 1,
            localCells: const [(0, 0)],
            number: 4,
            movement: MovementConstraint.horizontalOnly,
          ),
          PieceModel(
            id: 2,
            key: 'pinned_2x1_4',
            col: 1,
            row: 1,
            localCells: const [(0, 0), (1, 0)],
            number: 4,
            movement: MovementConstraint.pinned,
          ),
          // Ice blocks with target = 4 (LOWER than 8), target = 8 (EXACT match), target = 16 (HIGHER)
          PieceModel(
            id: 3,
            key: 'ice4',
            col: 0,
            row: 3,
            localCells: const [(0, 0)],
            number: 4,
            iceTarget: 4,
          ),
          PieceModel(
            id: 4,
            key: 'ice8',
            col: 1,
            row: 3,
            localCells: const [(0, 0)],
            number: 8,
            iceTarget: 8,
          ),
          PieceModel(
            id: 5,
            key: 'ice16',
            col: 2,
            row: 3,
            localCells: const [(0, 0)],
            number: 16,
            iceTarget: 16,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );

      await _mountAndLoadGame(tester, game);

      final pinnedSurvivor = game.debugPieces.firstWhere((p) => p.model.id == 2);
      final ice4 = game.debugPieces.firstWhere((p) => p.model.id == 3);
      final ice8 = game.debugPieces.firstWhere((p) => p.model.id == 4);
      final ice16 = game.debugPieces.firstWhere((p) => p.model.id == 5);

      // Drag h4 (0,1) into pinned_2x1_4 (1,1) and release to create an `8`
      final gesture = await tester.startGesture(game.debugCellCenterCanvas(0, 1));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(game.debugCellCenterCanvas(1, 1));
      await tester.pump(const Duration(milliseconds: 32));
      await gesture.up();

      // At t = 32ms after commit:
      // 1) Pinned + Horizontal -> Horizontal!
      // 2) `debugShrinkingScrewScale` starts near 1.0 (1 - curve) and shrinks toward 0.0!
      // 3) ONLY `ice8` unlocked in model (`target == 8`); `ice4` (`4 != 8`) MUST stay frozen!
      // 4) `ice8.debugIsIceCovered` is STILL true during the 0.3833s badge Pop animation!
      await tester.pump(const Duration(milliseconds: 32));
      expect(pinnedSurvivor.model.number, 8);
      expect(pinnedSurvivor.model.movement, MovementConstraint.horizontalOnly);
      expect(pinnedSurvivor.debugShrinkingScrewScale, greaterThan(0.65));

      expect(ice4.model.isFrozen, isTrue);
      expect(ice8.model.isFrozen, isFalse);
      expect(ice16.model.isFrozen, isTrue);
      expect(ice8.debugIsIceCovered, isTrue);
      expect(audio.iceBreakCount, 0);

      // Advance past 0.40s -> screws finished shrinking to 0.0, and ice8 Pop finished & shattered!
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(pinnedSurvivor.debugShrinkingScrewScale, 0.0);
      expect(ice8.debugIsIceCovered, isFalse);
      expect(ice4.debugIsIceCovered, isTrue);
      expect(ice16.debugIsIceCovered, isTrue);
      expect(audio.iceBreakCount, 1);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'CanCompleteMerge blocks illegal overhang into wall, while TryMergeOffCorner + StepOntoMergeContact merges diagonally across open corner',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 9,
        title: 'Test Overhang Block & Off-Corner Merge',
        cols: 4,
        rows: 3,
        timeSeconds: 120,
        timerDisabled: true,
        // Wall at (1, 1) blocks vertical 1x2 piece at (0,0)..(0,1) from stepping right onto (1,0)..(1,1)!
        // Meanwhile (2, 0) has a 1x1 #2, both (3, 0) and (2, 1) are open, and (3, 1) has a pinned 1x1 #2 diagonally!
        walls: const {(1, 1)},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'tall4',
            col: 0,
            row: 0,
            localCells: const [(0, 0), (0, 1)],
            number: 4,
          ),
          PieceModel(
            id: 2,
            key: 'target4',
            col: 1,
            row: 0,
            localCells: const [(0, 0)],
            number: 4,
            movement: MovementConstraint.pinned,
          ),
          PieceModel(
            id: 3,
            key: 'cornerMover2',
            col: 2,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 4,
            key: 'cornerTarget2',
            col: 3,
            row: 1,
            localCells: const [(0, 0)],
            number: 2,
            movement: MovementConstraint.pinned,
          ),
          PieceModel(
            id: 5,
            key: 'anchor32',
            col: 0,
            row: 2,
            localCells: const [(0, 0)],
            number: 32,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );

      await _mountAndLoadGame(tester, game);

      // Part A: Drag tall4 at (0,0) right into target4 at (1,0) -> MUST NOT arm or merge because (1,1) is a wall!
      final tall4 = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final target4 = game.debugPieces.firstWhere((p) => p.model.id == 2);

      final g1 = await tester.startGesture(game.debugCellCenterCanvas(0, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g1.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));

      expect(tall4.isMergeCandidate, isFalse);
      expect(target4.isMergeCandidate, isFalse);

      await g1.up();
      await tester.pump(const Duration(milliseconds: 64));
      expect(audio.mergeCount, 0);
      expect(game.debugPieces.length, 5);

      // Part B: Diagonal off-corner merge! Drag cornerMover2 at (2,0) diagonally +42% right and +42% down
      // (below the 0.55 step threshold on both axes so cornerMover2 is still at (2,0), while pressing into (3,1)!)
      final mover2 = game.debugPieces.firstWhere((p) => p.model.id == 3);
      final cornerTarget2 = game.debugPieces.firstWhere((p) => p.model.id == 4);

      final c20 = game.debugCellCenterCanvas(2, 0);
      final c31 = game.debugCellCenterCanvas(3, 1);
      final diagPt = Offset(
        c20.dx + (c31.dx - c20.dx) * 0.42,
        c20.dy + (c31.dy - c20.dy) * 0.42,
      );

      final g2 = await tester.startGesture(c20);
      await tester.pump(const Duration(milliseconds: 16));
      await g2.moveTo(diagPt);
      await tester.pump(const Duration(milliseconds: 32));

      // `mover2` has NOT stepped to col=3 or row=1 yet, yet `TryMergeOffCorner` armed `cornerTarget2`!
      expect(mover2.model.col, 2);
      expect(mover2.model.row, 0);
      expect(mover2.isPartnerCandidate, isTrue);
      expect(cornerTarget2.isSurvivorCandidate, isTrue);
      expect(cornerTarget2.previewMergedNumber, 4);

      // Release finger -> `StepOntoMergeContact` steps onto contactOrigin and commits the merge into (3,1)!
      await g2.up();
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(audio.mergeCount, 1);
      expect(cornerTarget2.model.number, 4);
      expect(game.debugPieces.length, 4);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Unity board & camera framing scales cellSize 1:1 across 3x3 tutorial, 5x6 normal, and 7x8 large levels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));
      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      LevelDefinition makeGridLevel(int number, int cols, int rows) =>
          LevelDefinition(
            number: number,
            title: 'Test Grid $cols x $rows',
            cols: cols,
            rows: rows,
            timeSeconds: 120,
            timerDisabled: true,
            walls: const {},
            initialPieces: [
              PieceModel(
                id: 1,
                key: 'p1',
                col: 0,
                row: 0,
                localCells: const [(0, 0)],
                number: 2,
              ),
            ],
          );

      final game = BlockOrderGame(
        initialLevel: makeGridLevel(1, 3, 3),
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);

      // 540x960 -> u = 0.5, safeH = 960, availW = 539.8
      // Tutorial 3x3 (number <= 3): availH = 580.84, framedCols = 3.90, framedRows = 3.9720588 -> ~138.41 px
      expect(game.debugCellSize, closeTo(539.8 / 3.90, 0.05));
      expect(game.debugCellSize, greaterThan(130.0));

      // Normal 5x6 (number = 10): availH = 642.24, framedCols = 5.90, framedRows = 7.0375668 -> ~91.26 px
      game.loadLevel(makeGridLevel(10, 5, 6));
      await tester.pump(const Duration(milliseconds: 32));
      const expected5x6Rows = (6 + 0.30) * 1.021836 + 0.60;
      expect(game.debugCellSize, closeTo(642.24 / expected5x6Rows, 0.05));
      expect(game.debugCellSize, greaterThan(90.0));

      // Large 7x8 (number = 50): availW = 539.8, framedCols = 7.90, framedRows = 9.0812388 -> ~68.33 px
      game.loadLevel(makeGridLevel(50, 7, 8));
      await tester.pump(const Duration(milliseconds: 32));
      expect(game.debugCellSize, closeTo(539.8 / 7.90, 0.05));
      expect(game.debugCellSize, greaterThan(68.0));

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Unity merge audio & haptic choreography layers playPut + playMerge on release and fires delayed merge impact haptic',
    (tester) async {
      // Verify real AudioHapticsService emits zero haptics on playAttract()
      final rawAudio = AudioHapticsService()
        ..toggleSound()
        ..clearDebugLogs();
      expect(rawAudio.hapticsEnabled, isTrue);
      rawAudio.playAttract();
      expect(rawAudio.debugHapticsLog, isEmpty);

      await tester.binding.setSurfaceSize(const Size(540, 960));
      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 4,
        title: 'Test Merge Audio & Haptics',
        cols: 3,
        rows: 3,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'p1',
            col: 0,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 2,
            key: 'p2',
            col: 1,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 3,
            key: 'anchor',
            col: 2,
            row: 2,
            localCells: const [(0, 0)],
            number: 32,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);

      final g = await tester.startGesture(game.debugCellCenterCanvas(0, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));

      // Hold-to-merge armed: attract SFX fired once, zero put/merge/impact haptic yet
      expect(audio.attractCount, 1);
      expect(audio.putCount, 0);
      expect(audio.mergeCount, 0);
      expect(audio.mergeImpactHapticCount, 0);

      // Finger release commits merge -> BOTH sfx_block_put and sfx_block_merge fire immediately!
      await g.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(audio.putCount, 1);
      expect(audio.mergeCount, 1);
      expect(audio.mergeImpactHapticCount, 0);

      // Advancing past 45ms fires TriggerMerge mediumImpact haptic once
      await tester.pump(const Duration(milliseconds: 40));
      expect(audio.mergeImpactHapticCount, 1);

      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(audio.mergeImpactHapticCount, 1);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Zero-slop drag responds immediately to sub-18px movement and WinOverlay completes Stage 1 -> Stage 2 -> Coin Flight',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 1200));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        await UnitySpriteRegistry.preloadAll();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 4,
        title: 'Level 4',
        cols: 3,
        rows: 3,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'p1',
            col: 0,
            row: 1,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 2,
            key: 'p2',
            col: 2,
            row: 1,
            localCells: const [(0, 0)],
            number: 4,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);
      // Finish remaining intro zoom so stage scale == 1.0
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      final p1 = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final initialX = p1.position.x;

      // Move by only +8px (well below Flutter's 18px touch-slop): piece MUST respond immediately!
      final startPt = game.debugCellCenterCanvas(0, 1);
      final g = await tester.startGesture(startPt);
      await tester.pump(const Duration(milliseconds: 16));
      expect(p1.isDragging, isTrue);

      await g.moveBy(const Offset(8.0, 0.0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(p1.position.x, greaterThan(initialX + 2.0));
      await g.up();
      await tester.pump(const Duration(milliseconds: 32));

      // Verify WinOverlay 2-stage progression & Stage 3 coin flight collection
      bool stage2Shown = false;
      int collectedCoins = 0;
      bool nextLevelTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WinOverlay(
              levelLabel: 'Level 4',
              rewardCoins: 25,
              onStage2Shown: () => stage2Shown = true,
              onCoinChunkArrived: (chunk) => collectedCoins += chunk,
              onNextLevel: () => nextLevelTriggered = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 250));
      expect(stage2Shown, isFalse);

      // Advance past 62% of 1450ms (~950ms) -> Stage 2 (`AMAZING!`, `Level 4`, `25`, `Next Level`) appears
      await tester.pump(const Duration(milliseconds: 1300));
      expect(stage2Shown, isTrue);
      expect(find.text('AMAZING!'), findsWidgets);
      expect(find.text('Level 4'), findsWidgets);
      expect(find.text('25'), findsWidgets);
      expect(find.text('Next Level'), findsWidgets);

      // Tap `Next Level` -> triggers Stage 3 curved coin flight totaling 25 coins -> `onNextLevel`
      await tester.tap(find.byType(UnityCtaButton));
      for (int i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(collectedCoins, 25);
      expect(nextLevelTriggered, isTrue);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'LoseOverlay matches PlayOn_Open 1.50s banner -> Continue? popup, hold-to-peek, 450 coin gate, Close -> Level failed -> Try Again, and ExitGameplayPopup',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(540, 1200);
      await tester.binding.setSurfaceSize(const Size(540, 1200));
      await tester.runAsync(() async {
        await UnitySpriteRegistry.preloadAll();
      });

      bool playOnCoinsFired = false;
      bool playOnAdFired = false;
      bool failedStageEntered = false;
      bool retryFired = false;
      final peekLog = <bool>[];

      // 1. Mount LoseOverlay with unaffordable coins (100 < 450)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoseOverlay(
              levelLabel: 'Level 4',
              playerCoins: 100,
              remainingLives: 4,
              playOnCost: 450,
              extraSeconds: 30,
              onPlayOnCoins: () => playOnCoinsFired = true,
              onPlayOnAd: () => playOnAdFired = true,
              onEnterFailedStage: () => failedStageEntered = true,
              onPeekingChanged: peekLog.add,
              onRetry: () => retryFired = true,
            ),
          ),
        ),
      );

      // At t = 500ms: `OUT OF TIME` banner is visible; `Continue?` popup has not appeared yet (`t < 1.333s`)
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('OUT OF TIME'), findsWidgets);
      expect(find.text('Continue?'), findsNothing);

      // Advance past 1.50s -> `OUT OF TIME` wiped out; `Continue?` card & `Tap to see the board` visible!
      await tester.pump(const Duration(milliseconds: 1100));
      expect(find.text('OUT OF TIME'), findsNothing);
      expect(find.text('Continue?'), findsWidgets);
      expect(find.text('+30'), findsWidgets);
      expect(find.text('s'), findsWidgets);
      expect(find.text('Add 30 seconds to keep playing!'), findsOneWidget);
      expect(find.text('450'), findsWidgets);
      expect(find.text('Tap to see the board'), findsOneWidget);

      // Verify exact 0.816 PopupContainer outer hit-box width (`(1106.25 + 120) * 0.816 * (540 / 1080) = 500.31`)
      final cardRect = tester.getRect(find.byType(UnityPopupCard));
      expect(cardRect.width, closeTo((1106.25 + 120.0) * 0.816 * 0.5, 0.25));

      // Tapping disabled CoinsButton (`100 < 450`) must NOT fire `onPlayOnCoins` nor trigger board peek!
      await tester.tap(find.text('450').last);
      await tester.pump();
      expect(playOnCoinsFired, isFalse);
      expect(peekLog, isEmpty);

      // Holding pointer down on `"Tap to see the board"` area triggers board peek; releasing unpeeks!
      final peekPt = tester.getCenter(find.text('Tap to see the board'));
      final holdGesture = await tester.startGesture(peekPt);
      await tester.pump(const Duration(milliseconds: 160));
      expect(peekLog, [true]);

      await holdGesture.up();
      await tester.pump(const Duration(milliseconds: 160));
      expect(peekLog, [true, false]);

      // Tapping CloseButton (`Button_Close.png`) enters Stage 2 (`Level 4 failed`, `-1`, `Try Again`)
      final closeBtnFinder = find.ancestor(
        of: find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/images/Button_Close.png',
        ),
        matching: find.byType(UnitySpriteButton),
      );
      expect(closeBtnFinder, findsOneWidget);
      await tester.tap(closeBtnFinder);
      await tester.pump(const Duration(milliseconds: 220));

      expect(failedStageEntered, isTrue);
      expect(find.text('Level 4 failed'), findsWidgets);
      expect(find.text('-1'), findsWidgets);
      expect(find.text('Try Again'), findsWidgets);
      expect(closeBtnFinder, findsNothing);

      // Tap `Try Again` (`UnityPopupCtaButton`) -> fires `onRetry`
      await tester.tap(find.byType(UnityPopupCtaButton));
      await tester.pump(const Duration(milliseconds: 100));
      expect(retryFired, isTrue);

      // 2. Verify affordable CoinsButton (`500 >= 450`) & AdsButton on 16:9 (`540 x 960`) screen
      tester.view.physicalSize = const Size(540, 960);
      await tester.binding.setSurfaceSize(const Size(540, 960));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LoseOverlay(
              key: const ValueKey('affordable_lose'),
              levelLabel: 'Level 5',
              playerCoins: 500,
              remainingLives: 5,
              playOnCost: 450,
              onPlayOnCoins: () => playOnCoinsFired = true,
              onPlayOnAd: () => playOnAdFired = true,
              onRetry: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.tap(find.text('450').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(playOnCoinsFired, isTrue);

      final adIconCenter = tester.getCenter(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/images/Icon_Ad.png',
        ),
      );
      await tester.tapAt(adIconCenter);
      await tester.pump(const Duration(milliseconds: 100));
      expect(playOnAdFired, isTrue);

      // 3. Verify ExitGameplayPopup (`Restart level?` -> `You will lose a life!` -> `Restart`)
      bool exitRestartFired = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExitGameplayPopup(
              onConfirmRestart: () => exitRestartFired = true,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.text('Restart level?'), findsWidgets);
      expect(find.text('You will lose a life!'), findsOneWidget);
      expect(find.text('Restart'), findsWidgets);
      await tester.tap(find.byType(UnityPopupCtaButton));
      await tester.pump(const Duration(milliseconds: 100));
      expect(exitRestartFired, isTrue);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  testWidgets(
    'Booster 1:1 flow: unlock levels 17 & 27, locked non-interactivity, 2-step FTUE FREE immediate execution preserving x3 inventory, and PowerUpBuyPopup (600/450 x3 & Watch x1)',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(540, 1200);
      await tester.binding.setSurfaceSize(const Size(540, 1200));

      late final LevelRepository repo;
      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        repo = await LevelRepository.loadFromAssets();
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        await UnitySpriteRegistry.preloadAll();
        for (final s in [
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
        ]) {
          await Flame.images.load(s);
        }
        await ScrewTextureCleaner.ensureCleanedScrewsLoaded();
      });

      // 1. Verify exact `remote_config.json` unlock levels & pack prices
      expect(PlayerProgressService.levelUpUnlockLevel, 17);
      expect(PlayerProgressService.timeFreezeUnlockLevel, 27);
      expect(PlayerProgressService.levelUpPackCost, 600);
      expect(PlayerProgressService.timeFreezePackCost, 450);
      expect(PlayerProgressService.initialPowerUpInventory, 3);

      SharedPreferences.setMockInitialValues({'bo_current_level': 1});
      final progressL1 = PlayerProgressService();
      await tester.runAsync(() => progressL1.init());
      expect(progressL1.isLevelUpUnlockedForLevel(16), isFalse);
      expect(progressL1.isLevelUpUnlockedForLevel(17), isTrue);
      expect(progressL1.isTimeFreezeUnlockedForLevel(26), isFalse);
      expect(progressL1.isTimeFreezeUnlockedForLevel(27), isTrue);

      // 2. On Level 1 (< 17), tapping locked HUD power-ups does NOTHING (no snackbar, no modal)
      final audio = _SilentAudioHapticsService();
      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            key: const ValueKey('gp_l1'),
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: audio,
            progress: progressL1,
          ),
        ),
      );
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      await tester.tap(
        find.byKey(const ValueKey('hud_level_up_btn')),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(const ValueKey('hud_time_freeze_btn')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(PowerUpBuyPopup), findsNothing);

      // 3. Level 17 first entry -> 2-step `PowerUpFtueOverlay` -> FREE execution keeps `levelUpCount == 3`
      SharedPreferences.setMockInitialValues({
        'bo_current_level': 17,
        'bo_highest_level': 17,
        'bo_coins': 1200,
      });
      final progressL17 = PlayerProgressService();
      await tester.runAsync(() => progressL17.init());
      expect(progressL17.levelUpCount, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            key: const ValueKey('gp_l17'),
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: audio,
            progress: progressL17,
          ),
        ),
      );
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(find.byType(PowerUpFtueOverlay), findsOneWidget);
      expect(find.text('Level Up'), findsWidgets);
      expect(find.text('New power-up unlocked!'), findsWidgets);
      expect(
        find.text('Merge a matching pair instantly, wherever they are!'),
        findsOneWidget,
      );
      // Verify Step 1 layout: Title (`Level Up`) is strictly ABOVE SubTitle (`New power-up unlocked!`)
      final titleY = tester.getCenter(find.text('Level Up').first).dy;
      final subtitleY =
          tester.getCenter(find.text('New power-up unlocked!').first).dy;
      expect(titleY, lessThan(subtitleY));

      // Tap `Continue` -> enters Step 2 with highlighted bottom `"FREE"` button (`ftue_free_level_up_btn`)
      await tester.tap(find.byType(UnityCtaButton));
      await tester.pump(const Duration(milliseconds: 100));
      final freeLvUpBtn = find.byKey(const ValueKey('ftue_free_level_up_btn'));
      expect(freeLvUpBtn, findsOneWidget);
      expect(
        find.descendant(
          of: freeLvUpBtn,
          matching: find.byWidgetPredicate(
            (w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName ==
                    'assets/images/PowerUp_Free.png',
          ),
        ),
        findsOneWidget,
      );

      final gameL17 =
          tester.widget<GameWidget<BlockOrderGame>>(find.byType(GameWidget<BlockOrderGame>)).game!;
      final piecesBeforeFreeLvUp = gameL17.debugPieces.length;

      // Tap `"FREE"` -> closes FTUE, executes LevelUp merge immediately, and keeps inventory at `3`!
      await tester.tap(freeLvUpBtn);
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(find.byType(PowerUpFtueOverlay), findsNothing);
      expect(progressL17.levelUpCount, 3);
      expect(gameL17.debugPieces.length, piecesBeforeFreeLvUp - 1);

      // 4. Level 27 first entry -> 2-step `PowerUpFtueOverlay` -> FREE Time Freeze flies clock & freezes 20s keeping `timeFreezeCount == 3`
      SharedPreferences.setMockInitialValues({
        'bo_current_level': 27,
        'bo_highest_level': 27,
        'bo_coins': 1200,
        'bo_seen_mechanics': ['pu_level_up'],
      });
      final progressL27 = PlayerProgressService();
      await tester.runAsync(() => progressL27.init());
      expect(progressL27.timeFreezeCount, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            key: const ValueKey('gp_l27'),
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: audio,
            progress: progressL27,
          ),
        ),
      );
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(find.byType(PowerUpFtueOverlay), findsOneWidget);
      expect(find.text('Time Freeze'), findsWidgets);
      expect(find.text('Freezes the timer for 20 seconds'), findsOneWidget);

      await tester.tap(find.byType(UnityCtaButton));
      await tester.pump(const Duration(milliseconds: 100));
      final freeTfBtn =
          find.byKey(const ValueKey('ftue_free_time_freeze_btn'));
      expect(freeTfBtn, findsOneWidget);

      final gameL27 =
          tester.widget<GameWidget<BlockOrderGame>>(find.byType(GameWidget<BlockOrderGame>)).game!;
      expect(gameL27.isTimeFrozen, isFalse);

      await tester.tap(freeTfBtn);
      // Advance past 820ms clock flight (`t >= 0.66` impact) -> 20s freeze engages even before first drag!
      for (int i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(progressL27.timeFreezeCount, 3);
      expect(gameL27.isTimeFrozen, isTrue);
      expect(gameL27.timeFreezeNotifier.value, greaterThan(18.0));

      // 5. Empty inventory (`count == 0`) opens `PowerUpBuyPopup` (`600` / `450`, `x3`, `x1`, `Watch`) BEFORE checking timer started!
      SharedPreferences.setMockInitialValues({
        'bo_current_level': 27,
        'bo_highest_level': 27,
        'bo_coins': 1200,
        'bo_pu_level_up': 0,
        'bo_pu_time_freeze': 0,
        'bo_seen_mechanics': [
          'ice',
          'dud',
          'arrows',
          'pinned',
          'pu_level_up',
          'pu_time_freeze',
        ],
      });
      final progressEmpty = PlayerProgressService();
      await tester.runAsync(() => progressEmpty.init());

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            key: const ValueKey('gp_l27_buy'),
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: audio,
            progress: progressEmpty,
          ),
        ),
      );
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      // Tap LevelUp `+` -> opens `PowerUpBuyPopup` (`LEVEL UP`, `600`, `x3`, `x1`, `Watch`)
      await tester.tap(find.byKey(const ValueKey('hud_level_up_btn')));
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.byType(PowerUpBuyPopup), findsOneWidget);
      expect(find.text('LEVEL UP'), findsWidgets);
      expect(find.text('600'), findsWidgets);
      expect(find.text('x3'), findsWidgets);
      expect(find.text('x1'), findsWidgets);
      expect(find.text('Watch'), findsWidgets);

      // Buy `x3` pack for 600 coins -> coins `1200 -> 600`, `levelUpCount: 0 -> 3`
      await tester.tap(find.text('600').last);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(PowerUpBuyPopup), findsNothing);
      expect(progressEmpty.coins, 600);
      expect(progressEmpty.levelUpCount, 3);

      // Tap TimeFreeze `+` (even BEFORE timer has started!) -> opens `PowerUpBuyPopup` (`TIME FREEZE`, `450`)
      await tester.tap(find.byKey(const ValueKey('hud_time_freeze_btn')));
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.byType(PowerUpBuyPopup), findsOneWidget);
      expect(find.text('TIME FREEZE'), findsWidgets);
      expect(find.text('450'), findsWidgets);

      // Tap `Watch` ad -> adds `+1` (`timeFreezeCount: 0 -> 1`) without spending coins (`600`)
      await tester.tap(find.text('Watch').last);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(PowerUpBuyPopup), findsNothing);
      expect(progressEmpty.coins, 600);
      expect(progressEmpty.timeFreezeCount, 1);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  testWidgets(
    'Tutorial & MechanicFTUE 1:1 flow: persistent Levels 1-3 TutorialText, Level 1 TutorialHand ignores stationary tap & fades ONLY on actual move/merge, and MechanicUnlockDialog hides SubTitleContainer',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(540, 1200);
      await tester.binding.setSurfaceSize(const Size(540, 1200));

      late final LevelRepository repo;
      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        repo = await LevelRepository.loadFromAssets();
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        await UnitySpriteRegistry.preloadAll();
        for (final s in [
          'Hand_01.png',
          'PowerUp_Icon_Arrow.png',
          'Sparkle_01.png',
          'ParticleFlare.png',
          'Explosion_Halo.png',
          'Glow_Ring.png',
          'Glow_02.png',
        ]) {
          await Flame.images.load(s);
        }
      });

      SharedPreferences.setMockInitialValues({'bo_current_level': 1});
      final progress = PlayerProgressService();
      await tester.runAsync(() => progress.init());
      final audio = _SilentAudioHapticsService();

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: audio,
            progress: progress,
          ),
        ),
      );
      for (int i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      final hintText = repo.tutorialHints[1]!;
      expect(find.text(hintText), findsWidgets);

      final gwFinder = find.byType(GameWidget<BlockOrderGame>);
      final gwTopLeft = tester.getTopLeft(gwFinder);
      final game = tester.widget<GameWidget<BlockOrderGame>>(gwFinder).game!;
      expect(game.debugHasTutorialHand, isTrue);

      // Verify top HUD `Level 1` and `CoinsWidget` are non-interactive (no debug level picker or +250 coin cheat)
      final initialCoins = progress.coins;
      await tester.tapAt(tester.getCenter(find.text('Level 1').first));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.isModalPaused, isFalse);

      await tester.tapAt(tester.getCenter(find.text('$initialCoins').first));
      await tester.pump(const Duration(milliseconds: 50));
      expect(progress.coins, initialCoins);

      final movable = game.debugPieces.firstWhere(
        (p) => p.model.col == 0 && p.model.row == 0 && p.model.canBeDragged,
      );
      final pieceScreenPt = gwTopLeft + game.debugCellCenterCanvas(0, 0);

      // 1. Quick stationary tap (touch & release without moving grid cell) MUST NOT dismiss TutorialHand!
      final tapGesture = await tester.startGesture(pieceScreenPt);
      await tester.pump(const Duration(milliseconds: 24));
      await tapGesture.up();
      for (int i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(game.debugHasTutorialHand, isTrue);
      expect(find.text(hintText), findsWidgets);

      // 2. Slide Level 1 2x2 piece `A` (`col=0, row=0`) down into open cells `(0..1, 2..3)`
      final destScreenPt = gwTopLeft + game.debugCellCenterCanvas(0, 2);
      final dragGesture = await tester.startGesture(pieceScreenPt);
      await tester.pump(const Duration(milliseconds: 16));
      await dragGesture.moveTo(destScreenPt);
      await tester.pump(const Duration(milliseconds: 32));
      await dragGesture.up();
      expect((movable.model.col, movable.model.row), (0, 2));

      // Advance past `0.30s` `FadeOutAsync`: TutorialHand is dismissed, AND TutorialText stays visible!
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(game.debugHasTutorialHand, isFalse);
      expect(find.text(hintText), findsWidgets);

      // 3. Verify `MechanicUnlockDialog` (`MechanicFTUE.prefab`) hides `"New mechanic unlocked!"` across all 4 obstacles
      for (final info in const [
        MechanicUnlockInfo.ice,
        MechanicUnlockInfo.dud,
        MechanicUnlockInfo.arrows,
        MechanicUnlockInfo.pinned,
      ]) {
        bool dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MechanicUnlockDialog(
                key: ValueKey('mech_${info.id}'),
                info: info,
                onDismiss: () => dismissed = true,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(info.title), findsWidgets);
        expect(find.text(info.note), findsOneWidget);
        expect(find.text('New mechanic unlocked!'), findsNothing);
        await tester.tap(find.byType(UnityCtaButton));
        await tester.pump(const Duration(milliseconds: 50));
        expect(dismissed, isTrue);
      }

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    'Obstacles 1:1 mechanics: enclosed inner wall island pillar blocking, Dud sliding & non-blocking win condition, and Arrow axis constraint + H/V merge -> free',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      bool levelWon = false;
      final level = LevelDefinition(
        number: 21,
        title: 'Level 21',
        cols: 5,
        rows: 5,
        timeSeconds: 120,
        timerDisabled: true,
        // Enclosed inner wall island at `(2, 2)` (surrounded by playable cells on all 8 neighbors)
        walls: const {(2, 2)},
        initialPieces: [
          // Horizontal-only `4` at `(1, 2)` left of inner wall island `(2, 2)`
          PieceModel(
            id: 1,
            key: 'h_arrow',
            col: 1,
            row: 2,
            localCells: const [(0, 0)],
            number: 4,
            movement: MovementConstraint.horizontalOnly,
          ),
          // Vertical-only `4` at `(0, 0)`
          PieceModel(
            id: 2,
            key: 'v_arrow',
            col: 0,
            row: 0,
            localCells: const [(0, 0)],
            number: 4,
            movement: MovementConstraint.verticalOnly,
          ),
          // Dud (`number: null`) at `(4, 4)`
          PieceModel(
            id: 3,
            key: 'dud_block',
            col: 4,
            row: 4,
            localCells: const [(0, 0)],
            number: null,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () => levelWon = true,
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);

      final hPiece = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final vPiece = game.debugPieces.firstWhere((p) => p.model.id == 2);
      final dudPiece = game.debugPieces.firstWhere((p) => p.model.id == 3);

      // 1. Horizontal-only piece at `(1, 2)`:
      //    - Cannot drag vertically to `(1, 1)` (locked vertical axis)
      //    - Cannot drag right through enclosed inner wall island `(2, 2)` to `(3, 2)`
      var g = await tester.startGesture(game.debugCellCenterCanvas(1, 2));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(1, 1));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      await tester.pump(const Duration(milliseconds: 32));
      expect((hPiece.model.col, hPiece.model.row), (1, 2));

      g = await tester.startGesture(game.debugCellCenterCanvas(1, 2));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(3, 2));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      await tester.pump(const Duration(milliseconds: 32));
      expect((hPiece.model.col, hPiece.model.row), (1, 2));

      //    - CAN slide left along horizontal axis to `(0, 2)`!
      g = await tester.startGesture(game.debugCellCenterCanvas(1, 2));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(0, 2));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      await tester.pump(const Duration(milliseconds: 32));
      expect((hPiece.model.col, hPiece.model.row), (0, 2));

      // 2. Dud block (`number: null`) slides freely `(4, 4) -> (4, 2)` and CANNOT merge with numbered block!
      g = await tester.startGesture(game.debugCellCenterCanvas(4, 4));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(4, 2));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      await tester.pump(const Duration(milliseconds: 32));
      expect((dudPiece.model.col, dudPiece.model.row), (4, 2));
      expect(levelWon, isFalse);

      // 3. Vertical-only `4` at `(0, 0)` cannot drag horizontally to `(1, 0)`,
      //    but CAN drag down to `(0, 2)` to merge with Horizontal-only `4`!
      //    Resulting `8` inherits `horizontalOnly + verticalOnly == MovementConstraint.free`
      //    AND triggers win immediately even though the Dud block remains on the board!
      g = await tester.startGesture(game.debugCellCenterCanvas(0, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));
      expect((vPiece.model.col, vPiece.model.row), (0, 0));

      await g.moveTo(game.debugCellCenterCanvas(0, 2));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      for (int i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      final numberedRemaining =
          game.debugPieces.where((p) => !p.model.isDud).toList();
      expect(numberedRemaining.length, 1);
      expect(numberedRemaining.single.model.number, 8);
      expect(numberedRemaining.single.model.movement, MovementConstraint.free);
      expect(game.debugPieces.any((p) => p.model.isDud), isTrue);
      expect(levelWon, isTrue);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  testWidgets(
    '120Hz performance optimizations: static piece GPU sprite cache & dynamic drag bypass, flat occupancy grid sync across moves/merges, and smart modal engine sleep + peek wakeup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      final level = LevelDefinition(
        number: 30,
        title: 'Level 30',
        cols: 4,
        rows: 4,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'p2_a',
            col: 0,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 2,
            key: 'p2_b',
            col: 2,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 3,
            key: 'p4_c',
            col: 0,
            row: 2,
            localCells: const [(0, 0)],
            number: 4,
          ),
          PieceModel(
            id: 4,
            key: 'p8_d',
            col: 1,
            row: 2,
            localCells: const [(0, 0)],
            number: 8,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);

      // Advance past camera intro & incremental prewarms so all pieces rest & bake static GPU sprites
      for (int i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      final pA = game.debugPieces.firstWhere((p) => p.model.id == 1);
      final pB = game.debugPieces.firstWhere((p) => p.model.id == 2);
      final pC = game.debugPieces.firstWhere((p) => p.model.id == 3);
      final pD = game.debugPieces.firstWhere((p) => p.model.id == 4);

      for (final p in [pA, pB, pC, pD]) {
        expect(p.isVisuallyAtRest, isTrue);
        expect(p.debugHasStaticBakedSprite, isTrue);
        expect(p.debugUsedStaticSpriteLastRender, isTrue);
      }

      // 1. Grab pA at (0, 0) -> immediately bypasses static sprite for live 2.5D jelly/lift rendering,
      //    while untouched resting piece pD continues rendering from its single-drawImage GPU cache!
      var g = await tester.startGesture(game.debugCellCenterCanvas(0, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(pA.isVisuallyAtRest, isFalse);
      expect(pA.debugUsedStaticSpriteLastRender, isFalse);
      expect(pD.debugUsedStaticSpriteLastRender, isTrue);

      // Slide pA from (0, 0) -> (1, 0) and release
      await g.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      expect((pA.model.col, pA.model.row), (1, 0));

      // Let pA finish its full authentic underdamped jelly wobble (zeta=0.20, ~1.5s) -> re-engages cached static GPU sprite
      for (int i = 0; i < 52; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(pA.isVisuallyAtRest, isTrue);
      expect(pA.debugUsedStaticSpriteLastRender, isTrue);

      // 2. Verify flat `_occupancyGrid` vacated `(0, 0)` (pC `4` slides `(0, 2) -> (0, 0)`)
      //    AND blocks `(1, 0)` against non-matching pD `8` (`(1, 2) -> stops at (1, 1)`)!
      g = await tester.startGesture(game.debugCellCenterCanvas(0, 2));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(0, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      expect((pC.model.col, pC.model.row), (0, 0));

      g = await tester.startGesture(game.debugCellCenterCanvas(1, 2));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      expect((pD.model.col, pD.model.row), (1, 1));

      // Merge pA (`2` at `(1, 0)`) into pB (`2` at `(2, 0)`) -> `(1, 0)` vacates immediately in `_occupancyGrid`
      // so pD (`8` at `(1, 1)`) can slide into `(1, 0)` right away!
      g = await tester.startGesture(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(2, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      await tester.pump(const Duration(milliseconds: 16));

      g = await tester.startGesture(game.debugCellCenterCanvas(1, 1));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      expect((pD.model.col, pD.model.row), (1, 0));

      // 3. Smart Modal Engine Sleep: while merge VFX & piece settles are still active,
      //    `setModalPauseState(modalPaused: true, canSuspendBoard: true)` waits until animations finish,
      //    then suspends `game.paused == true`!
      game.setModalPauseState(modalPaused: true, canSuspendBoard: true);
      expect(game.paused, isFalse);

      for (int i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(game.paused, isTrue);

      // Peeking the board (`"Tap to see the board"`, `canSuspendBoard: false`) wakes engine immediately!
      game.setModalPauseState(modalPaused: true, canSuspendBoard: false);
      expect(game.paused, isFalse);

      // Closing modal (`modalPaused: false`) keeps engine active
      game.setModalPauseState(modalPaused: false, canSuspendBoard: false);
      expect(game.paused, isFalse);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  testWidgets(
    '4-Step Magic Sand Jar Win Sequence: jar above board matches targetWinNumber color, final tile glows & bursts light, sand streams up to fill & reveal hidden object, jar opens with fullscreen light wave -> Next Level popup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      bool levelWon = false;
      // Level with two `8`s and one `16` -> sum is `8 + 8 + 16 = 32` (`targetWinNumber == 32`).
      final level = LevelDefinition(
        number: 15,
        title: 'Level 15',
        cols: 3,
        rows: 3,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'p8_a',
            col: 0,
            row: 0,
            localCells: const [(0, 0)],
            number: 8,
          ),
          PieceModel(
            id: 2,
            key: 'p8_b',
            col: 1,
            row: 0,
            localCells: const [(0, 0)],
            number: 8,
          ),
          PieceModel(
            id: 3,
            key: 'p16_c',
            col: 2,
            row: 0,
            localCells: const [(0, 0)],
            number: 16,
          ),
        ],
      );

      expect(level.targetWinNumber, 32);

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () => levelWon = true,
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);

      // 0. Before any merge: Jar is ALWAYS visible (`appearProgress == 1.0`) above the board and colored to `32` (`targetWinNumber`)!
      expect(game.debugSandJar, isNotNull);
      expect(game.debugSandJar!.appearProgress, closeTo(1.0, 1e-3));
      expect(game.debugJarColorNumber, 32);
      expect(game.debugJarFillProgress, 0.0);
      expect(game.debugIsJarOpen, isFalse);

      // Intermediate merge (`8 + 8 -> 16`): does NOT trigger the win sequence yet!
      var g = await tester.startGesture(game.debugCellCenterCanvas(0, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(game.debugPieces.length, 2);
      expect(game.debugJarFillProgress, 0.0);
      expect(audio.waterStreamFlowCount, 0);
      expect(levelWon, isFalse);

      // Final merge (`16 + 16 -> 32`): triggers the 4-Step Magic Sand Jar Win Sequence!
      g = await tester.startGesture(game.debugCellCenterCanvas(1, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(game.debugCellCenterCanvas(2, 0));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();

      // Step 1 (`t = 32ms`): Final tile (`32`) glows (`levelUpTargetGlow > 0.8`) and scales up gently!
      await tester.pump(const Duration(milliseconds: 32));
      final finalTile = game.debugPieces.single;
      expect(finalTile.model.number, 32);
      expect(finalTile.levelUpTargetGlow, greaterThan(0.85));
      expect(game.debugJarColorNumber, 32);

      // Step 2 & Step 3a (`t ~ 1.15s`): Final tile crumbles into sand (`debugWinCrumbleProgress == 1.0`, `visualOpacity == 0.0`)
      // as sand streams up from board into jar; jar shakes, glows & fills (`0 < fillProgress < 1`)!
      for (int i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(finalTile.debugWinCrumbleProgress, closeTo(1.0, 1e-3));
      expect(finalTile.visualOpacity, closeTo(0.0, 1e-3));
      expect(game.debugJarFillProgress, greaterThan(0.25));
      expect(game.debugJarGlowIntensity, greaterThan(0.40));
      expect(game.debugJarShakeIntensity, greaterThan(0.10));
      expect(audio.waterStreamFlowCount, 1);
      expect(levelWon, isFalse);

      // Step 3b & Step 4 (`t ~ 2.43s`): Jar reaches 100% fill (`reveal texture/hidden object`), pops open with light wave,
      // and fullscreen flash intensity rises (`winScreenFlashNotifier > 0`), while `levelWon` still waits for peak bloom (`2.62s`)!
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(game.debugJarFillProgress, closeTo(1.0, 1e-3));
      expect(game.debugIsJarOpen, isTrue);
      expect(game.winScreenFlashNotifier.value, greaterThan(0.20));
      expect(levelWon, isFalse);

      // Step 4 completion (`t >= 2.62s`): Fullscreen light wave triggers `onLevelWon()` popup!
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(levelWon, isTrue);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  testWidgets(
    'Merge Combo & Praise Callout System: consecutive merges within 3.5s escalate x1 -> x2 (NICE!) -> x3 (GREAT!) -> x4 (PERFECT!) and reset after countdown expires',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));
      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
      });
      final audio = _SilentAudioHapticsService();

      expect(ComboPraiseTier.forCombo(1).comboLabel, 'X1');
      expect(ComboPraiseTier.forCombo(2).comboLabel, 'X2');
      expect(ComboPraiseTier.forCombo(3).comboLabel, 'X3');
      expect(ComboPraiseTier.forCombo(1).praiseText, isNull);
      expect(ComboPraiseTier.forCombo(2).praiseText, 'NICE!');
      expect(ComboPraiseTier.forCombo(4).praiseText, 'AWESOME!');
      expect(ComboPraiseTier.forCombo(5).praiseText, 'AMAZING!');
      expect(ComboPraiseTier.forCombo(6).praiseText, 'BRILLIANT!');
      expect(ComboPraiseTier.forCombo(7).praiseText, 'EXCELLENT!');
      expect(ComboPraiseTier.forCombo(8).praiseText, 'FLAWLESS!');
      expect(ComboPraiseTier.forCombo(9).praiseText, 'LEGENDARY!');
      expect(ComboPraiseTier.forCombo(10).praiseText, 'INCREDIBLE!');

      final level = LevelDefinition(
        number: 40,
        title: 'Test Combo Chain',
        cols: 5,
        rows: 4,
        timeSeconds: 120,
        timerDisabled: true,
        walls: const {},
        initialPieces: [
          PieceModel(
            id: 1,
            key: 'a',
            col: 0,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 2,
            key: 'b',
            col: 1,
            row: 0,
            localCells: const [(0, 0)],
            number: 2,
          ),
          PieceModel(
            id: 3,
            key: 'c',
            col: 2,
            row: 0,
            localCells: const [(0, 0)],
            number: 4,
          ),
          PieceModel(
            id: 4,
            key: 'd',
            col: 3,
            row: 0,
            localCells: const [(0, 0)],
            number: 8,
          ),
          PieceModel(
            id: 5,
            key: 'e',
            col: 4,
            row: 0,
            localCells: const [(0, 0)],
            number: 16,
          ),
          PieceModel(
            id: 6,
            key: 'f',
            col: 0,
            row: 2,
            localCells: const [(0, 0)],
            number: 32,
          ),
          PieceModel(
            id: 7,
            key: 'g',
            col: 1,
            row: 2,
            localCells: const [(0, 0)],
            number: 64,
          ),
        ],
      );

      final game = BlockOrderGame(
        initialLevel: level,
        palette: palette,
        visualSettings: settings,
        audio: audio,
        onLevelWon: () {},
        onTimeExpired: () {},
      );
      await _mountAndLoadGame(tester, game);

      expect(game.debugComboCount, 0);
      expect(game.debugComboRemainingSeconds, 0.0);

      Future<void> dragMergeCell((int, int) from, (int, int) to) async {
        final g = await tester.startGesture(
          game.debugCellCenterCanvas(from.$1, from.$2),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await g.moveTo(game.debugCellCenterCanvas(to.$1, to.$2));
        await tester.pump(const Duration(milliseconds: 32));
        await g.up();
        await tester.pump(const Duration(milliseconds: 32));
      }

      // 1. First merge (`2 + 2 -> 4` at `(1, 0)`): activates COMBO x1 and 3.5s countdown
      await dragMergeCell((0, 0), (1, 0));
      expect(game.debugComboCount, 1);
      expect(game.debugComboRemainingSeconds, greaterThan(3.3));
      expect(game.comboCountdownFractionNotifier.value, greaterThan(0.9));

      // Wait ~0.6s (still well inside 3.5s window) -> merge `4 + 4 -> 8` at `(2, 0)` -> COMBO x2 (`NICE!`)
      for (int i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(game.debugComboRemainingSeconds, greaterThan(2.5));
      await dragMergeCell((1, 0), (2, 0));
      expect(game.debugComboCount, 2);
      expect(game.debugComboRemainingSeconds, greaterThan(3.3));
      expect(audio.comboPraises, contains(2));

      // Merge `8 + 8 -> 16` at `(3, 0)` -> COMBO x3 (`GREAT!`)
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      await dragMergeCell((2, 0), (3, 0));
      expect(game.debugComboCount, 3);
      expect(audio.comboPraises, contains(3));

      // Merge `16 + 16 -> 32` at `(4, 0)` -> COMBO x4 (`PERFECT!`)
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      await dragMergeCell((3, 0), (4, 0));
      expect(game.debugComboCount, 4);
      expect(audio.comboPraises, contains(4));

      // Now wait > 3.5s (`90 * 45ms = 4.05s`) without merging -> combo countdown expires & resets to 0!
      for (int i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 45));
      }
      expect(game.debugComboCount, 0);
      expect(game.debugComboRemainingSeconds, 0.0);
      expect(game.comboCountdownFractionNotifier.value, 0.0);

      await tester.binding.setSurfaceSize(null);
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );
}
