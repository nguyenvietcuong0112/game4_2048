import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/services/ads_manager.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/iap_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/services/remote_config_service.dart';
import 'package:block_order_2048/ui/home_screen.dart';
import 'package:block_order_2048/ui/journey_view.dart';
import 'package:block_order_2048/ui/shop_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late bool prevEnableAds;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AdsManager.mockRewardResult = null;
    AdsManager.setAdsRemoved(false);
    IapService.resetMocks();
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
    AdsManager.setAdsRemoved(false);
    AdsManager.enableAds = prevEnableAds;
    IapService.resetMocks();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('fgsdk/events'),
      null,
    );
    messenger.setMockMethodCallHandler(const MethodChannel('fgsdk'), null);
  });

  group('IapService & AdsManager No Ads integration', () {
    test('buys No Ads, bundles, Fail Offer, and Gold 1..5 accurately', () async {
      final progress = PlayerProgressService();
      await progress.init();
      progress.cheatSetCoins(0);

      IapService.debugMockPurchaseResult = true;

      AdsManager.enableAds = true;
      expect(AdsManager.areNonRewardedAdsAllowed, isTrue);

      // 1. No Ads
      expect(
        await IapService.buyBundlePack(
          pack: IapService.noAdsPack,
          progress: progress,
          location: 'shop',
        ),
        isTrue,
      );
      expect(progress.noAdsPurchased, isTrue);
      expect(AdsManager.isAdsRemoved, isTrue);
      expect(AdsManager.areNonRewardedAdsAllowed, isFalse);

      // Rewarded Ads still work when No Ads is active
      AdsManager.mockRewardResult = true;
      var rewardedCalled = false;
      await AdsManager.showRewardedAd(
        placement: 'shop_free_coins',
        levelNumber: 1,
        onRewardResult: (ok) => rewardedCalled = ok,
      );
      expect(rewardedCalled, isTrue);

      // 2. No Ads Bundle: +2,000 coins & +1 each of 4 boosters
      final initLvUp = progress.levelUpCount;
      final initFreeze = progress.timeFreezeCount;
      final initShuffle = progress.shuffleCount;
      final initHammer = progress.hammerCount;
      expect(
        await IapService.buyBundlePack(
          pack: IapService.noAdsBundlePack,
          progress: progress,
          location: 'shop',
        ),
        isTrue,
      );
      expect(progress.coins, 2000);
      expect(progress.levelUpCount, initLvUp + 1);
      expect(progress.timeFreezeCount, initFreeze + 1);
      expect(progress.shuffleCount, initShuffle + 1);
      expect(progress.hammerCount, initHammer + 1);

      // 3. Beginner Bundle: +10,000 coins, +2 each booster (8 total), +2h infinity
      expect(
        await IapService.buyBundlePack(
          pack: IapService.beginnerBundle,
          progress: progress,
          location: 'shop',
        ),
        isTrue,
      );
      expect(progress.coins, 12000);
      expect(progress.levelUpCount, initLvUp + 3);
      expect(progress.isInfinityLives(), isTrue);

      // 4. Master Bundle: +20,000 coins, +5 each booster (20 total)
      expect(
        await IapService.buyBundlePack(
          pack: IapService.masterBundle,
          progress: progress,
          location: 'shop',
        ),
        isTrue,
      );
      expect(progress.coins, 32000);
      expect(progress.hammerCount, initHammer + 8);

      // 5. Fail Offer: +1,500 coins, +1 each booster
      expect(
        await IapService.buyBundlePack(
          pack: IapService.failOfferPack,
          progress: progress,
          location: 'fail_offer',
        ),
        isTrue,
      );
      expect(progress.coins, 33500);
      expect(progress.shuffleCount, initShuffle + 9);

      // 6. Paid Coin packs Gold 1..5
      for (final coinPack in IapService.coinPacks.where((c) => !c.isFreeRewardedAd)) {
        final before = progress.coins;
        final bought = await IapService.buyCoinPack(
          pack: coinPack,
          progress: progress,
          location: 'shop',
        );
        expect(bought, isTrue);
        expect(progress.coins, before + coinPack.coins);
      }
      expect(progress.coins, 33500 + 100 + 5000 + 10000 + 25000 + 50000);
    });

    test('restorePurchases activates No Ads cleanly', () async {
      final progress = PlayerProgressService();
      await progress.init();
      IapService.debugMockRestoreResult = true;

      final ok = await IapService.restorePurchases(progress);
      expect(ok, isTrue);
      expect(progress.noAdsPurchased, isTrue);
      expect(AdsManager.isAdsRemoved, isTrue);
    });
  });

  group('Journey progression & Gallery unlock', () {
    test('schedule matches all 13 levels and grants rewards + equips BGs', () async {
      final progress = PlayerProgressService();
      await progress.init();
      progress.cheatSetCoins(0);

      expect(progress.isJourneyUnlocked, isFalse);
      expect(progress.isJourneyBgUnlocked(0), isTrue);
      expect(progress.isJourneyBgUnlocked(1), isFalse);

      // Simulate winning up to Level 20 -> currentLevel/highestLevel becomes 21
      progress.setCurrentLevel(21);
      expect(progress.isJourneyUnlocked, isTrue);
      expect(progress.isJourneyMilestoneUnlocked(1), isTrue);
      expect(progress.isJourneyMilestoneUnlocked(15), isTrue);
      expect(progress.isJourneyMilestoneUnlocked(20), isTrue);
      expect(progress.isJourneyMilestoneUnlocked(30), isFalse);

      final frozenMilestone =
          JourneyMilestoneConfig.schedule.firstWhere((m) => m.levelUnlock == 20);
      expect(progress.claimJourneyMilestone(frozenMilestone), isTrue);
      expect(progress.isJourneyBgUnlocked(1), isTrue);
      expect(progress.selectedJourneyBgId, 1);

      // Claiming Level 175 grants 1x LevelUp (Growth) booster when reached
      progress.setCurrentLevel(176);
      final beforeLvUp = progress.levelUpCount;
      final lv175 =
          JourneyMilestoneConfig.schedule.firstWhere((m) => m.levelUnlock == 175);
      expect(lv175.boosterType, BoosterType.levelUp);
      expect(progress.claimJourneyMilestone(lv175), isTrue);
      expect(progress.levelUpCount, beforeLvUp + 1);
    });
  });

  group('ShopView & JourneyView widgets (standalone while Home nav is deferred)', () {
    testWidgets(
      'HomeScreen hides Shop/Journey/IAP while standalone ShopView & JourneyView render and award coins cleanly',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(412, 892));
        try {
          late final LevelRepository repo;
          final audio = AudioHapticsService();
          final progress = PlayerProgressService();
          await tester.runAsync(() async {
            repo = await LevelRepository.loadFromAssets();
            await progress.init();
            progress.setCurrentLevel(6);
          });
          progress.cheatSetCoins(500);

          // 1. HomeScreen keeps Shop/Journey/Promo controls commented out
          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(
                repository: repo,
                audio: audio,
                progress: progress,
                onPlayLevel: () {},
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('home_nav_shop_btn')), findsNothing);
          expect(find.byKey(const ValueKey('home_nav_lock_btn')), findsNothing);
          expect(find.byKey(const ValueKey('home_no_ads_btn')), findsNothing);
          expect(
            find.byKey(const ValueKey('home_starter_pack_btn')),
            findsNothing,
          );

          // 2. Standalone ShopView renders cleanly and Free Gold 0 awards +100 coins
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ShopView(progress: progress),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
          expect(find.byType(ShopView), findsOneWidget);
          expect(find.text('No Ads'), findsOneWidget);
          expect(find.text('No Ads Bundle'), findsWidgets);
          expect(find.text('Coins'), findsWidgets);

          AdsManager.enableAds = true;
          AdsManager.mockRewardResult = true;
          await tester.ensureVisible(
            find.byKey(const ValueKey('shop_coin_btn_free')),
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(find.byKey(const ValueKey('shop_coin_btn_free')));
          await tester.pump(const Duration(milliseconds: 250));
          expect(progress.coins, 600);

          // 3. Standalone JourneyView renders progression track cleanly after Lv20 unlock
          progress.setCurrentLevel(21);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: JourneyView(progress: progress),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull);
          expect(find.byType(JourneyView), findsOneWidget);
          expect(
            find.byKey(const ValueKey('journey_list_view')),
            findsOneWidget,
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
