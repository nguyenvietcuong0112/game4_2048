package com.funtap.global.sdk.flutter

import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.funtap.global.sdk.FGSDK
import com.funtap.global.sdk.HandleDeepLinkIntent
import com.funtap.global.sdk.bridge.FGBridgeCore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Glue MỎNG nối [FGBridgeCore] (cross-platform, dùng chung với 2 bản Cocos) vào kênh
 * Flutter. Tương đương `FGBridge2x` của Cocos 2.4 / `FGBridgeAndroid` của 3.8, chỉ đổi
 * đường truyền:
 *   Dart→native : MethodChannel "fgsdk", method "send", arg = chuỗi JSON `{m,args,cb}`
 *   native→Dart : EventChannel  "fgsdk/events", đẩy chuỗi JSON `{e,…}`
 *
 * Protocol GIỮ NGUYÊN 100% ⇒ hành vi y hệt bản Cocos, KHÔNG đụng logic/quirk SDK.
 */
class FGSDKFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.NewIntentListener {

    private companion object {
        const val METHOD_CHANNEL = "fgsdk"
        const val EVENT_CHANNEL = "fgsdk/events"

        /**
         * Event phát sinh TRƯỚC khi Dart kịp `listen` sẽ được đệm lại rồi flush.
         * Cần vì SDK init sớm (init_sdk / remoteconfig.fetched) có thể bắn trước khi
         * widget tree gắn stream — bản Cocos không cần do bridge cài đồng bộ lúc khởi động.
         */
        const val MAX_PENDING = 64
    }

    private var method: MethodChannel? = null
    private var events: EventChannel? = null
    private val main = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<String>()

    private var activityBinding: ActivityPluginBinding? = null
    private var sdkStarted = false

    // ── FlutterPlugin ─────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        method = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        events = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        method?.setMethodCallHandler(null); method = null
        events?.setStreamHandler(null); events = null
        FGBridgeCore.emit = null
        sink = null
        synchronized(pending) { pending.clear() }
    }

    // ── Dart → native ─────────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "send") { result.notImplemented(); return }
        val json = call.arguments as? String
        if (json == null) {
            result.error("bad_args", "send cần đúng 1 chuỗi JSON", null)
            return
        }
        // Kết quả (nếu có) quay về qua EventChannel dạng {e:"ret",cb,v} — giống bản Cocos.
        FGBridgeCore.handle(json)
        result.success(null)
    }

    // ── native → Dart ─────────────────────────────────────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        this.sink = sink
        if (sink == null) return
        synchronized(pending) {
            while (pending.isNotEmpty()) sink.success(pending.removeFirst())
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    /** EventSink CHỈ được gọi trên main thread; callback SDK có thể ở thread khác. */
    private fun emit(json: String) {
        main.post {
            val s = sink
            if (s != null) {
                s.success(json)
            } else {
                synchronized(pending) {
                    if (pending.size >= MAX_PENDING) pending.removeFirst()
                    pending.addLast(json)
                }
            }
        }
    }

    // ── ActivityAware (SDK cần Activity để init) ──────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        if (sdkStarted) return
        sdkStarted = true
        FGSDK.init(binding.activity)
        FGBridgeCore.emit = { json -> emit(json) }
        FGBridgeCore.start()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()

    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    /** Deeplink / AppsFlyer OneLink (spec §12). */
    override fun onNewIntent(intent: Intent): Boolean {
        FGSDK.HandleDeepLinkIntent(intent)
        return false
    }
}
