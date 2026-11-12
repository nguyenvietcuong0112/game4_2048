import 'package:flutter/foundation.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';

/// Remote Config Service for Block Order 2048 Ads & Gameplay parameters.
/// Reads values from Funtap Global SDK with robust defaults matching the ad spec.
class RemoteConfigService {
  RemoteConfigService._();

  // Keys from Ad Specification & Gameplay
  static const String keyInterLevelX = 'Inter_level_x';
  static const String keyAdsInterval = 'Ads_interval';
  static const String keyAoaFormat = 'Aoa_format';
  static const String keyAdsReplay = 'Ads_replay';
  static const String keyAdsResume = 'Ads_resume';
  static const String keyCheatEnable = 'cheat_enable';

  // Cached values with defaults (`cheat_enable` defaults to `false` for store safety!)
  static int _interLevelX = 2; // Show inter from Level 2 onwards
  static int _adsInterval = 25; // 25s cooldown between interstitials
  static bool _aoaFormat = false; // false = AdMob, true = MAX
  static bool _adsReplay = false; // false = Inter, true = Native full screen
  static bool _adsResume = false; // false = AOA, true = Inter
  static bool _isListening = false;
  static final ValueNotifier<bool> cheatEnableNotifier =
      ValueNotifier<bool>(false);

  static int get interLevelX => _interLevelX;
  static int get adsInterval => _adsInterval;
  static bool get aoaFormat => _aoaFormat;
  static bool get adsReplay => _adsReplay;
  static bool get adsResume => _adsResume;
  static bool get cheatEnable => cheatEnableNotifier.value;

  /// Initializes RemoteConfigService and fetches remote configs immediately.
  /// Safe to call regardless of whether `AdsManager.enableAds` is true or false.
  static void init() {
    listenToUpdates();
    fetchConfigs();
  }

  /// Fetch all Remote Configs from FGSDK
  static Future<void> fetchConfigs() async {
    try {
      final isReady = await FGSDK.isRemoteConfigReady();
      debugPrint('[RemoteConfig] isRemoteConfigReady: $isReady');

      _interLevelX = await _fetchInt(keyInterLevelX, 2);
      _adsInterval = await _fetchInt(keyAdsInterval, 25);
      _aoaFormat = await _fetchBool(keyAoaFormat, false);
      _adsReplay = await _fetchBool(keyAdsReplay, false);
      _adsResume = await _fetchBool(keyAdsResume, false);
      final fetchedCheat = await _fetchBool(
        keyCheatEnable,
        await _fetchBool('Cheat_enable', false),
      );
      if (cheatEnableNotifier.value != fetchedCheat) {
        cheatEnableNotifier.value = fetchedCheat;
      }

      debugPrint(
        '[RemoteConfig] Configs loaded -> '
        'interLevelX: $_interLevelX, '
        'adsInterval: ${_adsInterval}s, '
        'aoaFormat: $_aoaFormat, '
        'adsReplay: $_adsReplay, '
        'adsResume: $_adsResume, '
        'cheat_enable: ${cheatEnableNotifier.value}',
      );
    } catch (e) {
      debugPrint('[RemoteConfig] Error fetching remote configs: $e');
    }
  }

  /// Listen to real-time remote config fetched event
  static void listenToUpdates() {
    if (_isListening) return;
    _isListening = true;
    try {
      FGSDK.onRemoteConfigFetched.listen((_) {
        debugPrint('[RemoteConfig] onRemoteConfigFetched triggered, refreshing...');
        fetchConfigs();
      });
    } catch (e) {
      debugPrint('[RemoteConfig] listenToUpdates error: $e');
    }
  }

  @visibleForTesting
  static void setMockValues({
    int? interLevelX,
    int? adsInterval,
    bool? aoaFormat,
    bool? adsReplay,
    bool? adsResume,
    bool? cheatEnable,
  }) {
    if (interLevelX != null) _interLevelX = interLevelX;
    if (adsInterval != null) _adsInterval = adsInterval;
    if (aoaFormat != null) _aoaFormat = aoaFormat;
    if (adsReplay != null) _adsReplay = adsReplay;
    if (adsResume != null) _adsResume = adsResume;
    if (cheatEnable != null) cheatEnableNotifier.value = cheatEnable;
  }

  static Future<bool> _fetchBool(String key, bool defaultValue) async {
    try {
      final s = (await FGSDK.getRemoteConfigString(key, '')).toLowerCase().trim();
      if (s.isEmpty) return defaultValue;
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return await FGSDK.getRemoteConfigBool(key, defaultValue);
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<int> _fetchInt(String key, int defaultValue) async {
    try {
      final s = (await FGSDK.getRemoteConfigString(key, '')).trim();
      if (s.isEmpty) return defaultValue;
      final parsed = int.tryParse(s);
      if (parsed != null) return parsed;
      return await FGSDK.getRemoteConfigInt(key, defaultValue);
    } catch (_) {
      return defaultValue;
    }
  }
}
