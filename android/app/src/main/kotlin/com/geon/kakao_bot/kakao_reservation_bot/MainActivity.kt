package com.geon.kakao_bot.kakao_reservation_bot

import android.app.Notification
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.geon.kakao_bot/notification"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        FlutterEngineCache.getInstance().put("my_engine_id", flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(isNotificationServiceEnabled())
                }
                "requestPermission" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                "checkBatteryOptimization" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryOptimization" -> {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    result.success(null)
                }
                "sendReply" -> {
                    val roomName = call.argument<String>("roomName")
                    val message = call.argument<String>("message")
                    if (roomName != null && message != null) {
                        val success = NotificationService.instance?.sendReply(roomName, message) ?: false
                        if (success) result.success(true) else result.error("REPLY_FAILED", "Could not find reply action for room", null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Room name or message is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val cn = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return cn != null && cn.contains(packageName)
    }
}
