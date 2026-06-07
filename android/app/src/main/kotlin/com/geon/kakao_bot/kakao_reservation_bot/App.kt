package com.geon.kakao_bot.kakao_reservation_bot

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.os.Build
import android.provider.Settings
import com.google.firebase.FirebaseApp
import com.google.firebase.crashlytics.FirebaseCrashlytics
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class App : Application() {

    companion object {
        const val ENGINE_ID = "my_engine_id"
        const val CHANNEL = "com.geon.kakao_bot/notification"
        const val PREFS = "kakao_reservation_prefs"
        const val BOT_MODE_ENABLED = "bot_mode_enabled"
    }

    var currentActivity: WeakReference<MainActivity>? = null

    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
        FirebaseCrashlytics.getInstance().log("App.onCreate — 프로세스 시작")
        createAdminNotificationChannel()
        initFlutterEngine()
    }

    private fun initFlutterEngine() {
        val engine = FlutterEngine(this)

        // MethodChannel 핸들러를 Dart 실행 전에 등록해야 BotProvider._init() 호출을 받을 수 있음
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission" -> {
                        val cn = Settings.Secure.getString(
                            contentResolver, "enabled_notification_listeners"
                        )
                        result.success(cn != null && cn.contains(packageName))
                    }
                    "checkBatteryOptimization" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestPermission" -> {
                        val activity = currentActivity?.get()
                        if (activity != null) {
                            activity.startActivity(
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            )
                            result.success(null)
                        } else {
                            result.error("NO_ACTIVITY", "앱을 열고 다시 시도해주세요", null)
                        }
                    }
                    "requestBatteryOptimization" -> {
                        val activity = currentActivity?.get()
                        if (activity != null) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            activity.startActivity(intent)
                            result.success(null)
                        } else {
                            result.error("NO_ACTIVITY", "앱을 열고 다시 시도해주세요", null)
                        }
                    }
                    "setBotMode" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        setBotMode(enabled)
                        result.success(null)
                    }
                    "sendReply" -> {
                        val roomName = call.argument<String>("roomName")
                        val message = call.argument<String>("message")
                        if (roomName != null && message != null) {
                            val success =
                                NotificationService.instance?.sendReply(roomName, message) ?: false
                            if (success) {
                                result.success(true)
                            } else {
                                FirebaseCrashlytics.getInstance()
                                    .log("sendReply 실패 — 방 없음: $roomName")
                                result.error(
                                    "REPLY_FAILED",
                                    "답장 액션을 찾을 수 없습니다: $roomName",
                                    null
                                )
                            }
                        } else {
                            result.error("INVALID_ARGUMENT", "roomName 또는 message가 null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        FirebaseCrashlytics.getInstance().log("FlutterEngine 초기화 완료")
    }

    private fun setBotMode(enabled: Boolean) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(BOT_MODE_ENABLED, enabled)
            .apply()

        if (enabled) {
            ForegroundKeepAliveService.start(this)
            NotificationService.requestRebindSafely(this)
        } else {
            ForegroundKeepAliveService.stop(this)
        }
        FirebaseCrashlytics.getInstance().log("Bot mode changed: enabled=$enabled")
    }

    private fun createAdminNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "reservation_updates",
            "예약 알림",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "새 예약과 예약 변경 알림"
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
