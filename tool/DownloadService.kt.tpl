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
 * Keeps DROM alive while files are downloading (also after the app is closed)
 * and shows one notification with percent, MB, speed and Pause / Resume.
 *
 * The download engine itself runs in Dart; this service only holds the process
 * and draws the notification. Button presses go back to Dart through [onAction].
 */
class DownloadService : Service() {

    companion object {
        const val CHANNEL_PROGRESS = "drom_downloads"
        const val CHANNEL_DONE = "drom_done"
        const val NOTIF_ID = 4711

        const val ACTION_UPDATE = "app.drom.UPDATE"
        const val ACTION_PAUSE = "app.drom.PAUSE_ALL"
        const val ACTION_RESUME = "app.drom.RESUME_ALL"

        @Volatile var instance: DownloadService? = null

        /** Set by MainActivity: forwards "pauseAll" / "resumeAll" to Dart. */
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
            val done = NotificationChannel(
                CHANNEL_DONE, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Tells you when a download finishes or fails" }
            nm.createNotificationChannel(progress)
            nm.createNotificationChannel(done)
        }

        fun bundleOf(m: Map<String, Any?>): Bundle {
            val b = Bundle()
            b.putString("title", m["title"] as? String ?: "DROM")
            b.putString("text", m["text"] as? String ?: "")
            b.putInt("progress", (m["progress"] as? Number)?.toInt() ?: 0)
            b.putInt("max", (m["max"] as? Number)?.toInt() ?: 100)
            b.putBoolean("indeterminate", m["indeterminate"] as? Boolean ?: false)
            b.putBoolean("paused", m["paused"] as? Boolean ?: false)
            b.putString("actionLabel", m["actionLabel"] as? String ?: "")
            val lines = (m["lines"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList()
            b.putStringArrayList("lines", ArrayList(lines))
            return b
        }

        fun stopNow() {
            instance?.shutdown()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

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
            ACTION_UPDATE -> {
                val extras = intent?.extras
                if (extras != null) show(extras) else ensureForeground()
            }
        }
        return START_NOT_STICKY
    }

    /** Must still call startForeground() if we were started with an empty update. */
    private fun ensureForeground() {
        show(bundleOf(mapOf("title" to "DROM", "text" to "")))
    }

    fun show(b: Bundle) {
        val paused = b.getBoolean("paused")
        val n = build(b)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, n)
        }
        // Keep the CPU awake while bytes are flowing (refreshed on every update).
        if (paused) releaseWakeLock() else holdWakeLock()
    }

    private fun build(b: Bundle): Notification {
        val paused = b.getBoolean("paused")
        val lines = b.getStringArrayList("lines") ?: arrayListOf()
        val text = b.getString("text") ?: ""
        val label = b.getString("actionLabel") ?: ""

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)

        val open = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val openPi = if (open != null) PendingIntent.getActivity(this, 0, open, flags) else null

        val actionIntent = Intent(this, DownloadService::class.java).apply {
            action = if (paused) ACTION_RESUME else ACTION_PAUSE
        }
        val actionPi = PendingIntent.getService(this, 1, actionIntent, flags)

        val builder = NotificationCompat.Builder(this, CHANNEL_PROGRESS)
            .setSmallIcon(
                if (paused) android.R.drawable.ic_media_pause
                else android.R.drawable.stat_sys_download
            )
            .setContentTitle(b.getString("title"))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(
                if (paused) android.R.drawable.ic_media_play else android.R.drawable.ic_media_pause,
                label,
                actionPi
            )
        if (openPi != null) builder.setContentIntent(openPi)

        if (!paused) {
            builder.setProgress(
                b.getInt("max", 100),
                b.getInt("progress", 0),
                b.getBoolean("indeterminate")
            )
        }

        if (lines.size > 1) {
            val style = NotificationCompat.InboxStyle()
            for (l in lines) style.addLine(l)
            builder.setStyle(style)
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(text))
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
