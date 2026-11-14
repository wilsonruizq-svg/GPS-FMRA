package com.gpsfmra.gps_fmra

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity requerido por local_auth (huella / biometría).
class MainActivity : FlutterFragmentActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      CHANNEL,
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "startKeepAlive" -> {
          KeepAliveService.start(applicationContext, launchApp = false)
          result.success(true)
        }
        "stopKeepAlive" -> {
          KeepAliveService.stop(applicationContext)
          result.success(true)
        }
        else -> result.notImplemented()
      }
    }
  }

  companion object {
    private const val CHANNEL = "gps_fmra/keep_alive"
  }
}
