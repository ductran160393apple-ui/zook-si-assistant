import AppKit
import SwiftUI

/// Popup menu bar: chức năng, bật/tắt auto, tự học, chọn model, nhập key.
struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("\(L("Tóm tắt", "Summarize")) (⌘⇧7)") { orch().handle(.summarize) }
            Button("\(L("Dịch", "Translate")) (⌘⇧8)") { orch().handle(.translate) }
            Button("\(L("Giải đề", "Solve")) (⌘⇧9)") { orch().handle(.solve) }
            Button("\(L("Kiểm tra lừa đảo", "Scam check")) (⌘⇧0)") { orch().handle(.scamCheck) }
            Divider()
            Toggle(L("Tự động phát hiện lừa đảo", "Auto scam detection"), isOn: Binding(
                get: { state.autoDetect },
                set: {
                    state.autoDetect = $0
                    UserDefaults.standard.set($0, forKey: "autoDetect")
                    let o = orch()
                    $0 ? o.monitor.start(state: state, analyzer: o.analyzer) : o.monitor.stop()
                }
            ))
            Toggle(L("Tự động phân tích màn hình", "Auto screen analysis"), isOn: Binding(
                get: { state.autoAnalyze },
                set: { state.autoAnalyze = $0; UserDefaults.standard.set($0, forKey: "autoAnalyze") }
            ))
            Divider()
            Picker(L("Mô hình", "Backend"), selection: $state.backend) {
                ForEach([BackendID.metaApi, .claudeCode, .geminiCli, .antigravity, .anthropic], id: \.self) {
                    Text($0.displayName(state.lang)).tag($0)
                }
            }
            Picker("Ngôn ngữ / Language", selection: Binding(
                get: { state.lang },
                set: { state.lang = $0; UserDefaults.standard.set($0.rawValue, forKey: "appLang") }
            )) {
                Text("Tiếng Việt").tag(AppLang.vi)
                Text("English").tag(AppLang.en)
            }
            SecureField("Meta API key", text: $state.metaApiKey)
                .onSubmit { AiRunner.saveKey(state.metaApiKey, account: "meta-api-key"); state.metaApiKey = "" }
            SecureField("Anthropic API key", text: $state.anthropicApiKey)
                .onSubmit { AiRunner.saveKey(state.anthropicApiKey, account: "anthropic-api-key"); state.anthropicApiKey = "" }
            TextField("Meta base URL", text: $state.metaBaseURL)
                .onSubmit { UserDefaults.standard.set(state.metaBaseURL, forKey: "metaBaseURL") }
            ModelPickerRow(title: L("Model Muse/Meta", "Muse/Meta model"), model: $state.metaModel, known: MetaModels.list, defaultsKey: "metaModel")
            ModelPickerRow(title: L("Model Claude Code", "Claude Code model"), model: $state.claudeModel, known: ClaudeModels.list, defaultsKey: "claudeModel")
            ModelPickerRow(title: L("Model Antigravity", "Antigravity model"), model: $state.agyModel, known: AgyModels.list, defaultsKey: "agyModel")
            TextField(L("Gemini model (trống = CLI tự chọn)", "Gemini model (empty = CLI auto-selects)"), text: $state.geminiModel)
                .onSubmit { UserDefaults.standard.set(state.geminiModel, forKey: "geminiModel") }
            PanelColorRow(title: L("Màu chữ kết quả", "Result text color"), hex: $state.resultTextColorHex, defaultsKey: "resultTextColorHex")
            PanelColorRow(title: L("Màu chữ gỡ lỗi", "Debug text color"), hex: $state.debugTextColorHex, defaultsKey: "debugTextColorHex")
            PanelColorRow(title: L("Màu chữ cảnh báo", "Warning text color"), hex: $state.warningTextColorHex, defaultsKey: "warningTextColorHex")
            Text(L("Chạm để chọn (lưu ngay); ô tự nhập nhấn Enter để lưu.", "Tap to select (saves instantly); custom fields need Enter."))
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            Button(state.isLearning ? L("Đang học…", "Learning…") : L("Chạy học ngay", "Learn now")) { LearnScheduler.runNow(state: state) }
                .disabled(state.isLearning)
            Picker(L("Tự học", "Auto-learn"), selection: $state.learnAuto) {
                ForEach(LearnAuto.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .onChange(of: state.learnAuto) {
                UserDefaults.standard.set(state.learnAuto.rawValue, forKey: "learnAuto")
                state.applyLearnAuto()
            }
            Button(L("Mở cảnh báo tự động", "Open auto alerts")) { AppDelegate.current?.showWarningPanel() }
            Button(L("Mở gỡ lỗi", "Open debug")) { AppDelegate.current?.openDebugWindow() }
            Button(L("Thoát", "Quit")) { NSApplication.shared.terminate(nil) }
            Text("SiAssitant \(L("bản", "build")) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 300)
    }

    private func orch() -> Orchestrator {
        AppDelegate.current?.orchestrator ?? Orchestrator()
    }
}

/// Danh sách model đã biết theo backend (phần tử đầu = mặc định).
/// Nguồn: https://dev.meta.ai/docs/models (Meta), `agy models` (Antigravity),
/// bí danh --model của claude CLI (opus/sonnet/haiku).
enum MetaModels {
    static let list = ["muse-spark-1.3", "muse-spark-1.2", "muse-spark-1.1"]
}

enum ClaudeModels {
    static let list = ["opus", "sonnet", "haiku"]
}

enum AgyModels {
    static let list = [
        "gemini-4-argon-medium", "gemini-4-argon-high", "gemini-4-argon-low",
        "gemini-3.8-flash-high", "gemini-3.8-flash-medium", "gemini-3.8-flash-low",
        "claude-opus-5-5-low", "claude-opus-5-5-medium", "claude-opus-5-5-high",
        "claude-sonnet-5-5-low", "claude-sonnet-5-5-medium", "claude-sonnet-5-5-high",
        "gpt-oss-120b-medium",
    ]
}

/// Logic chọn model (hàm thuần, có unit test): model trong danh sách thì
/// Picker chọn trực tiếp, còn lại (kể cả rỗng) rơi vào ô "Tự nhập…".
enum ModelChoice {
    static let customTag = "￼tự-nhập"

    static func selection(model: String, known: [String]) -> String {
        known.contains(model) ? model : customTag
    }

    /// Chốt ô tự nhập: cắt khoảng trắng thừa; bỏ trống thì về mặc định.
    static func commit(text: String, defaultModel: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? defaultModel : t
    }
}

/// Một hàng chọn model: Picker lưu ngay vào UserDefaults; mục "Tự nhập…"
/// mở ô text cho model ID mới (Enter để lưu).
struct ModelPickerRow: View {
    let title: String
    @Binding var model: String
    let known: [String]
    let defaultsKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker(title, selection: Binding(
                get: { ModelChoice.selection(model: model, known: known) },
                set: {
                    if $0 == ModelChoice.customTag {
                        model = ""
                    } else {
                        model = $0
                        UserDefaults.standard.set($0, forKey: defaultsKey)
                    }
                }
            )) {
                ForEach(known, id: \.self) { Text($0).tag($0) }
                Text(L("Tự nhập…", "Custom…")).tag(ModelChoice.customTag)
            }
            if ModelChoice.selection(model: model, known: known) == ModelChoice.customTag {
                TextField(L("Nhập model ID rồi Enter", "Type model ID, then Enter"), text: $model)
                    .onSubmit {
                        model = ModelChoice.commit(text: model, defaultModel: known.first ?? "")
                        UserDefaults.standard.set(model, forKey: defaultsKey)
                    }
            }
        }
    }
}

/// Màu chữ panel do người dùng chọn (hàm thuần, có unit test).
/// Hex hợp lệ "#RRGGBB" (có/không dấu #); còn lại → màu hệ thống.
enum PanelColor {
    static func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (
            r: Double((v >> 16) & 0xFF) / 255,
            g: Double((v >> 8) & 0xFF) / 255,
            b: Double(v & 0xFF) / 255
        )
    }

    static func textColor(hex: String) -> Color {
        guard let c = rgb(hex: hex) else { return .primary }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Chốt ô hex tự nhập: cắt khoảng trắng; rỗng = tự động; sai → giữ cũ.
    static func commitHex(text: String, current: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        return rgb(hex: t) == nil ? current : t
    }
}

/// Một hàng chọn màu chữ cho một panel: chấm màu chạm là lưu ngay (không
/// lag như ColorPicker kéo-thả) + ô hex cho màu tùy ý (Enter để lưu).
struct PanelColorRow: View {
    let title: String
    @Binding var hex: String
    let defaultsKey: String
    /// Nháp ô hex: gõ không động vào panel (tránh nhấp nháy + lag),
    /// chỉ Enter mới chốt.
    @State private var draft = ""

    /// Bảng màu iOS chuẩn, đọc tốt trên nền kính cả sáng lẫn tối.
    static let presets = ["#000000", "#FFFFFF", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#AF52DE"]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                ForEach(Self.presets, id: \.self) { p in
                    Button {
                        hex = p
                        UserDefaults.standard.set(p, forKey: defaultsKey)
                    } label: {
                        Circle()
                            .fill(PanelColor.textColor(hex: p))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: hex == p ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                }
                Button(L("Tự động", "Auto")) {
                    hex = ""
                    UserDefaults.standard.set("", forKey: defaultsKey)
                }
            }
            TextField(L("Hex vd #FFCC00 (Enter để lưu, xóa = tự động)", "Hex e.g. #FFCC00 (Enter to save, clear = auto)"), text: $draft)
                .onAppear { draft = hex }
                .onChange(of: hex) { draft = hex }
                .onSubmit {
                    hex = PanelColor.commitHex(text: draft, current: hex)
                    UserDefaults.standard.set(hex, forKey: defaultsKey)
                    draft = hex
                }
        }
    }
}

/// Nền kính trong suốt: thấy rõ màn hình sau (không blur, lớp phủ rất
/// loãng), chữ đọc được nhờ vầng sáng ngược tông trên text.
struct GlassBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        (scheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.18))
    }
}

/// Panel kết quả nổi, chia tab theo tác vụ tay (mỗi tab giữ kết quả
/// riêng, không đè nhau): header đặc dễ đọc + nội dung nền kính xuyên thấu
/// (GlassBackground trên cửa sổ trong suốt) + chữ có vầng sáng nhẹ;
/// zoom 0,6×–2× (nút hoặc ⌘⇧=/⌘⇧− khi mở); Sao chép/Đóng;
/// đánh giá case Đúng là lừa đảo/Báo nhầm.
struct ResultPanel: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header đặc (không xuyên thấu) để luôn dễ đọc.
            HStack {
                Text("SiAssitant")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            TabView(selection: $state.selectedTask) {
                ForEach(ManualTabs.list, id: \.self) { task in
                    tabContent(task: task)
                        .tabItem { Text(PanelTitle.name(task: task, lang: state.lang)) }
                        .tag(task)
                }
            }
            HStack {
                Button("−") { state.zoom = max(0.6, state.zoom - 0.1) }
                Button("+") { state.zoom = min(2.0, state.zoom + 0.1) }
                Button(L("Sao chép", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.result(for: state.selectedTask), forType: .string)
                }
                Button(L("Đúng là lừa đảo", "Confirmed scam")) { LearnStore.load().recordVerdict(state: state, scam: true) }
                Button(L("Báo nhầm", "False alarm")) { LearnStore.load().recordVerdict(state: state, scam: false) }
                Button(L("Đóng", "Close")) { AppDelegate.current?.hidePanel() }
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 520)
        .background(GlassBackground())
    }

    private func tabContent(task: AiTask) -> some View {
        VStack(alignment: .leading) {
            let warn = state.warning(for: task)
            if !warn.isEmpty {
                Text(warn).background(.red).foregroundColor(.white).padding(4)
            }
            ScrollView {
                Text(state.result(for: task))
                    .foregroundColor(PanelColor.textColor(hex: state.resultTextColorHex))
                    .textSelection(.enabled)
                    // Vầng sáng ngược tông để chữ nổi trên nền kính.
                    .shadow(color: scheme == .dark ? .black.opacity(0.8) : .white, radius: 3)
            }
            .scaleEffect(state.zoom)
        }
        .padding()
    }
}

/// Panel cảnh báo auto (riêng với panel tay): verdict lừa đảo mới nhất +
/// ô phân tích tự động + màu mức độ trên header.
struct WarningPanel: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    /// Tên màu mức cảnh báo (hàm thuần, có unit test).
    static func levelColorName(level: String) -> String {
        switch level {
        case "dangerous": return "red"
        case "suspicious": return "orange"
        default: return "green"
        }
    }

    static func levelColor(level: String) -> Color {
        switch levelColorName(level: level) {
        case "red": return .red
        case "orange": return .orange
        default: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(state.autoWarnTitle.isEmpty ? L("Cảnh báo tự động", "Auto alerts") : state.autoWarnTitle)
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(Self.levelColor(level: state.autoWarnLevel))
                    .frame(width: 12, height: 12)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            VStack(alignment: .leading) {
                ScrollView {
                    Text(state.autoWarnBody)
                        .foregroundColor(PanelColor.textColor(hex: state.warningTextColorHex))
                        .textSelection(.enabled)
                        .shadow(color: scheme == .dark ? .black.opacity(0.8) : .white, radius: 3)
                }
                if !state.autoAnalysis.isEmpty {
                    Divider()
                    Text(L("Phân tích tự động", "Automatic analysis"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(state.autoAnalysis)
                            .font(.callout)
                            .foregroundColor(PanelColor.textColor(hex: state.warningTextColorHex))
                            .textSelection(.enabled)
                            .shadow(color: scheme == .dark ? .black.opacity(0.8) : .white, radius: 3)
                    }
                    .frame(maxHeight: 180)
                }
                HStack {
                    Button(L("Sao chép", "Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.autoWarnBody, forType: .string)
                    }
                    Spacer()
                    Button(L("Đóng", "Close")) { AppDelegate.current?.hideWarningPanel() }
                }
            }
            .padding()
        }
        .frame(minWidth: 420, minHeight: 520)
        .background(GlassBackground())
    }
}

/// Gán nền trong suốt cho NSWindow chứa view SwiftUI (gắn qua .background).
/// Nội dung tự lót material để chữ vẫn đọc rõ.
struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Dòng kết quả realtime cho mỗi lần quét tự động mới (hàm thuần, có
/// unit test). An toàn: 1 dòng; đáng ngờ: kèm lý do.
enum AutoClear {
    /// Monitor nhường panel cho kết quả bấm tay trong cửa sổ này.
    static let manualWindowSecs = 30.0

    /// Kết quả bấm tay còn mới không (hàm thuần, có unit test).
    static func manualFresh(since: Date?, now: Date) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) < manualWindowSecs
    }

    static func scanLine(app: String, score: UInt32, level: String, reasons: [String], date: Date, lang: AppLang) -> String {
        let name: String
        switch (level, lang) {
        case ("suspicious", .en): name = "SUSPICIOUS"
        case ("suspicious", _): name = "ĐÁNG NGỜ"
        case (_, .en): name = "Safe"
        default: name = "An toàn"
        }
        var s = "\(name) (\(score)/100) — \(app) · \(LogTime.string(from: date))."
        if level == "suspicious", !reasons.isEmpty {
            s += "\n" + reasons.map { "• \($0)" }.joined(separator: "\n")
        }
        return s
    }
}

/// Mặt icon status-bar theo mức cảnh báo (hàm thuần, có unit test).
/// MenuBarExtra luôn render đơn sắc nên app dùng NSStatusItem với ảnh tô
/// màu thật: đỏ khi nguy hiểm, cam khi đáng ngờ, đơn sắc khi an toàn.
enum AlertFace {
    static func symbol(level: String) -> String {
        switch level {
        case "dangerous": return "exclamationmark.shield.fill"
        case "suspicious": return "shield.fill"
        default: return "shield"
        }
    }

    /// Tên màu khiên: red/orange/none (none = đơn sắc theo hệ thống).
    static func shieldColorName(level: String) -> String {
        switch level {
        case "dangerous": return "red"
        case "suspicious": return "orange"
        default: return "none"
        }
    }

    /// Ảnh status-bar 16pt tô màu theo mức (màu thật, không template).
    static func statusImage(level: String) -> NSImage {
        let fallback = NSImage(size: NSSize(width: 18, height: 18))
        guard let base = NSImage(systemSymbolName: symbol(level: level), accessibilityDescription: "SiAssitant") else {
            return fallback
        }
        var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let color: NSColor? =
            level == "dangerous" ? .systemRed :
            level == "suspicious" ? .systemOrange : nil
        if let c = color {
            let pal = NSImage.SymbolConfiguration(paletteColors: [c])
            config = config.applying(pal) ?? config
        }
        let img = base.withSymbolConfiguration(config) ?? base
        img.isTemplate = (color == nil)
        return img
    }

    /// Khung phát sáng (radiant) cho nhịp nhấp nháy khi nguy hiểm: cùng
    /// kích thước khung thường, vầng đỏ/cam quanh symbol.
    static func glowImage(level: String) -> NSImage {
        let base = statusImage(level: level)
        let size = base.size
        let out = NSImage(size: size)
        out.lockFocus()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowColor = level == "dangerous" ? NSColor.systemRed : NSColor.systemOrange
        shadow.shadowOffset = .zero
        shadow.set()
        base.draw(
            in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: size),
            operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: nil
        )
        out.unlockFocus()
        out.isTemplate = false
        return out
    }
}

/// Giờ HH:mm:ss cho từng dòng nhật ký (hàm thuần, có unit test).
enum LogTime {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func string(from date: Date) -> String { fmt.string(from: date) }
}

/// Cửa sổ debug 4 tab: Nhật ký / Kho luật / Báo cáo / Mạng. Nền kính xuyên thấu
/// (GlassBackground, cùng kiểu với panel kết quả).
struct DebugWindow: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            List(state.entries) { e in
                VStack(alignment: .leading) {
                    Text("\(LogTime.string(from: e.date)) · \(e.app) · \(e.score) · \(label(e.level))")
                    ForEach(e.reasons, id: \.self) { Text("• \($0)").font(.caption) }
                    Text(e.tokens).font(.caption2).foregroundColor(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .tabItem { Text(L("Nhật ký", "Log")) }
            VStack(alignment: .leading) {
                Text(state.rulesSummary).font(.caption)
                HStack {
                    Button(state.isLearning ? L("Đang học…", "Learning…") : L("Chạy học ngay", "Learn now")) { LearnScheduler.runNow(state: state) }
                        .disabled(state.isLearning)
                    if state.isLearning {
                        Button(L("Hủy", "Cancel")) { LearnScheduler.cancel() }
                    }
                    Button(L("Hoàn tác", "Undo")) { LearnStore.load().undo(state: state) }
                }
            }
            .padding()
            .tabItem { Text(L("Kho luật", "Rules")) }
            ScrollView { Text(state.lastReport).font(.caption) }
                .padding()
                .tabItem { Text(L("Báo cáo", "Report")) }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(L("Mức", "Level")): \(state.netLevel)").bold()
                    Text(state.netSummary.isEmpty ? L("Chưa quét.", "Not scanned yet.") : state.netSummary).font(.caption)
                    Text(state.netTop).font(.caption).foregroundColor(.secondary)
                    Divider()
                    Toggle(L("Bật giám sát mạng (60s)", "Enable net monitor (60s)"), isOn: Binding(
                        get: { state.netDetect },
                        set: { state.netDetect = $0; UserDefaults.standard.set($0, forKey: "netDetect") }
                    )).font(.caption)
                    Toggle(L("LLM on-device hiệu đính", "On-device LLM review"), isOn: Binding(
                        get: { state.netLlmEnabled },
                        set: { state.netLlmEnabled = $0; UserDefaults.standard.set($0, forKey: "netLlmEnabled") }
                    )).font(.caption)
                    TextField("Base URL (Ollama /v1)", text: Binding(
                        get: { state.netLlmBase },
                        set: { state.netLlmBase = $0; UserDefaults.standard.set($0, forKey: "netLlmBase") }
                    )).font(.caption).textFieldStyle(.roundedBorder)
                    TextField(L("Model (vd: llama3.2)", "Model (e.g. llama3.2)"), text: Binding(
                        get: { state.netLlmModel },
                        set: { state.netLlmModel = $0; UserDefaults.standard.set($0, forKey: "netLlmModel") }
                    )).font(.caption).textFieldStyle(.roundedBorder)
                    if !state.netLlmVerdict.isEmpty {
                        Text(L("LLM hiệu đính:", "LLM review:")).bold().font(.caption)
                        Text(state.netLlmVerdict).font(.caption)
                    }
                }
                .padding()
            }
            .tabItem { Text(L("Mạng", "Net")) }
        }
        .foregroundColor(PanelColor.textColor(hex: state.debugTextColorHex))
        .frame(width: 640, height: 480)
        .background(TransparentWindow())
        .background(GlassBackground())
    }

    private func label(_ level: String) -> String {
        switch level {
        case "dangerous": return L("NGUY HIỂM", "DANGEROUS")
        case "suspicious": return L("ĐÁNG NGỜ", "SUSPICIOUS")
        default: return L("AN TOÀN", "SAFE")
        }
    }

    /// openWindow không đẩy cửa sổ đã mở lên trước → tự kích hoạt app
    /// và đưa cửa sổ Gỡ lỗi lên đầu, lấy focus.
    static func bringToFront() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.title == "Gỡ lỗi" {
                w.makeKeyAndOrderFront(nil)
            }
        }
    }
}
