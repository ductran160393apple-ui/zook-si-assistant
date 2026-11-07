import Foundation

/// Cấu hình backend LLM on-device (Ollama / `fm serve` qua HTTP
/// OpenAI-compat). Đọc từ UserDefaults ở luồng chính, truyền trị vào actor.
struct NetLLMConfig {
    var enabled: Bool
    var baseURL: String
    var model: String
    var lang: AiLang
}

/// Worker hiệu đính verdict mạng bằng LLM local, CHẠY SAU (không chặn
/// luồng quét): hàng đợi giới hạn + debounce theo fingerprint + cache TTL
/// + backoff khi lỗi liên tiếp. FFI chặn chạy trên detached task.
actor NetLLMWorker {
    struct Job {
        var fingerprint: String
        var verdict: String
    }

    static let maxQueue = 20
    static let cacheTTL: TimeInterval = 6 * 3600
    private var queue: [Job] = []
    private var cache: [String: (text: String, at: Date)] = [:]
    private var consecutiveErrors = 0
    private var nextAllowed = Date.distantPast
    private var pumping = false
    private(set) var dropped = 0

    func enqueue(verdict: String, config: NetLLMConfig, state: AppState) {
        guard config.enabled else { return }
        let fp = Self.fingerprint(verdictJson: verdict)
        if let c = cache[fp], Date().timeIntervalSince(c.at) < Self.cacheTTL {
            let text = c.text
            Task { @MainActor in state.netLlmVerdict = text + L(" (cache)", " (cached)") }
            return
        }
        guard !queue.contains(where: { $0.fingerprint == fp }) else { return }
        queue.append(Job(fingerprint: fp, verdict: verdict))
        if queue.count > Self.maxQueue {
            queue.removeFirst(queue.count - Self.maxQueue)
            dropped += 1
            DiagLog.line("net-llm: hàng đợi đầy, bỏ job cũ (tổng \(dropped))")
        }
        if !pumping {
            pumping = true
            Task { await self.pump(config: config, state: state) }
        }
    }

    private func pump(config: NetLLMConfig, state: AppState) async {
        defer { pumping = false }
        while !queue.isEmpty {
            if Date() < nextAllowed {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }
            let job = queue.removeFirst()
            if cache[job.fingerprint] != nil { continue }
            let system = netLlmSystemPrompt(lang: config.lang)
            let user = netLlmUserPrompt(verdictJson: job.verdict, lang: config.lang)
            var text: String?
            for _ in 0..<2 {
                let out: String? = await Task.detached(priority: .utility) {
                    try? netLlmCall(
                        baseUrl: config.baseURL, model: config.model,
                        system: system, user: user, timeoutSecs: 120
                    )
                }.value
                if let out, !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = out
                    break
                }
            }
            if let text {
                consecutiveErrors = 0
                cache[job.fingerprint] = (text, Date())
                Task { @MainActor in state.netLlmVerdict = text }
                DiagLog.line("net-llm: hiệu đính xong (\(text.count) chữ)")
            } else {
                consecutiveErrors += 1
                let backoff = min(60 * consecutiveErrors, 600)
                nextAllowed = Date().addingTimeInterval(TimeInterval(backoff))
                DiagLog.line("net-llm: lỗi calling LLM (\(config.baseURL)), nghỉ \(backoff)s")
            }
        }
    }

    // MARK: - Hàm thuần (có unit test)

    /// Dấu vân để debounce/cache: level + bucket điểm + top-3 tên app.
    /// JSON hỏng → "unknown" (vẫn cho vào hàng đợi, lõi lo).
    static func fingerprint(verdictJson: String) -> String {
        guard let d = verdictJson.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return "unknown" }
        let level = o["level"] as? String ?? "?"
        let bucket = ((o["score"] as? NSNumber)?.intValue ?? 0) / 10
        var names: [String] = []
        if let top = o["top"] as? [[String: Any]] {
            for t in top.prefix(3) { names.append(t["name"] as? String ?? "?") }
        }
        return "\(level):\(bucket):\(names.joined(separator: ","))"
    }

    /// Cắt hàng đợi về trần, trả số job bị bỏ. Thuần để test.
    static func boundedEnqueue(_ queue: [Job], job: Job, limit: Int) -> (kept: [Job], dropped: Int) {
        var q = queue
        if q.contains(where: { $0.fingerprint == job.fingerprint }) { return (q, 0) }
        q.append(job)
        let over = max(0, q.count - limit)
        if over > 0 { q.removeFirst(over) }
        return (q, over)
    }
}
