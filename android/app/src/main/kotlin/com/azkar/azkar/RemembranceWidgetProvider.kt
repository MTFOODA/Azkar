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
import android.content.res.Configuration
import android.util.SizeF
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.LruCache
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
            // StackView keeps the manually selected position; showNext advances
            // from that actual position instead of resetting the adapter.
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
            val views = RemoteViews(context.packageName, R.layout.remembrance_widget_single)
            val size = remembranceSize(context, id)
            if (Build.VERSION.SDK_INT >= 31) {
                // StackView reserves 10% for perspective and 4dp per frame edge.
                // Enlarge its canvas, then align the front card with the viewport.
                val stackWidth = (size.width + 8f) / 0.9f
                val stackHeight = (size.height + 8f) / 0.9f
                views.setViewLayoutWidth(R.id.remembrance_stack, stackWidth, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutHeight(R.id.remembrance_stack, stackHeight, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutMargin(R.id.remembrance_stack, RemoteViews.MARGIN_LEFT, -4f, TypedValue.COMPLEX_UNIT_DIP)
                views.setViewLayoutMargin(R.id.remembrance_stack, RemoteViews.MARGIN_TOP, -4f - stackHeight * 0.1f, TypedValue.COMPLEX_UNIT_DIP)
            }
            val adapter = Intent(context, RemembranceWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse("azkar-widget://remembrance/$id")
            }
            if (Build.VERSION.SDK_INT >= 31) {
                // Direct collection items avoid the deprecated service adapter's
                // asynchronous conversion on recent Android versions. Keep stable
                // IDs so reapplying the adapter preserves a manual selection.
                val cards = loopingRemembranceCards(context)
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
            // New Android hosts can merge partial updates before applying them;
            // showNext has MERGE_IGNORE and is dropped during that merge. Send
            // the complete collection and its relative command together instead.
            if (advance) views.showNext(R.id.remembrance_stack)
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
        cards = loopingRemembranceCards(context)
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

private fun loopingRemembranceCards(context: Context): JSONArray {
    val source = readRemembranceCards(context)
    val count = source.length()
    if (count == 0) return source
    // StackView keeps five active frames. With <=5 rows its loop uses virtual
    // positions beyond the adapter count; rebinding RemoteCollectionItems can
    // leave those frames empty. Repeat complete copies of the available sequence
    // to at least six rows so both automatic and manual wrap use real positions.
    // Complete copies preserve A,B,C,A,B,C order at the seam as well.
    val copies = maxOf(1, (6 + count - 1) / count)
    return JSONArray().apply {
        for (index in 0 until count * copies) put(source.getJSONObject(index % count))
    }
}

private fun remembranceItemId(card: JSONObject, position: Int): Long =
    "${card.optString("id")}:$position".fold(1125899906842597L) { hash, char -> hash * 31 + char.code }

private fun remembranceSize(context: Context, widgetId: Int): SizeF {
    val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
    val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
    val width = options.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 250).toFloat()
    val height = options.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 160).toFloat()
    val sizes = if (Build.VERSION.SDK_INT >= 31) options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES) else null
    val selected = sizes?.minByOrNull { kotlin.math.abs(it.width - width) + kotlin.math.abs(it.height - height) }
    return SizeF(maxOf(100f, selected?.width ?: width), maxOf(60f, selected?.height ?: height))
}

private fun remembranceNameCount(cards: JSONArray): Int =
    (0 until cards.length()).mapNotNull { cards.optJSONObject(it)?.optString("deceasedName") }
        .filter { it.isNotBlank() }.toSet().size.coerceAtLeast(1)

private object RemembranceNameRenderer {
    private val cache = LruCache<String, Bitmap>(16)
    fun render(context: Context, name: String, size: SizeF, nameCount: Int): Bitmap? = try {
        val metrics = context.resources.displayMetrics
        val width = maxOf(40, (size.width - 20f).toInt())
        val height = 48
        // Reserve only one third of the RemoteViews bitmap allowance for names.
        // Repeated loop rows share the same cached bitmap, and large collections
        // lower their raster scale instead of exceeding the widget IPC limit.
        val pixelBudget = size.width * size.height * metrics.density * metrics.density * 0.5f / nameCount
        val scale = minOf(metrics.density, kotlin.math.sqrt(pixelBudget / (width * height))).coerceAtLeast(0.1f)
        val fontScale = metrics.scaledDensity / metrics.density
        val key = "$name|$width|$scale|$fontScale"
        cache.get(key) ?: run {
            val face = if (Build.VERSION.SDK_INT >= 26) context.resources.getFont(R.font.aref_ruqaa_bold)
                else Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/aref_ruqaa/ArefRuqaa-Bold.ttf")
            val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; typeface = face }
            var layout: StaticLayout? = null
            for (fontSize in 24 downTo 14) {
                paint.textSize = fontSize * fontScale
                val candidate = StaticLayout.Builder.obtain(name, 0, name.length, paint, width)
                    .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(true).build()
                layout = candidate
                if (candidate.height <= height && candidate.lineCount <= 2) break
            }
            val fitted = if (layout!!.height > height || layout!!.lineCount > 2)
                StaticLayout.Builder.obtain(name, 0, name.length, paint, width)
                    .setAlignment(Layout.Alignment.ALIGN_CENTER).setIncludePad(true)
                    .setMaxLines(2).setEllipsize(TextUtils.TruncateAt.END).build() else layout!!
            Bitmap.createBitmap(kotlin.math.ceil(width * scale).toInt(), kotlin.math.ceil(height * scale).toInt(), Bitmap.Config.ARGB_8888).also { bitmap ->
                Canvas(bitmap).apply {
                    scale(scale, scale)
                    translate(0f, maxOf(0f, (height - fitted.height) / 2f))
                    fitted.draw(this)
                }
                cache.put(key, bitmap)
            }
        }
    } catch (_: Exception) { null }
}

private fun remembranceCardView(context: Context, card: JSONObject, size: SizeF, nameCount: Int): RemoteViews =
    RemoteViews(context.packageName, R.layout.remembrance_widget_ruqaa_card).apply {
        val density = context.resources.displayMetrics.density
        setInt(R.id.remembrance_card, "setMinimumWidth", kotlin.math.ceil(size.width * density).toInt())
        setInt(R.id.remembrance_card, "setMinimumHeight", kotlin.math.ceil(size.height * density).toInt())
        val name = card.optString("deceasedName")
        val heading = card.optString("dedicationHeading")
        val named = name.isNotBlank() && heading.isNotBlank()
        setTextViewText(R.id.remembrance_card_title, if (named) heading else card.optString("title"))
        val nameImage = if (named) RemembranceNameRenderer.render(context, name, size, nameCount) else null
        setViewVisibility(R.id.remembrance_deceased_name, if (named && nameImage == null) View.VISIBLE else View.GONE)
        setTextViewText(R.id.remembrance_deceased_name, name)
        setViewVisibility(R.id.remembrance_name_image, if (nameImage != null) View.VISIBLE else View.GONE)
        if (nameImage != null) setImageViewBitmap(R.id.remembrance_name_image, nameImage)
        setContentDescription(R.id.remembrance_name_image, name)
        setViewVisibility(R.id.remembrance_card_text, if (card.optString("text").isBlank()) View.GONE else View.VISIBLE)
        setTextViewText(R.id.remembrance_card_text, card.optString("text"))
        setOnClickFillInIntent(R.id.remembrance_card, Intent().putExtra("content_route", card.optString("route", "/")))
    }
