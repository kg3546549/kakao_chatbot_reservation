package com.geon.kakao_bot.kakao_reservation_bot

import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
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
    }

    var currentActivity: WeakReference<MainActivity>? = null

    override fun onCreate() {
        super.onCreate()
        FirebaseApp.initializeApp(this)
        FirebaseCrashlytics.getInstance().log("App.onCreate — 프로세스 시작")
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
}
