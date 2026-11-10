package com.azkar.azkar

import android.util.SizeF
import kotlin.math.ceil
import kotlin.math.roundToInt

/** Cancel StackView's perspective gutter inside an opaque, clipped viewport. */
internal class RemembrancePagerGeometry(size: SizeF, density: Float) {
    val insetX = (RemembranceCardRenderer.pagerInsetX(size) * density).toInt()
    val insetY = (RemembranceCardRenderer.pagerInsetY(size) * density).toInt()
    private val width = (size.width * density).roundToInt() - insetX * 2
    private val height = (size.height * density).roundToInt() - insetY * 2
    // Overscan one physical pixel per edge so fractional translations cannot
    // expose even a one-pixel strip of another card on high-density launchers.
    val rowWidth = width + 2
    val rowHeight = height + 2
    private val frame = ceil(4 * density).toInt()
    val left = -frame - 1
    val top = -ceil(height * .1f).toInt() - frame - 1
    val right = (width * .9f).roundToInt() - rowWidth - frame * 2 - left
    val bottom = (height * .9f).roundToInt() - rowHeight - frame * 2 - top
    val contentSize = SizeF(rowWidth / density, rowHeight / density)
}
