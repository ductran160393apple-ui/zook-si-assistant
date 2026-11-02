package vn.aiassistant

// Client Messages API cho Android: prompt/timeout/retry/HTTP do lõi Rust sở
// hữu (FFI messagesCall, blocking — luôn gọi trên Dispatchers.Default).
// Kotlin chỉ giữ key (EncryptedSharedPreferences) và truyền cấu hình.
object MetaApiClient {
    data class Outcome(val text: String, val tokens: String)

    fun run(
        task: uniffi.aiassist_core.AiTaskKind,
        redactedText: String,
        baseUrl: String,
        apiKey: String,
        model: String,
        english: Boolean = false,
    ): Outcome {
        if (apiKey.isBlank()) return Outcome("Thiếu Meta API key. Nhập key trong app.", "")
        return try {
            val res = uniffi.aiassist_core.messagesCall(
                uniffi.aiassist_core.FfiMessagesCall(
                    baseUrl, apiKey, null, model, task, redactedText,
                    1.25, 4.25, "meta",
                    if (english) uniffi.aiassist_core.AiLang.EN else uniffi.aiassist_core.AiLang.VI,
                ),
            )
            val cost = res.costUsd
            val tok = if (cost != null) {
                "in ${res.inputTokens} · out ${res.outputTokens} · $${"%.4f".format(cost)}"
            } else {
                "in ${res.inputTokens} · out ${res.outputTokens}"
            }
            Outcome(res.text, tok)
        } catch (e: Exception) {
            Outcome("Lỗi Meta: ${e.message}. Đã thử 3 lần.", "")
        }
    }
}
