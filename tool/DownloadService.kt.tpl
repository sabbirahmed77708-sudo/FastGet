package __PACKAGE__

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * Keeps SDM alive while files are downloading (also after the app is closed)
 * and shows the download notifications: one per download (percent, MB, speed,
 * Pause / Resume) plus a summary with Pause all / Resume all.
 *
 * The download engine itself runs in Dart; this service only holds the process
 * and draws the notifications. Button presses go back to Dart through [onAction].
 * What is shown (speed, time left, buttons, lock screen, ...) comes from the
 * user's notification settings, which Dart puts into every update.
 */
class DownloadService : Service() {

    companion object {
        const val CHANNEL_PROGRESS = "drom_downloads"
        const val NOTIF_ID = 4711
        const val GROUP = "drom_downloads_group"
        const val EXTRA_KEY = "key"

        const val ACTION_UPDATE = "app.drom.UPDATE"
        const val ACTION_PAUSE = "app.drom.PAUSE_ALL"
        const val ACTION_RESUME = "app.drom.RESUME_ALL"
        const val ACTION_PAUSE_ONE = "app.drom.PAUSE_ONE"
        const val ACTION_RESUME_ONE = "app.drom.RESUME_ONE"

        @Volatile var instance: DownloadService? = null

        /** Set by MainActivity: forwards button presses to Dart. */
        @Volatile var onAction: ((String) -> Unit)? = null

        fun createChannels(ctx: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val progress = NotificationChannel(
                CHANNEL_PROGRESS, "Downloads", NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows download progress"
                setShowBadge(false)
            }
            nm.createNotificationChannel(progress)
        }

        /**
         * Channel for "download finished / failed" notifications. Sound, vibration
         * and pop-up are channel properties on Android 8+, so every combination
         * the user can pick gets its own channel (created when first needed).
         */
        fun doneChannelId(ctx: Context, sound: Boolean, vibrate: Boolean, popup: Boolean): String {
            val id = "drom_done_" + (if (sound) "1" else "0") +
                (if (vibrate) "1" else "0") + (if (popup) "1" else "0")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.getNotificationChannel(id) == null) {
                    val parts = ArrayList<String>()
                    if (sound) parts.add("sound")
                    if (vibrate) parts.add("vibrate")
                    if (popup) parts.add("pop-up")
                    val label = if (parts.isEmpty()) "silent" else parts.joinToString(", ")
                    val ch = NotificationChannel(
                        id,
                        "Finished downloads ($label)",
                        if (popup) NotificationManager.IMPORTANCE_HIGH
                        else NotificationManager.IMPORTANCE_DEFAULT
                    )
                    ch.description = "Tells you when a download finishes or fails"
                    if (!sound) ch.setSound(null, null)
                    ch.enableVibration(vibrate)
                    nm.createNotificationChannel(ch)
                }
            }
            return id
        }

        private fun fill(b: Bundle, m: Map<*, *>) {
            b.putString("title", m["title"] as? String ?: "SDM")
            b.putString("text", m["text"] as? String ?: "")
            b.putInt("progress", (m["progress"] as? Number)?.toInt() ?: 0)
            b.putInt("max", (m["max"] as? Number)?.toInt() ?: 100)
            b.putBoolean("indeterminate", m["indeterminate"] as? Boolean ?: false)
            b.putBoolean("paused", m["paused"] as? Boolean ?: false)
            b.putString("actionLabel", m["actionLabel"] as? String ?: "")
            b.putBoolean("showButtons", m["showButtons"] as? Boolean ?: true)
            b.putBoolean("showProgress", m["showProgress"] as? Boolean ?: true)
            b.putInt(
                "visibility",
                (m["visibility"] as? Number)?.toInt() ?: NotificationCompat.VISIBILITY_PUBLIC
            )
        }

        /** Top-level bundle: the main notification + one bundle per download. */
        fun bundleOf(m: Map<String, Any?>): Bundle {
            val b = Bundle()
            fill(b, m)
            (m["actionKey"] as? String)?.let { b.putString("actionKey", it) }
            val list = ArrayList<Bundle>()
            for (e in (m["items"] as? List<*>) ?: emptyList<Any>()) {
                val im = e as? Map<*, *> ?: continue
                val ib = Bundle()
                fill(ib, im)
                ib.putString("key", im["key"] as? String ?: continue)
                ib.putInt("nid", (im["nid"] as? Number)?.toInt() ?: continue)
                list.add(ib)
            }
            b.putParcelableArrayList("items", list)
            return b
        }

        fun stopNow() {
            instance?.shutdown()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private val shown = HashSet<Int>() // ids of the per-download notifications

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PAUSE -> onAction?.invoke("pauseAll")
            ACTION_RESUME -> onAction?.invoke("resumeAll")
            ACTION_PAUSE_ONE ->
                intent?.getStringExtra(EXTRA_KEY)?.let { onAction?.invoke("pause:$it") }
            ACTION_RESUME_ONE ->
                intent?.getStringExtra(EXTRA_KEY)?.let { onAction?.invoke("resume:$it") }
            ACTION_UPDATE -> {
                val extras = intent?.extras
                try {
                    if (extras != null) show(extras) else ensureForeground()
                } catch (e: Exception) {
                    // e.g. Android refuses a foreground service from the background:
                    // downloads go on in the app process, only the notification is lost
                    stopSelf()
                }
            }
        }
        return START_NOT_STICKY
    }

    /** Must still call startForeground() if we were started with an empty update. */
    private fun ensureForeground() {
        show(bundleOf(mapOf("title" to "SDM", "text" to "")))
    }

    @Suppress("DEPRECATION")
    fun show(b: Bundle) {
        val paused = b.getBoolean("paused")
        val items: List<Bundle> = b.getParcelableArrayList<Bundle>("items") ?: arrayListOf()
        val multi = items.size > 1
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // main notification: a summary when there are several downloads
        val main = build(b, isSummary = multi, isChild = false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, main, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, main)
        }

        // one notification per download, each with its own Pause / Resume
        val now = HashSet<Int>()
        if (multi) {
            for (item in items) {
                val nid = item.getInt("nid")
                now.add(nid)
                nm.notify(nid, build(item, isSummary = false, isChild = true))
            }
        }
        for (old in shown) if (!now.contains(old)) nm.cancel(old)
        shown.clear()
        shown.addAll(now)

        // Keep the CPU awake while bytes are flowing (refreshed on every update).
        if (paused) releaseWakeLock() else holdWakeLock()
    }

    private fun build(b: Bundle, isSummary: Boolean, isChild: Boolean): Notification {
        val paused = b.getBoolean("paused")
        val text = b.getString("text") ?: ""
        val label = b.getString("actionLabel") ?: ""
        val key = b.getString("key") ?: b.getString("actionKey")
        val showButtons = b.getBoolean("showButtons", true)
        val showProgress = b.getBoolean("showProgress", true)

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPi = if (open != null) PendingIntent.getActivity(this, 0, open, flags) else null

        // button: one download (key) or all downloads
        val actionIntent = Intent(this, DownloadService::class.java)
        val reqCode: Int
        if (key != null) {
            actionIntent.action = if (paused) ACTION_RESUME_ONE else ACTION_PAUSE_ONE
            actionIntent.putExtra(EXTRA_KEY, key)
            reqCode = if (isChild) b.getInt("nid") else 2
        } else {
            actionIntent.action = if (paused) ACTION_RESUME else ACTION_PAUSE
            reqCode = 1
        }
        val actionPi = PendingIntent.getService(this, reqCode, actionIntent, flags)

        val builder = NotificationCompat.Builder(this, CHANNEL_PROGRESS)
            .setSmallIcon(
                if (paused) android.R.drawable.ic_media_pause
                else android.R.drawable.stat_sys_download
            )
            .setContentTitle(b.getString("title"))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(b.getInt("visibility", NotificationCompat.VISIBILITY_PUBLIC))
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        if (showButtons && label.isNotEmpty()) {
            builder.addAction(
                if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                label,
                actionPi
            )
        }
        if (openPi != null) builder.setContentIntent(openPi)

        if (isSummary || isChild) {
            builder.setGroup(GROUP)
            builder.setGroupAlertBehavior(NotificationCompat.GROUP_ALERT_SUMMARY)
            if (isSummary) builder.setGroupSummary(true)
        }

        if (!paused && showProgress) {
            builder.setProgress(
                b.getInt("max", 100),
                b.getInt("progress", 0),
                b.getBoolean("indeterminate")
            )
        }
        return builder.build()
    }

    private fun holdWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = wakeLock ?: pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "drom:download")
                .also { it.setReferenceCounted(false); wakeLock = it }
            wl.acquire(10 * 60 * 1000L)
        } catch (_: Exception) {
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
    }

    fun shutdown() {
        releaseWakeLock()
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            for (id in shown) nm.cancel(id)
        } catch (_: Exception) {
        }
        shown.clear()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (instance === this) instance = null
        super.onDestroy()
    }
}
