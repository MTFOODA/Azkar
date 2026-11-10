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
import org.json.JSONArray
import org.json.JSONObject

class RemembranceWidgetProvider : AppWidgetProvider() {
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
        if (Build.VERSION.SDK_INT < 31) manager.notifyAppWidgetViewDataChanged(id, R.id.remembrance_stack)
        scheduleRotation(context)
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

        @Suppress("DEPRECATION")
        private fun update(context: Context, manager: AppWidgetManager, id: Int, advance: Boolean = false) {
            val views = RemoteViews(context.packageName, R.layout.remembrance_widget_pager)
            val size = remembranceSize(context, id)
            val cards = readRemembranceCards(context)
            val density = context.resources.displayMetrics.density
            val geometry = RemembrancePagerGeometry(size, density)
            views.setImageViewBitmap(R.id.remembrance_widget_surface, RemembranceCardRenderer.surface(context, size))
            views.setViewPadding(R.id.remembrance_pager_frame,
                geometry.insetX, geometry.insetY, geometry.insetX, geometry.insetY)
            // StackView reserves 10% for its rear frames and 4dp per frame edge.
            // Expand the selected frame back into this clipped, opaque viewport.
            // setViewPadding works on older RemoteViews hosts as well as API 31+.
            views.setViewPadding(R.id.remembrance_stack,
                geometry.left, geometry.top, geometry.right, geometry.bottom)
            val adapter = Intent(context, RemembranceWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                // Older launchers cache factories by Intent identity. A new
                // account must never reuse another account's cached rows.
                val account = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
                    .getString("active_account", "signed-out")
                data = Uri.parse("azkar-widget://remembrance/$id/$account")
            }
            if (Build.VERSION.SDK_INT >= 31) {
                val nameCount = remembranceNameCount(cards)
                val items = RemoteViews.RemoteCollectionItems.Builder()
                    .setHasStableIds(true).setViewTypeCount(1)
                for (index in 0 until remembranceAdapterCount(cards.length())) {
                    val cardIndex = remembranceCardIndex(index, cards.length())
                    val card = cards.getJSONObject(cardIndex)
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
            // Relative navigation follows manual swipes instead of resetting to
            // a saved provider index. Navigation actions are discarded when
            // merging partial updates, so keep this in the full cached update.
            if (advance && cards.length() > 1) views.showPrevious(R.id.remembrance_stack)
            manager.updateAppWidget(id, views)
        }
    }
}

class RemembranceWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = RemembranceViews(applicationContext,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID),
        intent.data?.lastPathSegment)
}

private class RemembranceViews(private val context: Context, private val widgetId: Int,
    private val account: String?) : RemoteViewsService.RemoteViewsFactory {
    private var cards = JSONArray()
    private var nameCount = 1
    private fun isActive() = account != null && account ==
        context.getSharedPreferences(RemembranceWidgetProvider.STORE, Context.MODE_PRIVATE)
            .getString("active_account", null)
    override fun onCreate() { onDataSetChanged() }
    override fun onDataSetChanged() {
        cards = if (isActive()) readRemembranceCards(context) else JSONArray()
        nameCount = remembranceNameCount(cards)
    }
    override fun onDestroy() { cards = JSONArray() }
    override fun getCount(): Int = if (isActive()) remembranceAdapterCount(cards.length()) else 0
    override fun getViewAt(position: Int): RemoteViews? {
        if (!isActive() || cards.length() == 0) return null
        val card = cards.getJSONObject(remembranceCardIndex(position, cards.length()))
        return remembranceCardView(context, card, remembranceSize(context, widgetId), nameCount)
    }
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long {
        val index = remembranceCardIndex(position, cards.length())
        return remembranceItemId(cards.optJSONObject(index) ?: JSONObject(), position)
    }
    override fun hasStableIds(): Boolean = true
}

// Native StackView swipes upward with showPrevious(). Keep card zero first and
// reverse the remaining adapter positions so upward movement follows A,B,C,A.
// For tiny collections, provide complete repeated cycles with unique slot IDs.
// StackView otherwise creates a virtual window larger than the adapter itself;
// refreshing that window can leave its selected frame empty at the wrap point.
private fun remembranceAdapterCount(count: Int): Int =
    if (count == 0) 0 else if (count < 6) ((6 + count - 1) / count) * count else count

private fun remembranceCardIndex(position: Int, count: Int): Int {
    if (count == 0) return 0
    // A host may briefly request an old position while a filtered dataset shrinks.
    val current = position.mod(count)
    return if (current == 0) 0 else count - current
}

private fun readRemembranceCards(context: Context): JSONArray = try {
    val store = context.getSharedPreferences(RemembranceWidgetProvider.STORE, Context.MODE_PRIVATE)
    val raw = store.getString("content", null)
    val account = store.getString("active_account", null)
    val payload = if (raw == null) null else JSONObject(raw)
    val source = if (account != null && payload?.optInt("version") == 2 &&
        payload.optString("accountFingerprint") == account) payload.getJSONArray("cards") else JSONArray()
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
        val geometry = RemembrancePagerGeometry(size, density)
        val contentSize = geometry.contentSize
        setInt(R.id.remembrance_card, "setMinimumWidth", geometry.rowWidth)
        setInt(R.id.remembrance_card, "setMinimumHeight", geometry.rowHeight)
        if (Build.VERSION.SDK_INT >= 31) {
            setViewLayoutHeight(R.id.remembrance_card, geometry.rowHeight.toFloat(), TypedValue.COMPLEX_UNIT_PX)
        }
        setViewPadding(R.id.remembrance_card_content, 0, 0, 0, 0)
        setImageViewBitmap(R.id.remembrance_surface, RemembranceCardRenderer.pagerSurface(context, size))
        val name = card.optString("deceasedName")
        val heading = card.optString("dedicationHeading")
        val named = name.isNotBlank() && heading.isNotBlank()
        val displayName = card.optString("displayName").ifBlank {
            if (name.startsWith("\u0627\u0644\u0645\u0631\u062d\u0648\u0645")) name
            else (if (heading.contains("\u0644\u0647\u0627")) "\u0627\u0644\u0645\u0631\u062d\u0648\u0645\u0629 " else "\u0627\u0644\u0645\u0631\u062d\u0648\u0645 ") + name
        }
        val text = card.optString("text")
        val bitmap = if (named) RemembranceCardRenderer.dedication(context, displayName, text, size, nameCount, contentSize) else null
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
