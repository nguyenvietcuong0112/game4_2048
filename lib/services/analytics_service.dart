import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';
import '../firebase_options.dart';

/// Centralized Analytics & Crashlytics Service for Block Order 2048.
/// Strict adherence to Funtap Client Event Tracking Specification (FW37):
/// - `FGSDK` (`funtap_global_sdk`) natively dispatches directly to Firebase Analytics
///   (`FGFirebaseProvider` — including early-boot event buffering before SDK ready)
///   and automatically mirrors MAX / AppLovin events (`FGAppLovinEventMapper`).
/// - Do NOT call `FirebaseAnalytics.instance.logEvent` alongside `FGSDK`, otherwise
///   every event is logged twice in Firebase DebugView!
class AnalyticsService {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  /// Optional test observer invoked synchronously whenever an analytics event is emitted.
  @visibleForTesting
  static void Function(String eventName, Map<String, Object?> params)?
      debugEventObserver;

  static void _notifyDebugObserver(
    String eventName,
    Map<String, Object?> params,
  ) {
    debugEventObserver?.call(eventName, Map<String, Object?>.unmodifiable(params));
  }

  /// Initialize Firebase Core & Crashlytics for error reporting.
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Pass framework errors to Crashlytics as non-fatal diagnostics
      FlutterError.onError = (errorDetails) {
        if (errorDetails.silent) return;
        FirebaseCrashlytics.instance.recordFlutterError(errorDetails);
      };

      // Pass all uncaught asynchronous errors to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      _isInitialized = true;
      debugPrint(
        '[AnalyticsService] Initialized Firebase Core & Crashlytics successfully.',
      );
    } catch (e, stack) {
      debugPrint('[AnalyticsService] Init failed: $e\n$stack');
    }
  }

  // ── 1. loading_start ──────────────────────────────────────────────────────
  /// Trigger khi bắt đầu tiến trình load data/content game.
  static void logLoadingStart({String placement = 'splash'}) {
    try {
      debugPrint('[Analytics] loading_start: placement=$placement');
      _notifyDebugObserver('loading_start', {'placement': placement});
      FGSDK.logLoadingStart(placement);
    } catch (e) {
      debugPrint('[Analytics] logLoadingStart error: $e');
    }
  }

  // ── 2. loading_finish ─────────────────────────────────────────────────────
  /// Trigger khi kết thúc tiến trình load data/content game.
  static void logLoadingFinish({
    String placement = 'splash',
    bool success = true,
    required double value,
  }) {
    try {
      debugPrint(
        '[Analytics] loading_finish: placement=$placement, success=$success, value=${value.toStringAsFixed(2)}s',
      );
      _notifyDebugObserver('loading_finish', {
        'placement': placement,
        'is_load': success ? 1 : 0,
        'success': success.toString(),
        'value': value,
      });
      FGSDK.logLoadingEnd(
        placement,
        success,
        value,
        extra: {
          'success': success.toString(),
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logLoadingFinish error: $e');
    }
  }

  // ── 3. level_start ────────────────────────────────────────────────────────
  /// Trigger khi user bắt đầu chơi 1 level.
  /// Params: level (Number), play_count (Number), lose_count (Number), play_mode (String = "default")
  static void logLevelStart({
    required int level,
    int playCount = 1,
    int loseCount = 0,
    String playMode = 'default',
  }) {
    try {
      debugPrint(
        '[Analytics] logLevelStart: level=$level, playCount=$playCount, loseCount=$loseCount, mode=$playMode',
      );
      _notifyDebugObserver('level_start', {
        'level': level,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_mode': playMode,
      });
      FGSDK.logLevelStart(
        level,
        playCount,
        loseCount,
        playMode,
      );
    } catch (e) {
      debugPrint('[Analytics] logLevelStart error: $e');
    }
  }

  // ── 4. level_end ──────────────────────────────────────────────────────────
  /// Trigger khi user kết thúc màn chơi (thắng hoặc thua).
  /// Params: level, play_mode, play_count, lose_count, play_duration, total_items, cleared_items, success, reason, ad_duration
  static void logLevelEnd({
    required int level,
    int playCount = 1,
    int loseCount = 0,
    required double playDuration,
    int totalItems = 1,
    int clearedItems = 1,
    required bool success,
    required String reason,
    double adDuration = 0.0,
    String playMode = 'default',
  }) {
    try {
      debugPrint(
        '[Analytics] logLevelEnd: level=$level, success=$success, duration=${playDuration.toStringAsFixed(1)}s, reason=$reason',
      );
      _notifyDebugObserver('level_end', {
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_duration': playDuration.toInt(),
        'total_items': totalItems,
        'cleared_items': clearedItems,
        'success': success.toString(),
        'reason': reason,
        'ad_duration': adDuration.toInt(),
      });
      // Keep native `success` string ("true"/"false") intact so `FGAppLovinEventMapper`
      // derives `level_complete` on win!
      FGSDK.logLevelEnd(
        level,
        playCount,
        loseCount,
        playMode,
        playDuration,
        success,
        reason,
        extra: {
          'play_duration': playDuration.toInt(),
          'total_items': totalItems,
          'cleared_items': clearedItems,
          'ad_duration': adDuration.toInt(),
        },
      );
    } catch (e) {
      debugPrint('[Analytics] logLevelEnd error: $e');
    }
  }

  // ── 5. level_exit ─────────────────────────────────────────────────────────
  /// Trigger khi user đang trong level và thoát game (menu, settings, restart)
  static void logLevelExit({
    required int level,
    int playCount = 1,
    int loseCount = 0,
    required double playDuration,
    int totalItems = 1,
    int clearedItems = 0,
    required String reason,
    String playMode = 'default',
  }) {
    try {
      debugPrint(
        '[Analytics] logLevelExit: level=$level, reason=$reason, duration=${playDuration.toStringAsFixed(1)}s',
      );
      final params = <String, Object>{
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_duration': playDuration.toInt(),
        'total_items': totalItems,
        'cleared_items': clearedItems,
        'reason': reason,
      };
      _notifyDebugObserver('level_exit', params);
      FGSDK.logEvent('level_exit', params: params);
    } catch (e) {
      debugPrint('[Analytics] logLevelExit error: $e');
    }
  }

  // ── 6. level_retry ────────────────────────────────────────────────────────
  static void logLevelRetry({required int level}) {
    try {
      debugPrint('[Analytics] logLevelRetry: level=$level');
      _notifyDebugObserver('level_retry', {'level': level});
      FGSDK.logEvent('level_retry', params: {'level': level});
    } catch (e) {
      debugPrint('[Analytics] logLevelRetry error: $e');
    }
  }

  // ── 7. level_reopen ───────────────────────────────────────────────────────
  /// Trigger khi user quay trở lại game sau khi minimize (level được resume/load lại).
  /// Params: level, play_mode, play_count, lose_count, total_items, cleared_items
  static void logLevelReopen({
    required int level,
    int playCount = 1,
    int loseCount = 0,
    int totalItems = 1,
    int clearedItems = 0,
    String playMode = 'default',
  }) {
    try {
      debugPrint(
        '[Analytics] logLevelReopen: level=$level, items=$clearedItems/$totalItems',
      );
      final params = <String, Object>{
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'total_items': totalItems,
        'cleared_items': clearedItems,
      };
      _notifyDebugObserver('level_reopen', params);
      FGSDK.logEvent('level_reopen', params: params);
    } catch (e) {
      debugPrint('[Analytics] logLevelReopen error: $e');
    }
  }

  // ── 8. resource_source ────────────────────────────────────────────────────
  /// Trigger khi user nhận được tài nguyên bất kỳ.
  /// Params: play_mode, level, type (currency / booster), name (coins, level_up, time_freeze), amount, reason (win_level, rewarded_ad, buy_pack), balance
  static void logEarnResource({
    required int level,
    String? type,
    String? name,
    required double amount,
    required String reason,
    required double balance,
    String playMode = 'default',
  }) {
    try {
      final actualType = type ?? 'currency';
      final actualName = name ?? 'coins';
      final actualReason = reason.isNotEmpty ? reason : 'win_level';

      debugPrint(
        '[Analytics] resource_source: +$amount $actualName (type=$actualType, reason=$actualReason, balance=$balance)',
      );
      _notifyDebugObserver('resource_source', {
        'play_mode': playMode,
        'level': level,
        'type': actualType,
        'name': actualName,
        'amount': amount,
        'reason': actualReason,
        'balance': balance,
      });
      FGSDK.logEarnResource(
        playMode,
        level,
        actualType,
        actualName,
        amount,
        actualReason,
        actualName,
        '',
        balance,
        extra: {'reason': actualReason, 'type': actualType},
      );
    } catch (e) {
      debugPrint('[Analytics] logEarnResource error: $e');
    }
  }

  // ── 9. resource_sink ──────────────────────────────────────────────────────
  /// Trigger khi user sử dụng tài nguyên bất kỳ.
  /// Params: play_mode, level, type (currency / booster), name (coins, level_up, time_freeze), amount, reason (gameplay, buy_booster_pack, play_on), balance
  static void logSpendResource({
    required int level,
    String? type,
    String? name,
    required double amount,
    required String reason,
    required double balance,
    String playMode = 'default',
  }) {
    try {
      final actualType = type ?? 'currency';
      final actualName = name ?? 'coins';
      final actualReason = reason.isNotEmpty ? reason : 'gameplay';

      debugPrint(
        '[Analytics] resource_sink: -$amount $actualName (type=$actualType, reason=$actualReason, balance=$balance)',
      );
      _notifyDebugObserver('resource_sink', {
        'play_mode': playMode,
        'level': level,
        'type': actualType,
        'name': actualName,
        'amount': amount,
        'reason': actualReason,
        'balance': balance,
      });
      FGSDK.logSpendResource(
        playMode,
        level,
        actualType,
        actualName,
        amount,
        actualReason,
        actualReason,
        actualName,
        '',
        balance,
        extra: {'reason': actualReason, 'type': actualType},
      );
    } catch (e) {
      debugPrint('[Analytics] logSpendResource error: $e');
    }
  }

  // ── 10. tut_action ────────────────────────────────────────────────────────
  /// Trigger theo đúng thứ tự phễu FTUE (First-Time User Experience):
  /// - `ftue_loading_start` (1) -> `ftue_loading_finish` (2) -> `tut_start` (3)
  ///   -> `action_1` (4) -> `action_2` (5) -> `action_3` (6) -> `tut_finish` (7)
  static void logTutorial({
    required String name,
    required int value,
  }) {
    try {
      debugPrint('[Analytics] tut_action: name=$name, value=$value');
      _notifyDebugObserver('tut_action', {'name': name, 'value': value});
      FGSDK.logTutorial(
        name,
        value.toString(),
        extra: {'value': value},
      );
    } catch (e) {
      debugPrint('[Analytics] logTutorial error: $e');
    }
  }

  // ── 11. mechanic_unlock ───────────────────────────────────────────────────
  static void logMechanicUnlock({
    required String mechanicId,
    required int level,
  }) {
    try {
      debugPrint('[Analytics] mechanic_unlock: id=$mechanicId, level=$level');
      final params = <String, Object>{
        'mechanic_id': mechanicId,
        'level': level,
      };
      _notifyDebugObserver('mechanic_unlock', params);
      FGSDK.logEvent('mechanic_unlock', params: params);
    } catch (e) {
      debugPrint('[Analytics] logMechanicUnlock error: $e');
    }
  }

  // ── 12. popup_show ────────────────────────────────────────────────────────
  static void logPopupShow({required String name, required int level}) {
    try {
      debugPrint('[Analytics] popup_show: name=$name, level=$level');
      final params = <String, Object>{'name': name, 'level': level};
      _notifyDebugObserver('popup_show', params);
      FGSDK.logEvent('popup_show', params: params);
    } catch (e) {
      debugPrint('[Analytics] logPopupShow error: $e');
    }
  }

  // ── 13. User Properties ───────────────────────────────────────────────────
  /// Cập nhật User Properties qua `FGSDK.setUserProperties` (tự động set lên Firebase).
  static void updateUserProperties({
    int? currentLevel,
    int? highestLevel,
    int? coins,
    int winStreak = 0,
    int loseStreak = 0,
  }) {
    try {
      final props = <String, Object>{
        'current_level': currentLevel ?? 1,
        'current_mode': 'default',
        'connection_type': 'online',
        'is_iap_user_n': 0,
        'iap_count_n': 0,
        'win_streak_n': winStreak,
        'lose_streak_n': loseStreak,
        'balance_coin_n': coins ?? 0,
      };

      debugPrint('[Analytics] setUserProperties: $props');
      FGSDK.setUserProperties(props);
    } catch (e) {
      debugPrint('[Analytics] updateUserProperties error: $e');
    }
  }

  // ── AppsFlyer Events (Sheet 2) ────────────────────────────────────────────
  /// Trigger khi ấn nút bất kỳ theo logic hiển thị Interstitial của game
  static void logAfIntersLogicGame() {
    try {
      debugPrint('[Analytics] af_inters_logicgame (AppsFlyer)');
      _notifyDebugObserver('af_inters_logicgame', const {});
      FGSDK.logEvent(
        'af_inters_logicgame',
        providers: [FGProviderType.appsFlyer],
      );
    } catch (e) {
      debugPrint('[Analytics] logAfIntersLogicGame error: $e');
    }
  }

  /// Trigger khi ấn nút bất kỳ theo logic hiển thị Rewarded của game
  static void logAfRewardedLogicGame() {
    try {
      debugPrint('[Analytics] af_rewarded_logicgame (AppsFlyer)');
      _notifyDebugObserver('af_rewarded_logicgame', const {});
      FGSDK.logEvent(
        'af_rewarded_logicgame',
        providers: [FGProviderType.appsFlyer],
      );
    } catch (e) {
      debugPrint('[Analytics] logAfRewardedLogicGame error: $e');
    }
  }

  /// Trigger khi hoàn thành level lần đầu tiên (param: level: level id)
  static void logAfLevelAchieved({required int level}) {
    try {
      debugPrint('[Analytics] af_level_achieved: level=$level (AppsFlyer)');
      final params = <String, Object>{'level': level, 'af_level': level};
      _notifyDebugObserver('af_level_achieved', params);
      FGSDK.logEvent(
        'af_level_achieved',
        params: params,
        providers: [FGProviderType.appsFlyer],
      );
    } catch (e) {
      debugPrint('[Analytics] logAfLevelAchieved error: $e');
    }
  }
}
