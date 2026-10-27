import Foundation
import ScreenCaptureKit
import Vision

/// Chụp cửa sổ trên cùng của app đang ở phía trước (theo z-order của
/// CGWindowList), không bao giờ chụp cửa sổ của chính app; OCR bằng Vision
/// ngay trên máy (ưu tiên vi rồi en), sắp xếp theo thứ tự đọc.
/// Ảnh chỉ nằm trong RAM, không ghi đĩa. App nhạy cảm → trả nil.
enum ScreenReader {
    /// Bundle id app đang ở phía trước + text OCR được (nil nếu app nhạy cảm).
    static func captureFrontWindow() async -> (app: String, text: String)? {
        guard let (app, image) = await captureFrontImage() else { return nil }
        return (app, ocr(image))
    }

    /// Chụp ảnh thô (chưa OCR) để auto-monitor so thumbnail trước khi OCR.
    static func captureFrontImage() async -> (app: String, image: CGImage)? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ) else { return nil }

        // Cửa sổ trên cùng không thuộc về chính app.
        guard let win = content.windows.first(where: { $0.owningApplication?.processID != ownPID }) else {
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
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: streamConfig(scale: 1)
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
