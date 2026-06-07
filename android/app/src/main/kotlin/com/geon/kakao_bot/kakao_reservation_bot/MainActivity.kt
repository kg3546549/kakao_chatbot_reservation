package com.geon.kakao_bot.kakao_reservation_bot

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {

    // App.kt가 만들어 놓은 캐시 엔진을 재사용 — MainActivity가 죽어도 엔진은 살아있음
    override fun getCachedEngineId(): String = App.ENGINE_ID

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Activity가 열린 동안 currentActivity 참조를 유지해 requestPermission 등이 동작하게 함
        (application as App).currentActivity = WeakReference(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        (application as App).currentActivity = WeakReference(this)
        ForegroundKeepAliveService.start(this)
    }

    override fun onResume() {
        super.onResume()
        ForegroundKeepAliveService.start(this)
    }

    override fun onDestroy() {
        (application as App).currentActivity = null
        super.onDestroy()
    }
}
