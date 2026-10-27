package vn.aiassistant

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

// Overlay cảnh báo đỏ + nút nổi "AI". Mọi hành động an toàn đều do NGƯỜI DÙNG
// bấm: về màn hình chính, mở cài đặt app điều khiển từ xa để dừng.
// KHÔNG BAO GIỜ tự bấm hay nhập trong app khác.
object OverlayManager {
    private var dangerView: LinearLayout? = null
    private var aiButton: Button? = null

    fun showDanger(ctx: Context, score: Int, reasons: List<String>) {
        if (!Settings.canDrawOverlays(ctx)) return
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        hideDanger(ctx)
        val layout = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(0xFFB71C1C.toInt())
            setPadding(32, 32, 32, 32)
            addView(TextView(ctx).apply {
                text = "NGUY HIỂM ($score/100)"
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 20f
            })
            addView(TextView(ctx).apply {
                text = reasons.joinToString("\n• ", prefix = "• ")
                setTextColor(0xFFFFFFFF.toInt())
            })
            addView(Button(ctx).apply {
                text = "Về màn hình chính"
                setOnClickListener {
                    val home = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    ctx.startActivity(home)
                }
            })
            addView(Button(ctx).apply {
                text = "Mở cài đặt app điều khiển từ xa"
                setOnClickListener {
                    // Người dùng tự bấm Dừng trong Cài đặt.
                    val i = Intent(Settings.ACTION_APPLICATION_SETTINGS).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    ctx.startActivity(i)
                }
            })
            addView(Button(ctx).apply {
                text = "Đã hiểu, đóng"
                setOnClickListener { hideDanger(ctx) }
            })
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP }
        dangerView = layout
        wm.addView(layout, params)
    }

    fun hideDanger(ctx: Context) {
        dangerView?.let {
            try {
                (ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it)
            } catch (_: Exception) { }
            dangerView = null
        }
    }

    /** Nút nổi "AI" mở app khi bấm. */
    fun showAiButton(ctx: Context) {
        if (!Settings.canDrawOverlays(ctx) || aiButton != null) return
        val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val b = Button(ctx).apply {
            text = "AI"
            setOnClickListener {
                ctx.startActivity(Intent(ctx, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                })
            }
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.BOTTOM or Gravity.END }
        aiButton = b
        wm.addView(b, params)
    }

    fun openAppSettings(ctx: Context, pkg: String) {
        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        ctx.startActivity(i)
    }

    fun isNotificationServiceEnabled(ctx: Context): Boolean {
        val flat = Settings.Secure.getString(ctx.contentResolver, "enabled_notification_listeners") ?: ""
        return flat.contains(ctx.packageName)
    }

    fun isOverlayGranted(ctx: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(ctx) else true
}
