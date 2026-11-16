import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/unity_ui_kit.dart';
import 'package:block_order_2048/ui/water_garden_view.dart';
import 'package:block_order_2048/ui/win_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await UnitySpriteRegistry.loadOne('Button_Green.png');
    await UnitySpriteRegistry.loadOne('Button_Yellow.png');
    await UnitySpriteRegistry.loadOne('Button_CTA.png');
    await UnitySpriteRegistry.loadOne('Inset_Button_CTA.png');
    await UnitySpriteRegistry.loadOne('popup_bg.png');
    await UnitySpriteRegistry.loadOne('frame_content.png');
    await UnitySpriteRegistry.loadOne('Frame_Popup_Title.png');
  });

  group('Vase & Garden Progression Metagame Tests', () {
    test('1. Initial fresh install defaults to Vase 1 (Crystal Fishbowl, Pink Tulip, 3 steps)', () async {
      SharedPreferences.setMockInitialValues({});
      final progress = PlayerProgressService();
      await progress.init();

      expect(progress.vaseCurrentId, 1);
      expect(progress.vaseStepCount, 0);
      expect(progress.currentVaseProgress, 0.0);
      expect(progress.isCurrentVaseReadyToClaim, isFalse);

      final cfg = progress.currentVaseConfig;
      expect(cfg.vaseId, 1);
      expect(cfg.title, 'Crystal Fishbowl');
      expect(cfg.flowerTitle, 'Pink Tulip');
      expect(cfg.totalSteps, 3);
      expect(cfg.rewardCoins, 150);
    });

    test('2. Stepping through Vase 1 levels (1 -> 2 -> 3) advances progress 33% -> 66% -> 100% and marks ready to claim', () async {
      SharedPreferences.setMockInitialValues({});
      final progress = PlayerProgressService();
      await progress.init();

      // Win Level 1
      final r1 = progress.recordLevelWonVaseStep(1);
      expect(r1.oldStep, 0);
      expect(r1.newStep, 1);
      expect(r1.oldProgress, 0.0);
      expect(r1.newProgress, closeTo(0.333, 0.01));
      expect(r1.didReach100Percent, isFalse);
      expect(progress.isCurrentVaseReadyToClaim, isFalse);

      // Win Level 2
      final r2 = progress.recordLevelWonVaseStep(2);
      expect(r2.oldStep, 1);
      expect(r2.newStep, 2);
      expect(r2.newProgress, closeTo(0.666, 0.01));
      expect(r2.didReach100Percent, isFalse);

      // Win Level 3 -> 100%!
      final r3 = progress.recordLevelWonVaseStep(3);
      expect(r3.oldStep, 2);
      expect(r3.newStep, 3);
      expect(r3.newProgress, 1.0);
      expect(r3.didReach100Percent, isTrue);
      expect(progress.isCurrentVaseReadyToClaim, isTrue);
      expect(progress.isVaseUnlocked(1), isTrue);

      // Claiming Vase 1 awards 150 coins and advances to Vase 2 (Azure Ceramic Vase)
      final initialCoins = progress.coins;
      progress.claimCurrentVaseMilestone();

      expect(progress.coins, initialCoins + 150);
      expect(progress.hasClaimedVase(1), isTrue);
      expect(progress.vaseCurrentId, 2);
      expect(progress.vaseStepCount, 0);
      expect(progress.currentVaseProgress, 0.0);

      final cfg2 = progress.currentVaseConfig;
      expect(cfg2.vaseId, 2);
      expect(cfg2.title, 'Azure Ceramic Vase');
      expect(cfg2.flowerTitle, 'Trio Daisies');
      expect(cfg2.totalSteps, 5);
      expect(cfg2.unlockMechanicId, 'ice');
    });

    test('3. Completing Vase 2 (Levels 4..8) unlocks Ice mechanic and awards 200 coins', () async {
      SharedPreferences.setMockInitialValues({
        'bo_vase_current_id': 2,
        'bo_vase_step_count': 4, // 4/5 steps
      });
      final progress = PlayerProgressService();
      await progress.init();

      expect(progress.vaseCurrentId, 2);
      expect(progress.vaseStepCount, 4);
      expect(progress.hasSeenMechanic('ice'), isFalse);

      // 5th win reaches 100%
      final r = progress.recordLevelWonVaseStep(8);
      expect(r.didReach100Percent, isTrue);
      expect(r.newProgress, 1.0);

      final initialCoins = progress.coins;
      progress.claimCurrentVaseMilestone();

      expect(progress.coins, initialCoins + 200);
      expect(progress.hasSeenMechanic('ice'), isTrue);
      expect(progress.vaseCurrentId, 3);
      expect(progress.vaseStepCount, 0);
    });

    testWidgets('4. WaterGardenView renders pouring jar, rising water wave, and capsule progress bar', (tester) async {
      final advanceResult = VaseStepAdvanceResult(
        vaseId: 1,
        oldStep: 0,
        newStep: 1,
        totalSteps: 3,
        oldProgress: 0.0,
        newProgress: 0.333,
        didReach100Percent: false,
        config: VaseMilestoneConfig.getForVaseId(1),
      );

      bool nextLevelTapped = false;
      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF0330AC),
            body: WaterGardenView(
              advanceResult: advanceResult,
              finalBlockNumber: 2048,
              onNextLevel: () => nextLevelTapped = true,
              onClaimMilestone: () {},
            ),
          ),
        ),
      );

      // Advance through pouring and water rising animation (1400ms duration)
      for (int i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Next Level'), findsOneWidget);
      expect(find.text('Reward x2'), findsOneWidget);
      expect(find.text('+25'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.text('67% to unlock'), findsOneWidget);

      // Tap Next Level button
      await tester.tap(find.text('Next Level').first, warnIfMissed: false);
      await tester.pump();
      expect(nextLevelTapped, isTrue);
    });

    testWidgets('5. WaterGardenView tap-to-skip fast forwards pouring and triggers completion immediately', (tester) async {
      final advanceResult = VaseStepAdvanceResult(
        vaseId: 1,
        oldStep: 1,
        newStep: 2,
        totalSteps: 3,
        oldProgress: 0.333,
        newProgress: 0.666,
        didReach100Percent: false,
        config: VaseMilestoneConfig.getForVaseId(1),
      );

      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF0330AC),
            body: WaterGardenView(
              advanceResult: advanceResult,
              finalBlockNumber: 1024,
              onNextLevel: () {},
              onClaimMilestone: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Tap screen to fast forward
      await tester.tapAt(const Offset(270, 480));
      await tester.pump();

      expect(find.text('33% to unlock'), findsOneWidget);
    });

    testWidgets('6. WaterGardenView 100% bloom displays New Mechanic claim modal with rewards', (tester) async {
      final advanceResult = VaseStepAdvanceResult(
        vaseId: 2,
        oldStep: 4,
        newStep: 5,
        totalSteps: 5,
        oldProgress: 0.80,
        newProgress: 1.00,
        didReach100Percent: true,
        config: VaseMilestoneConfig.getForVaseId(2),
      );

      bool milestoneClaimed = false;
      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xFF0330AC),
            body: WaterGardenView(
              advanceResult: advanceResult,
              finalBlockNumber: 4096,
              onNextLevel: () {},
              onClaimMilestone: () => milestoneClaimed = true,
            ),
          ),
        ),
      );

      // Let full 2500ms sequence complete
      for (int i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 100% Bloom Modal
      expect(find.byKey(const ValueKey<String>('New Mechanic!')), findsOneWidget);
      expect(find.text('Ice Blocks'), findsOneWidget);
      expect(find.text('+200'), findsOneWidget);
      expect(find.text('Claim'), findsWidgets);

      // Tap Claim button
      await tester.tap(find.text('Claim').last);
      await tester.pump();
      expect(milestoneClaimed, isTrue);
    });

    testWidgets('7. WinOverlay shows single Next Level button on Levels 1..6 and unlocks Dual Next Level + Reward x2 from Level 7+', (tester) async {
      final advanceResult = VaseStepAdvanceResult(
        vaseId: 1,
        oldStep: 0,
        newStep: 1,
        totalSteps: 3,
        oldProgress: 0.0,
        newProgress: 0.333,
        didReach100Percent: false,
        config: VaseMilestoneConfig.getForVaseId(1),
      );

      bool nextLevelCalled = false;
      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A. Level 6 (< 7): ONLY single centered Next Level (+25) button, NO Reward x2 button
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WinOverlay(
              key: const ValueKey('win_lv6'),
              levelNumber: 6,
              levelLabel: 'Level 6',
              rewardCoins: 25,
              gardenResult: advanceResult,
              finalBlockNumber: 2048,
              onNextLevel: () => nextLevelCalled = true,
            ),
          ),
        ),
      );

      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(WaterGardenView), findsOneWidget);
      expect(find.text('67% to unlock'), findsOneWidget);
      expect(find.text('Next Level'), findsOneWidget);
      expect(find.text('+25'), findsOneWidget);
      expect(find.text('Reward x2'), findsNothing);
      expect(find.text('+50'), findsNothing);
      expect(find.byKey(const ValueKey('garden_reward_x2_btn')), findsNothing);

      await tester.tap(find.text('Next Level').first, warnIfMissed: false);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(nextLevelCalled, isTrue);

      // B. Level 7 (>= 7): Dual side-by-side Next Level (+25) + Reward x2 (+50) buttons
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WinOverlay(
              key: const ValueKey('win_lv7'),
              levelNumber: 7,
              levelLabel: 'Level 7',
              rewardCoins: 25,
              gardenResult: advanceResult,
              finalBlockNumber: 2048,
              onNextLevel: () {},
            ),
          ),
        ),
      );

      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Next Level'), findsOneWidget);
      expect(find.text('Reward x2'), findsOneWidget);
      expect(find.text('+25'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
      expect(find.byKey(const ValueKey('garden_reward_x2_btn')), findsOneWidget);
    });

    testWidgets('8. Claiming 100% vase reveals Panel 6 New Empty Vase (0%) and all 5 vase/flower types render cleanly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Verify all 5 VaseMilestoneConfig shapes & flower bouquets render at 100% without error
      for (int id = 1; id <= 5; id++) {
        final cfg = VaseMilestoneConfig.getForVaseId(id);
        bool claimed = false;
        bool advancedLevel = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WaterGardenView(
                key: ValueKey('vase_test_$id'),
                advanceResult: VaseStepAdvanceResult(
                  vaseId: id,
                  oldStep: cfg.totalSteps - 1,
                  newStep: cfg.totalSteps,
                  totalSteps: cfg.totalSteps,
                  oldProgress: (cfg.totalSteps - 1) / cfg.totalSteps,
                  newProgress: 1.0,
                  didReach100Percent: true,
                  config: cfg,
                ),
                finalBlockNumber: 2048,
                onClaimMilestone: () => claimed = true,
                onNextLevel: () => advancedLevel = true,
              ),
            ),
          ),
        );

        // Pump through full bloom & modal reveal
        for (int i = 0; i < 28; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(find.text('Claim'), findsWidgets);
        await tester.tap(find.text('Claim').last);
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(claimed, isTrue);

        // Panel 6: New Empty Vase (100% to unlock + ? badge) + Dual Buttons
        expect(find.text('100% to unlock'), findsOneWidget);
        expect(find.text('?'), findsOneWidget);
        expect(find.text('Next Level'), findsOneWidget);
        expect(find.text('Reward x2'), findsOneWidget);

        await tester.tap(find.text('Next Level').first);
        await tester.pump();
        expect(advancedLevel, isTrue);
      }
    });

    testWidgets('9. WinOverlay Reward x2 button handles failed ad safely and doubles pending coins on completed ad', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final progress = PlayerProgressService();
      await progress.init();
      final startCoins = progress.coins;
      progress.stageLevelWinReward(rewardCoins: 25, isBonus: false);

      final advanceResult = progress.recordLevelWonVaseStep(1);
      bool adShouldSucceed = false;
      int adRequests = 0;
      bool nextAfterAdCalled = false;
      bool regularNextCalled = false;

      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WinOverlay(
              levelNumber: 7,
              levelLabel: 'Level 7',
              rewardCoins: 25,
              gardenResult: advanceResult,
              finalBlockNumber: 2048,
              onCoinChunkArrived: progress.collectPendingWinCoinChunk,
              onWatchRewardX2: () async {
                adRequests++;
                if (adShouldSucceed) {
                  progress.doublePendingWinCoins(25);
                  return true;
                }
                return false;
              },
              onNextLevelAfterRewardAd: () {
                progress.flushPendingWinCoins();
                nextAfterAdCalled = true;
              },
              onNextLevel: () {
                progress.flushPendingWinCoins();
                regularNextCalled = true;
              },
            ),
          ),
        ),
      );

      for (int i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 1. Failed / cancelled ad keeps overlay open without collecting coins
      await tester.tap(find.byKey(const ValueKey('garden_reward_x2_btn')));
      await tester.pump();
      expect(adRequests, 1);
      expect(nextAfterAdCalled, isFalse);
      expect(regularNextCalled, isFalse);
      expect(progress.coins, startCoins);

      // 2. Successful Reward x2 ad doubles pending coins (25 -> 50), flies 12 coin chunks, and advances
      adShouldSucceed = true;
      await tester.tap(find.byKey(const ValueKey('garden_reward_x2_btn')));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(adRequests, 2);
      expect(nextAfterAdCalled, isTrue);
      expect(regularNextCalled, isFalse);
      expect(progress.coins, startCoins + 50);
    });
  });
}

