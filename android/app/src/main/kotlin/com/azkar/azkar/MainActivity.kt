package com.azkar.azkar

import io.flutter.embedding.android.FlutterActivity
import android.content.Intent

class MainActivity : FlutterActivity() {
    override fun getInitialRoute(): String? =
        if (intent?.action == PrayerWidgetProvider.OPEN_PRAYER) "/worship"
        else if (intent?.action == RemembranceWidgetProvider.OPEN_CONTENT) contentRoute(intent)
        else super.getInitialRoute()

    private fun contentRoute(intent: Intent): String {
        val route = intent.getStringExtra("content_route") ?: "/"
        return if (route == "/" || route in listOf("/azkar", "/dua", "/dedications") ||
            Regex("^/m/[a-z0-9-]+$").matches(route)) route else "/"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == PrayerWidgetProvider.OPEN_PRAYER) {
            flutterEngine?.navigationChannel?.pushRoute("/worship")
        } else if (intent.action == RemembranceWidgetProvider.OPEN_CONTENT) {
            flutterEngine?.navigationChannel?.pushRoute(contentRoute(intent))
        }
    }

}
