package vn.aiassistant

import android.accessibilityservice.AccessibilityService
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

// Đọc chữ trực tiếp từ cây Accessibility: bỏ ô mật khẩu, giới hạn 800 node /
// 6000 ký tự, debounce 600ms; MediaProjection + ML Kit OCR làm dự phòng
// (xem ScreenOcrFallback). Không bao giờ đọc app nhạy cảm (chặn sớm theo
// danh sách lõi + lõi trả 0 điểm phòng thủ sâu).
class ScamAccessibilityService : AccessibilityService() {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: Runnable? = null
    private var lastText = ""

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        if (pkg == packageName) return // bỏ qua chính mình
        if (CoreBridge.isSensitivePackage(pkg)) return // app nhạy cảm: không đọc
        pending?.let { handler.removeCallbacks(it) }
        pending = Runnable {
            val root = rootInActiveWindow ?: return@Runnable
            val text = collectText(root, 0).trim()
            if (text.isBlank() || text == lastText) return@Runnable
            lastText = text
            handleText(pkg, text)
        }
        handler.postDelayed(pending!!, 600)
    }

    override fun onInterrupt() {}

    private fun handleText(pkg: String, text: String) {
        ForegroundApp.isBankOpen = CoreBridge.isBankPackage(pkg)
        val res = try {
            CoreBridge.scan(
                text, pkg, this,
                remoteAppRunning = CoreBridge.isRemotePackage(pkg),
                inCall = CallTracker.inCall,
                bankAppOpen = ForegroundApp.isBankOpen,
            )
        } catch (_: Exception) { return }
        CoreBridge.recordCase(this, pkg, text, res.score, res.reasons)
        if (res.level == "dangerous") {
            OverlayManager.showDanger(this, res.score.toInt(), res.reasons)
        }
    }

    private fun collectText(node: AccessibilityNodeInfo?, depth: Int): String {
        if (node == null || depth > 800) return ""
        if (node.isPassword) return ""
        val sb = StringBuilder()
        node.text?.let { sb.append(it).append(' ') }
        for (i in 0 until node.childCount) {
            sb.append(collectText(node.getChild(i), depth + 1))
            if (sb.length > 6000) break
        }
        return sb.toString()
    }
}

/** Trạng thái app ngân hàng ở phía trước (service cập nhật khi event tới). */
object ForegroundApp {
    @Volatile var isBankOpen: Boolean = false
}
