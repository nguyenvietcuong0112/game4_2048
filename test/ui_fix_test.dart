import 'dart:ui' as ui;
import 'package:flame/extensions.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/game/piece_component.dart';
import 'package:block_order_2048/game/vfx_components.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/ads_manager.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/mechanic_unlock_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UI Fix verification', () {
    testWidgets(
      'MechanicUnlockDialog renders New Mechanic (Next Level) and New Feature (Claim / Claim X2) layouts cleanly',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));

        for (final info in const [
          MechanicUnlockInfo.ice,
          MechanicUnlockInfo.dud,
          MechanicUnlockInfo.arrows,
          MechanicUnlockInfo.pinned,
        ]) {
          bool nextPressed = false;
          bool closed = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MechanicUnlockDialog(
                  key: ValueKey('mech_${info.id}'),
                  info: info,
                  onDismiss: () {},
                  onNextLevel: () => nextPressed = true,
                  onClose: () => closed = true,
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byKey(const ValueKey('new_feature_popup_card')), findsOneWidget);
          expect(find.text('New Mechanic'), findsWidgets);
          expect(find.text(info.title), findsOneWidget);
          expect(find.text(info.note), findsOneWidget);
          expect(find.text('Next Level'), findsWidgets);

          await tester.tap(find.byKey(const ValueKey('mechanic_next_level_btn')));
          await tester.pump(const Duration(milliseconds: 60));
          expect(nextPressed, isTrue);

          await tester.tap(find.byKey(const ValueKey('mechanic_close_btn')));
          await tester.pump(const Duration(milliseconds: 60));
          expect(closed, isTrue);
        }

        for (final info in const [
          MechanicUnlockInfo.levelUpPowerUp,
          MechanicUnlockInfo.timeFreezePowerUp,
        ]) {
          bool claimed = false;
          bool closed = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MechanicUnlockDialog(
                  key: ValueKey('pu_${info.id}'),
                  info: info,
                  onDismiss: () {},
                  onClaim: () => claimed = true,
                  onClose: () => closed = true,
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byKey(const ValueKey('new_feature_popup_card')), findsOneWidget);
          expect(find.text('New Feature'), findsWidgets);
          expect(find.text('Claim'), findsWidgets);
          expect(find.text('Claim X2'), findsNothing);
          expect(find.byKey(const ValueKey('mechanic_claim_x2_btn')), findsNothing);

          await tester.tap(find.byKey(const ValueKey('mechanic_claim_btn')));
          await tester.pump(const Duration(milliseconds: 60));
          expect(claimed, isTrue);

          await tester.tap(find.byKey(const ValueKey('mechanic_close_btn')));
          await tester.pump(const Duration(milliseconds: 60));
          expect(closed, isTrue);
        }

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'Reworked Mechanic sprites (IceLock 159x189, Screws 220x219+, metallic Dud) load and render cleanly on PieceComponent',
      (tester) async {
        late final BlockOrderPalette palette;
        late final PieceVisualSettings settings;
        await tester.runAsync(() async {
          palette = await BlockOrderPalette.loadFromAssets();
          settings = await PieceVisualSettings.loadFromAssets();
          Flame.images.prefix = 'assets/images/';
          for (final s in const [
            'IceLock.png',
            'IceBlocks.png',
            'Icon_Mechanic_Blocker.png',
            'Screw_Greyscale_01.png',
            'Screw_Greyscale_02.png',
            'Screw_Greyscale_03.png',
          ]) {
            if (!Flame.images.containsKey(s)) {
              await Flame.images.load(s);
            }
          }
          await ScrewTextureCleaner.ensureCleanedScrewsLoaded();
        });

        expect(ScrewTextureCleaner.cleanedScrews.length, 3);
        final lockImg = Flame.images.fromCache('IceLock.png');
        expect(lockImg.width, 159);
        expect(lockImg.height, 189);
        final blockerImg = Flame.images.fromCache('Icon_Mechanic_Blocker.png');
        expect(blockerImg.width, 256);
        expect(blockerImg.height, 291);

        final dudStyle = palette.styleFor(number: null, isFrozen: false);
        expect(dudStyle.bottomLip, const Color(0xFF4F5173));

        final dudPiece = PieceComponent(
          model: PieceModel(
            id: 1,
            key: 'dud_1',
            col: 0,
            row: 0,
            localCells: const [(0, 0)],
            number: null,
          ),
          cellSize: 80,
          palette: palette,
          visualSettings: settings,
          boardOrigin: Vector2.zero(),
        );
        final dudRect2x1 = PieceComponent(
          model: PieceModel(
            id: 11,
            key: 'dud_2x1',
            col: 0,
            row: 1,
            localCells: const [(0, 0), (1, 0)],
            number: null,
          ),
          cellSize: 80,
          palette: palette,
          visualSettings: settings,
          boardOrigin: Vector2.zero(),
        );
        final dudLShape = PieceComponent(
          model: PieceModel(
            id: 12,
            key: 'dud_l',
            col: 0,
            row: 2,
            localCells: const [(0, 0), (0, 1), (1, 1)],
            number: null,
          ),
          cellSize: 80,
          palette: palette,
          visualSettings: settings,
          boardOrigin: Vector2.zero(),
        );
        final icePiece = PieceComponent(
          model: PieceModel(
            id: 2,
            key: 'ice_2',
            col: 1,
            row: 0,
            localCells: const [(0, 0)],
            number: 8,
            iceTarget: 64,
          ),
          cellSize: 80,
          palette: palette,
          visualSettings: settings,
          boardOrigin: Vector2.zero(),
        );
        final pinnedPiece = PieceComponent(
          model: PieceModel(
            id: 3,
            key: 'pin_3',
            col: 2,
            row: 0,
            localCells: const [(0, 0)],
            number: 16,
            movement: MovementConstraint.pinned,
          ),
          cellSize: 80,
          palette: palette,
          visualSettings: settings,
          boardOrigin: Vector2.zero(),
        );

        for (final piece in [
          dudPiece,
          dudRect2x1,
          dudLShape,
          icePiece,
          pinnedPiece,
        ]) {
          final rec = ui.PictureRecorder();
          final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, 260, 260));
          piece.render(canvas);
          expect(rec.endRecording(), isNotNull);
        }
      },
    );

    testWidgets(
      'GameplayScreen MechanicUnlockDialog Next Level dismisses and Top HUD hides during win water flow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));

        try {
          late final BlockOrderPalette palette;
          late final PieceVisualSettings settings;
          late final LevelRepository repo;
          final audio = AudioHapticsService();
          final progress = PlayerProgressService();

          await tester.runAsync(() async {
            palette = await BlockOrderPalette.loadFromAssets();
            settings = await PieceVisualSettings.loadFromAssets();
            repo = await LevelRepository.loadFromAssets();
            await progress.init();
          });

          // Find first campaign level with ice mechanic
          final iceLevel = repo.campaignLevels.firstWhere((l) => !l.isBonus && l.hasIce);
          progress.setCurrentLevel(iceLevel.number);

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
          await tester.pump(const Duration(milliseconds: 350));

          expect(find.byKey(const ValueKey('new_feature_popup_card')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('mechanic_next_level_btn')));
          await tester.pump(const Duration(milliseconds: 100));

          expect(progress.hasSeenMechanic(MechanicUnlockInfo.ice.id), isTrue);
          expect(find.byKey(const ValueKey('new_feature_popup_card')), findsNothing);

          // Test dud mechanic unlock + Top HUD hiding on win sequence
          final dudLevel = repo.campaignLevels.firstWhere((l) => !l.isBonus && l.hasDud);
          await progress.cheatResetAllProgress();
          progress.markMechanicSeen(MechanicUnlockInfo.ice.id);
          progress.markMechanicSeen(MechanicUnlockInfo.arrows.id);
          progress.markMechanicSeen(MechanicUnlockInfo.pinned.id);
          progress.setCurrentLevel(dudLevel.number);

          await tester.pumpWidget(
            MaterialApp(
              key: const ValueKey('second_gameplay_screen'),
              home: GameplayScreen(
                repository: repo,
                palette: palette,
                visualSettings: settings,
                audio: audio,
                progress: progress,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 350));

          expect(find.byKey(const ValueKey('new_feature_popup_card')), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('mechanic_next_level_btn')));
          await tester.pump(const Duration(milliseconds: 100));

          expect(progress.hasSeenMechanic(MechanicUnlockInfo.dud.id), isTrue);
          expect(find.byKey(const ValueKey('new_feature_popup_card')), findsNothing);

          final hudFinder = find.byKey(const ValueKey('gameplay_top_header_hud'));
          expect(hudFinder, findsOneWidget);
          expect(
            tester
                .widget<AnimatedOpacity>(
                  find.descendant(
                    of: hudFinder,
                    matching: find.byType(AnimatedOpacity),
                  ).first,
                )
                .opacity,
            1.0,
          );

          final game = tester
              .widget<GameWidget<BlockOrderGame>>(
                find.byType(GameWidget<BlockOrderGame>),
              )
              .game!;
          game.isWinSequenceActiveNotifier.value = true;
          await tester.pump(const Duration(milliseconds: 220));
          expect(
            tester
                .widget<AnimatedOpacity>(
                  find.descendant(
                    of: hudFinder,
                    matching: find.byType(AnimatedOpacity),
                  ).first,
                )
                .opacity,
            0.0,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          AdsManager.mockRewardResult = null;
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'GameplayScreen Tutorial Level 1 hides Level badge and Coins in top header HUD',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));
        try {
          late final BlockOrderPalette palette;
          late final PieceVisualSettings settings;
          late final LevelRepository repo;
          final audio = AudioHapticsService();
          final progress = PlayerProgressService();

          await tester.runAsync(() async {
            palette = await BlockOrderPalette.loadFromAssets();
            settings = await PieceVisualSettings.loadFromAssets();
            repo = await LevelRepository.loadFromAssets();
            await progress.init();
          });

          expect(progress.currentLevel, 1);

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
          await tester.pump(const Duration(milliseconds: 350));

          final hudFinder = find.byKey(const ValueKey('gameplay_top_header_hud'));
          expect(hudFinder, findsOneWidget);
          expect(
            find.descendant(of: hudFinder, matching: find.text('Level 1')),
            findsNothing,
          );
          expect(
            find.descendant(of: hudFinder, matching: find.text('875')),
            findsNothing,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  });
}
