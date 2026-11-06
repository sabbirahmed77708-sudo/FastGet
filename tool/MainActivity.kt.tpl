package __PACKAGE__

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Bundle
import android.provider.Settings
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
        const val EXTRA_OPEN = "drom_open"

        private var shareChannel: MethodChannel? = null
        private var notifyChannel: MethodChannel? = null

        @Volatile
        private var pending: String? = null

        @Volatile
        private var pendingOpen: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        val existed = FlutterEngineCache.getInstance().contains(ENGINE_ID)
        if (!existed) createEngine()
        super.onCreate(savedInstanceState)

        // A link shared into the app, or a tapped "download finished" notification,
        // while the Dart side is already running (engine survived) is pushed right
        // away; on a cold start Dart asks for it.
        if (savedInstanceState == null) {
            val text = sharedText(intent)
            if (text != null) {
                if (existed) shareChannel?.invokeMethod("onShared", text) else pending = text
            }
            val open = openKey(intent)
            if (open != null) {
                if (existed) shareChannel?.invokeMethod("onOpen", open) else pendingOpen = open
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

        // Links shared from other apps ("Share" -> DROM) and notification taps.
        val share = MethodChannel(messenger, "drom/share")
        share.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    result.success(pending)
                    pending = null
                }
                "getInitialOpen" -> {
                    result.success(pendingOpen)
                    pendingOpen = null
                }
                else -> result.notImplemented()
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

        // Download notifications + foreground service.
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
                "enabled" -> {
                    result.success(NotificationManagerCompat.from(ctx).areNotificationsEnabled())
                }
                "openSettings" -> {
                    try {
                        val i = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        ctx.startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        notifyChannel = notify
        DownloadService.onAction = { action -> notifyChannel?.invokeMethod("onAction", action) }
    }

    /** "Download complete / failed" (and test) notifications, built from the user's settings. */
    private fun showDone(ctx: Context, m: Map<String, Any?>) {
        try {
            val id = (m["id"] as? Number)?.toInt() ?: return
            val sound = m["sound"] as? Boolean ?: true
            val vibrate = m["vibrate"] as? Boolean ?: true
            val popup = m["popup"] as? Boolean ?: true
            val failed = m["failed"] == true
            val visibility =
                (m["visibility"] as? Number)?.toInt() ?: NotificationCompat.VISIBILITY_PUBLIC
            val channel = DownloadService.doneChannelId(ctx, sound, vibrate, popup)

            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
                // tapping a finished download opens the file
                (m["openKey"] as? String)?.let { putExtra(EXTRA_OPEN, it) }
            }

            var defaults = 0
            if (sound) defaults = defaults or Notification.DEFAULT_SOUND
            if (vibrate) defaults = defaults or Notification.DEFAULT_VIBRATE

            val title = m["title"] as? String ?: "DROM"
            val text = m["text"] as? String ?: ""
            val builder = NotificationCompat.Builder(ctx, channel)
                .setSmallIcon(
                    if (failed) android.R.drawable.stat_notify_error
                    else android.R.drawable.stat_sys_download_done
                )
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
                .setPriority(
                    if (popup) NotificationCompat.PRIORITY_HIGH
                    else NotificationCompat.PRIORITY_DEFAULT
                )
                .setDefaults(defaults)
                .setVisibility(visibility)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
            if (open != null) {
                builder.setContentIntent(PendingIntent.getActivity(ctx, id, open, flags))
            }
            NotificationManagerCompat.from(ctx).notify(id, builder.build())
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
        sharedText(intent)?.let { shareChannel?.invokeMethod("onShared", it) }
        openKey(intent)?.let { shareChannel?.invokeMethod("onOpen", it) }
    }

    // "Share" -> DROM gives the link as text; tapping a link and choosing
    // DROM ("Open with") gives it as the intent data.
    private fun sharedText(i: Intent?): String? {
        if (i == null) return null
        return when (i.action) {
            Intent.ACTION_SEND -> i.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_VIEW -> {
                val u = i.data
                if (u != null && (u.scheme == "http" || u.scheme == "https")) u.toString() else null
            }
            else -> null
        }
    }

    private fun openKey(i: Intent?): String? = i?.getStringExtra(EXTRA_OPEN)
}
