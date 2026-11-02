import AppKit
import Foundation
import ScreenCaptureKit
import Vision

/// Chụp màn hình + OCR bằng Vision ngay trên máy (ưu tiên vi rồi en),
/// sắp xếp theo thứ tự đọc. Bấm tay chụp cửa sổ trước mặt (current view);
/// auto-monitor chụp từng cửa sổ giữ lại (bắt cả tab nhỏ nền, tối đa 8).
/// Không bao giờ chụp cửa sổ của chính app; ảnh chỉ nằm trong RAM, không
/// ghi đĩa. App nhạy cảm → trả nil (bấm tay) hoặc bị loại khỏi danh sách
/// quét (auto).
enum ScreenReader {
    /// true khi lần lấy nội dung chia sẻ gần nhất bị chặn TCC (quyền Ghi
    /// màn hình bị thu hồi — thường do ký lại app). Monitor đọc để hiện
    /// panel hướng dẫn cấp quyền một lần; thành công thì về false.
    static var tccBlocked = false

    /// Bundle id app đang ở phía trước + text OCR được (nil nếu app nhạy cảm).
    static func captureFrontWindow() async -> (app: String, text: String)? {
        guard let (app, image) = await captureFrontImage() else { return nil }
        return (app, ocr(image))
    }

    /// Cửa sổ hệ thống không bao giờ là mục tiêu (từng bị chụp nhầm).
    private static let systemBundles: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
    ]

    /// Quyết định giữ app trong ảnh toàn màn hình (hàm thuần, có unit
    /// test): bỏ app của mình, app nhạy cảm (ngân hàng...) và app hệ thống
    /// (dock, banner thông báo...); giữ lại còn lại. Áp qua
    /// `excludingApplications` (KHÔNG dùng `exceptingWindows` — tham số đó
    /// nghĩa ngược: cửa sổ được giữ lại dù app bị loại).
    static func keepApp(bundleID: String, ownBundle: String?) -> Bool {
        if bundleID.isEmpty { return false }
        if bundleID == ownBundle { return false }
        if systemBundles.contains(bundleID) { return false }
        return !isSensitiveApp(appId: bundleID)
    }

    /// Chụp từng cửa sổ giữ lại cho auto-monitor (bắt cả tab nhỏ nền).
    /// Dùng filter desktopIndependentWindow đã kiểm chứng (filter display bị
    /// lỗi invalid parameter trên máy này). Nil khi: không lấy được nội dung
    /// chia sẻ / app trước mặt nhạy cảm / không có cửa sổ nào. Cửa sổ chụp
    /// lỗi bị bỏ qua, không làm hỏng cả nhịp.
    static func captureKeptWindows() async -> (front: String, shots: [(id: UInt32, app: String, image: CGImage)])? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            DiagLog.line("auto: không lấy được danh sách cửa sổ: \(error.localizedDescription)")
            tccBlocked = true
            return nil
        }
        tccBlocked = false
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if !front.isEmpty, isSensitive(front) {
            DiagLog.line("auto: app trước mặt nhạy cảm, bỏ nhịp")
            return nil
        }
        let wins = keptWindows(in: content, ownPID: ownPID, ownBundle: ownBundle)
        // Chẩn đoán khi không quét được: tổng số cửa sổ hệ thấy + danh
        // sách giữ lại (chỉ ghi khi thất bại để khỏi spam file log).
        func diag() -> String {
            let kept = wins.map {
                "\($0.owningApplication?.bundleIdentifier ?? "?"):\(Int($0.frame.width))x\(Int($0.frame.height))"
            }.joined(separator: ",")
            return "thấy=\(content.windows.count) giữ=[\(kept)]"
        }
        if wins.isEmpty {
            DiagLog.line("auto: không có cửa sổ nào để quét (\(diag()))")
            return nil
        }
        var shots: [(UInt32, String, CGImage)] = []
        var firstErr = ""
        for w in wins {
            do {
                let img = try await captureWindowImage(w)
                shots.append((w.windowID, w.owningApplication?.bundleIdentifier ?? "", img))
            } catch {
                if firstErr.isEmpty { firstErr = error.localizedDescription }
            }
        }
        if shots.count < wins.count {
            DiagLog.line("auto: chụp \(shots.count)/\(wins.count) cửa sổ (\(diag())) lỗi=\(firstErr)")
            if shots.isEmpty { return nil }
        }
        return (front, shots)
    }

    /// Cửa sổ giữ lại để quét: bỏ app mình/nhạy cảm/hệ thống + cửa sổ tí hon
    /// (< 120×80), lấy tối đa `maxCount` theo diện tích giảm dần.
    static func keptWindows(
        in content: SCShareableContent,
        ownPID: pid_t,
        ownBundle: String?,
        maxCount: Int = 8
    ) -> [SCWindow] {
        content.windows
            .filter {
                $0.frame.width >= 120 && $0.frame.height >= 80
                    && $0.owningApplication?.processID != ownPID
                    && keepApp(bundleID: $0.owningApplication?.bundleIdentifier ?? "", ownBundle: ownBundle)
            }
            .sorted { ($0.frame.width * $0.frame.height) > ($1.frame.width * $1.frame.height) }
            .prefix(maxCount)
            .map { $0 }
    }

    /// Kích thước pixel chụp cho 1 cửa sổ (điểm × tỉ lệ màn hình, tối
    /// thiểu 1 — SCK từ chối width/height = 0). Hàm thuần, có unit test.
    static func capturePixelSize(points: CGSize, scale: CGFloat) -> (Int, Int) {
        (max(1, Int(points.width * scale)), max(1, Int(points.height * scale)))
    }

    /// Cấu hình chụp với kích thước pixel rõ ràng.
    private static func windowConfig(pixelWidth: Int, pixelHeight: Int) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.showsCursor = false
        c.scalesToFit = false
        c.width = pixelWidth
        c.height = pixelHeight
        return c
    }

    /// Chụp 1 cửa sổ (ném lỗi để bên gọi ghi chẩn đoán).
    static func captureWindowImage(_ win: SCWindow) async throws -> CGImage {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let (w, h) = capturePixelSize(points: win.frame.size, scale: scale)
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: win),
            configuration: windowConfig(pixelWidth: w, pixelHeight: h)
        )
    }

    /// Chụp ảnh thô (chưa OCR) để auto-monitor so thumbnail trước khi OCR.
    static func captureFrontImage() async -> (app: String, image: CGImage)? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ) else { return nil }

        // Danh sách windows không theo thứ tự z và chứa cửa sổ hệ thống →
        // ưu tiên cửa sổ LỚN NHẤT của app đang ở phía trước (current view).
        let ownBundle = Bundle.main.bundleIdentifier
        let cands = content.windows.filter {
            $0.owningApplication?.processID != ownPID
                && $0.frame.width > 1 && $0.frame.height > 1
                && !(systemBundles.contains($0.owningApplication?.bundleIdentifier ?? ""))
        }
        var win: SCWindow?
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !front.isEmpty, front != ownBundle
        {
            win = cands.filter { $0.owningApplication?.bundleIdentifier == front }
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        }
        if win == nil { win = cands.first }
        guard let win else {
            return await captureFullScreenImage(excludingOwnPID: ownPID, content: content)
        }
        let appID = win.owningApplication?.bundleIdentifier ?? ""
        guard !isSensitive(appID) else { return nil }
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: win),
            configuration: streamConfig(scale: 2)
        ) else { return nil }
        return (appID, image)
    }

    /// Dự phòng khi không thấy cửa sổ nào (hiếm). Fails closed.
    private static func captureFullScreenImage(
        excludingOwnPID ownPID: pid_t,
        content: SCShareableContent
    ) async -> (app: String, image: CGImage)? {
        guard let display = content.displays.first else { return nil }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: content.applications.filter { $0.processID == ownPID },
            exceptingWindows: []
        )
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let (w, h) = capturePixelSize(points: display.frame.size, scale: scale)
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: windowConfig(pixelWidth: w, pixelHeight: h)
        ) else { return nil }
        return ("", image)
    }

    /// Ảnh thu nhỏ 16×16 xám để so thay đổi (auto-detect, ngưỡng 2,5/255).
    static func thumbnail16(_ image: CGImage) -> [UInt8] {
        let w = 16, h = 16
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &px,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return px }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }

    /// Chênh lệch trung bình 2 thumbnail (đơn vị /255).
    static func meanDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var sum = 0.0
        for i in a.indices { sum += Double(abs(Int(a[i]) - Int(b[i]))) }
        return sum / Double(a.count)
    }

    private static func streamConfig(scale: Int) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.showsCursor = false
        c.scalesToFit = false
        if scale <= 1 {
            c.width = 0  // 1x: giữ phân giải gốc cho OCR auto
            c.height = 0
        }
        return c
    }

    /// OCR ngay trên máy (Vision). Public để auto-monitor OCR sau khi so thumbnail.
    static func ocr(_ image: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLanguages = ["vi", "en"]
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([req])) != nil else { return "" }
        let obs = (req.results ?? [])
        // Thứ tự đọc: trên xuống (maxY lớn trước), trái sang phải.
        let sorted = obs.sorted {
            let ay = Int($0.boundingBox.maxY * 40), by = Int($1.boundingBox.maxY * 40)
            if ay != by { return ay > by }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private static func isSensitive(_ appID: String) -> Bool {
        // Danh sách do lõi sở hữu (FFI); lõi vẫn trả 0 điểm để phòng thủ sâu.
        isSensitiveApp(appId: appID)
    }
}
