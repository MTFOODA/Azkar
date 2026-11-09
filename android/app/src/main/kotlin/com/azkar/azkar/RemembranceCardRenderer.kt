package com.azkar.azkar

import android.content.Context
import android.appwidget.AppWidgetManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.util.LruCache
import android.util.SizeF
import kotlin.math.*

/** Mirrors CardShapeGeometry.primary and IslamicPatternPainter in Flutter. */
internal object RemembranceCardRenderer {
    private val surfaces = object : LruCache<String, Bitmap>(8 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private val passages = object : LruCache<String, Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.allocationByteCount
    }
    private const val SURFACE = 0xFF102A23.toInt()
    private const val TEXT = 0xFFF3F4F6.toInt()
    private const val BORDER = 0xFF1F3B33.toInt()

    fun horizontalPadding(size: SizeF) = (size.width * 0.09f).coerceIn(20f, 72f)
    fun verticalPadding(size: SizeF) = (size.height * 0.09f).coerceIn(16f, 36f)

    fun widgetSize(context: Context, widgetId: Int): SizeF {
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(widgetId)
        val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val width = options.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 250).toFloat()
        val height = options.getInt(if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 160).toFloat()
        val sizes = if (Build.VERSION.SDK_INT >= 31) options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES) else null
        val selected = sizes?.minByOrNull { abs(it.width - width) + abs(it.height - height) }
        return SizeF(max(100f, selected?.width ?: width), max(60f, selected?.height ?: height))
    }

    private fun scale(context: Context, width: Float, height: Float, fraction: Float, count: Int, cap: Int): Float {
        val m = context.resources.displayMetrics
        // Android limits the combined bitmap memory of an entire RemoteViews
        // collection. Repeated rows reuse cached bitmap instances; backgrounds
        // and all unique passages together stay below that allowance.
        val bytes = min(m.widthPixels.toDouble() * m.heightPixels * 6 * fraction, cap.toDouble()) / max(1, count)
        return min(m.density.toDouble(), sqrt(bytes / 4 / (width * height))).toFloat().coerceAtLeast(0.1f)
    }

    fun surface(context: Context, size: SizeF): Bitmap {
        val scale = scale(context, size.width, size.height, .25f, 1, 8 * 1024 * 1024)
        val key = "${size.width}|${size.height}|$scale"
        surfaces.get(key)?.let { return it }
        val bitmap = Bitmap.createBitmap(ceil(size.width * scale).toInt(), ceil(size.height * scale).toInt(), Bitmap.Config.ARGB_8888)
        bitmap.density = Bitmap.DENSITY_NONE
        val canvas = Canvas(bitmap)
        canvas.scale(scale, scale)
        val blend = max(((size.height / size.width - 2) / 1.5f).coerceIn(0f, 1f), ((260 - size.width) / 160).coerceIn(0f, 1f))
        val base = floatArrayOf(.5f,.1f, .1f,.5f, .5f,.1f, .1f,.5f)
        val radii = FloatArray(8) { index ->
            val safe = if (index % 2 == 0) .06f else .1f
            (base[index] + (safe - base[index]) * blend) * if (index % 2 == 0) size.width else size.height
        }
        val path = Path().apply { addRoundRect(RectF(.6f, .6f, size.width - .6f, size.height - .6f), radii, Path.Direction.CW) }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = SURFACE }
        canvas.drawPath(path, paint)
        canvas.save()
        canvas.clipPath(path)
        paint.color = Color.argb(20, 156, 163, 175)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1f
        val step = if (size.width < 320) 42f else 56f
        var x = -step
        while (x < size.width + step) {
            var y = -step
            while (y < size.height + step) {
                val cx = x + if (round(y / step).toInt() % 2 == 0) 0f else step / 2
                val star = Path()
                for (i in 0 until 16) {
                    val angle = (i * 22.5 - 90) * PI / 180
                    val r = step * .28f * if (i % 2 == 0) 1f else .45f
                    val px = cx + (r * cos(angle)).toFloat()
                    val py = y + (r * sin(angle)).toFloat()
                    if (i == 0) star.moveTo(px, py) else star.lineTo(px, py)
                }
                star.close()
                canvas.drawPath(star, paint)
                y += step
            }
            x += step
        }
        canvas.restore()
        paint.color = BORDER
        paint.strokeWidth = 1.2f
        canvas.drawPath(path, paint)
        surfaces.put(key, bitmap)
        return bitmap
    }

    fun dedication(context: Context, name: String, text: String, size: SizeF, count: Int): Bitmap? = try {
        val width = (size.width - horizontalPadding(size) * 2).toInt().coerceAtLeast(40)
        val height = (size.height - verticalPadding(size) * 2).toInt().coerceAtLeast(30)
        val scale = scale(context, width.toFloat(), height.toFloat(), .5f, count, 16 * 1024 * 1024)
        val m = context.resources.displayMetrics
        val fontScale = m.scaledDensity / m.density
        val key = "$name|$text|$width|$height|$scale|$fontScale"
        passages.get(key) ?: run {
            val face = if (Build.VERSION.SDK_INT >= 26) context.resources.getFont(R.font.aref_ruqaa_bold)
                else Typeface.createFromAsset(context.assets, "flutter_assets/assets/fonts/aref_ruqaa/ArefRuqaa-Bold.ttf")
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = TEXT; typeface = face }
            fun paragraph(value: String, sp: Float, maxLines: Int = Int.MAX_VALUE): StaticLayout {
                val paragraphPaint = TextPaint(paint).apply { textSize = sp * fontScale }
                return StaticLayout.Builder.obtain(value, 0, value.length, paragraphPaint, width)
                    .setAlignment(Layout.Alignment.ALIGN_CENTER).setTextDirection(TextDirectionHeuristics.RTL)
                    .setIncludePad(true).setMaxLines(maxLines).setEllipsize(TextUtils.TruncateAt.END).build()
            }
            var title = paragraph(name, 26f, 2)
            var body = paragraph(text, 20f)
            var gap = 16f
            for (step in 0..10) {
                title = paragraph(name, 26f - step * .8f, 2)
                body = paragraph(text, 20f - step * .8f)
                gap = max(6f, 16f - step)
                if (title.height + body.height + gap <= height) break
            }
            if (title.height + body.height + gap > height) {
                body = paragraph(text, 12f, max(1, ((height - title.height - gap) / (body.paint.fontSpacing.coerceAtLeast(1f))).toInt()))
            }
            val bitmap = Bitmap.createBitmap(ceil(width * scale).toInt(), ceil(height * scale).toInt(), Bitmap.Config.ARGB_8888)
            bitmap.density = Bitmap.DENSITY_NONE
            val canvas = Canvas(bitmap)
            canvas.scale(scale, scale)
            canvas.translate(0f, max(0f, (height - title.height - body.height - gap) / 2))
            title.draw(canvas)
            canvas.translate(0f, title.height + gap)
            body.draw(canvas)
            passages.put(key, bitmap)
            bitmap
        }
    } catch (_: Exception) { null }
}
