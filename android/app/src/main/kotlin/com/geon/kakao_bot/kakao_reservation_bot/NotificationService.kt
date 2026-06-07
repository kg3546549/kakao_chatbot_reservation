package com.geon.kakao_bot.kakao_reservation_bot

import android.app.Notification
import android.app.RemoteInput
import android.content.ComponentName
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.crashlytics.FirebaseCrashlytics
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class NotificationService : NotificationListenerService() {

    private val TAG = "NotificationService"

    private lateinit var analytics: FirebaseAnalytics
    private lateinit var crashlytics: FirebaseCrashlytics

    companion object {
        var replyActions = mutableMapOf<String, Notification.Action>()
        var instance: NotificationService? = null

        fun requestRebindSafely(context: android.content.Context) {
            requestRebind(ComponentName(context, NotificationService::class.java))
        }
    }

    // ─── 생명주기 ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        instance = this
        analytics = FirebaseAnalytics.getInstance(this)
        crashlytics = FirebaseCrashlytics.getInstance()

        crashlytics.log("NotificationService.onCreate")
        logEvent("service_created")
    }

    override fun onDestroy() {
        crashlytics.log("NotificationService.onDestroy — 서비스 종료됨")
        logEvent("service_destroyed")
        instance = null
        super.onDestroy()
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        crashlytics.log("onListenerConnected — 시스템이 리스너 연결함")
        logEvent("listener_connected")
        Log.d(TAG, "리스너 연결됨")
    }

    override fun onListenerDisconnected() {
        // Doze 모드 등으로 시스템이 언바인드한 경우 — 재연결 요청
        crashlytics.log("onListenerDisconnected — 재연결 요청")
        logEvent("listener_disconnected")
        Log.w(TAG, "리스너 끊김, 재연결 요청")
        requestRebindSafely(this)
        super.onListenerDisconnected()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    // ─── 알림 수신 ────────────────────────────────────────────────────────────

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        if (packageName != "com.kakao.talk") return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        val roomName = if (subText.isNotEmpty()) subText else title
        val senderName = if (subText.isNotEmpty()) title else "Personal Chat"

        // 답장 액션 캐시
        var foundAction: Notification.Action? = null
        val wearExtender = Notification.WearableExtender(sbn.notification)
        for (action in wearExtender.actions) {
            if (action.remoteInputs != null && action.remoteInputs.isNotEmpty()) {
                foundAction = action
                break
            }
        }
        if (foundAction == null && sbn.notification.actions != null) {
            for (action in sbn.notification.actions) {
                if (action.remoteInputs != null && action.remoteInputs.isNotEmpty()) {
                    foundAction = action
                    break
                }
            }
        }
        if (foundAction != null) replyActions[roomName] = foundAction

        // Flutter로 전달
        val messenger = FlutterEngineCache.getInstance()
            .get(App.ENGINE_ID)?.dartExecutor?.binaryMessenger

        if (messenger == null) {
            val msg = "FlutterEngine 없음 — 알림 전달 불가 (room=$roomName)"
            Log.e(TAG, msg)
            crashlytics.log(msg)
            logEvent("engine_missing")
            return
        }

        crashlytics.log("알림 수신: room=$roomName, text=${text.take(30)}")
        MethodChannel(messenger, App.CHANNEL).invokeMethod(
            "onNotification",
            mapOf(
                "roomName" to roomName,
                "senderName" to senderName,
                "message" to text,
                "packageName" to packageName
            )
        )
    }

    // ─── 답장 전송 ────────────────────────────────────────────────────────────

    fun sendReply(roomName: String, message: String): Boolean {
        val action = replyActions[roomName] ?: run {
            val msg = "sendReply 실패 — replyAction 없음: $roomName"
            Log.w(TAG, msg)
            crashlytics.log(msg)
            logEvent("reply_failed", "reason" to "no_action", "room" to roomName)
            return false
        }

        val remoteInput = action.remoteInputs[0]
        val bundle = Bundle().apply {
            putCharSequence(remoteInput.resultKey, message)
        }
        val intent = Intent()
        RemoteInput.addResultsToIntent(action.remoteInputs, intent, bundle)

        return try {
            action.actionIntent.send(applicationContext, 0, intent)
            logEvent("reply_sent", "room" to roomName)
            true
        } catch (e: Exception) {
            Log.e(TAG, "답장 전송 실패", e)
            crashlytics.recordException(e)
            logEvent("reply_failed", "reason" to "exception", "room" to roomName)
            false
        }
    }

    // ─── Firebase Analytics 헬퍼 ─────────────────────────────────────────────

    private fun logEvent(event: String, vararg params: Pair<String, String>) {
        val bundle = Bundle().apply {
            params.forEach { (key, value) -> putString(key, value) }
        }
        analytics.logEvent(event, bundle)
    }
}
