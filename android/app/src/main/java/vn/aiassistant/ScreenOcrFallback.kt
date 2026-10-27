package vn.aiassistant

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

// Dự phòng khi cây Accessibility không đủ chữ: xin chia sẻ màn hình
// (MediaProjection) + ML Kit OCR ngay trên máy. Ảnh chỉ xử lý trong RAM.
object ScreenOcrFallback {
    private const val REQ = 9001
    private var projection: MediaProjection? = null
    private var starter: Activity? = null

    fun start(activity: Activity) {
        starter = activity
        val mgr = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        activity.startActivityForResult(mgr.createScreenCaptureIntent(), REQ)
    }

    fun onActivityResult(ctx: Context, requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ || resultCode != Activity.RESULT_OK || data == null) return
        val mgr = ctx.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = mgr.getMediaProjection(resultCode, data)
        captureOnce(ctx)
    }

    private fun captureOnce(ctx: Context) {
        val proj = projection ?: return
        val dm = ctx.resources.displayMetrics
        val reader = ImageReader.newInstance(dm.widthPixels, dm.heightPixels, PixelFormat.RGBA_8888, 2)
        var vd: VirtualDisplay? = null
        vd = proj.createVirtualDisplay(
            "ocr", dm.widthPixels, dm.heightPixels, dm.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.surface, null, null,
        )
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val img = reader.acquireLatestImage() ?: return@postDelayed
                val planes = img.planes
                val buf = planes[0].buffer
                val bmp = Bitmap.createBitmap(dm.widthPixels, dm.heightPixels, Bitmap.Config.ARGB_8888)
                bmp.copyPixelsFromBuffer(buf)
                img.close()
                ocr(ctx, bmp)
            } finally {
                vd?.release()
                reader.close()
            }
        }, 500)
    }

    private fun ocr(ctx: Context, bmp: Bitmap) {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            .process(InputImage.fromBitmap(bmp, 0))
            .addOnSuccessListener { visionText ->
                val text = visionText.text
                if (text.isBlank()) return@addOnSuccessListener
                try {
                    val res = CoreBridge.scan(text, "screen-ocr", ctx)
                    CoreBridge.recordCase(ctx, "screen-ocr", text, res.score, res.reasons)
                    if (res.level == "dangerous") {
                        OverlayManager.showDanger(ctx, res.score.toInt(), res.reasons)
                    }
                } catch (_: Exception) { }
            }
    }
}
