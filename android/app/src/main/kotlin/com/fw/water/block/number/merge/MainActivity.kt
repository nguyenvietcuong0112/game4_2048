package com.fw.water.block.number.merge

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val APP_INFO_CHANNEL = "com.fw.water.block.number.merge/app_info"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_INFO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> result.success(readAppVersionName())
                    else -> result.notImplemented()
                }
            }
    }

    private fun readAppVersionName(): String {
        return try {
            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
            pkgInfo.versionName ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighestRefreshRate()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enableHighestRefreshRate()
        }
    }

    private fun enableHighestRefreshRate() {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return

            val modes = currentDisplay.supportedModes
            if (modes.isEmpty()) return

            val activeMode = currentDisplay.mode
            val sameResModes = modes.filter {
                it.physicalWidth == activeMode.physicalWidth &&
                    it.physicalHeight == activeMode.physicalHeight
            }
            val candidates = sameResModes.ifEmpty { modes.toList() }
            val bestMode = candidates.maxByOrNull { it.refreshRate } ?: return

            val params = window.attributes
            if (params.preferredDisplayModeId != bestMode.modeId ||
                params.preferredRefreshRate != bestMode.refreshRate
            ) {
                params.preferredDisplayModeId = bestMode.modeId
                params.preferredRefreshRate = bestMode.refreshRate
                window.attributes = params
            }
        } catch (_: Exception) {
            // Emulators or virtual devices may not support display mode switching
        }
    }
}
