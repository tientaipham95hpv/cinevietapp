package live.cineviet.cineviet_app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val brightnessChannel = "live.cineviet/brightness"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, brightnessChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> {
                    val value = window.attributes.screenBrightness
                    result.success(if (value >= 0f) value.toDouble() else 0.5)
                }
                "set" -> {
                    val value = (call.argument<Double>("value") ?: 0.5).coerceIn(0.0, 1.0).toFloat()
                    val params = window.attributes
                    params.screenBrightness = value
                    window.attributes = params
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
