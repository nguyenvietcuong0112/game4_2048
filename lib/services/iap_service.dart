import 'package:flutter/foundation.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';
import 'ads_manager.dart';
import 'player_progress_service.dart';
import 'remote_config_service.dart';

/// Product catalog entry for Shop bundles, No Ads packs, and Fail Offer.
class ShopBundlePack {
  final String productId;
  final String enumKey;
  final String title;
  final String fallbackPrice;
  final int coins;

  /// Quantity granted for EACH of the 4 in-game boosters
  /// (`levelUp`, `timeFreeze`, `shuffle`, `hammer`), so `1` = 4 boosters total.
  final int boosterEachCount;
  final int infinityHours;
  final bool removesAds;
  final bool isNonConsumable;
  final String? badgeText;
  final String? frameAsset;
  final String? coinAsset;

  const ShopBundlePack({
    required this.productId,
    required this.enumKey,
    required this.title,
    required this.fallbackPrice,
    this.coins = 0,
    this.boosterEachCount = 0,
    this.infinityHours = 0,
    this.removesAds = false,
    this.isNonConsumable = false,
    this.badgeText,
    this.frameAsset,
    this.coinAsset,
  });

  int get totalBoosters => boosterEachCount * BoosterType.values.length;
}

/// Product catalog entry for Shop coin grid items (`Gold 0`..`Gold 5`).
class ShopCoinPack {
  final String? productId;
  final String? enumKey;
  final String title;
  final String fallbackPrice;
  final int coins;
  final bool isFreeRewardedAd;
  final String coinAsset;

  const ShopCoinPack({
    required this.productId,
    required this.enumKey,
    required this.title,
    required this.fallbackPrice,
    required this.coins,
    required this.isFreeRewardedAd,
    required this.coinAsset,
  });
}

/// Centralized catalog + purchase/restore orchestration for IAP and Shop rewards.
class IapService {
  IapService._();

  static const String noAdsProductId = 'com.fw.water.block.number.merge';
  static const String noAdsBundleProductId =
      'com.fw.water.block.number.merge.no_ads_bundle';
  static const String starterPackProductId =
      'com.fw.water.block.number.merge.starter_pack';
  static const String limitedPackProductId =
      'com.fw.water.block.number.merge.limited_pack';
  static const String beginnerBundleProductId =
      'com.fw.water.block.number.merge.beginner_bundle';
  static const String masterBundleProductId =
      'com.fw.water.block.number.merge.master_bundle';
  static const String failOfferProductId =
      'com.fw.water.block.number.merge.fail_offer';

  static const ShopBundlePack noAdsPack = ShopBundlePack(
    productId: noAdsProductId,
    enumKey: 'no_ads',
    title: 'No Ads',
    fallbackPrice: r'$5.99',
    removesAds: true,
    isNonConsumable: true,
    frameAsset: 'assets/images/Shop/frame_noads.png',
  );

  static const ShopBundlePack noAdsBundlePack = ShopBundlePack(
    productId: noAdsBundleProductId,
    enumKey: 'no_ads_bundle',
    title: 'No Ads Bundle',
    fallbackPrice: r'$6.99',
    coins: 2000,
    boosterEachCount: 1,
    removesAds: true,
    frameAsset: 'assets/images/Shop/frame_starter+noads.png',
    coinAsset: 'assets/images/Shop/asset_coin_4.png',
  );

  static const ShopBundlePack starterPack = ShopBundlePack(
    productId: starterPackProductId,
    enumKey: 'starter_pack',
    title: 'Starter Pack',
    fallbackPrice: r'$2.99',
    coins: 2000,
    boosterEachCount: 1,
    badgeText: '50%\nOFF',
    frameAsset: 'assets/images/Shop/frame_starter+noads.png',
    coinAsset: 'assets/images/Shop/asset_coin_4.png',
  );

  static const ShopBundlePack limitedPack = ShopBundlePack(
    productId: limitedPackProductId,
    enumKey: 'limited_pack',
    title: 'Limited Pack',
    fallbackPrice: r'$5.99',
    coins: 5000,
    boosterEachCount: 1,
    infinityHours: 1,
    frameAsset: 'assets/images/Shop/frame_limitedpack.png',
    coinAsset: 'assets/images/Shop/asset_coin_7.png',
  );

  static const ShopBundlePack beginnerBundle = ShopBundlePack(
    productId: beginnerBundleProductId,
    enumKey: 'beginner_bundle',
    title: 'Beginner Bundle',
    fallbackPrice: r'$14.99',
    coins: 10000,
    boosterEachCount: 2,
    infinityHours: 2,
    frameAsset: 'assets/images/Shop/frame_beginerpack.png',
    coinAsset: 'assets/images/Shop/asset_coin_5.png',
  );

  static const ShopBundlePack masterBundle = ShopBundlePack(
    productId: masterBundleProductId,
    enumKey: 'master_bundle',
    title: 'Master Bundle',
    fallbackPrice: r'$29.99',
    coins: 20000,
    boosterEachCount: 5,
    infinityHours: 5,
    frameAsset: 'assets/images/Shop/frame_masterpack.png',
    coinAsset: 'assets/images/Shop/asset_coin_6.png',
  );

  static const ShopBundlePack failOfferPack = ShopBundlePack(
    productId: failOfferProductId,
    enumKey: 'fail_offer',
    title: 'Fail Offer',
    fallbackPrice: r'$3.99',
    coins: 1500,
    boosterEachCount: 1,
    frameAsset: 'assets/images/Shop/frame_limitedpack.png',
    coinAsset: 'assets/images/Shop/asset_coin_4.png',
  );

  /// Bundles shown inside the "Bundles" section of Shop.
  static const List<ShopBundlePack> shopBundles = [
    starterPack,
    limitedPack,
    beginnerBundle,
    masterBundle,
  ];

  /// Coins grid items (`Gold 0` .. `Gold 5`) matching the Shop Coins spreadsheet.
  static const List<ShopCoinPack> coinPacks = [
    ShopCoinPack(
      productId: null,
      enumKey: null,
      title: 'Gold 0',
      fallbackPrice: 'Free',
      coins: 100,
      isFreeRewardedAd: true,
      coinAsset: 'assets/images/Shop/asset_coin_1.png',
    ),
    ShopCoinPack(
      productId: 'com.fw.water.block.number.merge.gold_1',
      enumKey: 'gold_1',
      title: 'Gold 1',
      fallbackPrice: r'$0.99',
      coins: 100,
      isFreeRewardedAd: false,
      coinAsset: 'assets/images/Shop/asset_coin_2.png',
    ),
    ShopCoinPack(
      productId: 'com.fw.water.block.number.merge.gold_2',
      enumKey: 'gold_2',
      title: 'Gold 2',
      fallbackPrice: r'$7.99',
      coins: 5000,
      isFreeRewardedAd: false,
      coinAsset: 'assets/images/Shop/asset_coin_3.png',
    ),
    ShopCoinPack(
      productId: 'com.fw.water.block.number.merge.gold_3',
      enumKey: 'gold_3',
      title: 'Gold 3',
      fallbackPrice: r'$15.99',
      coins: 10000,
      isFreeRewardedAd: false,
      coinAsset: 'assets/images/Shop/asset_coin_4.png',
    ),
    ShopCoinPack(
      productId: 'com.fw.water.block.number.merge.gold_4',
      enumKey: 'gold_4',
      title: 'Gold 4',
      fallbackPrice: r'$29.99',
      coins: 25000,
      isFreeRewardedAd: false,
      coinAsset: 'assets/images/Shop/asset_coin_5.png',
    ),
    ShopCoinPack(
      productId: 'com.fw.water.block.number.merge.gold_5',
      enumKey: 'gold_5',
      title: 'Gold 5',
      fallbackPrice: r'$55.99',
      coins: 50000,
      isFreeRewardedAd: false,
      coinAsset: 'assets/images/Shop/asset_coin_6.png',
    ),
  ];

  static final Map<String, String> _localizedPrices = {};

  @visibleForTesting
  static bool? debugMockPurchaseResult;

  @visibleForTesting
  static bool? debugMockRestoreResult;

  static void resetMocks() {
    debugMockPurchaseResult = null;
    debugMockRestoreResult = null;
    _localizedPrices.clear();
  }

  static String priceLabelFor(String productId, String fallbackPrice) {
    final cached = _localizedPrices[productId];
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }
    return fallbackPrice;
  }

  /// Syncs cached No Ads state & fetches localized store prices on app boot.
  static Future<void> syncOnBoot(PlayerProgressService progress) async {
    bool removed = progress.noAdsPurchased;
    if (!removed) {
      try {
        final noAdsOwned = await FGSDK.productIsPurchased(noAdsProductId);
        final noAdsBundleOwned =
            await FGSDK.productIsPurchased(noAdsBundleProductId);
        removed = noAdsOwned || noAdsBundleOwned;
      } catch (_) {}
    }

    if (removed) {
      progress.setNoAdsPurchased(true);
      AdsManager.setAdsRemoved(true);
      try {
        FGSDK.activateRemoveAds();
        FGSDK.removeAds();
      } catch (_) {}
    } else {
      AdsManager.setAdsRemoved(false);
    }

    // Best-effort localized price warmup; falls back gracefully on offline/test.
    final ids = <String>[
      noAdsProductId,
      noAdsBundleProductId,
      starterPackProductId,
      limitedPackProductId,
      beginnerBundleProductId,
      masterBundleProductId,
      failOfferProductId,
      for (final c in coinPacks)
        if (c.productId != null) c.productId!,
    ];
    for (final id in ids) {
      try {
        final price = await FGSDK.getProductPrice(id);
        if (price.trim().isNotEmpty) {
          _localizedPrices[id] = price.trim();
        }
      } catch (_) {}
    }
  }

  /// Purchases a [ShopBundlePack] via FGSDK and credits all entitlements.
  static Future<bool> buyBundlePack({
    required ShopBundlePack pack,
    required PlayerProgressService progress,
    required String location,
  }) async {
    _safeLogIapClick(
      level: progress.currentLevel,
      location: location,
      type: pack.enumKey,
      productId: pack.productId,
    );

    final ok = await _executePurchase(
      productId: pack.productId,
      location: location,
      level: progress.currentLevel,
    );
    if (!ok) return false;

    if (pack.coins > 0) {
      progress.addCoins(pack.coins);
    }
    if (pack.boosterEachCount > 0) {
      for (final type in BoosterType.values) {
        progress.grantFreePowerUp(
          boosterType: type,
          count: pack.boosterEachCount,
        );
      }
    }
    if (pack.infinityHours > 0) {
      progress.addInfinityLives(Duration(hours: pack.infinityHours));
    }
    if (pack.removesAds) {
      progress.setNoAdsPurchased(true);
      AdsManager.setAdsRemoved(true);
      try {
        FGSDK.activateRemoveAds();
        FGSDK.removeAds();
      } catch (_) {}
    }
    progress.markPackPurchased(pack.productId);
    return true;
  }

  /// Purchases a paid [ShopCoinPack] (`Gold 1..5`) via FGSDK and credits coins.
  static Future<bool> buyCoinPack({
    required ShopCoinPack pack,
    required PlayerProgressService progress,
    required String location,
  }) async {
    final pid = pack.productId;
    if (pid == null) return false;

    _safeLogIapClick(
      level: progress.currentLevel,
      location: location,
      type: pack.enumKey ?? 'gold',
      productId: pid,
    );

    final ok = await _executePurchase(
      productId: pid,
      location: location,
      level: progress.currentLevel,
    );
    if (!ok) return false;

    progress.addCoins(pack.coins);
    return true;
  }

  /// Restores store purchases and re-applies any No Ads entitlement found.
  static Future<bool> restorePurchases(PlayerProgressService progress) async {
    if (debugMockRestoreResult != null) {
      if (debugMockRestoreResult == true) {
        progress.setNoAdsPurchased(true);
        AdsManager.setAdsRemoved(true);
      }
      return debugMockRestoreResult!;
    }

    try {
      final restored = await FGSDK.restorePurchases();
      final noAdsOwned = await FGSDK.productIsPurchased(noAdsProductId);
      final noAdsBundleOwned =
          await FGSDK.productIsPurchased(noAdsBundleProductId);
      final hasRemoveAds = noAdsOwned || noAdsBundleOwned || restored;
      if (hasRemoveAds && (noAdsOwned || noAdsBundleOwned)) {
        progress.setNoAdsPurchased(true);
        AdsManager.setAdsRemoved(true);
        FGSDK.activateRemoveAds();
        FGSDK.removeAds();
      }
      return restored || noAdsOwned || noAdsBundleOwned;
    } catch (e) {
      debugPrint('[IapService] restorePurchases error: $e');
      return false;
    }
  }

  static void logIapShow({
    required int level,
    required String location,
    required String type,
    required String productId,
  }) {
    try {
      FGSDK.logIAPShow('classic', level, location, type, productId);
    } catch (_) {}
  }

  static void _safeLogIapClick({
    required int level,
    required String location,
    required String type,
    required String productId,
  }) {
    try {
      FGSDK.logIAPClick('classic', level, location, type, productId);
    } catch (_) {}
  }

  static Future<bool> _executePurchase({
    required String productId,
    required String location,
    required int level,
  }) async {
    if (debugMockPurchaseResult != null) {
      return debugMockPurchaseResult!;
    }
    try {
      final result =
          await FGSDK.buyProduct(productId, location, 'classic', level);
      return result.ok;
    } catch (e) {
      debugPrint('[IapService] buyProduct($productId) failed: $e');
      return false;
    }
  }
}
