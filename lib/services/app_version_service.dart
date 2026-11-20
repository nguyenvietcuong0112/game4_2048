import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Detects and caches the running app's semantic version (`versionName` on
/// Android, `CFBundleShortVersionString` on iOS) via a lightweight native
/// [MethodChannel] — zero external plugin/CocoaPods dependencies required.
class AppVersionService {
  AppVersionService._();

  static const String channelName = 'com.fw.water.block.number.merge/app_info';
  static const String methodGetAppVersion = 'getAppVersion';

  /// Fallback matching `pubspec.yaml` when running on unsupported platforms
  /// (e.g. headless widget tests) or before the native channel responds.
  static const String fallbackVersion = '1.0.1';

  static const String _dartDefineVersion =
      String.fromEnvironment('APP_VERSION');

  static const MethodChannel _channel = MethodChannel(channelName);

  static String _initialVersion() {
    final defined = normalize(_dartDefineVersion);
    return defined.isNotEmpty ? defined : fallbackVersion;
  }

  /// Emits the normalized app version string without leading `v.` (e.g. `'1.0.1'`).
  static final ValueNotifier<String> versionNotifier =
      ValueNotifier<String>(_initialVersion());

  static Future<String>? _initFuture;

  /// Normalized version string without prefix (e.g. `'1.0.1'`).
  static String get version => versionNotifier.value;

  /// Display string for Settings / QA UI (e.g. `'v.1.0.1'`).
  static String get displayLabel => 'v.${versionNotifier.value}';

  /// Strips whitespace and any leading `v` / `v.` prefix so formatting as
  /// `'v.$version'` never duplicates the prefix.
  static String normalize(String? raw) {
    if (raw == null) return '';
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return '';
    cleaned = cleaned.replaceFirst(RegExp(r'^[vV]\.?\s*'), '').trim();
    return cleaned;
  }

  /// Queries the native platform (`PackageInfo.versionName` on Android,
  /// `CFBundleShortVersionString` on iOS) once and updates [versionNotifier].
  static Future<String> init() {
    return _initFuture ??= _fetchFromNative();
  }

  static Future<String> _fetchFromNative() async {
    try {
      final raw = await _channel.invokeMethod<String>(methodGetAppVersion);
      final normalized = normalize(raw);
      if (normalized.isNotEmpty && versionNotifier.value != normalized) {
        versionNotifier.value = normalized;
      }
    } catch (_) {
      // MissingPluginException in tests / desktop builds — keep fallback safely.
    }
    return versionNotifier.value;
  }

  @visibleForTesting
  static void setVersionForTest(String version) {
    final normalized = normalize(version);
    versionNotifier.value =
        normalized.isNotEmpty ? normalized : fallbackVersion;
    _initFuture = Future<String>.value(versionNotifier.value);
  }

  @visibleForTesting
  static void resetForTest() {
    _initFuture = null;
    versionNotifier.value = _initialVersion();
  }
}
