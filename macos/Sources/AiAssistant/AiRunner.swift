import Foundation
import Security

/// Thực thi tác vụ AI theo backend đã chọn. Mọi prompt/timeout/retry/HTTP
/// nằm trong lõi Rust (FFI); Swift chỉ giữ key, chọn backend và thực thi
/// tiến trình `claude` trong thư mục tạm.
enum AiRunner {
    struct Outcome {
        let text: String
        /// Chuỗi token/chi phí hiển thị, ví dụ "in 812 · out 214 · $0.004".
        let tokens: String
    }

    static func run(task: AiTask, redactedText: String, state: AppState) async -> Outcome {
        let coreTask = coreTask(task)
        switch state.backend {
        case .claudeCode:
            return runClaude(task: coreTask, redactedText: redactedText, model: state.claudeModel)
        case .metaApi:
            guard let key = loadKey(account: "meta-api-key") ?? nonEmpty(state.metaApiKey) else {
                return Outcome(text: "Thiếu API key (meta). Nhập key trong menu.", tokens: "")
            }
            return await runCoreMessages(
                task: coreTask, baseURL: state.metaBaseURL, apiKey: key,
                model: state.metaModel, backend: "meta", version: nil,
                priceIn: 0.00015, priceOut: 0.0006, rawText: redactedText
            )
        case .anthropic:
            guard let key = loadKey(account: "anthropic-api-key") ?? nonEmpty(state.anthropicApiKey) else {
                return Outcome(text: "Thiếu API key (anthropic). Nhập key trong menu.", tokens: "")
            }
            return await runCoreMessages(
                task: coreTask, baseURL: "https://api.anthropic.com/v1", apiKey: key,
                model: state.claudeModel, backend: "anthropic", version: "2023-06-01",
                priceIn: 0.003, priceOut: 0.015, rawText: redactedText
            )
        case .argon:
            return Outcome(text: "Antigravity chưa hỗ trợ trong bản này.", tokens: "")
        }
    }

    // -- Claude Code CLI cô lập (lệnh do lõi dựng) ---------------------------
    private static func runClaude(task: AiTaskKind, redactedText: String, model: String) -> Outcome {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cmd = claudeCommandArgs(model: model, task: task, redacted: redactedText)
        let timeout = TimeInterval(taskTimeoutSecs(task: task))
        var last: String?
        for _ in 0 ... 2 {
            // /usr/bin/env để giải PATH (executableURL không tự tìm PATH).
            if let out = exec("/usr/bin/env", args: [cmd.bin] + cmd.args, cwd: dir, timeout: timeout) {
                last = out
                break
            }
        }
        guard let out = last else {
            return Outcome(text: "Lỗi: không gọi được claude CLI (hết giờ/lỗi mạng). Đã thử 3 lần.", tokens: "")
        }
        // Thử đọc JSON {result, usage}; không có thì dùng text thô + ước tính.
        if let data = out.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String
        {
            let usage = json["usage"] as? [String: Any]
            let tin = (usage?["input_tokens"] as? UInt64) ?? estimateTokens(text: out)
            let tout = (usage?["output_tokens"] as? UInt64) ?? estimateTokens(text: result)
            return Outcome(text: result, tokens: "in \(tin) · out \(tout) · lõi ước tính")
        }
        return Outcome(text: out, tokens: "ước tính")
    }

    private static func exec(_ bin: String, args: [String], cwd: URL, timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline { p.terminate(); return nil }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // -- HTTP Messages API qua lõi (blocking → chạy nền) ----------------------
    private static func runCoreMessages(
        task: AiTaskKind,
        baseURL: String,
        apiKey: String,
        model: String,
        backend: String,
        version: String?,
        priceIn: Double,
        priceOut: Double,
        rawText: String
    ) async -> Outcome {
        let call = FfiMessagesCall(
            baseUrl: baseURL, apiKey: apiKey, anthropicVersion: version,
            model: model, task: task, rawText: rawText,
            priceInPerMtok: priceIn, priceOutPerMtok: priceOut, backendName: backend
        )
        do {
            // messagesCall chặn luồng (có retry nội) → tách khỏi executor chung.
            let res = try await Task.detached { try messagesCall(c: call) }.value
            let tok: String
            if let cost = res.costUsd {
                tok = "in \(res.inputTokens) · out \(res.outputTokens) · $\(String(format: "%.4f", cost))"
            } else {
                tok = "in \(res.inputTokens) · out \(res.outputTokens)"
            }
            return Outcome(text: res.text, tokens: tok)
        } catch {
            return Outcome(text: "Lỗi \(backend): \(error.localizedDescription).", tokens: "")
        }
    }

    // -- Dùng chung ----------------------------------------------------------
    private static func coreTask(_ t: AiTask) -> AiTaskKind {
        switch t {
        case .summarize: return .summarize
        case .translate: return .translate
        case .solve: return .solve
        case .analyze, .scamCheck: return .analyze
        }
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    // Keychain: API key chỉ giữ trong Keychain + RAM, không log.
    static func saveKey(_ key: String, account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = key.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadKey(account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
