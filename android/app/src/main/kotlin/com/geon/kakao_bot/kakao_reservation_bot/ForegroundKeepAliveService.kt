package com.geon.kakao_bot.kakao_reservation_bot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics

class ForegroundKeepAliveService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var analytics: FirebaseAnalytics
    private lateinit var crashlytics: FirebaseCrashlytics

    private val watchdog = object : Runnable {
        override fun run() {
            val listenerEnabled = isNotificationListenerEnabled()
            if (listenerEnabled) {
                NotificationService.requestRebindSafely(this@ForegroundKeepAliveService)
            }

            updateNotification(listenerEnabled)
            analytics.logEvent(
                "keep_alive_tick",
                android.os.Bundle().apply {
                    putString("listener_enabled", listenerEnabled.toString())
                }
            )
            handler.postDelayed(this, WATCHDOG_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        analytics = FirebaseAnalytics.getInstance(this)
        crashlytics = FirebaseCrashlytics.getInstance()

        crashlytics.log("ForegroundKeepAliveService.onCreate")
        startInForeground(isNotificationListenerEnabled())
        handler.post(watchdog)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        updateNotification(isNotificationListenerEnabled())
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        crashlytics.log("ForegroundKeepAliveService.onDestroy")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startInForeground(listenerEnabled: Boolean) {
        createNotificationChannel()
        val notification = buildNotification(listenerEnabled)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                FOREGROUND_NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            )
        } else {
            startForeground(FOREGROUND_NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(listenerEnabled: Boolean) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(FOREGROUND_NOTIFICATION_ID, buildNotification(listenerEnabled))
    }

    private fun buildNotification(listenerEnabled: Boolean): Notification {
        val contentText = if (listenerEnabled) {
            "알림 감시 유지 중"
        } else {
            "알림 접근 권한 필요"
        }

        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("카카오봇 백그라운드 실행 중")
            .setContentText(contentText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "카카오봇 백그라운드 서비스",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "카카오봇을 백그라운드에서 유지합니다"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val listeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        return listeners.contains(ComponentName(this, NotificationService::class.java).flattenToString())
    }

    companion object {
        private const val CHANNEL_ID = "kakao_bot_keep_alive"
        private const val FOREGROUND_NOTIFICATION_ID = 9101
        private const val WATCHDOG_INTERVAL_MS = 5 * 60 * 1000L

        fun start(context: Context) {
            val intent = Intent(context, ForegroundKeepAliveService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ForegroundKeepAliveService::class.java))
        }
    }
}
