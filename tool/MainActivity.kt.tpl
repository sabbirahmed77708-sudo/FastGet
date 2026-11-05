package __PACKAGE__

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * DROM's activity.
 *
 * The Flutter engine (and with it the Dart download engine) is created once,
 * cached, and NOT destroyed when this activity closes. Together with
 * [DownloadService] (a foreground service) this keeps downloads running when the
 * app is in the background or has been swiped away.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val ENGINE_ID = "drom_engine"

        private var shareChannel: MethodChannel? = null
        private var notifyChannel: MethodChannel? = null

        @Volatile
        private var pending: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val existed = FlutterEngineCache.getInstance().contains(ENGINE_ID)
        if (!existed) createEngine()
        super.onCreate(savedInstanceState)

        // A link shared into the app while the Dart side is already running
        // (engine survived) is pushed right away; on a cold start Dart asks for it.
        if (savedInstanceState == null) {
            val text = sharedText(intent)
            if (text != null) {
                if (existed) shareChannel?.invokeMethod("onShared", text) else pending = text
            }
        }
    }

    override fun getCachedEngineId(): String = ENGINE_ID

    // Keep the engine alive after the activity is gone.
    override fun shouldDestroyEngineWithHost(): Boolean = false

    // Plugins and channels are registered once in createEngine().
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {}

    private fun createEngine() {
        val ctx = applicationContext
        val engine = FlutterEngine(ctx)
        GeneratedPluginRegistrant.registerWith(engine)
        setupChannels(ctx, engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    private fun setupChannels(ctx: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        // Links shared from other apps ("Share" -> DROM).
        val share = MethodChannel(messenger, "drom/share")
        share.setMethodCallHandler { call, result ->
            if (call.method == "getInitialText") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        shareChannel = share

        // Wi-Fi only: is the active network Wi-Fi / Ethernet?
        MethodChannel(messenger, "drom/net").setMethodCallHandler { call, result ->
            if (call.method == "isWifi") result.success(onUnmeteredLink(ctx))
            else result.notImplemented()
        }

        // "Share app": path of the installed APK so Dart can share the file itself.
        MethodChannel(messenger, "drom/app").setMethodCallHandler { call, result ->
            if (call.method == "apkPath") result.success(ctx.packageCodePath)
            else result.notImplemented()
        }

        // Download notification + foreground service.
        val notify = MethodChannel(messenger, "drom/notify")
        notify.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    val bundle = DownloadService.bundleOf(map)
                    val svc = DownloadService.instance
                    if (svc != null) {
                        svc.show(bundle)
                        result.success(true)
                    } else {
                        try {
                            val i = Intent(ctx, DownloadService::class.java)
                                .setAction(DownloadService.ACTION_UPDATE)
                                .putExtras(bundle)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ctx.startForegroundService(i)
                            } else {
                                ctx.startService(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                "stop" -> {
                    DownloadService.stopNow()
                    result.success(true)
                }
                "done" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                    showDone(ctx, map)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        notifyChannel = notify
        DownloadService.onAction = { action -> notifyChannel?.invokeMethod("onAction", action) }
    }

    private fun showDone(ctx: Context, m: Map<String, Any?>) {
        try {
            DownloadService.createChannels(ctx)
            val id = (m["id"] as? Number)?.toInt() ?: return
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val n = NotificationCompat.Builder(ctx, DownloadService.CHANNEL_DONE)
                .setSmallIcon(
                    if (m["failed"] == true) android.R.drawable.stat_notify_error
                    else android.R.drawable.stat_sys_download_done
                )
                .setContentTitle(m["title"] as? String ?: "DROM")
                .setContentText(m["text"] as? String ?: "")
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .apply {
                    if (open != null) setContentIntent(PendingIntent.getActivity(ctx, 0, open, flags))
                }
                .build()
            NotificationManagerCompat.from(ctx).notify(id, n)
        } catch (_: Exception) {
            // no notification permission: ignore
        }
    }

    private fun onUnmeteredLink(ctx: Context): Boolean {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(net) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedText(intent) ?: return
        shareChannel?.invokeMethod("onShared", text)
    }

    private fun sharedText(i: Intent?): String? {
        if (i == null || i.action != Intent.ACTION_SEND) return null
        return i.getStringExtra(Intent.EXTRA_TEXT)
    }
}
