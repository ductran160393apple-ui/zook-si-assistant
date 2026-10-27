import AppKit
import SwiftUI

/// Điểm vào app menu-bar. Toàn bộ chấm điểm/che PII/kiểm duyệt luật nằm
/// trong lõi Rust (FFI sinh bằng UniFFI); Swift chỉ thu thập chữ và vẽ UI.
@main
struct AiAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    init() {
        let s = AppState.shared
        delegate.state = s
        // --selftest: chạy kiểm tra rồi thoát, không cần quyền màn hình.
        if CommandLine.arguments.contains("--selftest") {
            let ok = SelfTest.run(state: s)
            print(ok ? "SELFTEST: ĐẠT" : "SELFTEST: HỎNG")
            exit(ok ? 0 : 1)
        }
        if CommandLine.arguments.contains("--selftest-learn") {
            // runNow chạy nền → chờ tới khi xong (tối đa 320s) rồi in báo cáo.
            LearnScheduler.runNow(state: s)
            let deadline = Date().addingTimeInterval(320)
            while s.isLearning && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.5))
            }
            print(s.lastReport)
            exit(s.isLearning ? 1 : 0)
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest-learn-local"), i + 1 < args.count {
            let ok = SelfTest.runLearnLocal(state: s, agentOutputPath: args[i + 1])
            print(ok ? "SELFTEST-LEARN: ĐẠT" : "SELFTEST-LEARN: HỎNG")
            exit(ok ? 0 : 1)
        }
    }

    var body: some Scene {
        MenuBarExtra("Trợ lý AI", systemImage: "shield") {
            MenuView(state: state)
        }
        Window("Gỡ lỗi", id: "debug") {
            DebugWindow(state: state)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

/// Panel kết quả: NSPanel nổi (.floating), không lấy focus (.nonactivatingPanel)
/// để trang web vẫn nhận bàn phím; ghi nhớ kích thước; zoom 0,6×–2×.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state = AppState.shared
    private var panel: NSPanel?
    let orchestrator = Orchestrator()

    func applicationDidFinishLaunching(_ note: Notification) {
        orchestrator.state = state
        Hotkeys.register { [weak self] task in self?.orchestrator.handle(task) }
        if state.autoDetect { orchestrator.monitor.start(state: state, analyzer: orchestrator.analyzer) }
        LearnStore.load().refreshRulesSummary(state: state)
    }

    func showPanel() {
        if panel == nil {
            let size = loadPanelSize()
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isFloatingPanel = true
            p.becomesKeyOnlyIfNeeded = true
            p.contentView = NSHostingView(rootView: ResultPanel(state: state))
            p.center()
            p.delegate = self
            panel = p
        }
        panel?.orderFrontRegardless()
        Hotkeys.registerZoom(state: state)
    }

    func hidePanel() {
        savePanelSize()
        panel?.orderOut(nil)
        Hotkeys.unregisterZoom()
    }

    private func loadPanelSize() -> NSSize {
        let w = UserDefaults.standard.double(forKey: "panelWidth")
        let h = UserDefaults.standard.double(forKey: "panelHeight")
        return (w > 200 && h > 200) ? NSSize(width: w, height: h) : NSSize(width: 420, height: 520)
    }

    private func savePanelSize() {
        guard let f = panel?.frame else { return }
        UserDefaults.standard.set(f.width, forKey: "panelWidth")
        UserDefaults.standard.set(f.height, forKey: "panelHeight")
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Hotkeys.unregisterZoom()
    }
}

/// Nối phím tắt/menu → chụp → quét → AI → panel.
final class Orchestrator {
    var state = AppState.shared
    let monitor = AutoMonitor()
    let analyzer = AutoAnalyzer()

    func handle(_ task: AiTask) {
        analyzer.manualBusy = true
        Task {
            await run(task)
            analyzer.manualBusy = false
        }
    }

    private func run(_ task: AiTask) async {
        guard let (app, text) = await ScreenReader.captureFrontWindow() else { return }
        let flags = state.scanFlags(frontApp: app)
        let res = scanText(text: text, appId: app, flags: flags)
        let level = res.level == "dangerous" ? "NGUY HIỂM"
            : res.level == "suspicious" ? "ĐÁNG NGỜ" : "AN TOÀN"
        await MainActor.run {
            state.lastScan = AppState.LastScan(app: app, text: text, score: res.score, reasons: res.reasons)
            // FR-13: kiểm tra lừa đảo luôn chạy kèm; ≥ Đáng ngờ thì dải cảnh báo trên kết quả.
            state.lastWarning = res.score >= 35
                ? "\(level) (\(res.score)): " + res.reasons.joined(separator: "; ")
                : ""
            state.log(app: app, score: res.score, level: res.level, reasons: res.reasons, tokens: "luật máy · 0 token")
        }
        // Lưu case: mọi lần kiểm tra thủ công, hoặc điểm ≥ 15.
        LearnStore.load().recordCase(app: app, text: text, score: res.score, reasons: res.reasons)

        if task == .scamCheck {
            await MainActor.run {
                state.lastResult = res.score < 35
                    ? "An toàn (\(res.score)/100)."
                    : "Xem dải cảnh báo phía trên."
                NSApp.delegate.flatMap { $0 as? AppDelegate }?.showPanel()
            }
            return
        }
        let redacted = redactText(text: text)
        let out = await AiRunner.run(task: task, redactedText: redacted, state: state)
        await MainActor.run {
            state.lastResult = out.text
            state.log(app: app, score: res.score, level: res.level, reasons: res.reasons, tokens: out.tokens)
            NSApp.delegate.flatMap { $0 as? AppDelegate }?.showPanel()
        }
    }
}
