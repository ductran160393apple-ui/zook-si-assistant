import Combine
import Foundation

enum BackendID: String, CaseIterable {
    case claudeCode = "Claude Code (mặc định)"
    case metaApi = "Muse/Meta (API key)"
    case argon = "Gemini Argon (Antigravity)"
    case anthropic = "Anthropic API (dự phòng)"
}

enum AiTask: String {
    case summarize, translate, solve, analyze, scamCheck
}

struct ScanEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let app: String
    let score: UInt32
    let level: String
    let reasons: [String]
    let tokens: String
}

/// State dùng chung: lựa chọn backend/model, log debug (RAM, ≤300 dòng).
final class AppState: ObservableObject {
    static let shared = AppState()

    /// Ngữ cảnh lần quét cuối cho nút đánh giá case.
    struct LastScan {
        let app: String
        let text: String
        let score: UInt32
        let reasons: [String]
    }
    @Published var backend: BackendID = .claudeCode
    @Published var metaApiKey: String = ""
    @Published var anthropicApiKey: String = ""
    @Published var isLearning = false
    @Published var metaBaseURL = "https://api.meta.ai/v1"
    @Published var claudeModel = "opus-5.5"
    @Published var metaModel = "meta-llama-3.1-70b"
    @Published var autoDetect = false
    @Published var autoAnalyze = false
    @Published var entries: [ScanEntry] = []
    @Published var lastResult: String = ""
    @Published var lastWarning: String = ""
    @Published var zoom: Double = 1.0
    @Published var rulesSummary: String = "Chưa tải kho luật."
    @Published var lastReport: String = "Chưa có báo cáo vòng học."
    var lastScan: LastScan?

    func log(app: String, score: UInt32, level: String, reasons: [String], tokens: String) {
        entries.append(ScanEntry(app: app, score: score, level: level, reasons: reasons, tokens: tokens))
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }
}
