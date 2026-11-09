package com.azkar.azkar

import android.app.PendingIntent
import android.app.AlarmManager
import android.app.KeyguardManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import kotlin.math.ceil
import org.json.JSONArray
import org.json.JSONObject

class RemembranceWidgetProvider : AppWidgetProvider() {
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
        if (Build.VERSION.SDK_INT < 31) manager.notifyAppWidgetViewDataChanged(ids, R.id.remembrance_stack)
        scheduleRotation(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ROTATE) {
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (power.isInteractive && !power.isPowerSaveMode && !keyguard.isKeyguardLocked) {
                val manager = AppWidgetManager.getInstance(context)
                manager.getAppWidgetIds(ComponentName(context, RemembranceWidgetProvider::class.java))
                    .forEach { update(context, manager, it, advance = true) }
            }
            scheduleRotation(context)
        } else if (intent.action in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            refreshAll(context)
        }
    }

    override fun onDisabled(context: Context) {
        // A removal broadcast may arrive after a replacement was already bound.
        scheduleRotation(context)
    }

    companion object {
        const val STORE = "azkar_remembrance_widget"
        const val OPEN_CONTENT = "com.azkar.azkar.OPEN_REMEMBRANCE"
        const val ROTATE = "com.azkar.azkar.REMEMBRANCE_ROTATE"
        const val ROTATION_MILLIS = 7000L

        private fun rotationIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 903, Intent(context, RemembranceWidgetProvider::class.java).setAction(ROTATE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        private fun scheduleRotation(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val tick = rotationIntent(context)
            val count = readRemembranceCards(context).length()
            if (count < 2 || manager.getAppWidgetIds(ComponentName(context, RemembranceWidgetProvider::class.java)).isEmpty()) {
                alarm.cancel(tick)
                return
            }
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val delay = if (power.isPowerSaveMode) 60000L else ROTATION_MILLIS
            val at = SystemClock.elapsedRealtime() + delay
            // Non-wakeup alarm: never wake a sleeping phone for a card change.
            if (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()) {
                alarm.setExact(AlarmManager.ELAPSED_REALTIME, at, tick)
            } else {
                alarm.set(AlarmManager.ELAPSED_REALTIME, at, tick)
            }
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, RemembranceWidgetProvider::class.java))
            ids.forEach { update(context, manager, it) }
            if (Build.VERSION.SDK_INT < 31) manager.notifyAppWidgetViewDataChanged(ids, R.id.remembrance_stack)
            scheduleRotation(context)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int, advance: Boolean = false) {
            val views = RemoteViews(context.packageName, R.layout.remembrance_widget_scroll)
            val size = remembranceSize(context, id)
            val cards = readRemembranceCards(context)
            val state = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val positionKey = "position_$id"
            val previous = state.getInt(positionKey, 0).coerceAtLeast(0)
            val position = if (cards.length() == 0) 0 else
                (previous + if (advance) 1 else 0) % cards.length()
            state.edit().putInt(positionKey, position).apply()
            val adapter = Intent(context, RemembranceWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse("azkar-widget://remembrance/$id")
            }
            if (Build.VERSION.SDK_INT >= 31) {
                // A normal vertical collection has no overlapping rear frames.
                // Each full-height row can therefore keep transparent artistic corners.
                val nameCount = remembranceNameCount(cards)
                val items = RemoteViews.RemoteCollectionItems.Builder()
                    .setHasStableIds(true).setViewTypeCount(1)
                for (index in 0 until cards.length()) {
                    val card = cards.getJSONObject(index)
                    items.addItem(remembranceItemId(card, index), remembranceCardView(context, card, size, nameCount))
                }
                views.setRemoteAdapter(R.id.remembrance_stack, items.build())
            } else {
                views.setRemoteAdapter(R.id.remembrance_stack, adapter)
            }
            views.setEmptyView(R.id.remembrance_stack, R.id.remembrance_empty)
            views.setTextViewText(R.id.remembrance_empty, "لا يوجد محتوى ظاهر. اختر النصوص من إعدادات ويدجت الأذكار.")
            val open = Intent(context, MainActivity::class.java).setAction(OPEN_CONTENT)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            views.setPendingIntentTemplate(R.id.remembrance_stack, PendingIntent.getActivity(
                context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            ))
            views.setOnClickPendingIntent(R.id.remembrance_empty, PendingIntent.getActivity(
                context, id + 5000, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            ))
            // Advance cyclically through actual rows; empty/filtered items are
            // removed before indexing. Manual vertical scrolling stays native.
            views.setScrollPosition(R.id.remembrance_stack, position)
            manager.updateAppWidget(id, views)
        }
    }
}

class RemembranceWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = RemembranceViews(applicationContext,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID))
}

private class RemembranceViews(private val context: Context, private val widgetId: Int) : RemoteViewsService.RemoteViewsFactory {
    private var cards = JSONArray()
    private var nameCount = 1
    override fun onCreate() { onDataSetChanged() }
    override fun onDataSetChanged() {
        cards = readRemembranceCards(context)
        nameCount = remembranceNameCount(cards)
    }
    override fun onDestroy() {}
    override fun getCount(): Int = cards.length()
    override fun getViewAt(position: Int): RemoteViews {
        val card = cards.optJSONObject(position) ?: JSONObject()
        return remembranceCardView(context, card, remembranceSize(context, widgetId), nameCount)
    }
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = remembranceItemId(cards.optJSONObject(position) ?: JSONObject(), position)
    override fun hasStableIds(): Boolean = true
}

private fun readRemembranceCards(context: Context): JSONArray = try {
    val raw = context.getSharedPreferences(RemembranceWidgetProvider.STORE, Context.MODE_PRIVATE)
        .getString("content", null)
    val source = if (raw == null) JSONArray() else JSONObject(raw).getJSONArray("cards")
    JSONArray().apply {
        for (index in 0 until source.length()) {
            val card = source.optJSONObject(index) ?: continue
            if (card.optString("text").isNotBlank() || card.optString("deceasedName").isNotBlank()) put(card)
        }
    }
} catch (_: Exception) { JSONArray() }

private fun remembranceItemId(card: JSONObject, position: Int): Long =
    "${card.optString("id")}:$position".fold(1125899906842597L) { hash, char -> hash * 31 + char.code }

private fun remembranceSize(context: Context, widgetId: Int): SizeF =
    RemembranceCardRenderer.widgetSize(context, widgetId)

private fun remembranceNameCount(cards: JSONArray): Int =
    (0 until cards.length()).mapNotNull { cards.optJSONObject(it) }
        .filter { it.optString("deceasedName").isNotBlank() }
        .map { "${it.optString("displayName", it.optString("deceasedName"))}|${it.optString("text")}" }
        .toSet().size.coerceAtLeast(1)

private fun remembranceCardView(context: Context, card: JSONObject, size: SizeF, nameCount: Int): RemoteViews =
    RemoteViews(context.packageName, R.layout.remembrance_widget_surface_card).apply {
        val density = context.resources.displayMetrics.density
        setInt(R.id.remembrance_card, "setMinimumWidth", ceil(size.width * density).toInt())
        setInt(R.id.remembrance_card, "setMinimumHeight", ceil(size.height * density).toInt())
        if (Build.VERSION.SDK_INT >= 31) {
            setViewLayoutHeight(R.id.remembrance_card, size.height, TypedValue.COMPLEX_UNIT_DIP)
        }
        val h = (RemembranceCardRenderer.horizontalPadding(size) * density).toInt()
        val v = (RemembranceCardRenderer.verticalPadding(size) * density).toInt()
        setViewPadding(R.id.remembrance_card_content, h, v, h, v)
        setImageViewBitmap(R.id.remembrance_surface, RemembranceCardRenderer.surface(context, size))
        val name = card.optString("deceasedName")
        val heading = card.optString("dedicationHeading")
        val named = name.isNotBlank() && heading.isNotBlank()
        val displayName = card.optString("displayName").ifBlank {
            if (name.startsWith("\u0627\u0644\u0645\u0631\u062d\u0648\u0645")) name
            else (if (heading.contains("\u0644\u0647\u0627")) "\u0627\u0644\u0645\u0631\u062d\u0648\u0645\u0629 " else "\u0627\u0644\u0645\u0631\u062d\u0648\u0645 ") + name
        }
        val text = card.optString("text")
        val bitmap = if (named) RemembranceCardRenderer.dedication(context, displayName, text, size, nameCount) else null
        setViewVisibility(R.id.remembrance_name_image, if (bitmap != null) View.VISIBLE else View.GONE)
        if (bitmap != null) setImageViewBitmap(R.id.remembrance_name_image, bitmap)
        setContentDescription(R.id.remembrance_name_image, "$displayName\n$text")
        setViewVisibility(R.id.remembrance_text_fallback, if (bitmap == null) View.VISIBLE else View.GONE)
        setViewVisibility(R.id.remembrance_card_title, if (named) View.GONE else View.VISIBLE)
        setTextViewText(R.id.remembrance_card_title, card.optString("title"))
        setViewVisibility(R.id.remembrance_deceased_name, if (named) View.VISIBLE else View.GONE)
        setTextViewText(R.id.remembrance_deceased_name, displayName)
        setTextViewText(R.id.remembrance_card_text, text)
        setViewVisibility(R.id.remembrance_card_text, if (text.isBlank()) View.GONE else View.VISIBLE)
        setOnClickFillInIntent(R.id.remembrance_card, Intent().putExtra("content_route", card.optString("route", "/")))
    }
