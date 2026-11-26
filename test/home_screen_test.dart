import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/ads_manager.dart';
import 'package:block_order_2048/services/app_version_service.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/home_screen.dart';
import 'package:block_order_2048/ui/more_lives_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool prevEnableAds;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AdsManager.mockRewardResult = null;
    AdsManager.debugSetBannerVisible(false);
    prevEnableAds = AdsManager.enableAds;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('fgsdk/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('fgsdk'),
      (_) async => null,
    );
  });

  tearDown(() {
    AdsManager.mockRewardResult = null;
    AdsManager.debugSetBannerVisible(false);
    AdsManager.enableAds = prevEnableAds;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('fgsdk/events'),
      null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('fgsdk'), null);
  });

  group('HomeScreen UI & flows', () {
    testWidgets(
      'renders demo layout (Level, Full/timer, Coins, No Ads, Starter Pack, Shop/Home/Lock) with zero overflow',
      (tester) async {
        for (final surface in const [
          Size(412, 892),
          Size(446, 830),
          Size(540, 960),
        ]) {
          tester.view.physicalSize = surface;
          tester.view.devicePixelRatio = 1.0;
          await tester.binding.setSurfaceSize(surface);
          try {
            late final LevelRepository repo;
            final audio = AudioHapticsService();
            final progress = PlayerProgressService();

            await tester.runAsync(() async {
              repo = await LevelRepository.loadFromAssets();
              await progress.init();
              progress.setCurrentLevel(6);
            });
            progress.cheatSetCoins(150);
            progress.cheatSetLives(5);

            var playCount = 0;
            await tester.pumpWidget(
              MaterialApp(
                home: HomeScreen(
                  repository: repo,
                  audio: audio,
                  progress: progress,
                  onPlayLevel: () => playCount++,
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 250));

            expect(tester.takeException(), isNull);
            expect(find.text('Level 6'), findsOneWidget);
            expect(find.text('Full'), findsOneWidget);
            expect(find.text('150'), findsOneWidget);
            // Temporarily commented out while IAP/Shop/Journey are deferred to next version:
            expect(find.byKey(const ValueKey('home_no_ads_btn')), findsNothing);
            expect(
              find.byKey(const ValueKey('home_starter_pack_btn')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('home_bottom_nav_bar')),
              findsNothing,
            );
            expect(
              tester
                  .getCenter(find.byKey(const ValueKey('home_hearts_pill')))
                  .dy,
              lessThan(surface.height * 0.14),
            );
            expect(
              tester
                  .getCenter(find.byKey(const ValueKey('home_settings_btn')))
                  .dy,
              lessThan(surface.height * 0.14),
            );

            // Play CTA (`Level X`) sits lowered comfortably over the blue counter front (`y=1600`, fitXY).
            final expectedCounterCenterY = surface.height * (1600.0 / 2160.0);
            expect(
              tester
                  .getCenter(find.byKey(const ValueKey('home_play_level_btn')))
                  .dy,
              closeTo(expectedCounterCenterY, 16.0),
            );

            // Fixed bottom banner reservation (~167/2160) stays reserved at the bottom.
            final bannerFinder = find.byKey(const ValueKey('home_bottom_banner'));
            expect(bannerFinder, findsOneWidget);

            // Losing a life switches Heart badge from Full to countdown MM:SS.
            progress.cheatSetLives(3);
            await tester.pump(const Duration(milliseconds: 120));
            expect(find.text('Full'), findsNothing);
            expect(find.text('3'), findsOneWidget);
            expect(
              find.textContaining(':'),
              findsWidgets,
            );

            // Settings button opens compact Home settings overlay (Restore button temporarily commented out).
            await tester.tap(find.byKey(const ValueKey('home_settings_btn')));
            await tester.pump(const Duration(milliseconds: 200));
            expect(
              find.byKey(const ValueKey('home_settings_modal')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('home_settings_restore_btn')),
              findsNothing,
            );
            expect(find.text(AppVersionService.displayLabel), findsOneWidget);
            expect(find.text('Quit'), findsNothing);
            expect(find.text('Restart'), findsNothing);

            // Tapping Play enters Gameplay when lives > 0.
            await tester.tap(
              find.byKey(const ValueKey('home_play_level_btn')),
              warnIfMissed: false,
            );
            await tester.pump(const Duration(milliseconds: 120));
            // Modal intercepts taps until dismissed; dismiss first then tap Play.
            expect(playCount, 0);
            await tester.tapAt(const Offset(10, 10));
            await tester.pump(const Duration(milliseconds: 150));
            expect(
              find.byKey(const ValueKey('home_settings_modal')),
              findsNothing,
            );

            await tester.tap(find.byKey(const ValueKey('home_play_level_btn')));
            await tester.pump(const Duration(milliseconds: 100));
            expect(playCount, 1);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        }
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      '0 lives blocks Play, opens MoreLivesDialog, and Watch Ad recovers 1 life + auto-plays',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));
        try {
          late final LevelRepository repo;
          final audio = AudioHapticsService();
          final progress = PlayerProgressService();

          await tester.runAsync(() async {
            repo = await LevelRepository.loadFromAssets();
            await progress.init();
            progress.setCurrentLevel(3);
          });
          progress.cheatSetCoins(200);
          progress.cheatSetLives(0);

          var playCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(
                repository: repo,
                audio: audio,
                progress: progress,
                onPlayLevel: () => playCount++,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));

          await tester.tap(find.byKey(const ValueKey('home_play_level_btn')));
          await tester.pump(const Duration(milliseconds: 250));

          expect(playCount, 0);
          expect(find.byType(MoreLivesDialog), findsOneWidget);

          AdsManager.enableAds = true;
          AdsManager.mockRewardResult = true;
          await tester.tap(find.byKey(const ValueKey('more_lives_watch_ad_btn')));
          await tester.pump(const Duration(milliseconds: 350));

          expect(progress.lives, 1);
          expect(find.byType(MoreLivesDialog), findsNothing);
          expect(playCount, 1);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      '0 lives Refill (900 coins) restores 5 lives from Home MoreLivesDialog and auto-plays',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));
        try {
          late final LevelRepository repo;
          final audio = AudioHapticsService();
          final progress = PlayerProgressService();

          await tester.runAsync(() async {
            repo = await LevelRepository.loadFromAssets();
            await progress.init();
            progress.setCurrentLevel(4);
          });
          progress.cheatSetCoins(1000);
          progress.cheatSetLives(0);

          var playCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(
                repository: repo,
                audio: audio,
                progress: progress,
                onPlayLevel: () => playCount++,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));

          await tester.tap(find.byKey(const ValueKey('home_hearts_pill')));
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(MoreLivesDialog), findsOneWidget);

          // Opening from Hearts pill closes cleanly without auto-entering play unless Play was tapped.
          await tester.tap(
            find.byKey(const ValueKey('more_lives_refill_coins_btn')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(progress.lives, 5);
          expect(progress.coins, 100);
          expect(find.byType(MoreLivesDialog), findsNothing);
          expect(playCount, 0);

          // Now tap Play when coins/lives flow completes after Play-triggered modal.
          progress.cheatSetCoins(950);
          progress.cheatSetLives(0);
          await tester.pump(const Duration(milliseconds: 100));

          await tester.tap(find.byKey(const ValueKey('home_play_level_btn')));
          await tester.pump(const Duration(milliseconds: 250));
          expect(find.byType(MoreLivesDialog), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('more_lives_refill_coins_btn')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(progress.lives, 5);
          expect(progress.coins, 50);
          expect(playCount, 1);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'GameplayScreen Settings shows Quit (left) & Restart (right), deducts 1 life on Quit, shows Level Failed (-1), and Close exits to Home',
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
            progress.setCurrentLevel(2);
          });
          progress.cheatSetLives(4);

          var exitCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: GameplayScreen(
                repository: repo,
                palette: palette,
                visualSettings: settings,
                audio: audio,
                progress: progress,
                onExitToHome: () => exitCount++,
              ),
            ),
          );
          final game = tester
              .widget<GameWidget<BlockOrderGame>>(
                find.byType(GameWidget<BlockOrderGame>),
              )
              .game!;
          for (int i = 0; i < 40 && !game.canLevelUpNotifier.value; i++) {
            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 350));
          expect(game.canLevelUpNotifier.value, isTrue);

          // Open Settings -> sees Left Red Quit + Right Green Restart + v.1.0.0
          await tester.tap(find.byKey(const ValueKey('hud_settings_btn')));
          await tester.pump(const Duration(milliseconds: 220));

          final quitFinder = find.byKey(const ValueKey('settings_quit_btn'));
          final restartFinder = find.byKey(
            const ValueKey('settings_restart_btn'),
          );
          expect(quitFinder, findsOneWidget);
          expect(restartFinder, findsOneWidget);
          expect(find.text(AppVersionService.displayLabel), findsOneWidget);
          expect(
            tester.getCenter(quitFinder).dx,
            lessThan(tester.getCenter(restartFinder).dx),
          );

          // Tapping Quit mid-game deducts 1 life (4 -> 3) and opens Level Failed (-1) popup
          await tester.tap(quitFinder);
          await tester.pump(const Duration(milliseconds: 250));

          expect(progress.lives, 3);
          expect(
            find.byKey(const ValueKey('level_failed_popup_card')),
            findsOneWidget,
          );
          expect(find.text('Level 2'), findsWidgets);
          expect(find.text('-1'), findsWidgets);
          expect(find.text('Level Failed!'), findsOneWidget);
          expect(find.text('Try Again'), findsWidgets);
          expect(exitCount, 0);

          // Tapping Close (X) on Level Failed exits back to Home cleanly
          await tester.tap(find.byKey(const ValueKey('lose_failed_close_btn')));
          await tester.pump(const Duration(milliseconds: 200));

          expect(exitCount, 1);
          expect(progress.lives, 3);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'HomeScreen displays Infinity symbol & timer at 0 lives and allows Play without MoreLivesDialog',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));
        try {
          late final LevelRepository repo;
          final audio = AudioHapticsService();
          final progress = PlayerProgressService();

          await tester.runAsync(() async {
            repo = await LevelRepository.loadFromAssets();
            await progress.init();
            progress.setCurrentLevel(5);
          });
          progress.cheatSetLives(0);
          progress.addInfinityLives(const Duration(minutes: 15));

          var playCount = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(
                repository: repo,
                audio: audio,
                progress: progress,
                onPlayLevel: () => playCount++,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));

          expect(find.text('∞'), findsOneWidget);
          expect(find.text('Full'), findsNothing);
          expect(find.textContaining(':'), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('home_play_level_btn')));
          await tester.pump(const Duration(milliseconds: 120));
          expect(playCount, 1);
          expect(find.byType(MoreLivesDialog), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'Unity StartInteractiveLevel: first action spends 1 heart immediately, Quit does not double-spend, and Win refunds attempt heart',
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
            progress.setCurrentLevel(2);
          });
          progress.cheatSetLives(4);

          await tester.pumpWidget(
            MaterialApp(
              home: GameplayScreen(
                repository: repo,
                palette: palette,
                visualSettings: settings,
                audio: audio,
                progress: progress,
                onExitToHome: () {},
              ),
            ),
          );
          final game = tester
              .widget<GameWidget<BlockOrderGame>>(
                find.byType(GameWidget<BlockOrderGame>),
              )
              .game!;
          for (int i = 0; i < 40 && !game.canLevelUpNotifier.value; i++) {
            await tester.runAsync(
              () => Future.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 350));

          // Before interaction: heart is untouched (still 4)
          expect(game.hasPlayerInteracted, isFalse);
          expect(progress.lives, 4);

          // First interaction immediately spends 1 heart (4 -> 3)
          expect(game.triggerLevelUpPowerUp(), isTrue);
          expect(game.hasPlayerInteracted, isTrue);
          await tester.pump(const Duration(milliseconds: 250));
          expect(progress.lives, 3);

          // Tapping Quit after interacting MUST NOT double-deduct (stays 3)
          await tester.tap(find.byKey(const ValueKey('hud_settings_btn')));
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const ValueKey('settings_quit_btn')));
          await tester.pump(const Duration(milliseconds: 200));
          expect(progress.lives, 3);

          // Tap Try Again -> resets attempt; first move spends (3 -> 2), Win refunds (2 -> 3)
          await tester.tap(find.text('Try Again').last);
          await tester.pump(const Duration(milliseconds: 350));
          expect(progress.lives, 3);

          expect(game.triggerLevelUpPowerUp(), isTrue);
          await tester.pump(const Duration(milliseconds: 200));
          expect(progress.lives, 2);

          game.onLevelWon();
          await tester.pump(const Duration(milliseconds: 100));
          expect(progress.lives, 3);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  });
}
