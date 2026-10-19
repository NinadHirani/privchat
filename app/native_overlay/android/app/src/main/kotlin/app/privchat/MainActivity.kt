package app.privchat

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (biometric app lock).
class MainActivity : FlutterFragmentActivity() {
    private var wifiDirect: WifiDirectPlugin? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots & hide content in the recent-apps switcher.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        wifiDirect = WifiDirectPlugin(this, messenger)

        MethodChannel(messenger, "privchat/background").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { MeshService.start(this); result.success(true) }
                "stop" -> { MeshService.stop(this); result.success(true) }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "privchat/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportedAbis" -> {
                    result.success(android.os.Build.SUPPORTED_ABIS.toList())
                }
                else -> result.notImplemented()
            }
        }
        // Multipeer is iOS-only; Dart treats MissingPluginException as "not available".
    }

    override fun onDestroy() {
        wifiDirect?.dispose()
        super.onDestroy()
    }
}
