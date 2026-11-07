import Combine
import Foundation

/// Ngôn ngữ giao diện: tiếng Việt (mặc định) / English.
enum AppLang: String {
    case vi, en

    /// Đối chiếu sang enum lõi Rust (UniFFI).
    var core: AiLang { self == .en ? .en : .vi }
}

/// Chuỗi song ngữ: L("Tóm tắt", "Summarize"). Đọc ngôn ngữ hiện tại từ
/// AppState.shared — mọi view đều observe state nên đổi là vẽ lại ngay.
/// (Không gọi trong khởi tạo AppState.shared để tránh đệ quy.)
func L(_ vi: String, _ en: String) -> String {
    AppState.shared.lang == .en ? en : vi
}

enum BackendID: String, CaseIterable {
    case claudeCode = "Claude Code (CLI)"
    case metaApi = "Muse/Meta (API key, mặc định)"
    case geminiCli = "Gemini CLI"
    case antigravity = "Antigravity (agy CLI)"
    case anthropic = "Anthropic API (dự phòng)"

    /// Tên hiển thị theo ngôn ngữ (hàm thuần, có unit test).
    func displayName(_ lang: AppLang) -> String {
        guard lang == .en else { return rawValue }
        switch self {
        case .metaApi: return "Muse/Meta (API key, default)"
        case .anthropic: return "Anthropic API (fallback)"
        default: return rawValue
        }
    }
}

enum AiTask: String, Hashable {
    case summarize, translate, solve, analyze, scamCheck
}

/// Tab panel chính: 4 tác vụ bấm tay, mỗi tab giữ kết quả riêng để hiển
/// thị đồng thời (analyze chỉ chạy auto nên không có tab tay).
enum ManualTabs {
    static let list: [AiTask] = [.summarize, .translate, .solve, .scamCheck]
}

/// Tên tác vụ hiển thị trên header panel (hàm thuần, có unit test).
enum PanelTitle {
    static func name(task: AiTask, lang: AppLang = .vi) -> String {
        switch (task, lang) {
        case (.summarize, .vi): return "Tóm tắt"
        case (.summarize, _): return "Summarize"
        case (.translate, .vi): return "Dịch"
        case (.translate, _): return "Translate"
        case (.solve, .vi): return "Giải đề"
        case (.solve, _): return "Solve"
        case (.analyze, .vi): return "Phân tích"
        case (.analyze, _): return "Analyze"
        case (.scamCheck, .vi): return "Kiểm tra lừa đảo"
        case (.scamCheck, _): return "Scam check"
        }
    }
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
    @Published var backend: BackendID = .metaApi
    @Published var metaApiKey: String = ""
    @Published var anthropicApiKey: String = ""
    @Published var isLearning = false
    @Published var learnAuto: LearnAuto = LearnAuto(rawValue: UserDefaults.standard.string(forKey: "learnAuto") ?? "off") ?? .off
    @Published var metaBaseURL = UserDefaults.standard.string(forKey: "metaBaseURL") ?? "https://api.meta.ai/v1"
    @Published var claudeModel = UserDefaults.standard.string(forKey: "claudeModel") ?? "opus"
    @Published var metaModel = UserDefaults.standard.string(forKey: "metaModel") ?? "muse-spark-1.3"
    @Published var geminiModel = UserDefaults.standard.string(forKey: "geminiModel") ?? "auto"
    @Published var agyModel = UserDefaults.standard.string(forKey: "agyModel") ?? "gemini-4-argon-medium"
    @Published var autoDetect = UserDefaults.standard.bool(forKey: "autoDetect")
    @Published var autoAnalyze = UserDefaults.standard.bool(forKey: "autoAnalyze")
    @Published var entries: [ScanEntry] = []
    /// Ô kết quả + dải cảnh báo riêng từng tab tay (không đè nhau).
    @Published var taskResults: [AiTask: String] = [:]
    @Published var taskWarnings: [AiTask: String] = [:]
    @Published var selectedTask: AiTask = .summarize
    /// Panel cảnh báo auto: verdict mới nhất + phân tích + mức màu.
    @Published var autoWarnTitle: String = ""
    @Published var autoWarnBody: String = ""
    @Published var autoWarnLevel: String = "safe"
    @Published var autoAnalysis: String = ""
    /// Mức cảnh báo mới nhất (safe/suspicious/dangerous) để đổi icon menu.
    @Published var alertLevel: String = "safe"
    @Published var lang: AppLang = AppLang(rawValue: UserDefaults.standard.string(forKey: "appLang") ?? "vi") ?? .vi
    /// Màu chữ riêng từng panel (hex "#RRGGBB"); rỗng = tự động theo hệ thống.
    @Published var resultTextColorHex = UserDefaults.standard.string(forKey: "resultTextColorHex") ?? ""
    @Published var debugTextColorHex = UserDefaults.standard.string(forKey: "debugTextColorHex") ?? ""
    @Published var warningTextColorHex = UserDefaults.standard.string(forKey: "warningTextColorHex") ?? ""
    @Published var zoom: Double = 1.0
    // Giá trị đầu đọc UserDefaults trực tiếp (không qua L() để tránh
    // chạm AppState.shared trong lúc nó đang khởi tạo).
    @Published var rulesSummary: String = UserDefaults.standard.string(forKey: "appLang") == "en"
        ? "Rule store not loaded." : "Chưa tải kho luật."
    @Published var lastReport: String = UserDefaults.standard.string(forKey: "appLang") == "en"
        ? "No learning report yet." : "Chưa có báo cáo vòng học."
    var lastScan: LastScan?
    // Trạng thái giám sát mạng (NetMonitor tick 60s, riêng alertLevel scam).
    @Published var netLevel: String = "safe"
    @Published var netSummary: String = ""
    @Published var netTop: String = ""
    @Published var netLlmVerdict: String = ""
    @Published var netDetect: Bool = UserDefaults.standard.object(forKey: "netDetect") as? Bool ?? true
    @Published var netLlmEnabled: Bool = UserDefaults.standard.object(forKey: "netLlmEnabled") as? Bool ?? true
    @Published var netLlmBase: String = UserDefaults.standard.string(forKey: "netLlmBase") ?? "http://127.0.0.1:11434/v1"
    @Published var netLlmModel: String = UserDefaults.standard.string(forKey: "netLlmModel") ?? "llama3.2"

    func log(app: String, score: UInt32, level: String, reasons: [String], tokens: String) {
        entries.append(ScanEntry(app: app, score: score, level: level, reasons: reasons, tokens: tokens))
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
    }

    /// Đọc ô tab (trống khi chưa có kết quả). Có unit test.
    func result(for task: AiTask) -> String { taskResults[task] ?? "" }
    func warning(for task: AiTask) -> String { taskWarnings[task] ?? "" }

    /// Ghi ô tab + nhảy tới tab đó (analyze không có tab tay → về summarize).
    func showTask(_ task: AiTask, result: String, warning: String? = nil) {
        taskResults[task] = result
        if let w = warning { taskWarnings[task] = w }
        selectedTask = ManualTabs.list.contains(task) ? task : .summarize
    }
}
