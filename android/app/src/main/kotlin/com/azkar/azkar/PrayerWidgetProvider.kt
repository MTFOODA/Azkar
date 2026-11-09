package com.azkar.azkar

import android.app.PendingIntent
import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.text.NumberFormat

class PrayerWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { manager.updateAppWidget(it, render(context, it)) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        manager.updateAppWidget(id, render(context, id))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_MY_PACKAGE_REPLACED, REFRESH)) refreshAll(context)
    }

    override fun onDisabled(context: Context) {
        refreshAll(context)
    }

    companion object {
        const val STORE = "azkar_prayer_widget"
        const val OPEN_PRAYER = "com.azkar.azkar.OPEN_PRAYER"
        private const val REFRESH = "com.azkar.azkar.REFRESH_PRAYER_WIDGET"
        private val prayers = listOf("fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha")
        private val labels = listOf("الفجر", "الشروق", "الظهر", "العصر", "المغرب", "العشاء")
        private val fields = listOf(R.id.widget_fajr, R.id.widget_sunrise, R.id.widget_dhuhr,
            R.id.widget_asr, R.id.widget_maghrib, R.id.widget_isha)

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, PrayerWidgetProvider::class.java))
            if (ids.isEmpty()) {
                (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(tickIntent(context))
                return
            }
            ids.forEach { manager.updateAppWidget(it, render(context, it)) }
        }

        private fun tickIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 902, Intent(context, PrayerWidgetProvider::class.java).setAction(REFRESH),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        private fun scheduleRefresh(context: Context, now: Long, nextPrayer: Long, zone: TimeZone) {
            val midnight = Calendar.getInstance(zone).apply {
                timeInMillis = now
                add(Calendar.DAY_OF_MONTH, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            val triggerAt = minOf(nextPrayer, midnight)
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val tick = tickIntent(context)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || manager.canScheduleExactAlarms()) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, tick)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, tick)
            }
        }

        private fun render(context: Context, id: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.prayer_widget_artistic)
            val size = RemembranceCardRenderer.widgetSize(context, id)
            views.setImageViewBitmap(R.id.prayer_widget_surface, RemembranceCardRenderer.surface(context, size))
            val density = context.resources.displayMetrics.density
            val inset = (RemembranceCardRenderer.horizontalPadding(size) * density).toInt()
            views.setViewPadding(R.id.prayer_widget_content, inset, (4 * density).toInt(), inset, (4 * density).toInt())
            val open = Intent(context, MainActivity::class.java).apply {
                action = OPEN_PRAYER
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(
                context, 901, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))
            views.setTextViewText(R.id.widget_next, "افتح التطبيق واختر موقع الصلاة")
            views.setTextViewText(R.id.widget_gregorian, SimpleDateFormat("d/M/yyyy", Locale("ar")).format(Date()) + " م")
            views.setTextViewText(R.id.widget_hijri, "— هـ")
            fields.forEachIndexed { index, field ->
                views.setTextViewText(field, "${labels[index]}\n—")
            }
            try {
                val stored = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
                    .getString("calendar", null) ?: return views
                val calendar = JSONObject(stored)
                if (calendar.getInt("version") != 1) return views
                val zone = TimeZone.getTimeZone(calendar.getString("timezone"))
                views.setString(R.id.widget_clock, "setTimeZone", zone.id)
                val now = System.currentTimeMillis()
                val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = zone }
                val timeFormat = SimpleDateFormat("HH:mm", Locale("ar")).apply { timeZone = zone }
                val today = dateFormat.format(Date(now))
                val days = calendar.getJSONArray("days")
                var todayTimes: JSONObject? = null
                var hijri: JSONObject? = null
                var nextTime = Long.MAX_VALUE
                var nextName: String? = null
                for (i in 0 until days.length()) {
                    val day = days.getJSONObject(i)
                    val times = day.getJSONObject("times")
                    if (day.getString("date") == today) {
                        todayTimes = times
                        hijri = day.optJSONObject("hijri")
                    }
                    prayers.forEachIndexed { index, prayer ->
                        val time = times.getLong(prayer)
                        if (prayer != "sunrise" && time > now && time < nextTime) {
                            nextTime = time
                            nextName = labels[index]
                        }
                    }
                }
                val gregorianLabel = SimpleDateFormat("d/M/yyyy", Locale("ar")).apply { timeZone = zone }.format(Date(now))
                val digits = NumberFormat.getIntegerInstance(Locale("ar")).apply { isGroupingUsed = false }
                val hijriLabel = hijri?.let {
                    "${digits.format(it.getInt("day"))}/${digits.format(it.getInt("month"))}/${digits.format(it.getInt("year"))} هـ"
                } ?: "— هـ"
                views.setTextViewText(R.id.widget_gregorian, "$gregorianLabel م")
                views.setTextViewText(R.id.widget_hijri, hijriLabel)
                if (todayTimes == null) {
                    views.setTextViewText(R.id.widget_next, "افتح أذكار لتحديث مواقيت اليوم")
                    return views
                }
                fields.forEachIndexed { index, id ->
                    views.setTextViewText(id,
                        "${labels[index]}\n${timeFormat.format(Date(todayTimes.getLong(prayers[index])))}")
                }
                views.setTextViewText(R.id.widget_next, if (nextName != null)
                    "القادمة: $nextName\n${timeFormat.format(Date(nextTime))}"
                    else "افتح أذكار لتحديث الصلاة القادمة")
                scheduleRefresh(context, now, nextTime, zone)
            } catch (_: Exception) {
                views.setTextViewText(R.id.widget_next, "افتح أذكار لتحديث المواقيت")
            }
            return views
        }
    }
}
