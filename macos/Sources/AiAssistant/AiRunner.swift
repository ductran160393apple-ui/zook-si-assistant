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
            return runClaude(task: coreTask, redactedText: redactedText, model: state.claudeModel, lang: state.lang.core)
        case .metaApi:
            // Ưu tiên key vừa gõ (kẻo key cũ trong Keychain đè key mới chưa Enter).
            guard let key = nonEmpty(state.metaApiKey) ?? loadKey(account: "meta-api-key") else {
                return Outcome(text: L("Thiếu API key (meta). Nhập key trong popup menu.", "Missing API key (meta). Enter it in the popup menu."), tokens: "")
            }
            return await runCoreMessages(
                task: coreTask, baseURL: state.metaBaseURL, apiKey: key,
                model: state.metaModel, backend: "meta", version: nil,
                priceIn: 1.25, priceOut: 4.25, rawText: redactedText,
                lang: state.lang.core
            )
        case .anthropic:
            guard let key = nonEmpty(state.anthropicApiKey) ?? loadKey(account: "anthropic-api-key") else {
                return Outcome(text: L("Thiếu API key (anthropic). Nhập key trong popup menu.", "Missing API key (anthropic). Enter it in the popup menu."), tokens: "")
            }
            return await runCoreMessages(
                task: coreTask, baseURL: "https://api.anthropic.com/v1", apiKey: key,
                model: state.claudeModel, backend: "anthropic", version: "2023-06-01",
                priceIn: 0.003, priceOut: 0.015, rawText: redactedText,
                lang: state.lang.core
            )
        case .geminiCli:
            return runGenericCli(
                task: coreTask, redactedText: redactedText,
                cmd: geminiCommandArgs(model: state.geminiModel, task: coreTask, redacted: redactedText, lang: state.lang.core),
                label: "gemini",
                missingHint: L(
                    "chưa cài `gemini` (npm i -g @google/gemini-cli), chưa đăng nhập, hoặc hết giờ",
                    "`gemini` not installed (npm i -g @google/gemini-cli), not logged in, or timed out"
                )
            )
        case .antigravity:
            return runAgy(
                task: coreTask, redactedText: redactedText,
                cmd: agyCommandArgs(model: state.agyModel, task: coreTask, redacted: redactedText, lang: state.lang.core)
            )
        }
    }

    // -- Claude Code CLI cô lập (lệnh do lõi dựng) ---------------------------
    private static func runClaude(task: AiTaskKind, redactedText: String, model: String, lang: AiLang) -> Outcome {
        let cmd = claudeCommandArgs(model: model, task: task, redacted: redactedText, lang: lang)
        guard let out = runCliTool(cmd: cmd, timeout: TimeInterval(taskTimeoutSecs(task: task))) else {
            return Outcome(text: L(
                "Lỗi: không gọi được claude CLI (hết giờ/lỗi mạng). Đã thử 3 lần.",
                "Error: cannot reach claude CLI (timeout/network). Tried 3 times."
            ), tokens: "")
        }
        return parseClaudeOutput(out)
    }

    /// Đọc JSON `claude -p` {result, usage} (hàm thuần, có unit test);
    /// không phải JSON thì dùng text thô + ước tính.
    static func parseClaudeOutput(_ out: String) -> Outcome {
        if let data = out.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String
        {
            if (json["is_error"] as? Bool) ?? false {
                return Outcome(text: "\(L("Lỗi Claude: ", "Claude error: "))\(result)", tokens: "")
            }
            if result.isEmpty {
                return Outcome(text: L("(AI không trả về nội dung văn bản.)", "(The AI returned no text.)"), tokens: "")
            }
            let usage = json["usage"] as? [String: Any]
            let tin = (usage?["input_tokens"] as? UInt64) ?? estimateTokens(text: out)
            let tout = (usage?["output_tokens"] as? UInt64) ?? estimateTokens(text: result)
            return Outcome(text: result, tokens: "in \(tin) · out \(tout) · \(L("lõi ước tính", "core estimated"))")
        }
        return Outcome(text: out, tokens: L("ước tính", "estimated"))
    }

    /// Thực thi lệnh CLI trong thư mục tạm, thử 3 lần. nil = không chạy được.
    private static func runCliTool(cmd: FfiCliCommand, timeout: TimeInterval) -> String? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for _ in 0 ... 2 {
            // /usr/bin/env để giải PATH (executableURL không tự tìm PATH).
            if let out = exec("/usr/bin/env", args: [cmd.bin] + cmd.args, cwd: dir, timeout: timeout),
               !out.isEmpty
            {
                return out
            }
        }
        return nil
    }

    // -- Gemini CLI: JSON đọc khoan dung nhiều khóa, thiếu số liệu thì ước tính.
    private static func runGenericCli(
        task: AiTaskKind, redactedText: String, cmd: FfiCliCommand, label: String, missingHint: String
    ) -> Outcome {
        guard let out = runCliTool(cmd: cmd, timeout: TimeInterval(taskTimeoutSecs(task: task))) else {
            return Outcome(text: L(
                "Lỗi: không gọi được \(label) CLI (\(missingHint)). Đã thử 3 lần.",
                "Error: cannot reach \(label) CLI (\(missingHint)). Tried 3 times."
            ), tokens: "")
        }
        return parseGenericCliOutput(out)
    }

    /// Đọc JSON CLI khoan dung nhiều khóa (hàm thuần, có unit test).
    static func parseGenericCliOutput(_ out: String) -> Outcome {
        if let data = out.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            for key in ["response", "text", "output", "result"] {
                if let s = json[key] as? String, !s.isEmpty {
                    return Outcome(text: s, tokens: L("lõi ước tính", "core estimated"))
                }
            }
        }
        return Outcome(text: out, tokens: L("ước tính", "estimated"))
    }

    // -- Antigravity: envelope {status, response, error?, usage?} theo docs
    // headless; xác thực dùng chung phiên đăng nhập app (không key riêng).
    private static func runAgy(task: AiTaskKind, redactedText: String, cmd: FfiCliCommand) -> Outcome {
        guard let out = runCliTool(cmd: cmd, timeout: TimeInterval(taskTimeoutSecs(task: task))) else {
            return Outcome(
                text: L(
                    "Lỗi: không gọi được agy CLI (chưa cài, chưa đăng nhập, hoặc hết giờ). "
                        + "Cài: curl -fsSL https://antigravity.google/cli/install.sh | bash — rồi đăng nhập 1 lần. Đã thử 3 lần.",
                    "Error: cannot reach agy CLI (not installed, not logged in, or timed out). "
                        + "Install: curl -fsSL https://antigravity.google/cli/install.sh | bash — then log in once. Tried 3 times."
                ),
                tokens: ""
            )
        }
        return parseAgyOutput(out)
    }

    /// Đọc envelope agy {status, response, error?, usage?} (hàm thuần,
    /// có unit test với payload thật thu trên máy).
    static func parseAgyOutput(_ out: String) -> Outcome {
        if let data = out.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            if let status = json["status"] as? String, status != "SUCCESS" {
                let err = (json["error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? status
                return Outcome(text: "\(L("Lỗi agy: ", "agy error: "))\(err)", tokens: "")
            }
            if let s = json["response"] as? String, !s.isEmpty {
                if let usage = json["usage"] as? [String: Any],
                   let tin = usage["input_tokens"] as? UInt64,
                   let tout = usage["output_tokens"] as? UInt64
                {
                    return Outcome(text: s, tokens: "in \(tin) · out \(tout)")
                }
                return Outcome(text: s, tokens: L("lõi ước tính", "core estimated"))
            }
            return Outcome(text: L("(agy không trả về nội dung văn bản.)", "(agy returned no text.)"), tokens: "")
        }
        return Outcome(text: out, tokens: "ước tính")
    }

    private static func exec(_ bin: String, args: [String], cwd: URL, timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.currentDirectoryURL = cwd
        // App mở từ Finder không thừa hưởng PATH của shell → đặt đầy đủ để
        // /usr/bin/env tìm được claude/gemini/agy ở vị trí phổ biến.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = ProcessInfo.processInfo.environment
        let extra = ["/usr/local/bin", "/opt/homebrew/bin", "\(home)/.local/bin", "\(home)/.antigravity/bin"]
        let base = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = ([base] + extra).joined(separator: ":")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
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
        rawText: String,
        lang: AiLang
    ) async -> Outcome {
        let call = FfiMessagesCall(
            baseUrl: baseURL, apiKey: apiKey, anthropicVersion: version,
            model: model, task: task, rawText: rawText,
            priceInPerMtok: priceIn, priceOutPerMtok: priceOut, backendName: backend,
            lang: lang
        )
        do {
            // messagesCall chặn luồng (có retry nội) → tách khỏi executor chung.
            let res = try await Task.detached { try messagesCall(c: call) }.value
            if res.text.isEmpty {
                return Outcome(text: L("(AI không trả về nội dung văn bản.)", "(The AI returned no text.)"), tokens: "")
            }
            let tok: String
            if let cost = res.costUsd {
                tok = "in \(res.inputTokens) · out \(res.outputTokens) · $\(String(format: "%.4f", cost))"
            } else {
                tok = "in \(res.inputTokens) · out \(res.outputTokens)"
            }
            return Outcome(text: res.text, tokens: tok)
        } catch {
            if case let FfiAiError.Failed(message) = error {
                return Outcome(text: "\(L("Lỗi", "Error")) \(backend): \(message).", tokens: "")
            }
            return Outcome(text: "\(L("Lỗi", "Error")) \(backend): \(error.localizedDescription).", tokens: "")
        }
    }

    // -- Dùng chung ----------------------------------------------------------
    private static func coreTask(_ t: AiTask) -> AiTaskKind {
        switch t {
        case .summarize: return .summarize
        case .translate: return .translate
        case .solve: return .solve
        case .analyze: return .analyze
        case .scamCheck: return .scamCheck
        }
    }

    // Cắt khoảng trắng dán thừa (nguồn 401 phổ biến); rỗng → nil.
    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // Keychain: API key chỉ giữ trong Keychain + RAM, không log.
    static func saveKey(_ key: String, account: String) {
        guard let trimmed = nonEmpty(key) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = trimmed.data(using: .utf8)!
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadKey(account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: account,
                                kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8)
        else { return nil }
        return nonEmpty(s)
    }
}
