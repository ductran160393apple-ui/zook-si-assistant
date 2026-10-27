import AppKit
import SwiftUI

/// Thanh menu: chức năng, bật/tắt auto, tự học, chọn model, trạng thái.
struct MenuView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Button("Tóm tắt (⌘⇧7)") { orch().handle(.summarize) }
        Button("Dịch (⌘⇧8)") { orch().handle(.translate) }
        Button("Giải đề (⌘⇧9)") { orch().handle(.solve) }
        Button("Kiểm tra lừa đảo (⌘⇧0)") { orch().handle(.scamCheck) }
        Divider()
        Toggle("Tự động phát hiện lừa đảo", isOn: Binding(
            get: { state.autoDetect },
            set: {
                state.autoDetect = $0
                let o = orch()
                $0 ? o.monitor.start(state: state, analyzer: o.analyzer) : o.monitor.stop()
            }
        ))
        Toggle("Tự động phân tích màn hình", isOn: $state.autoAnalyze)
        Divider()
        Picker("Mô hình", selection: $state.backend) {
            // Chỉ backend đã sẵn sàng (Argon ẩn tới khi có hỗ trợ).
            ForEach([BackendID.claudeCode, .metaApi, .anthropic], id: \.self) { Text($0.rawValue).tag($0) }
        }
        SecureField("Meta API key", text: $state.metaApiKey)
            .onSubmit { AiRunner.saveKey(state.metaApiKey, account: "meta-api-key"); state.metaApiKey = "" }
        SecureField("Anthropic API key", text: $state.anthropicApiKey)
            .onSubmit { AiRunner.saveKey(state.anthropicApiKey, account: "anthropic-api-key"); state.anthropicApiKey = "" }
        Divider()
        Button(state.isLearning ? "Đang học…" : "Chạy học ngay") { LearnScheduler.runNow(state: state) }
            .disabled(state.isLearning)
        Button("Mở gỡ lỗi") {}
        Button("Thoát") { NSApplication.shared.terminate(nil) }
    }

    private func orch() -> Orchestrator {
        (NSApp.delegate as? AppDelegate)?.orchestrator ?? Orchestrator()
    }
}

/// Panel kết quả nổi: zoom 0,6×–2× (nút hoặc ⌘⇧=/⌘⇧− khi mở); Sao chép/Đóng;
/// đánh giá case Đúng là lừa đảo/Báo nhầm.
struct ResultPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            if !state.lastWarning.isEmpty {
                Text(state.lastWarning).background(.red).foregroundColor(.white).padding(4)
            }
            ScrollView { Text(state.lastResult).textSelection(.enabled) }
                .scaleEffect(state.zoom)
            HStack {
                Button("−") { state.zoom = max(0.6, state.zoom - 0.1) }
                Button("+") { state.zoom = min(2.0, state.zoom + 0.1) }
                Button("Sao chép") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.lastResult, forType: .string)
                }
                Button("Đúng là lừa đảo") { LearnStore.load().recordVerdict(state: state, scam: true) }
                Button("Báo nhầm") { LearnStore.load().recordVerdict(state: state, scam: false) }
                Button("Đóng") { (NSApp.delegate as? AppDelegate)?.hidePanel() }
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 520)
    }
}

/// Cửa sổ debug 3 tab: Nhật ký / Kho luật / Báo cáo.
struct DebugWindow: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            List(state.entries) { e in
                VStack(alignment: .leading) {
                    Text("\(e.app) · \(e.score) · \(label(e.level))")
                    ForEach(e.reasons, id: \.self) { Text("• \($0)").font(.caption) }
                    Text(e.tokens).font(.caption2).foregroundColor(.secondary)
                }
            }
            .tabItem { Text("Nhật ký") }
            VStack(alignment: .leading) {
                Text(state.rulesSummary).font(.caption)
                HStack {
                    Button(state.isLearning ? "Đang học…" : "Chạy học ngay") { LearnScheduler.runNow(state: state) }
                        .disabled(state.isLearning)
                    if state.isLearning {
                        Button("Hủy") { LearnScheduler.cancel() }
                    }
                    Button("Hoàn tác") { LearnStore.load().undo(state: state) }
                }
            }
            .padding()
            .tabItem { Text("Kho luật") }
            ScrollView { Text(state.lastReport).font(.caption) }
                .padding()
                .tabItem { Text("Báo cáo") }
        }
        .frame(width: 640, height: 480)
    }

    private func label(_ level: String) -> String {
        switch level {
        case "dangerous": return "NGUY HIỂM"
        case "suspicious": return "ĐÁNG NGỜ"
        default: return "AN TOÀN"
        }
    }
}
