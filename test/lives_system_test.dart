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
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/services/remote_config_service.dart';
import 'package:block_order_2048/ui/exit_gameplay_popup.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/lose_overlay.dart';
import 'package:block_order_2048/ui/more_lives_dialog.dart';
import 'package:block_order_2048/ui/powerup_buy_popup.dart';
import 'package:block_order_2048/ui/unity_ui_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool prevEnableAds;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AdsManager.mockRewardResult = null;
    RemoteConfigService.resetDefaultsForTest();
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
    RemoteConfigService.resetDefaultsForTest();
    AdsManager.enableAds = prevEnableAds;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('fgsdk/events'),
      null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('fgsdk'), null);
  });

  group('PlayerProgressService Heart / Lives system', () {
    test('max 5 hearts, loses to 0 cleanly, persists 0 across restart', () async {
      final t0 = DateTime.now();
      final progress = PlayerProgressService();
      await progress.init();

      expect(progress.lives, 5);
      for (int i = 0; i < 5; i++) {
        progress.loseLife(now: t0);
      }
      expect(progress.lives, 0);
      expect(progress.lastLifeRegenMs, t0.millisecondsSinceEpoch);

      // Simulate cold restart 10 seconds later: must stay at 0 (no silent auto-refill)
      final restarted = PlayerProgressService();
      await restarted.init();
      restarted.syncLivesRegen(now: t0.add(const Duration(seconds: 10)));
      expect(restarted.lives, 0);
    });

    test('real-time 15-min regen recovers multiple hearts offline & preserves remainder', () async {
      final t0 = DateTime(2026, 11, 17, 10, 0, 0);
      final progress = PlayerProgressService();
      await progress.init();

      // Drop from 5 -> 3 at t0
      progress.loseLife(now: t0);
      progress.loseLife(now: t0);
      expect(progress.lives, 3);
      expect(progress.formattedNextLifeCountdown(now: t0), '15:00');

      // Advance 20 minutes -> +1 heart (3 -> 4), 5 minutes elapsed toward 5th heart -> 10:00 remaining
      final t20m = t0.add(const Duration(minutes: 20));
      final gained1 = progress.syncLivesRegen(now: t20m);
      expect(gained1, 1);
      expect(progress.lives, 4);
      expect(progress.formattedNextLifeCountdown(now: t20m), '10:00');

      // Advance another 40 minutes -> recovers only up to max 5 and clears regen anchor
      final t60m = t20m.add(const Duration(minutes: 40));
      final gained2 = progress.syncLivesRegen(now: t60m);
      expect(gained2, 1);
      expect(progress.lives, 5);
      expect(progress.lastLifeRegenMs, isNull);
      expect(progress.formattedNextLifeCountdown(now: t60m), 'Full');
    });

    test('addOneLife & refillLivesWithCoins (900 coins -> 5 hearts)', () async {
      final t0 = DateTime(2026, 11, 17, 10, 0, 0);
      final progress = PlayerProgressService();
      await progress.init();

      progress.cheatSetCoins(500);
      progress.cheatSetLives(0, now: t0);
      expect(progress.lives, 0);

      // Cannot refill when coins < 900
      expect(progress.refillLivesWithCoins(), isFalse);
      expect(progress.lives, 0);

      // Watch ad -> +1 life
      progress.addOneLife(now: t0);
      expect(progress.lives, 1);

      // Give enough coins -> refill to 5 & stop timer anchor
      progress.cheatSetCoins(1000);
      expect(progress.refillLivesWithCoins(), isTrue);
      expect(progress.coins, 100);
      expect(progress.lives, 5);
      expect(progress.lastLifeRegenMs, isNull);
    });

    test(
      'Infinity Hearts (addInfinityLives): enables canPlay at 0, skips spend, formats mm:ss/hh:mm:ss/dd hh, and resumes regen cleanly on expiry',
      () async {
        final t0 = DateTime(2026, 11, 18, 8, 0, 0);
        final progress = PlayerProgressService();
        await progress.init();

        progress.cheatSetLives(2, now: t0);
        expect(progress.canPlay(now: t0), isTrue);

        // Drop to 0 -> cannot play without Infinity
        expect(progress.trySpendHeart(amount: 1, now: t0), isTrue);
        expect(progress.trySpendHeart(amount: 1, now: t0), isTrue);
        expect(progress.lives, 0);
        expect(progress.canPlay(now: t0), isFalse);

        // Grant 30m Infinity -> canPlay == true, spend skips deduction, mm:ss format
        progress.addInfinityLives(const Duration(minutes: 30), now: t0);
        expect(progress.isInfinityLives(now: t0), isTrue);
        expect(progress.canPlay(now: t0), isTrue);
        expect(progress.formattedNextLifeCountdown(now: t0), '30:00');
        expect(progress.trySpendHeart(amount: 1, now: t0), isTrue);
        expect(progress.lives, 0);

        // Adding another 90m extends Infinity -> 2h 00m (`02:00:00`), >24h formats `Xd Xh`
        progress.addInfinityLives(const Duration(minutes: 90), now: t0);
        expect(progress.formattedNextLifeCountdown(now: t0), '02:00:00');
        expect(
          PlayerProgressService.formatHeartTimerSeconds(26 * 3600),
          '1d 2h',
        );

        // While Infinity is active, normal regen does NOT happen (1h elapsed < 2h expiry)
        final t1h = t0.add(const Duration(hours: 1));
        expect(progress.syncLivesRegen(now: t1h), 0);
        expect(progress.lives, 0);

        // Offline 2h20m (Infinity expired at 2h -> 20m of normal regen elapsed -> +1 heart, 10:00 toward next)
        final t2h20m = t0.add(const Duration(hours: 2, minutes: 20));
        final gainedAfterExpiry = progress.syncLivesRegen(now: t2h20m);
        expect(progress.isInfinityLives(now: t2h20m), isFalse);
        expect(gainedAfterExpiry, 1);
        expect(progress.lives, 1);
        expect(progress.formattedNextLifeCountdown(now: t2h20m), '10:00');
      },
    );

    test(
      'addHearts(isFromBuy: true/false) and setMaxHearts return exact deltas and persist surplus',
      () async {
        final t0 = DateTime(2026, 11, 18, 8, 0, 0);
        final progress = PlayerProgressService();
        await progress.init();

        progress.cheatSetLives(4, now: t0);
        // Free add clamps at max (5) -> delta = 1
        expect(progress.addHearts(3, isFromBuy: false, now: t0), 1);
        expect(progress.lives, 5);

        // Purchased add allows surplus above max (5 -> 8) and persists across restart
        expect(progress.addHearts(3, isFromBuy: true, now: t0), 3);
        expect(progress.lives, 8);

        final reloaded = PlayerProgressService();
        await reloaded.init();
        expect(reloaded.lives, 8);
        expect(reloaded.isHeartsMax, isTrue);

        // Raise max hearts from 5 -> 7 and recover to max cleanly
        final progress2 = PlayerProgressService();
        await progress2.init();
        progress2.cheatSetLives(3, now: t0);
        final gained = progress2.setMaxHearts(7, now: t0);
        expect(progress2.currentMaxLives, 7);
        expect(progress2.lives, 7);
        expect(gained, 4);
      },
    );
  });

  group('MoreLivesDialog & GameplayScreen Heart flow', () {
    testWidgets('MoreLivesDialog renders heart count, countdown, and wires buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));
      try {
        final progress = PlayerProgressService();
        await tester.runAsync(() async {
          await progress.init();
          progress.cheatSetCoins(1000);
          progress.cheatSetLives(0);
        });

        bool watchedAd = false;
        bool refilledCoins = false;
        bool closed = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MoreLivesDialog(
                progress: progress,
                onWatchAdForOneLife: () => watchedAd = true,
                onRefillWithCoins: () => refilledCoins = true,
                onClose: () => closed = true,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(const ValueKey('more_lives_modal')), findsOneWidget);
        expect(find.text('More Lives?'), findsWidgets);
        expect(find.byKey(const ValueKey('more_lives_count_text')), findsOneWidget);
        expect(find.text('0'), findsWidgets);
        expect(find.byKey(const ValueKey('more_lives_countdown_text')), findsOneWidget);
        expect(find.text('Get more lives to continue playing'), findsOneWidget);
        expect(find.text('GET'), findsWidgets);
        expect(find.text('+1'), findsWidgets);
        expect(find.text('Refill Lives'), findsWidgets);
        expect(find.text('900'), findsWidgets);

        await tester.tap(find.byKey(const ValueKey('more_lives_watch_ad_btn')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(watchedAd, isTrue);

        await tester.tap(find.byKey(const ValueKey('more_lives_refill_coins_btn')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(refilledCoins, isTrue);

        await tester.tap(find.byKey(const ValueKey('more_lives_close_btn')));
        await tester.pump(const Duration(milliseconds: 50));
        expect(closed, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.binding.setSurfaceSize(null);
      }
    });

    testWidgets(
      'GameplayScreen: untouched board retry loses 0 lives; interacted board retry loses 1 life; 0 lives opens MoreLivesDialog',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));
        AdsManager.enableAds = false;
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
          progress.cheatSetCoins(1500);
          progress.cheatSetLives(2);

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
          expect(game.hasPlayerInteracted, isFalse);

          // 1. Untouched board -> Open Settings -> Restart -> shows "No life will be lost!" and keeps 2 lives
          await tester.tap(find.byKey(const ValueKey('hud_settings_btn')));
          await tester.pump(const Duration(milliseconds: 220));
          await tester.tap(find.text('Restart').first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 250));

          expect(find.byType(ExitGameplayPopup), findsOneWidget);
          expect(find.text('No life will be lost!'), findsOneWidget);
          expect(find.text('-1'), findsNothing);

          await tester.tap(find.text('Restart').first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 450));
          expect(progress.lives, 2);

          // 2. Interacted board -> perform action -> Restart loses 1 life (2 -> 1)
          final acted = game.triggerLevelUpPowerUp();
          expect(acted, isTrue);
          expect(game.hasPlayerInteracted, isTrue);
          await tester.pump(const Duration(milliseconds: 600));

          await tester.tap(find.byKey(const ValueKey('hud_settings_btn')));
          await tester.pump(const Duration(milliseconds: 220));
          await tester.tap(find.text('Restart').first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 250));

          expect(find.byType(ExitGameplayPopup), findsOneWidget);
          expect(find.text('You will lose a life!'), findsOneWidget);
          expect(find.text('-1'), findsWidgets);

          await tester.tap(find.text('Restart').first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 450));
          expect(progress.lives, 1);

          // 3. Interacted again on last heart (1 -> 0) -> MoreLivesDialog opens and blocks closing into level
          final acted2 = game.triggerLevelUpPowerUp();
          expect(acted2, isTrue);
          expect(game.hasPlayerInteracted, isTrue);
          await tester.pump(const Duration(milliseconds: 600));

          await tester.tap(find.byKey(const ValueKey('hud_settings_btn')));
          await tester.pump(const Duration(milliseconds: 220));
          await tester.tap(find.text('Restart').first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 250));
          await tester.tap(find.text('Restart').first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 350));

          expect(progress.lives, 0);
          expect(find.byKey(const ValueKey('more_lives_modal')), findsOneWidget);

          // Tapping X with 0 lives must NOT let player enter the level
          await tester.tap(find.byKey(const ValueKey('more_lives_close_btn')));
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byKey(const ValueKey('more_lives_modal')), findsOneWidget);

          // Watching rewarded ad grants +1 life and dismisses modal cleanly
          AdsManager.enableAds = true;
          AdsManager.mockRewardResult = true;
          await tester.tap(find.byKey(const ValueKey('more_lives_watch_ad_btn')));
          await tester.pump(const Duration(milliseconds: 450));
          expect(progress.lives, 1);
          expect(find.byKey(const ValueKey('more_lives_modal')), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'GameplayScreen cold-start at 0 lives opens MoreLivesDialog and Refill Lives (900 coins) restores 5 hearts',
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
          progress.cheatSetCoins(1200);
          progress.cheatSetLives(0);

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

          expect(find.byKey(const ValueKey('more_lives_modal')), findsOneWidget);

          await tester.tap(find.byKey(const ValueKey('more_lives_refill_coins_btn')));
          await tester.pump(const Duration(milliseconds: 350));

          expect(progress.lives, 5);
          expect(progress.coins, 300);
          expect(find.byKey(const ValueKey('more_lives_modal')), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'LoseOverlay Stage 2 displays Level X, broken heart (-1), Level Failed!, Try Again, and active Close button to Home',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(540, 960));
        var closedToHome = false;
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LoseOverlay(
                  levelLabel: 'Level 5',
                  playerCoins: 500,
                  remainingLives: 3,
                  onPlayOnCoins: () {},
                  onPlayOnAd: () {},
                  onCloseToHome: () => closedToHome = true,
                  onRetry: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 1600));

          await tester.tap(find.byType(UnitySpriteButton));
          await tester.pump(const Duration(milliseconds: 250));

          expect(find.text('Level 5'), findsWidgets);
          expect(find.text('-1'), findsWidgets);
          expect(find.text('Level Failed!'), findsOneWidget);
          expect(find.text('Try Again'), findsWidgets);
          expect(
            find.image(const AssetImage('assets/images/icon_heart2.png')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('lose_failed_close_btn')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('lose_failed_close_btn')));
          await tester.pump(const Duration(milliseconds: 100));
          expect(closedToHome, isTrue);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );

    testWidgets(
      'RemoteConfigService configures coin prices for boosters, live heart refill, and play-on',
      (tester) async {
        RemoteConfigService.setMockValues(
          boosterLevelUpPrice: 777,
          boosterTimeFreezePrice: 333,
          liveHeartRefillPrice: 1200,
          playOnBasePrice: 520,
          playOnIncrementPrice: 180,
          winLevelCoinReward: 75,
        );
        expect(RemoteConfigService.winLevelCoinReward, 75);

        final progress = PlayerProgressService();
        await tester.runAsync(() => progress.init());
        progress.cheatSetCoins(2000);
        progress.cheatSetLives(2);

        // PlayerProgressService defaults honor Remote Config overrides.
        expect(progress.buyLevelUpPack(), isTrue);
        expect(progress.coins, 2000 - 777);
        expect(progress.buyTimeFreezePack(), isTrue);
        expect(progress.coins, 2000 - 777 - 333);

        await tester.binding.setSurfaceSize(const Size(540, 960));
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MoreLivesDialog(
                  progress: progress,
                  onWatchAdForOneLife: () {},
                  onRefillWithCoins: () => progress.refillLivesWithCoins(),
                  onClose: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 280));
          expect(find.text('1200'), findsWidgets);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PowerUpBuyPopup(
                  isLevelUp: true,
                  playerCoins: progress.coins,
                  onBuyPack: () {},
                  onWatchAd: () {},
                  onClose: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 220));
          expect(find.text('777'), findsWidgets);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PowerUpBuyPopup(
                  isLevelUp: false,
                  playerCoins: progress.coins,
                  onBuyPack: () {},
                  onWatchAd: () {},
                  onClose: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 220));
          expect(find.text('333'), findsWidgets);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LoseOverlay(
                  levelLabel: 'Level 4',
                  playerCoins: progress.coins,
                  remainingLives: progress.lives,
                  onPlayOnCoins: () {},
                  onPlayOnAd: () {},
                  onRetry: () {},
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 1600));
          expect(find.text('520'), findsWidgets);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.binding.setSurfaceSize(null);
        }
      },
    );
  });
}
