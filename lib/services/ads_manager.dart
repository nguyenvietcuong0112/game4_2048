import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';
import 'analytics_service.dart';
import 'remote_config_service.dart';

/// Specific reason why a Rewarded Ad did not grant a reward, allowing UI layers
/// to surface accurate feedback (`No internet connection!` vs `No ads available!`).
enum RewardedAdFailReason {
  none,
  noInternet,
  noAdsAvailable,
  closedEarly,
  alreadyShowing,
}

/// Central Ad Manager for Block Order 2048.
/// Handles Interstitial, Rewarded, AppOpen (AOA), and Banner ads
/// with strict gating, cooldown countdown (25s), and state synchronization.
class AdsManager {
  AdsManager._();

  /// Master switch to enable or disable ads across the entire app.
  static bool enableAds = false;

  @visibleForTesting
  static bool? mockRewardResult;

  @visibleForTesting
  static RewardedAdFailReason? mockRewardFailReason;

  @visibleForTesting
  static Future<bool> Function()? mockInternetCheck;

  static DateTime? _lastInterOrResumeTime;
  static bool _isShowingAd = false;
  static DateTime? _showingAdStartTime;
  static bool _adWasClicked = false;
  static bool _isRewardedLoaded = false;
  static bool _isAppOpenLoaded = false;
  static bool _isInterLoaded = false;
  static bool _hasShownFirstInter = false;
  static Timer? _retryLoadTimer;
  static int _rewardedRetryAttempt = 0;
  static final List<StreamSubscription> _subscriptions = [];

  static bool get isShowingAd => _isShowingAd;
  static bool get isRewardedLoaded => _isRewardedLoaded;
  static bool get isAppOpenLoaded => _isAppOpenLoaded;
  static bool get isInterLoaded => _isInterLoaded;
  static DateTime? get lastInterOrResumeTime => _lastInterOrResumeTime;

  /// Initializes AdsManager, listens to reward completions and remote config updates
  static void init() {
    // Always initialize RemoteConfigService (including `cheat_enable`) even when `enableAds == false`!
    RemoteConfigService.init();

    if (!enableAds) {
      debugPrint('[AdsManager] Ads are disabled (enableAds = false). Skipping ads initialization.');
      return;
    }

    FGSDK.isInit().then((ready) {
      debugPrint('[AdsManager] 🟢 FGSDK.isInit() status -> $ready');
    }).catchError((e) {
      debugPrint('[AdsManager] 🔴 FGSDK.isInit() error -> $e');
    });

    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();

    // Track ad clicks to prevent App Resume ad collision when returning from external store
    _subscriptions.add(FGSDK.onInterstitialClicked.listen((info) {
      debugPrint('[AdsManager] 👆 onInterstitialClicked: placement=${info.placement} -> marking _adWasClicked = true');
      _adWasClicked = true;
    }));
    _subscriptions.add(FGSDK.onAppOpenClicked.listen((info) {
      debugPrint('[AdsManager] 👆 onAppOpenClicked: placement=${info.placement} -> marking _adWasClicked = true');
      _adWasClicked = true;
    }));
    _subscriptions.add(FGSDK.onRewardedClicked.listen((info) {
      debugPrint('[AdsManager] 👆 onRewardedClicked: placement=${info.placement} -> marking _adWasClicked = true');
      _adWasClicked = true;
    }));

    // Track rewarded ad loading lifecycle
    _subscriptions.add(FGSDK.onRewardedRequest.listen((placement) {
      debugPrint('[AdsManager] 🔄 onRewardedRequest: placement=$placement');
    }));
    _subscriptions.add(FGSDK.onRewardedLoaded.listen((info) {
      debugPrint('[AdsManager] ✅ onRewardedLoaded: placement=${info.placement}, network=${info.networkName}');
      _isRewardedLoaded = true;
      _cancelRetryTimer();
    }));
    _subscriptions.add(FGSDK.onRewardedFailedToLoad.listen((info) {
      debugPrint('[AdsManager] ❌ onRewardedFailedToLoad: placement=${info.placement}, network=${info.networkName}');
      _isRewardedLoaded = false;
      _scheduleRewardedRetry();
    }));
    _subscriptions.add(FGSDK.onRewardedShown.listen((info) {
      debugPrint('[AdsManager] 📺 onRewardedShown: placement=${info.placement}, network=${info.networkName}');
    }));
    _subscriptions.add(FGSDK.onRewardedFailedToShow.listen((info) {
      debugPrint('[AdsManager] ⚠️ onRewardedFailedToShow: placement=${info.placement}, network=${info.networkName}');
    }));
    _subscriptions.add(FGSDK.onRewardedClosed.listen((info) {
      debugPrint('[AdsManager] 🚪 onRewardedClosed: placement=${info.placement}');
      _isRewardedLoaded = false;
      preloadRewarded();
    }));

    // Track AppOpen loading lifecycle
    _subscriptions.add(FGSDK.onAppOpenRequest.listen((placement) {
      debugPrint('[AdsManager] 🔄 onAppOpenRequest: placement=$placement');
    }));
    _subscriptions.add(FGSDK.onAppOpenLoaded.listen((info) {
      debugPrint('[AdsManager] ✅ onAppOpenLoaded: placement=${info.placement}, network=${info.networkName}');
      _isAppOpenLoaded = true;
    }));
    _subscriptions.add(FGSDK.onAppOpenFailedToLoad.listen((info) {
      debugPrint('[AdsManager] ❌ onAppOpenFailedToLoad: placement=${info.placement}, network=${info.networkName}');
      _isAppOpenLoaded = false;
    }));
    _subscriptions.add(FGSDK.onAppOpenShown.listen((info) {
      debugPrint('[AdsManager] 📺 onAppOpenShown: placement=${info.placement}, network=${info.networkName}');
    }));
    _subscriptions.add(FGSDK.onAppOpenFailedToShow.listen((info) {
      debugPrint('[AdsManager] ⚠️ onAppOpenFailedToShow: placement=${info.placement}, network=${info.networkName}');
    }));
    _subscriptions.add(FGSDK.onAppOpenClosed.listen((info) {
      debugPrint('[AdsManager] 🚪 onAppOpenClosed: placement=${info.placement}');
      _isAppOpenLoaded = false;
    }));

    // Track Interstitial loading lifecycle
    _subscriptions.add(FGSDK.onInterstitialRequest.listen((placement) {
      debugPrint('[AdsManager] 🔄 onInterstitialRequest: placement=$placement');
    }));
    _subscriptions.add(FGSDK.onInterstitialLoaded.listen((info) {
      debugPrint('[AdsManager] ✅ onInterstitialLoaded: placement=${info.placement}, network=${info.networkName}');
      _isInterLoaded = true;
    }));
    _subscriptions.add(FGSDK.onInterstitialFailedToLoad.listen((info) {
      debugPrint('[AdsManager] ❌ onInterstitialFailedToLoad: placement=${info.placement}, network=${info.networkName}');
      _isInterLoaded = false;
    }));
    _subscriptions.add(FGSDK.onInterstitialShown.listen((info) {
      debugPrint('[AdsManager] 📺 onInterstitialShown: placement=${info.placement}, network=${info.networkName}');
    }));
    _subscriptions.add(FGSDK.onInterstitialFailedToShow.listen((info) {
      debugPrint('[AdsManager] ⚠️ onInterstitialFailedToShow: placement=${info.placement}, network=${info.networkName}');
    }));
    _subscriptions.add(FGSDK.onInterstitialClosed.listen((info) {
      debugPrint('[AdsManager] 🚪 onInterstitialClosed: placement=${info.placement}');
      _isInterLoaded = false;
    }));

    // Preload rewarded ad
    preloadRewarded();
  }

  /// Safely triggers a background preload for Rewarded Ad
  static void preloadRewarded() {
    if (!enableAds) return;
    try {
      debugPrint('[AdsManager] Preloading Rewarded ad...');
      FGSDK.loadRewarded();
    } catch (e) {
      debugPrint('[AdsManager] Error preloading rewarded ad: $e');
    }
  }

  static void _scheduleRewardedRetry() {
    if (!enableAds) return;
    _retryLoadTimer?.cancel();
    final delaySeconds = (5 * (1 << _rewardedRetryAttempt.clamp(0, 3))).clamp(5, 30);
    _retryLoadTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!enableAds) return;
      debugPrint('[AdsManager] Retrying rewarded ad preload (attempt: $_rewardedRetryAttempt, delay: ${delaySeconds}s)...');
      _rewardedRetryAttempt++;
      preloadRewarded();
    });
  }

  static void _cancelRetryTimer() {
    _retryLoadTimer?.cancel();
    _retryLoadTimer = null;
    _rewardedRetryAttempt = 0;
  }

  /// Whether the minimum interval (cooldown) has elapsed since last Inter / Resume ad
  static bool isCooldownPassed() {
    if (_lastInterOrResumeTime == null) return true;
    final elapsedSeconds = DateTime.now().difference(_lastInterOrResumeTime!).inSeconds;
    final cooldown = RemoteConfigService.adsInterval;
    return elapsedSeconds >= cooldown;
  }

  // ── Interstitial: Endgame ──────────────────────────────────────────────────
  /// Shows Interstitial ad at Endgame on Win or Lose exit.
  static Future<void> showInterEndgame({
    required int levelNumber,
    required VoidCallback onCompleted,
  }) async {
    if (!enableAds) {
      debugPrint('[AdsManager] Ads disabled (enableAds = false) -> skipping Endgame Interstitial.');
      onCompleted();
      return;
    }

    final threshold = RemoteConfigService.interLevelX;
    final isLevelEligible = levelNumber >= threshold;
    final isIntervalPassed = isCooldownPassed();

    debugPrint(
      '[AdsManager] showInterEndgame -> Level: $levelNumber (req >= $threshold: $isLevelEligible), '
      'Cooldown passed: $isIntervalPassed, isInterLoaded: $_isInterLoaded',
    );

    if (!isLevelEligible || !isIntervalPassed || _isShowingAd) {
      if (!isLevelEligible) {
        debugPrint('[AdsManager] ℹ️ Interstitial gated: Level $levelNumber < threshold $threshold');
      } else if (!isIntervalPassed) {
        final elapsed = _lastInterOrResumeTime == null
            ? 0
            : DateTime.now().difference(_lastInterOrResumeTime!).inSeconds;
        debugPrint(
          '[AdsManager] ℹ️ Interstitial gated: Cooldown active (${elapsed}s / ${RemoteConfigService.adsInterval}s)',
        );
      } else if (_isShowingAd) {
        debugPrint('[AdsManager] ℹ️ Interstitial gated: Another ad is currently displaying.');
      }
      onCompleted();
      return;
    }

    _isShowingAd = true;
    _adWasClicked = false;
    bool adShownSuccessfully = false;

    final completer = Completer<void>();
    StreamSubscription? showSub;
    StreamSubscription? closeSub;
    StreamSubscription? failSub;

    void finishAd() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    showSub = FGSDK.onInterstitialShown.listen((info) {
      debugPrint('[AdsManager] 📺 Interstitial displayed on screen! placement=${info.placement}, network=${info.networkName}');
      adShownSuccessfully = true;
    });

    closeSub = FGSDK.onInterstitialClosed.listen((info) {
      debugPrint('[AdsManager] 🚪 Interstitial closed by user. placement=${info.placement}');
      finishAd();
    });

    failSub = FGSDK.onInterstitialFailedToShow.listen((info) {
      debugPrint('[AdsManager] ⚠️ Interstitial failed to show! placement=${info.placement}, network=${info.networkName}');
      finishAd();
    });

    try {
      AnalyticsService.logAfIntersLogicGame();
      debugPrint('[AdsManager] Showing Interstitial (placement: endgame, level: $levelNumber)...');
      await Future.any([
        FGSDK.showInterstitial('endgame', 'classic', levelNumber),
        completer.future,
      ]);
      debugPrint('[AdsManager] showInterstitial call completed (adShownSuccessfully: $adShownSuccessfully)');
      if (adShownSuccessfully) {
        _recordAdCompleted();
      } else {
        debugPrint('[AdsManager] ⚠️ Ad did not actually appear on screen. Cooldown will NOT be penalized.');
      }
    } catch (e) {
      debugPrint('[AdsManager] ❌ Error showing endgame inter: $e');
    } finally {
      await showSub.cancel();
      await closeSub.cancel();
      await failSub.cancel();
      _isShowingAd = false;
      onCompleted();
    }
  }

  // ── Network Reachability Check ───────────────────────────────────────────
  /// Fast internet connectivity check (`< 30ms` when Wi-Fi / Mobile Data is off,
  /// bounded by `1500ms` timeout when on a dead router).
  static Future<bool> checkHasInternet() async {
    if (mockInternetCheck != null) {
      return mockInternetCheck!();
    }
    if (kIsWeb) return true;
    try {
      final result = await Future.any([
        InternetAddress.lookup('google.com'),
        InternetAddress.lookup('one.one.one.one'),
      ]).timeout(const Duration(milliseconds: 1500));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Rewarded Ads ───────────────────────────────────────────────────────────
  /// Shows Rewarded ad for Watch Ad in PowerUpBuyPopup or LoseOverlay Continue.
  static Future<void> showRewardedAd({
    required String placement,
    required int levelNumber,
    required Function(bool success) onRewardResult,
    void Function(RewardedAdFailReason reason)? onAdFailed,
  }) async {
    if (!enableAds) {
      debugPrint('[AdsManager] Ads disabled (enableAds = false) -> granting reward directly for $placement.');
      _recordAdCompleted();
      onRewardResult(true);
      return;
    }

    if (mockRewardResult != null || mockRewardFailReason != null || mockInternetCheck != null) {
      if (mockInternetCheck != null && !(await mockInternetCheck!())) {
        debugPrint('[AdsManager] mockInternetCheck returned false -> reporting noInternet.');
        onAdFailed?.call(RewardedAdFailReason.noInternet);
        onRewardResult(false);
        return;
      }
      if (mockRewardResult != null) {
        debugPrint('[AdsManager] mockRewardResult is set ($mockRewardResult) -> granting mock reward result.');
        if (mockRewardResult == true) {
          _recordAdCompleted();
          onRewardResult(true);
        } else {
          onAdFailed?.call(
            mockRewardFailReason ?? RewardedAdFailReason.noAdsAvailable,
          );
          onRewardResult(false);
        }
        return;
      }
      if (mockRewardFailReason != null &&
          mockRewardFailReason != RewardedAdFailReason.none) {
        onAdFailed?.call(mockRewardFailReason!);
        onRewardResult(false);
        return;
      }
    }

    // 1. Anti-deadlock guard
    if (_isShowingAd) {
      if (_showingAdStartTime != null &&
          DateTime.now().difference(_showingAdStartTime!).inSeconds > 45) {
        debugPrint('[AdsManager] Clearing hung _isShowingAd state after 45s.');
        _isShowingAd = false;
      } else {
        debugPrint('[AdsManager] Ad is already displaying or loading. Ignoring call.');
        onAdFailed?.call(RewardedAdFailReason.alreadyShowing);
        onRewardResult(false);
        return;
      }
    }

    _isShowingAd = true;
    _showingAdStartTime = DateTime.now();
    _adWasClicked = false;

    // 2. Verify active internet connection immediately so offline taps give instant feedback
    final hasInternet = await checkHasInternet();
    if (!hasInternet) {
      debugPrint('[AdsManager] Device is offline -> aborting Rewarded ad with noInternet.');
      _isShowingAd = false;
      _showingAdStartTime = null;
      onAdFailed?.call(RewardedAdFailReason.noInternet);
      onRewardResult(false);
      return;
    }

    AnalyticsService.logAfRewardedLogicGame();

    // 3. Check if Rewarded Ad is already loaded and ready
    bool isReady = false;
    try {
      isReady = await FGSDK.isRewardedReady().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () => false,
      );
    } catch (_) {
      isReady = false;
    }

    // 4. If not ready, request on-demand load and race Loaded vs FailedToLoad (up to 5s)
    if (!isReady) {
      debugPrint('[AdsManager] Rewarded ad not ready. Requesting on-demand load & waiting up to 5s...');
      preloadRewarded();
      try {
        isReady = await Future.any<bool>([
          FGSDK.onRewardedLoaded.first.then((_) => true),
          FGSDK.onRewardedFailedToLoad.first.then((_) => false),
        ]).timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        if (isReady) {
          debugPrint('[AdsManager] Rewarded ad loaded successfully on-demand!');
        }
      } catch (e) {
        debugPrint('[AdsManager] On-demand ad load timed out or failed: $e');
        isReady = false;
      }
    }

    // 5. If still not ready after waiting -> distinguish offline drop vs no ad fill
    if (!isReady) {
      final stillOnline = await checkHasInternet();
      final failReason = stillOnline
          ? RewardedAdFailReason.noAdsAvailable
          : RewardedAdFailReason.noInternet;
      debugPrint('[AdsManager] Rewarded ad unavailable ($failReason). Releasing state.');
      _isShowingAd = false;
      _showingAdStartTime = null;
      onAdFailed?.call(failReason);
      onRewardResult(false);
      return;
    }

    bool rewardEarned = false;
    bool adShown = false;
    bool failedToShow = false;
    final completer = Completer<void>();
    StreamSubscription? closeSub;
    StreamSubscription? failSub;
    StreamSubscription? rewardSub;
    StreamSubscription? showSub;
    Timer? watchdogTimer;

    void finishAd() {
      watchdogTimer?.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    closeSub = FGSDK.onRewardedClosed.listen((_) => finishAd());
    failSub = FGSDK.onRewardedFailedToShow.listen((_) {
      failedToShow = true;
      finishAd();
    });
    rewardSub = FGSDK.onRewardedCompleted.listen((_) {
      rewardEarned = true;
    });

    watchdogTimer = Timer(const Duration(seconds: 6), () {
      debugPrint('[AdsManager] Watchdog: Rewarded ad did not display within 6s. Aborting.');
      failedToShow = true;
      finishAd();
    });

    showSub = FGSDK.onRewardedShown.listen((_) {
      debugPrint('[AdsManager] onRewardedShown: Ad started playing.');
      adShown = true;
      watchdogTimer?.cancel();
      watchdogTimer = Timer(const Duration(seconds: 120), () {
        debugPrint('[AdsManager] Watchdog: Rewarded ad playback exceeded 120s.');
        finishAd();
      });
    });

    try {
      debugPrint('[AdsManager] Showing Rewarded ad (placement: $placement, level: $levelNumber)...');
      await Future.any([
        FGSDK.showRewarded(placement, 'classic', levelNumber),
        completer.future,
      ]);
    } catch (e) {
      debugPrint('[AdsManager] Error showing rewarded ad: $e');
      failedToShow = true;
    } finally {
      watchdogTimer?.cancel();
      await closeSub.cancel();
      await failSub.cancel();
      await rewardSub.cancel();
      await showSub.cancel();
      _isShowingAd = false;
      _showingAdStartTime = null;

      if (rewardEarned) {
        _recordAdCompleted();
        onRewardResult(true);
      } else {
        final reason = (failedToShow || !adShown)
            ? RewardedAdFailReason.noAdsAvailable
            : RewardedAdFailReason.closedEarly;
        onAdFailed?.call(reason);
        onRewardResult(false);
      }

      // Preload next rewarded ad in background
      preloadRewarded();
    }
  }

  // ── Splash Ads (AOA or Inter on cold start) ──────────────────────────────
  static Future<void> showSplashAd({int timeoutMs = 1800}) async {
    if (!enableAds) return;

    final showInter = RemoteConfigService.adsResume;
    debugPrint('[AdsManager] showSplashAd: Requesting Splash ad (format: ${showInter ? "Inter" : "AOA"})...');

    final waitStart = DateTime.now();
    while ((showInter ? !_isInterLoaded : !_isAppOpenLoaded) &&
        DateTime.now().difference(waitStart).inMilliseconds < timeoutMs) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    final isReady = showInter ? _isInterLoaded : _isAppOpenLoaded;
    if (!isReady) {
      debugPrint('[AdsManager] Splash ad not ready within timeout -> proceeding to game.');
      return;
    }

    final completer = Completer<void>();
    StreamSubscription? closeSub;
    StreamSubscription? failSub;

    void finishAd() {
      if (!completer.isCompleted) completer.complete();
    }

    if (showInter) {
      closeSub = FGSDK.onInterstitialClosed.listen((_) => finishAd());
      failSub = FGSDK.onInterstitialFailedToShow.listen((_) => finishAd());
    } else {
      closeSub = FGSDK.onAppOpenClosed.listen((_) => finishAd());
      failSub = FGSDK.onAppOpenFailedToShow.listen((_) => finishAd());
    }

    try {
      _isShowingAd = true;
      if (showInter) {
        AnalyticsService.logAfIntersLogicGame();
        FGSDK.showInterstitial('splash', 'classic', 1);
      } else {
        FGSDK.showAppOpen('splash', 'classic', 1);
      }
      await completer.future.timeout(const Duration(seconds: 6), onTimeout: () {});
      _recordAdCompleted();
    } catch (e) {
      debugPrint('[AdsManager] Error showing splash ad: $e');
    } finally {
      await closeSub.cancel();
      await failSub.cancel();
      _isShowingAd = false;
    }
  }

  // ── Resume Ads (AOA or Inter on App Resume) ───────────────────────────────
  static Future<void> handleAppResume({int currentLevel = 1}) async {
    preloadRewarded();

    if (!enableAds) return;
    if (_isShowingAd) return;

    if (_adWasClicked) {
      _adWasClicked = false;
      return;
    }

    if (!_hasShownFirstInter) {
      debugPrint('[AdsManager] Resume ad gated: user has not seen first Inter yet.');
      return;
    }

    if (!isCooldownPassed()) {
      debugPrint('[AdsManager] Resume ad gated: cooldown not reached yet.');
      return;
    }

    _isShowingAd = true;
    final showInter = RemoteConfigService.adsResume;
    final completer = Completer<void>();
    StreamSubscription? closeSub;
    StreamSubscription? failSub;

    void finishAd() {
      if (!completer.isCompleted) completer.complete();
    }

    if (showInter) {
      closeSub = FGSDK.onInterstitialClosed.listen((_) => finishAd());
      failSub = FGSDK.onInterstitialFailedToShow.listen((_) => finishAd());
    } else {
      closeSub = FGSDK.onAppOpenClosed.listen((_) => finishAd());
      failSub = FGSDK.onAppOpenFailedToShow.listen((_) => finishAd());
    }

    try {
      if (showInter) {
        AnalyticsService.logAfIntersLogicGame();
        FGSDK.showInterstitial('resume', 'classic', currentLevel);
      } else {
        FGSDK.showAppOpen('resume', 'classic', currentLevel);
      }
      await completer.future.timeout(const Duration(seconds: 15), onTimeout: () {});
      _recordAdCompleted();
    } catch (e) {
      debugPrint('[AdsManager] Error showing resume ad: $e');
    } finally {
      await closeSub.cancel();
      await failSub.cancel();
      _isShowingAd = false;
    }
  }

  // ── Banner Ads ─────────────────────────────────────────────────────────────
  static void showBanner(String placement, {int level = 1}) {
    if (!enableAds) return;
    try {
      FGSDK.showBanner(placement, 'classic', level);
    } catch (e) {
      debugPrint('[AdsManager] Error showing banner: $e');
    }
  }

  static void hideBanner() {
    if (!enableAds) return;
    try {
      FGSDK.hideBanner();
    } catch (e) {
      debugPrint('[AdsManager] Error hiding banner: $e');
    }
  }

  static void _recordAdCompleted() {
    _lastInterOrResumeTime = DateTime.now();
    _hasShownFirstInter = true;
    debugPrint('[AdsManager] Ad completed. Cooldown reset to now ($_lastInterOrResumeTime).');
  }
}
