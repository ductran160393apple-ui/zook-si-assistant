package vn.aiassistant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import java.util.concurrent.Executors

// Quét thông báo: chấm điểm text qua lõi; khi Nguy hiểm thì đăng thông báo
// cảnh báo KHÔNG chứa từ khóa lừa đảo (tránh tự kích hoạt lại khi đọc khay).
class NotificationScanner : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val pkg = sbn?.packageName ?: return
        if (pkg == packageName) return // bỏ qua chính mình
        if (CoreBridge.isSensitivePackage(pkg)) return // app nhạy cảm: không quét
        val text = sbn.notification?.extras?.getCharSequence("android.text")?.toString()
            ?: return
        val res = try {
            CoreBridge.scan(text, pkg, this, inCall = CallTracker.inCall)
        } catch (_: Exception) { return }
        CoreBridge.recordCase(this, pkg, text, res.score, res.reasons)
        if (res.level == "dangerous") postDangerAlert(res.score.toInt())
    }

    private fun postDangerAlert(score: Int) {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.createNotificationChannel(
            NotificationChannel("danger", "Cảnh báo an toàn", NotificationManager.IMPORTANCE_HIGH)
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Nội dung trung tính: không từ khóa lừa đảo, không tự kích hoạt lại.
        val n = NotificationCompat.Builder(this, "danger")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("SiAssitant: phát hiện nội dung nguy hiểm ($score/100)")
            .setContentText("Mở app để xem chi tiết và hướng xử lý.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        mgr.notify(1001, n)
    }
}

/** Chỉ theo dõi TRẠNG THÁI cuộc gọi cho tổ hợp (remote + call). Không đọc số. */
object CallTracker {
    @Volatile var inCall: Boolean = false
        private set

    fun start(ctx: Context) {
        try {
            val tm = ctx.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
            tm.registerTelephonyCallback(
                Executors.newSingleThreadExecutor(),
                object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        inCall = state != TelephonyManager.CALL_STATE_IDLE
                    }
                },
            )
        } catch (_: SecurityException) {
            // Thiếu READ_PHONE_STATE: tổ hợp cuộc gọi tạm tắt, app vẫn chạy.
        }
    }
}
