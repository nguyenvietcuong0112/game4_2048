import 'fg_ads_info.dart';
import 'fg_bridge.dart';
import 'fg_types.dart';

/// API công khai của Funtap Global SDK cho Flutter.
///
/// Mirror 1:1 wrapper bản Cocos (`fgsdk.ts` / `fgsdk.js`) — cùng tên method,
/// cùng tham số, cùng hành vi; chỉ khác đường truyền xuống native.
/// Native SDK dùng **chung** với bản Cocos nên tên event/param là VERBATIM.
///
/// Quy ước:
///  - getter / `show*` / `buy*` trả `Future`;
///  - `on*` trả `Stream` (broadcast — nhiều listener thoải mái);
///  - không có native (test/web/desktop) → no-op, getter trả default.
///
/// SDK **tự init** lúc app khởi động (đọc `fg_main_config.json`) — không cần
/// gọi hàm init nào.
class FGSDK {
  FGSDK._();

  // ── Helper ép kiểu kết quả từ native ───────────────────────────────────────
  static Future<String> _str(String m, [Map<String, Object?>? a, String def = '']) =>
      FGBridge.call(m, a).then((v) => (v as String?) ?? def);

  static Future<bool> _bool(String m, [Map<String, Object?>? a, bool def = false]) =>
      FGBridge.call(m, a).then((v) => (v as bool?) ?? def);

  static Future<int> _int(String m, Map<String, Object?>? a, int def) =>
      FGBridge.call(m, a).then((v) => (v as num?)?.toInt() ?? def);

  /// Bỏ key có value null để args gửi xuống khớp bản Cocos
  /// (Cocos chỉ set key khi tham số optional được truyền).
  static Map<String, Object?> _args(Map<String, Object?> m) =>
    Map<String, Object?>.fromEntries(m.entries.where((e) => e.value != null));

  // ── Core ───────────────────────────────────────────────────────────────────

  /// Version native SDK (verbatim Unity, vd `3.2.6`) — KHÁC version package.
  static Future<String> getSdkVersion() => _str('getSdkVersion');

  /// SDK đã init xong chưa. `false` thường do thiếu `fg_main_config.json`.
  static Future<bool> isInit() => _bool('isInit');

  /// Mở **Mediation Debugger** của AppLovin MAX — màn hình QA soi adapter / ad unit /
  /// waterfall ngay trên máy thật (mirror `MaxSdk.ShowMediationDebugger()` bên Unity).
  ///
  /// Chỉ dùng khi test. MAX chưa init thì native bỏ qua, không crash.
  static void showMediationDebugger() => FGBridge.voidCall('showMediationDebugger');

  // ── Tracking ───────────────────────────────────────────────────────────────

  /// Bắn 1 event tuỳ ý.
  ///
  /// KHÔNG truyền [providers] = **chỉ Firebase** (không phải tất cả provider).
  static void logEvent(String name, {FGParams? params, List<FGProviderType>? providers}) =>
      FGBridge.voidCall('logEvent', _args({
        'name': name,
        'params': params,
        'providers': providers?.map((p) => p.wireName).toList(),
      }));

  /// Set user property (áp cho mọi provider).
  static void setUserProperties(FGParams props) =>
      FGBridge.voidCall('setUserProperties', {'props': props});

  /// Event `level_start` — param: `level, play_count, lose_count, play_mode`.
  static void logLevelStart(int level, int playCount, int loseCount, String playMode,
          {FGParams? extra}) =>
      FGBridge.voidCall('logLevelStart', _args({
        'level': level, 'playCount': playCount, 'loseCount': loseCount,
        'playMode': playMode, 'extra': extra,
      }));

  /// Event `level_end` — param: `level, play_mode, play_count, lose_count,
  /// play_duration, success, reason`.
  static void logLevelEnd(int level, int playCount, int loseCount, String playMode,
          double playDuration, bool success, String reason, {FGParams? extra}) =>
      FGBridge.voidCall('logLevelEnd', _args({
        'level': level, 'playCount': playCount, 'loseCount': loseCount,
        'playMode': playMode, 'playDuration': playDuration, 'success': success,
        'reason': reason, 'extra': extra,
      }));

  /// Event `resource_source` (nhận tài nguyên).
  static void logEarnResource(String playMode, int level, String itemType, String name,
          double amount, String earnPlacement, String item, String booster, double balance,
          {FGParams? extra}) =>
      FGBridge.voidCall('logEarnResource', _args({
        'playMode': playMode, 'level': level, 'itemType': itemType, 'name': name,
        'amount': amount, 'earnPlacement': earnPlacement, 'item': item,
        'booster': booster, 'balance': balance, 'extra': extra,
      }));

  /// Event `resource_sink` (tiêu tài nguyên).
  static void logSpendResource(String playMode, int level, String itemType, String name,
          double amount, String spendPlacement, String spendReason, String item,
          String booster, double balance, {FGParams? extra}) =>
      FGBridge.voidCall('logSpendResource', _args({
        'playMode': playMode, 'level': level, 'itemType': itemType, 'name': name,
        'amount': amount, 'spendPlacement': spendPlacement, 'spendReason': spendReason,
        'item': item, 'booster': booster, 'balance': balance, 'extra': extra,
      }));

  /// Event `tut_action` — param `name`, `value`.
  ///
  /// Truyền [actionName] = `success` để SDK tự mirror `tutorial_complete`
  /// sang AppLovin.
  static void logTutorial(String actionName, String actionValue, {FGParams? extra}) =>
      FGBridge.voidCall('logTutorial', _args({
        'actionName': actionName, 'actionValue': actionValue, 'extra': extra,
      }));

  /// Event `loading_start`.
  static void logLoadingStart(String placement, {FGParams? extra}) =>
      FGBridge.voidCall('logLoadingStart', _args({'placement': placement, 'extra': extra}));

  /// Event `loading_finish` — param `placement`, `is_load`, `value`.
  static void logLoadingEnd(String placement, bool isLoad, double loadTime,
          {FGParams? extra}) =>
      FGBridge.voidCall('logLoadingEnd', _args({
        'placement': placement, 'isLoad': isLoad, 'loadTime': loadTime, 'extra': extra,
      }));

  /// Event `iap_show`.
  static void logIAPShow(String playMode, int level, String location, String type,
          String productId, {FGParams? extra}) =>
      FGBridge.voidCall('logIAPShow', _args({
        'playMode': playMode, 'level': level, 'location': location, 'type': type,
        'productId': productId, 'extra': extra,
      }));

  /// Event `iap_click`.
  static void logIAPClick(String playMode, int level, String location, String type,
          String productId, {FGParams? extra}) =>
      FGBridge.voidCall('logIAPClick', _args({
        'playMode': playMode, 'level': level, 'location': location, 'type': type,
        'productId': productId, 'extra': extra,
      }));

  // ── Ads ────────────────────────────────────────────────────────────────────

  /// Hiện Interstitial. Future hoàn tất khi quảng cáo đóng (hoặc fail).
  static Future<void> showInterstitial(String placement, String playMode, num level,
          {FGParams? params}) =>
      FGBridge.call('showInterstitial',
          _args({'placement': placement, 'playMode': playMode, 'level': level, 'params': params}));

  /// Hiện Rewarded. Future hoàn tất khi xong luồng thưởng.
  ///
  /// ⚠️ Muốn biết user có thực sự nhận thưởng không thì nghe
  /// [onRewardedCompleted], đừng chỉ dựa vào Future này.
  static Future<void> showRewarded(String placement, String playMode, num level,
          {FGParams? params}) =>
      FGBridge.call('showRewarded',
          _args({'placement': placement, 'playMode': playMode, 'level': level, 'params': params}));

  static Future<bool> isRewardedReady() => _bool('isRewardedReady');

  static void loadRewarded() => FGBridge.voidCall('loadRewarded');

  static void showBanner(String placement, String playMode, num level, {FGParams? params}) =>
      FGBridge.voidCall('showBanner',
          _args({'placement': placement, 'playMode': playMode, 'level': level, 'params': params}));

  static void hideBanner() => FGBridge.voidCall('hideBanner');

  static void showAppOpen(String placement, String playMode, num level, {FGParams? params}) =>
      FGBridge.voidCall('showAppOpen',
          _args({'placement': placement, 'playMode': playMode, 'level': level, 'params': params}));

  static void loadMRec() => FGBridge.voidCall('loadMRec');

  static void showMRec(String placement, String playMode, num level,
          {FGParams? params, FGMRecPosition? position}) =>
      FGBridge.voidCall('showMRec', {
        ..._args({'placement': placement, 'playMode': playMode, 'level': level, 'params': params}),
        ...?position?.toArgs(),
      });

  static void updateMRecPosition(FGMRecPosition position) =>
      FGBridge.voidCall('updateMRecPosition', position.toArgs());

  static void hideMRec() => FGBridge.voidCall('hideMRec');

  static void destroyMRec() => FGBridge.voidCall('destroyMRec');

  static Future<bool> isMRecReady() => _bool('isMRecReady');

  /// Tắt quảng cáo (sau khi user mua gói remove ads).
  static void removeAds() => FGBridge.voidCall('removeAds');

  // ── RemoteConfig ───────────────────────────────────────────────────────────

  static Future<int> getRemoteConfigInt(String key, int defaultValue) =>
      _int('getRemoteConfigInt', {'key': key, 'default': defaultValue}, defaultValue);

  static Future<bool> getRemoteConfigBool(String key, bool defaultValue) =>
      _bool('getRemoteConfigBool', {'key': key, 'default': defaultValue}, defaultValue);

  static Future<String> getRemoteConfigString(String key, String defaultValue) =>
      _str('getRemoteConfigString', {'key': key, 'default': defaultValue}, defaultValue);

  static Future<bool> isRemoteConfigReady() => _bool('isRemoteConfigReady');

  // ── IAP ────────────────────────────────────────────────────────────────────

  static void activateRemoveAds() => FGBridge.voidCall('activateRemoveAds');

  /// Mua sản phẩm. Trả `(thành công, transactionId)`.
  static Future<({bool ok, String transactionId})> buyProduct(
      String productId, String location, String playMode, int level) async {
    final v = await FGBridge.call('buyProduct', {
      'productId': productId, 'location': location, 'playMode': playMode, 'level': level,
    });
    final list = v is List ? v : const [];
    return (
      ok: list.isNotEmpty && list[0] == true,
      transactionId: list.length > 1 ? (list[1] as String?) ?? '' : '',
    );
  }

  static Future<bool> restorePurchases() => _bool('restorePurchases');

  static Future<bool> productIsPurchased(String productId) =>
      _bool('productIsPurchased', {'productId': productId});

  static Future<int> getProductPurchaseCount(String productId) =>
      _int('getProductPurchaseCount', {'productId': productId}, 0);

  static Future<String> getProductTitle(String productId) =>
      _str('getProductTitle', {'productId': productId});

  static Future<String> getProductPrice(String productId) =>
      _str('getProductPrice', {'productId': productId});

  // ── Deeplink ───────────────────────────────────────────────────────────────

  /// Kết quả deeplink `(scheme, data)`, `null` nếu app không mở từ deeplink.
  static Future<({String scheme, String data})?> getDeeplinkResult() async {
    final v = await FGBridge.call('getDeeplinkResult');
    if (v is! List || v.length < 2) return null;
    return (scheme: (v[0] as String?) ?? '', data: (v[1] as String?) ?? '');
  }

  // ── Event streams ──────────────────────────────────────────────────────────

  static Stream<FGAdsInfo> _info(String e) =>
      FGBridge.raw(e).map((a) => FGAdsInfo.fromMap((a.first as Map).cast<Object?, Object?>()));

  static Stream<String> _placement(String e) =>
      FGBridge.raw(e).map((a) => a.isEmpty ? '' : (a.first as String?) ?? '');

  static Stream<bool> _flag(String e) =>
      FGBridge.raw(e).map((a) => a.isNotEmpty && a.first == true);

  static Stream<String> _one(String e) =>
      FGBridge.raw(e).map((a) => a.isEmpty ? '' : (a.first as String?) ?? '');

  static Stream<({String a, String b})> _pair(String e) => FGBridge.raw(e).map((x) => (
        a: x.isNotEmpty ? (x[0] as String?) ?? '' : '',
        b: x.length > 1 ? (x[1] as String?) ?? '' : '',
      ));

  /// Stream tổng quát cho 1 ad event bất kỳ, vd `onAdEvent('reward', 'completed')`.
  ///
  /// ⚠️ format của Rewarded là `reward` (KHÔNG phải `rewarded`).
  static Stream<FGAdsInfo> onAdEvent(String format, String name) => _info('ad.$format.$name');

  // Interstitial
  static Stream<String> get onInterstitialRequest => _placement('ad.interstitial.request');
  static Stream<FGAdsInfo> get onInterstitialLoaded => _info('ad.interstitial.loaded');
  static Stream<FGAdsInfo> get onInterstitialFailedToLoad => _info('ad.interstitial.failed_to_load');
  static Stream<FGAdsInfo> get onInterstitialShown => _info('ad.interstitial.shown');
  static Stream<FGAdsInfo> get onInterstitialFailedToShow => _info('ad.interstitial.failed_to_show');
  static Stream<FGAdsInfo> get onInterstitialClicked => _info('ad.interstitial.clicked');
  static Stream<FGAdsInfo> get onInterstitialClosed => _info('ad.interstitial.closed');

  // AppOpen
  static Stream<String> get onAppOpenRequest => _placement('ad.app_open.request');
  static Stream<FGAdsInfo> get onAppOpenLoaded => _info('ad.app_open.loaded');
  static Stream<FGAdsInfo> get onAppOpenFailedToLoad => _info('ad.app_open.failed_to_load');
  static Stream<FGAdsInfo> get onAppOpenShown => _info('ad.app_open.shown');
  static Stream<FGAdsInfo> get onAppOpenFailedToShow => _info('ad.app_open.failed_to_show');
  static Stream<FGAdsInfo> get onAppOpenClicked => _info('ad.app_open.clicked');
  static Stream<FGAdsInfo> get onAppOpenClosed => _info('ad.app_open.closed');

  // Rewarded (format = "reward")
  static Stream<String> get onRewardedRequest => _placement('ad.reward.request');
  static Stream<FGAdsInfo> get onRewardedLoaded => _info('ad.reward.loaded');
  static Stream<FGAdsInfo> get onRewardedFailedToLoad => _info('ad.reward.failed_to_load');
  static Stream<FGAdsInfo> get onRewardedShown => _info('ad.reward.shown');
  static Stream<FGAdsInfo> get onRewardedFailedToShow => _info('ad.reward.failed_to_show');
  static Stream<FGAdsInfo> get onRewardedClicked => _info('ad.reward.clicked');
  static Stream<FGAdsInfo> get onRewardedClosed => _info('ad.reward.closed');

  /// User đã xem xong và **đủ điều kiện nhận thưởng** — phát thưởng ở đây.
  static Stream<FGAdsInfo> get onRewardedCompleted => _info('ad.reward.completed');

  // Banner
  static Stream<String> get onBannerRequest => _placement('ad.banner.request');
  static Stream<FGAdsInfo> get onBannerLoaded => _info('ad.banner.loaded');
  static Stream<FGAdsInfo> get onBannerFailedToLoad => _info('ad.banner.failed_to_load');
  static Stream<FGAdsInfo> get onBannerShown => _info('ad.banner.shown');
  static Stream<FGAdsInfo> get onBannerHidden => _info('ad.banner.hidden');
  static Stream<FGAdsInfo> get onBannerClicked => _info('ad.banner.clicked');
  static Stream<FGAdsInfo> get onBannerRevenuePaid => _info('ad.banner.revenue_paid');

  // MRec
  static Stream<String> get onMRecRequest => _placement('ad.mrec.request');
  static Stream<FGAdsInfo> get onMRecLoaded => _info('ad.mrec.loaded');
  static Stream<FGAdsInfo> get onMRecFailedToLoad => _info('ad.mrec.failed_to_load');
  static Stream<FGAdsInfo> get onMRecShown => _info('ad.mrec.shown');
  static Stream<FGAdsInfo> get onMRecHidden => _info('ad.mrec.hidden');
  static Stream<FGAdsInfo> get onMRecClicked => _info('ad.mrec.clicked');
  static Stream<FGAdsInfo> get onMRecRevenuePaid => _info('ad.mrec.revenue_paid');

  // IAP
  static Stream<bool> get onIAPInitialized => _flag('iap.initialized');
  static Stream<String> get onPurchaseProcessing => _one('iap.processing');

  /// `(a: productId, b: transactionId)`
  static Stream<({String a, String b})> get onPurchaseCompleted => _pair('iap.completed');

  /// `(a: productId, b: reason)`
  static Stream<({String a, String b})> get onPurchaseFailed => _pair('iap.failed');

  static Stream<bool> get onRestorePurchasesCompleted => _flag('iap.restored');

  // RemoteConfig
  static Stream<void> get onRemoteConfigFetched => FGBridge.raw('remoteconfig.fetched');
}
