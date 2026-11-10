import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';
import '../firebase_options.dart';

/// Centralized Analytics & Crashlytics Service for Block Order 2048.
/// Strict adherence to Funtap Client Event Tracking Specification (matching FW27):
/// - Events are routed through FGSDK native pipeline (AppsFlyer / MAX)
/// - Events are simultaneously dispatched directly to Firebase Analytics
class AnalyticsService {
  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

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
      debugPrint('[AnalyticsService] Initialized Firebase & Crashlytics successfully.');
    } catch (e, stack) {
      debugPrint('[AnalyticsService] Init failed: $e\n$stack');
    }
  }

  /// Dispatches an event directly to Firebase Analytics
  static void _logToFirebase(String name, [Map<String, Object>? parameters]) {
    if (!_isInitialized) return;
    try {
      Map<String, Object>? cleanedParams;
      if (parameters != null) {
        cleanedParams = {};
        parameters.forEach((key, value) {
          if (value is String || value is num) {
            cleanedParams![key] = value;
          } else if (value is bool) {
            cleanedParams![key] = value ? 1 : 0;
          } else {
            cleanedParams![key] = value.toString();
          }
        });
      }
      FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: cleanedParams,
      );
    } catch (e) {
      debugPrint('[FirebaseAnalytics] Error logging $name: $e');
    }
  }

  // ── 1. loading_start ──────────────────────────────────────────────────────
  /// Trigger khi bắt đầu tiến trình load data/content game.
  static void logLoadingStart({String placement = 'splash'}) {
    try {
      debugPrint('[Analytics] loading_start: placement=$placement');
      FGSDK.logLoadingStart(placement);
      _logToFirebase('loading_start', {
        'placement': placement,
      });
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
      debugPrint('[Analytics] loading_finish: placement=$placement, success=$success, value=${value.toStringAsFixed(2)}s');
      FGSDK.logLoadingEnd(
        placement,
        success,
        value,
        extra: {
          'success': success.toString(),
          'value': value,
        },
      );
      _logToFirebase('loading_finish', {
        'placement': placement,
        'success': success ? 1 : 0,
        'value': value,
      });
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
      debugPrint('[Analytics] logLevelStart: level=$level, playCount=$playCount, loseCount=$loseCount, mode=$playMode');
      FGSDK.logLevelStart(
        level,
        playCount,
        loseCount,
        playMode,
        extra: {
          'level': level,
          'play_count': playCount,
          'lose_count': loseCount,
          'play_mode': playMode,
        },
      );
      _logToFirebase('level_start', {
        'level': level,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_mode': playMode,
      });
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
      debugPrint('[Analytics] logLevelEnd: level=$level, success=$success, duration=${playDuration.toStringAsFixed(1)}s, reason=$reason');
      FGSDK.logLevelEnd(
        level,
        playCount,
        loseCount,
        playMode,
        playDuration,
        success,
        reason,
        extra: {
          'level': level,
          'play_mode': playMode,
          'play_count': playCount,
          'lose_count': loseCount,
          'play_duration': playDuration.toInt(),
          'total_items': totalItems,
          'cleared_items': clearedItems,
          'success': success,
          'reason': reason,
          'ad_duration': adDuration.toInt(),
        },
      );
      _logToFirebase('level_end', {
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_duration': playDuration.toInt(),
        'total_items': totalItems,
        'cleared_items': clearedItems,
        'success': success ? 1 : 0,
        'reason': reason,
        'ad_duration': adDuration.toInt(),
      });
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
      debugPrint('[Analytics] logLevelExit: level=$level, reason=$reason, duration=${playDuration.toStringAsFixed(1)}s');
      FGSDK.logEvent('level_exit', params: {
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_duration': playDuration.toInt(),
        'total_items': totalItems,
        'cleared_items': clearedItems,
        'reason': reason,
      });
      _logToFirebase('level_exit', {
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'play_duration': playDuration.toInt(),
        'total_items': totalItems,
        'cleared_items': clearedItems,
        'reason': reason,
      });
    } catch (e) {
      debugPrint('[Analytics] logLevelExit error: $e');
    }
  }

  // ── 6. level_retry ────────────────────────────────────────────────────────
  static void logLevelRetry({required int level}) {
    try {
      debugPrint('[Analytics] logLevelRetry: level=$level');
      FGSDK.logEvent('level_retry', params: {'level': level});
      _logToFirebase('level_retry', {'level': level});
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
      debugPrint('[Analytics] logLevelReopen: level=$level, items=$clearedItems/$totalItems');
      FGSDK.logEvent('level_reopen', params: {
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'total_items': totalItems,
        'cleared_items': clearedItems,
      });
      _logToFirebase('level_reopen', {
        'level': level,
        'play_mode': playMode,
        'play_count': playCount,
        'lose_count': loseCount,
        'total_items': totalItems,
        'cleared_items': clearedItems,
      });
    } catch (e) {
      debugPrint('[Analytics] logLevelReopen error: $e');
    }
  }

  // ── 7. resource_source ────────────────────────────────────────────────────
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

      debugPrint('[Analytics] resource_source: +$amount $actualName (type=$actualType, reason=$actualReason, balance=$balance)');
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
      _logToFirebase('resource_source', {
        'play_mode': playMode,
        'level': level,
        'type': actualType,
        'name': actualName,
        'amount': amount,
        'reason': actualReason,
        'balance': balance,
      });
    } catch (e) {
      debugPrint('[Analytics] logEarnResource error: $e');
    }
  }

  // ── 8. resource_sink ──────────────────────────────────────────────────────
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

      debugPrint('[Analytics] resource_sink: -$amount $actualName (type=$actualType, reason=$actualReason, balance=$balance)');
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
      _logToFirebase('resource_sink', {
        'play_mode': playMode,
        'level': level,
        'type': actualType,
        'name': actualName,
        'amount': amount,
        'reason': actualReason,
        'balance': balance,
      });
    } catch (e) {
      debugPrint('[Analytics] logSpendResource error: $e');
    }
  }

  // ── 9. tut_action ─────────────────────────────────────────────────────────
  /// Trigger khi user thực hiện action theo tutorial:
  /// name: tut_start (1), action_1 (2), tut_finish (3)
  static void logTutorial({
    required String name,
    required int value,
  }) {
    try {
      debugPrint('[Analytics] tut_action: name=$name, value=$value');
      FGSDK.logTutorial(name, value.toString(), extra: {'name': name, 'value': value});
      _logToFirebase('tut_action', {
        'name': name,
        'value': value,
      });
    } catch (e) {
      debugPrint('[Analytics] logTutorial error: $e');
    }
  }

  // ── 10. mechanic_unlock ───────────────────────────────────────────────────
  static void logMechanicUnlock({required String mechanicId, required int level}) {
    try {
      debugPrint('[Analytics] mechanic_unlock: id=$mechanicId, level=$level');
      FGSDK.logEvent('mechanic_unlock', params: {'mechanic_id': mechanicId, 'level': level});
      _logToFirebase('mechanic_unlock', {'mechanic_id': mechanicId, 'level': level});
    } catch (e) {
      debugPrint('[Analytics] logMechanicUnlock error: $e');
    }
  }

  // ── 11. popup_show ────────────────────────────────────────────────────────
  static void logPopupShow({required String name, required int level}) {
    try {
      debugPrint('[Analytics] popup_show: name=$name, level=$level');
      FGSDK.logEvent('popup_show', params: {'name': name, 'level': level});
      _logToFirebase('popup_show', {'name': name, 'level': level});
    } catch (e) {
      debugPrint('[Analytics] logPopupShow error: $e');
    }
  }

  // ── 12. User Properties ───────────────────────────────────────────────────
  /// Cập nhật User Properties theo chuẩn Sheet FW27:
  /// - current_level, current_mode, connection_type, is_iap_user_n, iap_count_n, balance_coin_n
  static void updateUserProperties({
    int? currentLevel,
    int? highestLevel,
    int? coins,
    int winStreak = 0,
    int loseStreak = 0,
  }) {
    try {
      final props = {
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
      if (_isInitialized) {
        props.forEach((key, value) {
          FirebaseAnalytics.instance.setUserProperty(
            name: key,
            value: value.toString(),
          );
        });
      }
    } catch (e) {
      debugPrint('[Analytics] updateUserProperties error: $e');
    }
  }

  // ── AppsFlyer Events (Sheet 2) ────────────────────────────────────────────
  /// Trigger khi ấn nút bất kỳ theo logic hiển thị Interstitial của game
  static void logAfIntersLogicGame() {
    try {
      debugPrint('[Analytics] af_inters_logicgame (AppsFlyer)');
      FGSDK.logEvent(
        'af_inters_logicgame',
        providers: [FGProviderType.appsFlyer],
      );
      _logToFirebase('af_inters_logicgame');
    } catch (e) {
      debugPrint('[Analytics] logAfIntersLogicGame error: $e');
    }
  }

  /// Trigger khi ấn nút bất kỳ theo logic hiển thị Rewarded của game
  static void logAfRewardedLogicGame() {
    try {
      debugPrint('[Analytics] af_rewarded_logicgame (AppsFlyer)');
      FGSDK.logEvent(
        'af_rewarded_logicgame',
        providers: [FGProviderType.appsFlyer],
      );
      _logToFirebase('af_rewarded_logicgame');
    } catch (e) {
      debugPrint('[Analytics] logAfRewardedLogicGame error: $e');
    }
  }

  /// Trigger khi hoàn thành level lần đầu tiên (param: level: level id)
  static void logAfLevelAchieved({required int level}) {
    try {
      debugPrint('[Analytics] af_level_achieved: level=$level (AppsFlyer)');
      FGSDK.logEvent(
        'af_level_achieved',
        params: {'level': level, 'af_level': level},
        providers: [FGProviderType.appsFlyer],
      );
      _logToFirebase('af_level_achieved', {'level': level});
    } catch (e) {
      debugPrint('[Analytics] logAfLevelAchieved error: $e');
    }
  }
}
