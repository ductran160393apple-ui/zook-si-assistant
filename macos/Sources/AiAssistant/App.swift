import AppKit
import Combine
import SwiftUI

/// Log chẩn đoán ra file (không ghi nội dung màn hình, chỉ đếm ký tự).
/// Đường dẫn: ~/Library/Logs/SiAssitant/debug.log — gửi kèm khi báo lỗi.
enum DiagLog {
    private static let maxBytes = 256 * 1024

    static func line(_ msg: String) {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SiAssitant")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("debug.log")
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           (attrs[.size] as? Int ?? 0) > maxBytes {
            try? fm.removeItem(at: url)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        if let fh = try? FileHandle(forWritingTo: url) {
            try? fh.seekToEnd()
            fh.write(Data("\(Date()): \(msg)\n".utf8))
            try? fh.close()
        }
    }
}

/// Điểm vào app menu-bar. Toàn bộ chấm điểm/che PII/kiểm duyệt luật nằm
/// trong lõi Rust (FFI sinh bằng UniFFI); Swift chỉ thu thập chữ và vẽ UI.
@main
struct AiAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    init() {
        let s = AppState.shared
        delegate.state = s
        // --probe-capture: thử chụp + OCR một lần để chẩn đoán quyền màn hình.
        if CommandLine.arguments.contains("--probe-capture") {
            let sem = DispatchSemaphore(value: 0)
            var code: Int32 = 0
            Task {
                if let (app, text) = await ScreenReader.captureFrontWindow() {
                    print("PROBE: app=\(app) chars=\(text.count)")
                } else {
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                    print("PROBE: nil (front=\(front); thiếu quyền Ghi màn hình, app nhạy cảm hoặc không có cửa sổ)")
                    code = 1
                }
                sem.signal()
            }
            // Bơm RunLoop chính khi chờ: Task thừa hưởng MainActor từ App,
            // sem.wait() trần sẽ deadlock (Task không bao giờ chạy).
            while sem.wait(timeout: .now() + 0.1) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            exit(code)
        }
        // --probe-net: quét traffic thật 2 mẫu cách nhau 2s, chấm bằng lõi.
        if CommandLine.arguments.contains("--probe-net") {
            let sem = DispatchSemaphore(value: 0)
            Task {
                guard let a1 = NetMonitor.collectApps(), let t1 = NetMonitor.interfaceTotals() else {
                    print("PROBE-NET: thu thập thất bại"); sem.signal(); return
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let a2 = NetMonitor.collectApps(), let t2 = NetMonitor.interfaceTotals() else {
                    print("PROBE-NET: thu thập thất bại"); sem.signal(); return
                }
                var apps: [(name: String, rx: UInt64, tx: UInt64)] = []
                for (name, c) in a2 {
                    let p = a1[name] ?? (0, 0)
                    apps.append((name, c.rx >= p.rx ? c.rx - p.rx : c.rx, c.tx >= p.tx ? c.tx - p.tx : c.tx))
                }
                let lang: AiLang = s.lang == .en ? .en : .vi
                let snap = NetMonitor.buildSnapshot(
                    apps: apps, totalRx: t2.rx >= t1.rx ? t2.rx - t1.rx : t2.rx,
                    totalTx: t2.tx >= t1.tx ? t2.tx - t1.tx : t2.tx,
                    windowSecs: 2.0, baseline: "{}"
                )
                print("PROBE-NET: \(netEvaluate(snapshotJson: snap, lang: lang))")
                sem.signal()
            }
            while sem.wait(timeout: .now() + 0.1) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            exit(0)
        }
        // --probe-ai <backend> <task> <model...> <text...>: chạy AI thật qua đúng
        // đường AiRunner (không chụp màn hình). backend: meta/claude/gemini/
        // agy/anthropic; task: summarize/translate/solve/analyze/scamcheck.
        // model: chuỗi model hoặc "-" để dùng mặc định của backend.
        if let i = CommandLine.arguments.firstIndex(of: "--probe-ai"),
           CommandLine.arguments.count > i + 4
        {
            let backendArg = CommandLine.arguments[i + 1]
            let taskArg = CommandLine.arguments[i + 2]
            let modelArg = CommandLine.arguments[i + 3]
            let text = CommandLine.arguments[(i + 4)...].joined(separator: " ")
            let st = AppState()
            switch backendArg {
            case "meta": st.backend = .metaApi
            case "claude": st.backend = .claudeCode
            case "gemini": st.backend = .geminiCli
            case "agy": st.backend = .antigravity
            case "anthropic": st.backend = .anthropic
            default: print("PROBE-AI: backend lạ: \(backendArg)"); exit(2)
            }
            let task: AiTask
            switch taskArg {
            case "summarize": task = .summarize
            case "translate": task = .translate
            case "solve": task = .solve
            case "analyze": task = .analyze
            case "scamcheck": task = .scamCheck
            default: print("PROBE-AI: task lạ: \(taskArg)"); exit(2)
            }
            if modelArg != "-" {
                switch st.backend {
                case .metaApi: st.metaModel = modelArg
                case .claudeCode: st.claudeModel = modelArg
                case .geminiCli: st.geminiModel = modelArg
                case .antigravity: st.agyModel = modelArg
                case .anthropic: break
                }
            }
            let sem = DispatchSemaphore(value: 0)
            Task {
                let out = await AiRunner.run(task: task, redactedText: redactText(text: text), state: st)
                print("PROBE-AI text: \(out.text)")
                print("PROBE-AI tokens: \(out.tokens)")
                sem.signal()
            }
            // Bơm RunLoop chính khi chờ (tránh deadlock MainActor như trên).
            while sem.wait(timeout: .now() + 0.1) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            exit(0)
        }
        // --probe-monitor <giây>: chạy monitor tự động thật (nhịp 1s +
        // quét ngay khi đổi app), in timestamp từng nhịp và từng lần gọi
        // AI phân tích, hết giờ thì dừng. Cần quyền Ghi màn hình mới quét
        // được nội dung; không quyền vẫn thấy nhịp tick.
        if let i = CommandLine.arguments.firstIndex(of: "--probe-monitor"),
           i + 1 < CommandLine.arguments.count
        {
            let seconds = TimeInterval(CommandLine.arguments[i + 1]) ?? 10
            ProbeMonitor.verbose = true
            ProbeMonitor.t0 = Date()
            let st = AppState()
            st.autoDetect = true
            st.autoAnalyze = true
            let mon = AutoMonitor()
            mon.start(state: st, analyzer: AutoAnalyzer())
            print("PROBE-MONITOR start giây=\(seconds)")
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
            mon.stop()
            print("PROBE-MONITOR xong nhịp=\(ProbeMonitor.ticks) gọi-AI=\(ProbeMonitor.analyzes)")
            exit(0)
        }
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
        // App chỉ sống trên status bar: NSStatusItem + NSPopover do
        // AppDelegate quản lý (MenuBarExtra luôn render icon đơn sắc nên
        // không thể hiện màu cảnh báo).
        Settings { EmptyView() }
    }
}

/// Panel kết quả: NSPanel nổi (.floating), không lấy focus (.nonactivatingPanel)
/// để trang web vẫn nhận bàn phím; nền kính xuyên thấu mà chữ vẫn rõ;
/// ghi nhớ kích thước; zoom 0,6×–2×.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Tham chiếu trực tiếp (không qua NSApp.delegate — chuỗi đó từng cho nil im lặng).
    static weak var current: AppDelegate?
    var state = AppState.shared
    private var panel: NSPanel?
    private var warnPanel: NSPanel?
    private var statusItem: NSStatusItem?
    private var menuPopover: NSPopover?
    private var debugWindow: NSWindow?
    private var alertSink: AnyCancellable?
    private var blinkTimer: Timer?
    private var blinkOn = false
    let orchestrator = Orchestrator()

    func applicationDidFinishLaunching(_ note: Notification) {
        AppDelegate.current = self
        DiagLog.line("launch finished; NSApp.delegate=\(NSApp.delegate.map { String(describing: type(of: $0)) } ?? "nil")")
        orchestrator.state = state
        Hotkeys.register { [weak self] task in self?.orchestrator.handle(task) }
        if state.autoDetect { orchestrator.monitor.start(state: state, analyzer: orchestrator.analyzer) }
        orchestrator.netMonitor.start(state: state)
        state.applyLearnAuto()
        LearnStore.load().refreshRulesSummary(state: state)
        setupStatusItem()
    }

    /// Status bar cổ điển: icon tô màu thật theo mức cảnh báo (đỏ/cam/đơn
    /// sắc) + popover menu khi bấm. Mọi set alertLevel đều chạy trên main.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = AlertFace.statusImage(level: state.alertLevel)
        item.button?.target = self
        item.button?.action = #selector(toggleMenuPopover(_:))
        statusItem = item
        let pop = NSPopover()
        pop.contentViewController = NSHostingController(rootView: MenuView(state: state))
        pop.behavior = .transient
        menuPopover = pop
        // removeDuplicates: alertLevel bị set mỗi nhịp quét, chỉ đổi icon
        // khi mức thật sự thay đổi.
        alertSink = state.$alertLevel.removeDuplicates().sink { [weak self] level in
            self?.updateStatusIcon(level: level)
        }
    }

    /// Đổi icon theo mức; nguy hiểm thì nhấp nháy radiant (đổi khung 0,6s),
    /// hết nguy hiểm thì dừng ngay về icon tĩnh.
    private func updateStatusIcon(level: String) {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard let btn = statusItem?.button else { return }
        guard level == "dangerous" else {
            btn.image = AlertFace.statusImage(level: level)
            return
        }
        DiagLog.line("status: nhấp nháy BẬT")
        blinkOn = false
        btn.image = AlertFace.statusImage(level: level)
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self, let b = self.statusItem?.button else { return }
            self.blinkOn.toggle()
            b.image = self.blinkOn
                ? AlertFace.glowImage(level: "dangerous")
                : AlertFace.statusImage(level: "dangerous")
        }
        RunLoop.main.add(t, forMode: .common)
        blinkTimer = t
    }

    @objc private func toggleMenuPopover(_ sender: Any?) {
        guard let btn = statusItem?.button, let pop = menuPopover else { return }
        if pop.isShown { pop.performClose(sender) }
        else { pop.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY) }
    }

    /// Cửa sổ Gỡ lỗi do delegate quản lý (thay SwiftUI Window scene đã bỏ
    /// cùng MenuBarExtra); bringToFront cũ vẫn khớp theo title.
    func openDebugWindow() {
        if debugWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Gỡ lỗi"
            w.contentViewController = NSHostingController(rootView: DebugWindow(state: state))
            w.isReleasedWhenClosed = false
            debugWindow = w
            w.center()
        }
        DebugWindow.bringToFront()
    }

    func showPanel() {
        DiagLog.line("showPanel called (panel exists=\(panel != nil))")
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
            // Panel xuyên thấu: cửa sổ trong suốt, nền kính do SwiftUI
            // (GlassBackground trong ResultPanel) để thấy rõ màn hình sau
            // mà chữ vẫn đọc được.
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.contentView = NSHostingView(rootView: ResultPanel(state: state))
            if let sc = NSScreen.main {
                let vf = sc.visibleFrame
                let rightX = vf.maxX - size.width - 24
                let topY = vf.maxY - size.height - 30
                if let wp = warnPanel, wp.isVisible {
                    p.setFrameOrigin(NSPoint(x: max(vf.minX + 500, wp.frame.minX - size.width - 16), y: topY))
                } else {
                    p.setFrameOrigin(NSPoint(x: rightX, y: topY))
                }
            } else {
                p.center()
            }
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

    /// Panel cảnh báo auto (riêng với panel tay để hiển thị đồng thời).
    /// Mở cạnh panel chính (so le) nếu panel chính đang mở, ngược lại giữa màn hình.
    func showWarningPanel() {
        DiagLog.line("showWarningPanel called (panel exists=\(warnPanel != nil))")
        if warnPanel == nil {
            let w = UserDefaults.standard.double(forKey: "warnPanelWidth")
            let h = UserDefaults.standard.double(forKey: "warnPanelHeight")
            let size = (w > 200 && h > 200) ? NSSize(width: w, height: h) : NSSize(width: 420, height: 520)
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
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.contentView = NSHostingView(rootView: WarningPanel(state: state))
            if let sc = NSScreen.main {
                let vf = sc.visibleFrame
                let rightX = vf.maxX - size.width - 24
                let topY = vf.maxY - size.height - 30
                p.setFrameOrigin(NSPoint(x: rightX, y: topY))
            } else {
                p.center()
            }
            p.delegate = self
            warnPanel = p
        }
        warnPanel?.orderFrontRegardless()
    }

    func hideWarningPanel() {
        if let f = warnPanel?.frame {
            UserDefaults.standard.set(f.width, forKey: "warnPanelWidth")
            UserDefaults.standard.set(f.height, forKey: "warnPanelHeight")
        }
        warnPanel?.orderOut(nil)
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
    let netMonitor = NetMonitor()

    func handle(_ task: AiTask) {
        analyzer.manualBusy = true
        Task {
            await run(task)
            analyzer.manualBusy = false
        }
    }

    /// Chụp có timeout: API hệ thống có thể treo (hộp quyền không hiện);
    /// quá hạn coi như thất bại để panel hướng dẫn luôn được hiện.
    /// Task chụp treo (nếu có) bị bỏ lại — ghi chú, không chặn luồng chính.
    private func captureWithTimeout(seconds: TimeInterval) async -> (app: String, text: String)? {
        await withCheckedContinuation { cont in
            let lock = NSLock()
            var done = false
            func finish(_ v: (app: String, text: String)?) {
                lock.lock(); defer { lock.unlock() }
                guard !done else { return }
                done = true
                cont.resume(returning: v)
            }
            Task { finish(await ScreenReader.captureFrontWindow()) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                finish(nil)
            }
        }
    }

    private func run(_ task: AiTask) async {
        DiagLog.line("handle task=\(task)")
        // Chụp thất bại hoặc treo quá 20s (thiếu quyền / app nhạy cảm) →
        // vẫn hiện panel hướng dẫn, không bao giờ im lặng.
        let t0 = Date()
        let captured = await captureWithTimeout(seconds: 20)
        DiagLog.line(String(format: "capture %.1fs nil=%@", Date().timeIntervalSince(t0), captured == nil ? "YES" : "NO"))
        // Chụp được nhưng không có chữ (cửa sổ trống/OCR trắng) → hiện
        // hướng dẫn, không gọi AI với <INPUT> rỗng.
        if let (app, text) = captured,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            await MainActor.run {
                state.showTask(task, result: L(
                    "Không đọc được chữ trên màn hình (cửa sổ trống hoặc OCR không nhận ra ký tự). Hãy mở nội dung cần xử lý rồi thử lại.",
                    "No text found on the screen (empty window or OCR recognized nothing). Open the content you need and retry."
                ), warning: "")
                state.log(app: app, score: 0, level: "safe",
                          reasons: [L("Không có chữ để xử lý", "No text to process")], tokens: "")
                AppDelegate.current?.showPanel()
            }
            return
        }
        guard let (app, text) = captured else {
            await MainActor.run {
                DiagLog.line("failure branch reached")
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                if !front.isEmpty && isSensitiveApp(appId: front) {
                    state.showTask(task, result: L(
                        "App đang mở thuộc loại nhạy cảm (ngân hàng/ví/mật khẩu) nên SiAssitant không đọc màn hình để bảo vệ bạn.",
                        "The front app is sensitive (bank/wallet/password), so SiAssitant did not read the screen to protect you."
                    ), warning: "")
                } else {
                    state.showTask(task, result: L(
                        "Không đọc được màn hình. Hãy cấp quyền Ghi màn hình cho SiAssitant: Cài đặt > Quyền riêng tư & Bảo mật > Ghi màn hình, bấm + và thêm app, rồi thử lại.",
                        "Cannot read the screen. Grant Screen Recording permission to SiAssitant: Settings > Privacy & Security > Screen Recording, click + and add the app, then retry."
                    ), warning: "")
                }
                state.log(app: front.isEmpty ? "-" : front, score: 0, level: "safe",
                          reasons: ["Không đọc được màn hình"], tokens: "")
                DiagLog.line("failure branch: showing panel, current=\(AppDelegate.current != nil ? "set" : "NIL")")
                AppDelegate.current?.showPanel()
            }
            return
        }
        let flags = state.scanFlags(frontApp: app)
        let res = scanText(text: text, appId: app, flags: flags, lang: state.lang.core)
        DiagLog.line("scan app=\(app) chars=\(text.count) score=\(res.score) level=\(res.level)")
        let level = res.level == "dangerous" ? L("NGUY HIỂM", "DANGEROUS")
            : res.level == "suspicious" ? L("ĐÁNG NGỜ", "SUSPICIOUS") : L("AN TOÀN", "SAFE")
        await MainActor.run {
            state.lastScan = AppState.LastScan(app: app, text: text, score: res.score, reasons: res.reasons)
            // FR-13: kiểm tra lừa đảo luôn chạy kèm; ≥ Đáng ngờ thì dải cảnh báo trên kết quả.
            state.taskWarnings[task] = res.score >= 35
                ? "\(level) (\(res.score)): " + res.reasons.joined(separator: "; ")
                : ""
            state.alertLevel = res.level
            state.log(app: app, score: res.score, level: res.level, reasons: res.reasons, tokens: L("luật máy · 0 token", "local rules · 0 tokens"))
        }
        // Lưu case: mọi lần kiểm tra thủ công, hoặc điểm ≥ 15.
        LearnStore.load().recordCase(app: app, text: text, score: res.score, reasons: res.reasons)

        if task == .scamCheck {
            let taskName = PanelTitle.name(task: task, lang: state.lang)
            // Tối ưu 1: nội dung quá ngắn thì chỉ chấm luật, khỏi gọi AI.
            guard ScamVerdict.shouldCallAi(text: text) else {
                await MainActor.run {
                    state.showTask(task, result: res.score < 35
                        ? L("An toàn (\(res.score)/100).", "Safe (\(res.score)/100).")
                        : L("Xem dải cảnh báo phía trên.", "See the warning banner above."))
                    AppDelegate.current?.showPanel()
                }
                return
            }
            await MainActor.run {
                state.showTask(task, result: "\(taskName)\(L(" đang xử lý…", " in progress…"))")
                AppDelegate.current?.showPanel()
            }
            // Tối ưu 2+3: 1 lần gọi AI duy nhất (tóm tắt + kết luận chung
            // một prompt), input cắt 2000 ký tự để giảm token.
            let redacted = String(redactText(text: text).prefix(ScamVerdict.maxAiChars))
            DiagLog.line("AI start task=scamCheck")
            let out = await AiRunner.run(task: .scamCheck, redactedText: redacted, state: state)
            DiagLog.line("AI done chars=\(out.text.count)")
            if out.tokens.isEmpty {
                DiagLog.line("AI lỗi: \(out.text.replacingOccurrences(of: "\n", with: " ").prefix(500))")
            }
            await MainActor.run {
                let aiLevel = ScamVerdict.isError(text: out.text) ? 0 : ScamVerdict.aiLevel(text: out.text)
                let final = ScamVerdict.combine(rulesScore: res.score, aiLevel: aiLevel)
                let warn: String? = final.escalated
                    ? "\(ScamVerdict.levelName(level: final.level, lang: state.lang)) (\(L("AI kiểm chéo", "AI cross-check")))"
                    : nil
                state.showTask(task, result: ScamVerdict.compose(
                    aiText: out.text, rulesScore: res.score,
                    finalLevel: final.level, escalated: final.escalated, lang: state.lang
                ), warning: warn)
                state.log(app: app, score: res.score, level: res.level, reasons: res.reasons, tokens: out.tokens)
                AppDelegate.current?.showPanel()
            }
            return
        }
        // Hiện panel ngay với chữ chờ (AI có thể mất phút) rồi mới gọi AI.
        let taskName = PanelTitle.name(task: task, lang: state.lang)
        await MainActor.run {
            state.showTask(task, result: "\(taskName)\(L(" đang xử lý…", " in progress…"))")
            AppDelegate.current?.showPanel()
        }
        let redacted = redactText(text: text)
        DiagLog.line("AI start task=\(task)")
        let out = await AiRunner.run(task: task, redactedText: redacted, state: state)
        DiagLog.line("AI done chars=\(out.text.count)")
        if out.tokens.isEmpty {
            DiagLog.line("AI lỗi: \(out.text.replacingOccurrences(of: "\n", with: " ").prefix(500))")
        }
        await MainActor.run {
            state.showTask(task, result: out.text)
            state.log(app: app, score: res.score, level: res.level, reasons: res.reasons, tokens: out.tokens)
            AppDelegate.current?.showPanel()
        }
    }
}
