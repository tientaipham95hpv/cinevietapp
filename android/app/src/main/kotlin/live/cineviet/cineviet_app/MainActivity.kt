package live.cineviet.cineviet_app

import android.content.Context
import android.media.AudioManager
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
                "getVolume" -> {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                    val current = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    result.success(current.toDouble() / max.toDouble())
                }
                "setVolume" -> {
                    val value = (call.argument<Double>("value") ?: 1.0).coerceIn(0.0, 1.0)
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                    val target = (value * max).toInt().coerceIn(0, max)
                    audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
