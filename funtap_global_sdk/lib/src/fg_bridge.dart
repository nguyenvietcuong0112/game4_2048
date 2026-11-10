import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Kênh JS↔native của bản Flutter — mirror 1:1 protocol `FGBridgeCore`
/// đang dùng cho Cocos, chỉ đổi đường truyền (MethodChannel/EventChannel
/// thay cho `jsb.bridge`).
///
/// Protocol GIỮ NGUYÊN nên hành vi giống hệt bản Cocos:
///  - Dart→native : `send(json)` với `{ "m": method, "args": {...}, "cb": id? }`
///  - native→Dart : chuỗi JSON trên EventChannel
///      `{ "e":"ret", "cb":id, "v":<json> }`      → kết quả getter/callback 1 lần
///      `{ "e":"ad.<format>.<name>", "info":… }`  → ad event (info = FGAdsInfo)
///      `{ "e":"iap.<name>", "args":[…] }`        → iap callback
///      `{ "e":"remoteconfig.fetched" }`          → remote config fetched
///
/// Không có native (unit test / web / desktop) → **no-op**, getter trả default,
/// giống cách wrapper Cocos xử lý khi chạy trong editor.
class FGBridge {
  FGBridge._();

  static const MethodChannel _method = MethodChannel('fgsdk');
  static const EventChannel _events = EventChannel('fgsdk/events');

  static int _cbSeq = 0;
  static final Map<String, Completer<Object?>> _cbMap = {};
  static final Map<String, StreamController<List<Object?>>> _controllers = {};

  static bool _installed = false;
  static bool _unavailable = false;
  static bool _warned = false;
  static StreamSubscription<dynamic>? _sub;

  /// Mở kênh sự kiện (idempotent). Gọi lazy ở lần dùng API đầu tiên.
  static void ensureInstalled() {
    if (_installed || _unavailable) return;
    _installed = true;
    try {
      _sub = _events.receiveBroadcastStream().listen(
            _onNative,
            onError: (Object e) => debugPrint('[FGSDK] event channel error: $e'),
          );
    } on MissingPluginException catch (e) {
      _markUnavailable(e);
    }
  }

  static void _markUnavailable(Object e) {
    _unavailable = true;
    for (final c in _cbMap.values) { if (!c.isCompleted) c.complete(null); }
    _cbMap.clear();
    if (!_warned) {
      _warned = true;
      debugPrint('[FGSDK] native không khả dụng ($e) — no-op, getter trả default.');
    }
  }

  static void _onNative(dynamic raw) {
    if (raw is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    final e = decoded['e'];
    if (e is! String) return;

    if (e == 'ret') {
      final cb = decoded['cb'];
      if (cb is String) {
        final c = _cbMap.remove(cb);
        if (c != null && !c.isCompleted) c.complete(decoded['v']);
      }
      return;
    }

    final ctrl = _controllers[e];
    if (ctrl == null || ctrl.isClosed || !ctrl.hasListener) return;
    // `info` (ad event) → 1 phần tử; `args` (iap/…) → list; không có gì → rỗng.
    final payload = decoded.containsKey('info')
        ? <Object?>[decoded['info']]
        : (decoded['args'] is List ? (decoded['args'] as List).cast<Object?>() : const <Object?>[]);
    ctrl.add(payload);
  }

  static void _send(String m, Map<String, Object?>? args, String? cb) {
    ensureInstalled();
    if (_unavailable) return;
    final payload = jsonEncode({'m': m, 'args': args ?? const {}, 'cb': cb});
    // Fire-and-forget: kết quả (nếu có) về qua EventChannel theo `cb`.
    _method.invokeMethod<void>('send', payload).catchError((Object e) {
      if (e is MissingPluginException) {
        _markUnavailable(e);
      } else {
        debugPrint('[FGSDK] send $m lỗi: $e');
      }
    });
  }

  /// Method không có kết quả trả về.
  static void voidCall(String m, [Map<String, Object?>? args]) => _send(m, args, null);

  /// Method có kết quả 1 lần (getter / `show*` / `buy*`).
  ///
  /// ⚠️ KHÔNG đặt timeout — mirror bản Cocos: `showInterstitial` chỉ resolve khi
  /// user đóng quảng cáo, có thể lâu tuỳ ý. Native không trả lời = Future treo,
  /// đúng như Promise bên TS.
  static Future<Object?> call(String m, [Map<String, Object?>? args]) {
    ensureInstalled();
    if (_unavailable) return Future<Object?>.value();
    final id = (++_cbSeq).toString();
    final c = Completer<Object?>();
    _cbMap[id] = c;
    _send(m, args, id);
    return c.future;
  }

  /// Stream thô của 1 event native (payload = list tham số).
  static Stream<List<Object?>> raw(String event) {
    ensureInstalled();
    return _controllers
        .putIfAbsent(event, () => StreamController<List<Object?>>.broadcast())
        .stream;
  }

  /// Chỉ dùng cho test: đóng kênh + xoá state.
  @visibleForTesting
  static Future<void> resetForTest() async {
    await _sub?.cancel();
    _sub = null;
    _installed = false;
    _unavailable = false;
    _cbMap.clear();
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}
