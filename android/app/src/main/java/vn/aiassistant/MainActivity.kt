package vn.aiassistant

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Màn hình chính Compose: trạng thái quyền, ô dán tin nhắn để kiểm tra,
// lịch sử kết quả, chọn backend Meta (key lưu EncryptedSharedPreferences),
// chế độ dự phòng chia sẻ màn hình (MediaProjection + ML Kit OCR).
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CallTracker.start(this)
        setContent { MainScreen() }
    }

    @Deprecated("Dùng cho MediaProjection dự phòng")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        ScreenOcrFallback.onActivityResult(this, requestCode, resultCode, data)
    }
}

@Composable
fun MainScreen() {
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val activity = ctx as? ComponentActivity
    val scope = rememberCoroutineScope()
    var input by remember { mutableStateOf("") }
    var result by remember { mutableStateOf("") }
    var history by remember { mutableStateOf(listOf<String>()) }
    var metaKey by remember { mutableStateOf(loadMetaKey(ctx)) }

    val accOn = isAccessibilityOn(ctx)
    val notifOn = OverlayManager.isNotificationServiceEnabled(ctx)
    val overlayOk = OverlayManager.isOverlayGranted(ctx)

    Column(Modifier.verticalScroll(rememberScrollState())) {
        Text("SiAssitant — chống lừa đảo")
        Text("Quyền: Accessibility=${onOff(accOn)} · Đọc thông báo=${onOff(notifOn)} · Overlay=${onOff(overlayOk)} · Cuộc gọi=${onOff(CallTracker.inCall)}")
        if (!accOn) Button(onClick = { ctx.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }) { Text("Bật Accessibility") }
        if (!notifOn) Button(onClick = { ctx.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }) { Text("Bật đọc thông báo") }
        if (!overlayOk) Button(onClick = {
            ctx.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${ctx.packageName}")))
        }) { Text("Cấp quyền overlay") }
        Button(onClick = { OverlayManager.showAiButton(ctx) }) { Text("Hiện nút nổi AI") }

        TextField(value = input, onValueChange = { input = it }, label = { Text("Dán tin nhắn để kiểm tra") })
        Row {
            Button(onClick = {
                scope.launch(Dispatchers.Default) {
                    val res = try {
                        CoreBridge.scan(input, "manual", ctx)
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result = "Lỗi lõi: ${e.message}" }
                        return@launch
                    }
                    CoreBridge.recordCase(ctx, "manual", input, res.score, res.reasons)
                    val line = "${CoreBridge.levelVi(res.level)} ${res.score}/100 — ${res.reasons.joinToString("; ")}"
                    withContext(Dispatchers.Main) {
                        result = line
                        history = (listOf(line) + history).take(50)
                    }
                    if (res.level == "dangerous") OverlayManager.showDanger(ctx, res.score.toInt(), res.reasons)
                }
            }) { Text("Kiểm tra") }
            Button(onClick = {
                scope.launch(Dispatchers.Default) {
                    val redacted = try { CoreBridge.redact(input) } catch (e: Exception) { input }
                    val out = MetaApiClient.run(uniffi.aiassist_core.AiTaskKind.ANALYZE, redacted, "https://api.meta.ai/v1", loadMetaKey(ctx), "muse-spark-1.3")
                    withContext(Dispatchers.Main) { result = out.text + "\n(${out.tokens})" }
                }
            }) { Text("Phân tích bằng Meta") }
        }
        Text(result)
        // Meta API là backend duy nhất trên Android (các CLI + Anthropic là macOS).
        Text("Backend: Meta API")
        TextField(value = metaKey, onValueChange = {
            metaKey = it
            saveMetaKey(ctx, it)
        }, label = { Text("Meta API key (lưu mã hóa)") })
        Button(onClick = {
            activity?.let { ScreenOcrFallback.start(it) }
        }) { Text("Chế độ dự phòng: chia sẻ màn hình + OCR") }
        Text("Lịch sử:")
        history.forEach { Text("• $it") }
    }
}

private fun onOff(b: Boolean) = if (b) "BẬT" else "TẮT"

private fun isAccessibilityOn(ctx: android.content.Context): Boolean {
    val am = ctx.getSystemService(android.content.Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    return am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_GENERIC).any {
        it.resolveInfo.serviceInfo.packageName == ctx.packageName
    }
}

private fun prefs(ctx: android.content.Context) = EncryptedSharedPreferences.create(
    ctx, "secrets", MasterKey.Builder(ctx).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
)

private fun loadMetaKey(ctx: android.content.Context): String =
    try { (prefs(ctx).getString("meta_key", "") ?: "").trim() } catch (_: Exception) { "" }

private fun saveMetaKey(ctx: android.content.Context, key: String) {
    try { prefs(ctx).edit().putString("meta_key", key.trim()).apply() } catch (_: Exception) { }
}
