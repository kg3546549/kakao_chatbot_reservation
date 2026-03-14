package com.geon.kakao_bot.kakao_reservation_bot

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class NotificationService : NotificationListenerService() {
    private val TAG = "NotificationService"
    private val CHANNEL = "com.geon.kakao_bot/notification"

    companion object {
        var replyActions = mutableMapOf<String, Notification.Action>()
        var instance: NotificationService? = null
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        if (packageName != "com.kakao.talk") return

        val extras = sbn.notification.extras
        val title = extras.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        val roomName = if (subText.isNotEmpty()) subText else title
        val senderName = if (subText.isNotEmpty()) title else "Personal Chat"

        // Cache reply action - Search all actions for RemoteInput
        var foundAction: Notification.Action? = null
        
        // 1. Try WearableExtender first
        val wearExtender = Notification.WearableExtender(sbn.notification)
        for (action in wearExtender.actions) {
            if (action.remoteInputs != null && action.remoteInputs.isNotEmpty()) {
                foundAction = action
                break
            }
        }
        
        // 2. Try regular actions if not found
        if (foundAction == null && sbn.notification.actions != null) {
            for (action in sbn.notification.actions) {
                if (action.remoteInputs != null && action.remoteInputs.isNotEmpty()) {
                    foundAction = action
                    break
                }
            }
        }
        
        if (foundAction != null) {
            replyActions[roomName] = foundAction
        }

        // Pass to Flutter
        val data = mapOf(
            "roomName" to roomName,
            "senderName" to senderName,
            "message" to text,
            "packageName" to packageName
        )

        val messenger = FlutterEngineCache.getInstance().get("my_engine_id")?.dartExecutor?.binaryMessenger
        if (messenger != null) {
            MethodChannel(messenger, CHANNEL).invokeMethod("onNotification", data)
        }
    }

    fun sendReply(roomName: String, message: String): Boolean {
        val action = replyActions[roomName] ?: return false
        val remoteInput = action.remoteInputs[0]
        val bundle = Bundle()
        bundle.putCharSequence(remoteInput.resultKey, message)
        
        val intent = Intent()
        RemoteInput.addResultsToIntent(action.remoteInputs, intent, bundle)
        
        try {
            action.actionIntent.send(applicationContext, 0, intent)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send reply", e)
            return false
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }
}
