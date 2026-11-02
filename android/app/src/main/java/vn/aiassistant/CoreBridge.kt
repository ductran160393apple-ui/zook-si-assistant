package vn.aiassistant

import android.content.Context
import java.io.File

// Cầu tới lõi Rust qua UniFFI (binding sinh từ bản build chưa strip,
// package uniffi.aiassist_core). Mọi chấm điểm/che PII/kiểm duyệt luật,
// phân loại app, dedup case chạy trong lõi; Kotlin chỉ thu thập chữ,
// vẽ UI và giữ file/key.
object CoreBridge {
    init {
        System.loadLibrary("aiassist_core")
    }

    private const val RULES_FILE = "learned-rules.json"
    private const val CASES_FILE = "cases.json"

    fun flags(
        remoteAppRunning: Boolean = false,
        inCall: Boolean = false,
        bankAppOpen: Boolean = false,
        ctx: Context? = null,
    ) = uniffi.aiassist_core.FfiScanFlags(
        remoteAppRunning,
        inCall,
        bankAppOpen,
        ctx?.let { loadRulesJson(it) } ?: "",
        "",
        ctx?.let { loadCasesJson(it) } ?: "",
    )

    fun scan(
        text: String,
        appId: String,
        ctx: Context? = null,
        remoteAppRunning: Boolean = false,
        inCall: Boolean = false,
        bankAppOpen: Boolean = false,
        english: Boolean = false,
    ): uniffi.aiassist_core.FfiScanResult =
        uniffi.aiassist_core.scanText(
            text, appId, flags(remoteAppRunning, inCall, bankAppOpen, ctx),
            if (english) uniffi.aiassist_core.AiLang.EN else uniffi.aiassist_core.AiLang.VI,
        )

    fun redact(text: String): String = uniffi.aiassist_core.redactText(text)

    fun levelVi(level: String): String = when (level) {
        "dangerous" -> "NGUY HIỂM"
        "suspicious" -> "ĐÁNG NGỜ"
        else -> "AN TOÀN"
    }

    fun loadRulesJson(ctx: Context): String = try {
        File(ctx.filesDir, RULES_FILE).takeIf { it.exists() }?.readText() ?: ""
    } catch (_: Exception) { "" }

    /** JSON kho case cho RAG (cache theo mtime, lõi bỏ qua khi rỗng). */
    private var casesCache: Pair<Long, String>? = null

    fun loadCasesJson(ctx: Context): String = try {
        val f = File(ctx.filesDir, CASES_FILE)
        if (!f.exists()) return ""
        val m = f.lastModified()
        casesCache?.takeIf { it.first == m }?.second?.let { return it }
        val s = f.readText()
        casesCache = m to s
        s
    } catch (_: Exception) { "" }

    fun invalidateCasesCache() { casesCache = null }

    /** Lưu case qua lõi (lõi che PII, cắt 1500 ký tự, dedup Jaccard, giữ 1000). */
    fun recordCase(ctx: Context, appId: String, text: String, score: UInt, reasons: List<String>) {
        if (score < 15u) return
        try {
            val f = File(ctx.filesDir, CASES_FILE)
            val current = if (f.exists()) f.readText() else ""
            val cand = org.json.JSONObject()
                .put("text", redact(text))
                .put("app_id", appId)
                .put("score", score.toInt())
                .put("reasons", org.json.JSONArray(reasons))
                .toString()
            f.writeText(uniffi.aiassist_core.storeAddCase(current, cand))
            invalidateCasesCache()
        } catch (_: Exception) { }
    }

    /** Phân loại app — danh sách do lõi sở hữu (nguồn duy nhất). */
    fun isSensitivePackage(pkg: String): Boolean =
        try { uniffi.aiassist_core.isSensitiveApp(pkg) } catch (_: Exception) { false }

    fun isRemotePackage(pkg: String): Boolean =
        try { uniffi.aiassist_core.isRemoteApp(pkg) } catch (_: Exception) { false }

    fun isBankPackage(pkg: String): Boolean =
        try { uniffi.aiassist_core.isBankApp(pkg) } catch (_: Exception) { false }
}
