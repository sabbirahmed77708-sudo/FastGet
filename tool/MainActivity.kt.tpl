package __PACKAGE__

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Receives text shared from other apps ("Share" -> DROX) and passes it to Dart.
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "drox/share")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "getInitialText") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        pending = sharedText(intent)

        // Wi-Fi only: lets Dart ask whether the active network is Wi-Fi/Ethernet.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "drox/net")
            .setMethodCallHandler { call, result ->
                if (call.method == "isWifi") result.success(onUnmeteredLink())
                else result.notImplemented()
            }
    }

    private fun onUnmeteredLink(): Boolean {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(net) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent) ?: return
        channel?.invokeMethod("onShared", text)
    }

    private fun sharedText(i: Intent?): String? {
        if (i == null || i.action != Intent.ACTION_SEND) return null
        return i.getStringExtra(Intent.EXTRA_TEXT)
    }
}
