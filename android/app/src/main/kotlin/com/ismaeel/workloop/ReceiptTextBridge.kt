package com.ismaeel.workloop

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.PorterDuff
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max

/** OCR runs locally; temporary PDF handles are private and deleted in finally. */
class ReceiptTextBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "workloop/receipt_text")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var busy = false
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "recognize") {
                result.notImplemented()
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                val mimeType = call.argument<String>("mimeType")
                if (bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024 ||
                    mimeType !in setOf("image/jpeg", "image/png", "application/pdf")) {
                    result.error("invalid_receipt", "Choose a JPEG, PNG or PDF up to 10 MB.", null)
                } else if (busy || closed) {
                    result.error("recognition_failed", "The receipt reader is busy. Try again.", null)
                } else {
                    busy = true
                    executor.execute {
                        try {
                            val value = recognize(bytes, mimeType!!)
                            main.post { busy = false; if (!closed) result.success(value) }
                        } catch (_: SecurityException) {
                            main.post { busy = false; if (!closed) result.error("receipt_locked", "Choose an unlocked PDF or enter the details yourself.", null) }
                        } catch (_: Exception) {
                            main.post { busy = false; if (!closed) result.error("receipt_unreadable", "This receipt could not be read. You can enter the details yourself.", null) }
                        }
                    }
                }
            }
        }
    }

    private fun recognize(bytes: ByteArray, mimeType: String): Map<String, Any> {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            if (mimeType != "application/pdf") {
                val bitmap = image(bytes)
                try {
                    val text = read(recognizer, bitmap)
                    return mapOf("text" to text.take(12000), "pageCount" to 1, "processedPages" to 1, "textTruncated" to (text.length > 12000))
                } finally { bitmap.recycle() }
            }
            val file = File.createTempFile("receipt-", ".pdf", context.cacheDir)
            try {
                file.writeBytes(bytes)
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
                    PdfRenderer(descriptor).use { document ->
                        check(document.pageCount > 0)
                        val count = minOf(document.pageCount, 5)
                        val pages = (0 until count).map { index ->
                            document.openPage(index).use { page ->
                                val scale = 2048.0 / max(page.width, page.height)
                                val bitmap = Bitmap.createBitmap(max(1, (page.width * scale).toInt()), max(1, (page.height * scale).toInt()), Bitmap.Config.ARGB_8888)
                                try {
                                    bitmap.eraseColor(Color.WHITE)
                                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                    read(recognizer, bitmap)
                                } finally { bitmap.recycle() }
                            }
                        }
                        return mapOf("text" to pages.joinToString("\n\n") { it.take(12000) }, "pageCount" to document.pageCount, "processedPages" to count, "textTruncated" to pages.any { it.length > 12000 })
                    }
                }
            } finally { file.delete() }
        } finally { recognizer.close() }
    }

    private fun read(recognizer: TextRecognizer, bitmap: Bitmap): String {
        val recognized = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)), 30, TimeUnit.SECONDS)
        // ML Kit groups columns into blocks; flatten in reading order so totals
        // and their labels are returned as adjacent lines for reviewed parsing.
        return recognized.textBlocks.flatMap { it.lines }.sortedWith(
            compareBy({ it.boundingBox?.top ?: 0 }, { it.boundingBox?.left ?: 0 }),
        ).joinToString("\n") { it.text }
    }

    private fun image(bytes: ByteArray): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        check(bounds.outWidth > 0 && bounds.outHeight > 0)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > 4096) sample *= 2
        val bitmap = requireNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
            BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.ARGB_8888
                inMutable = true
            }))
        try {
            if (bitmap.hasAlpha()) {
                // Transparent PNG pixels must become white, not black, for OCR.
                // Composite in place before rotation to avoid another full bitmap.
                Canvas(bitmap).drawColor(Color.WHITE, PorterDuff.Mode.DST_OVER)
                bitmap.setHasAlpha(false)
            }
        } catch (error: Exception) {
            bitmap.recycle()
            throw error
        }
        val orientation = ByteArrayInputStream(bytes).use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL) }
        val transform = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> transform.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> transform.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> transform.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { transform.setRotate(90f); transform.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> transform.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { transform.setRotate(-90f); transform.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> transform.setRotate(-90f)
        }
        if (transform.isIdentity) return bitmap
        return try { Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, transform, true) }
        finally { bitmap.recycle() }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }
}
