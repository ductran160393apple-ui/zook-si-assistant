import Darwin
import Foundation

/// Giám sát traffic mạng macOS: thu thập counter per-process (`nettop -P`)
/// + tổng interface (`getifaddrs`), lõi Rust chấm verdict, worker LLM hiệu
/// đính sau. Tick 60s riêng (không chung tick 1s màn hình). Chỉ đếm bytes —
/// không host/DNS/payload, không bao giờ vào prompt AI cloud.
final class NetMonitor {
    static let interval: TimeInterval = 60
    static let baselineFile = "net-baseline.json"
    private var timer: Timer?
    private var busy = false
    private var prevApps: [String: (rx: UInt64, tx: UInt64)]?
    private var prevTotals: (rx: UInt64, tx: UInt64)?
    private var lastTick: Date?
    private let worker = NetLLMWorker()

    func start(state: AppState) {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.kick(state: state)
        }
        t.tolerance = 10
        timer = t
        kick(state: state)
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func kick(state: AppState) {
        guard state.netDetect, !busy else { return }
        busy = true
        Task.detached(priority: .utility) { [weak self] in
            await self?.tick(state: state)
            await MainActor.run { [weak self] in self?.busy = false }
        }
    }

    private func tick(state: AppState) async {
        guard let curr = Self.collectApps(), let totals = Self.interfaceTotals() else {
            DiagLog.line("net: thu thập thất bại (nettop/getifaddrs)")
            return
        }
        let now = Date()
        defer {
            prevApps = curr
            prevTotals = totals
            lastTick = now
        }
        guard let prev = prevApps, let prevT = prevTotals, let last = lastTick else {
            DiagLog.line("net: tick đầu, lập nền (\(curr.count) tiến trình)")
            return
        }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed < 300 else { return } // Ngủ/gap dài: bỏ tick, lập nền mới.
        var apps: [(name: String, rx: UInt64, tx: UInt64)] = []
        for (name, c) in curr {
            let p = prev[name] ?? (0, 0)
            apps.append((name, c.rx >= p.rx ? c.rx - p.rx : c.rx, c.tx >= p.tx ? c.tx - p.tx : c.tx))
        }
        let dRx = totals.rx >= prevT.rx ? totals.rx - prevT.rx : totals.rx
        let dTx = totals.tx >= prevT.tx ? totals.tx - prevT.tx : totals.tx
        let baseline = Self.loadBaseline()
        let snap = Self.buildSnapshot(apps: apps, totalRx: dRx, totalTx: dTx, windowSecs: elapsed, baseline: baseline)
        let lang: AiLang = state.lang == .en ? .en : .vi
        let verdict = netEvaluate(snapshotJson: snap, lang: lang)
        guard let v = Self.parseVerdict(verdict) else {
            DiagLog.line("net: verdict hỏng")
            return
        }
        Self.saveBaseline(v.baselineJson)
        let summary = v.reasons.joined(separator: "; ")
        await MainActor.run {
            state.netLevel = v.level
            state.netSummary = summary
            state.netTop = v.top
        }
        DiagLog.line("net: \(v.level) score=\(v.score) \(summary.isEmpty ? "(yên)" : summary)")
        if netNeedsLlm(verdictJson: verdict) {
            let cfg = NetLLMConfig(
                enabled: state.netLlmEnabled, baseURL: state.netLlmBase,
                model: state.netLlmModel, lang: lang
            )
            await worker.enqueue(verdict: verdict, config: cfg, state: state)
        }
    }

    // MARK: - Thu thập (I/O, kiểm chứng bằng --probe-net)

    /// Chạy `nettop -l 1 -P -m tcp`, gom bytes theo tên tiến trình.
    static func collectApps() -> [String: (rx: UInt64, tx: UInt64)]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-l", "1", "-P", "-m", "tcp"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(20)
        var out = Data()
        while p.isRunning {
            if Date() > deadline { p.terminate(); return nil }
            out.append(pipe.fileHandleForReading.availableData)
            Thread.sleep(forTimeInterval: 0.1)
        }
        out.append(pipe.fileHandleForReading.readDataToEndOfFile())
        guard let text = String(data: out, encoding: .utf8), !text.isEmpty else { return nil }
        return parseNettop(text)
    }

    /// Tổng bytes up/down mọi interface vật lý (trừ loopback).
    static func interfaceTotals() -> (rx: UInt64, tx: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cur {
            defer { cur = ifa.pointee.ifa_next }
            guard ifa.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = ifa.pointee.ifa_data else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(d.ifi_ibytes)
            tx &+= UInt64(d.ifi_obytes)
        }
        return (rx, tx)
    }

    // MARK: - Hàm thuần (có unit test)

    /// Parse output `nettop -l 1 -P -m tcp`: mỗi dòng
    /// `<time> <tên.pid> <in> <đơnvị> <out> <đơnvị> ...`, gom theo tên.
    /// Tên có thể chứa cách/chấm, cắt 16 ký tự. Dòng lạ bỏ qua.
    static func parseNettop(_ out: String) -> [String: (rx: UInt64, tx: UInt64)] {
        var acc: [String: (rx: UInt64, tx: UInt64)] = [:]
        let pattern = #"^(\S+)\s+(.+?)\.(\d+)\s+(\d+(?:\.\d+)?)\s+([A-Za-z]+)\s+(\d+(?:\.\d+)?)\s+([A-Za-z]+)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [:] }
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            let range = NSRange(line.startIndex..., in: line)
            guard let m = re.firstMatch(in: line, range: range), m.numberOfRanges == 8 else { continue }
            func g(_ i: Int) -> String {
                Range(m.range(at: i), in: line).map { String(line[$0]) } ?? ""
            }
            let name = g(2).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  let inV = Double(g(4)), let inB = unitMult(g(5)),
                  let outV = Double(g(6)), let outB = unitMult(g(7)) else { continue }
            let rx = UInt64((inV * inB).rounded())
            let tx = UInt64((outV * outB).rounded())
            guard rx + tx > 0 else { continue }
            let old = acc[name] ?? (0, 0)
            acc[name] = (old.rx &+ rx, old.tx &+ tx)
        }
        return acc
    }

    /// Hệ số đơn vị nettop (nhị phân). Đơn vị lạ → nil (bỏ dòng).
    static func unitMult(_ unit: String) -> Double? {
        switch unit {
        case "B": return 1
        case "K", "KB", "KiB": return 1024
        case "M", "MB", "MiB": return 1024 * 1024
        case "G", "GB", "GiB": return 1024 * 1024 * 1024
        case "T", "TB", "TiB": return 1024 * 1024 * 1024 * 1024
        default: return nil
        }
    }

    /// Dựng snapshot JSON gửi lõi. Baseline hỏng → "{}".
    static func buildSnapshot(apps: [(name: String, rx: UInt64, tx: UInt64)], totalRx: UInt64, totalTx: UInt64, windowSecs: Double, baseline: String) -> String {
        var base: Any = [:]
        if let d = baseline.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) { base = o }
        let obj: [String: Any] = [
            "window_secs": windowSecs,
            "apps": apps.map { ["name": $0.name, "rx_bytes": $0.rx, "tx_bytes": $0.tx] },
            "total_rx": totalRx,
            "total_tx": totalTx,
            "baseline": base,
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Parse verdict JSON lõi trả về. Hỏng → nil.
    static func parseVerdict(_ json: String) -> (level: String, score: UInt32, reasons: [String], top: String, baselineJson: String)? {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let level = o["level"] as? String else { return nil }
        let score = (o["score"] as? NSNumber)?.uint32Value ?? 0
        let reasons = (o["reasons"] as? [String]) ?? []
        var topLines: [String] = []
        if let top = o["top"] as? [[String: Any]] {
            for t in top.prefix(8) {
                let n = t["name"] as? String ?? "?"
                let r = (t["rx_bytes"] as? NSNumber)?.uint64Value ?? 0
                let w = (t["tx_bytes"] as? NSNumber)?.uint64Value ?? 0
                topLines.append("\(n): ↑\(w) ↓\(r)")
            }
        }
        var baseJson = "{}"
        if let b = o["baseline"], let bd = try? JSONSerialization.data(withJSONObject: b),
           let bs = String(data: bd, encoding: .utf8) { baseJson = bs }
        return (level, score, reasons, topLines.joined(separator: "\n"), baseJson)
    }

    // MARK: - Baseline

    static func baselineURL() -> URL {
        LearnStore.dataDir().appendingPathComponent(baselineFile)
    }

    static func loadBaseline() -> String {
        (try? String(contentsOf: baselineURL(), encoding: .utf8)) ?? "{}"
    }

    static func saveBaseline(_ json: String) {
        let url = baselineURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }
}
