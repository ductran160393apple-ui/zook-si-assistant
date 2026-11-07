package vn.aiassistant

import kotlinx.coroutines.*
import org.json.JSONObject

// Worker hiệu đính verdict mạng bằng LLM cục bộ (Ollama qua HTTP
// OpenAI-compat), CHẠY SAU không chặn luồng quét — gương NetLLMWorker Swift:
// hàng đợi giới hạn + debounce theo fingerprint + cache TTL + backoff.
// RIÊNG TƯ: chỉ gọi Ollama do người dùng cấu hình, KHÔNG BAO GIỜ gửi số
// liệu mạng vào Meta cloud hay bất kỳ AI cloud nào.
class NetLlmWorker {
    data class Config(val enabled: Boolean, val baseUrl: String, val model: String)
    private data class Job(val fingerprint: String, val verdict: String)

    /** Gọi trên luồng chính khi có kết quả hiệu đính. */
    var onVerdict: ((String) -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val queue = ArrayDeque<Job>()
    private val cache = HashMap<String, Pair<String, Long>>()
    private var consecutiveErrors = 0
    private var nextAllowed = 0L
    private var pumping = false
    var dropped = 0
        private set

    @Synchronized
    fun enqueue(verdict: String, config: Config) {
        if (!config.enabled) return
        val fp = fingerprint(verdict)
        val now = System.currentTimeMillis()
        cache[fp]?.let { (text, at) ->
            if (now - at < CACHE_TTL_MS) {
                val t = "$text (cache)"
                scope.launch(Dispatchers.Main) { onVerdict?.invoke(t) }
                return
            }
        }
        if (queue.any { it.fingerprint == fp }) return
        queue.addLast(Job(fp, verdict))
        while (queue.size > MAX_QUEUE) {
            queue.removeFirst()
            dropped += 1
        }
        if (!pumping) {
            pumping = true
            scope.launch { pump(config) }
        }
    }

    private suspend fun pump(config: Config) {
        try {
            while (true) {
                val job = synchronized(this) {
                    if (queue.isEmpty()) {
                        pumping = false
                        null
                    } else {
                        queue.removeFirst()
                    }
                } ?: return
                if (System.currentTimeMillis() < nextAllowed) {
                    delay(5000)
                    synchronized(this) { queue.addFirst(job) }
                    continue
                }
                if (synchronized(this) { cache.containsKey(job.fingerprint) }) continue
                val system = try {
                    uniffi.aiassist_core.netLlmSystemPrompt(uniffi.aiassist_core.AiLang.VI)
                } catch (_: Exception) {
                    ""
                }
                val user = try {
                    uniffi.aiassist_core.netLlmUserPrompt(job.verdict, uniffi.aiassist_core.AiLang.VI)
                } catch (_: Exception) {
                    ""
                }
                var text: String? = null
                repeat(2) {
                    if (text != null) return@repeat
                    val out = try {
                        withContext(Dispatchers.IO) {
                            uniffi.aiassist_core.netLlmCall(
                                config.baseUrl, config.model, system, user, 120UL,
                            )
                        }
                    } catch (_: Exception) {
                        null
                    }
                    if (!out.isNullOrBlank()) text = out
                }
                val done = text
                if (done != null) {
                    synchronized(this) {
                        consecutiveErrors = 0
                        cache[job.fingerprint] = Pair(done, System.currentTimeMillis())
                    }
                    withContext(Dispatchers.Main) { onVerdict?.invoke(done) }
                } else {
                    synchronized(this) {
                        consecutiveErrors += 1
                        val backoff = minOf(60 * consecutiveErrors, 600)
                        nextAllowed = System.currentTimeMillis() + backoff * 1000L
                    }
                }
            }
        } catch (_: Exception) {
            synchronized(this) { pumping = false }
        }
    }

    companion object {
        const val MAX_QUEUE = 20
        const val CACHE_TTL_MS = 6 * 3600 * 1000L

        /** Dấu vân debounce/cache: level + bucket điểm + top-3 tên app. */
        fun fingerprint(verdictJson: String): String {
            val o = try {
                JSONObject(verdictJson)
            } catch (_: Exception) {
                return "unknown"
            }
            val level = o.optString("level", "?")
            val bucket = o.optInt("score", 0) / 10
            val names = ArrayList<String>()
            val top = o.optJSONArray("top")
            if (top != null) for (i in 0 until minOf(3, top.length())) {
                names.add(top.optJSONObject(i)?.optString("name", "?") ?: "?")
            }
            return "$level:$bucket:${names.joinToString(",")}"
        }
    }
}
