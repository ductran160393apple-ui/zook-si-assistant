import CoreGraphics
import Testing

@testable import AiAssistant

/// Unit test bộ lọc app cho ảnh toàn màn hình của auto-monitor
/// (danh sách nhạy cảm do lõi thật quyết qua FFI, không chạm màn hình).
struct ScreenFilterTests {
    private let own = "vn.aiassistant.macos"

    @Test func appThuongDuocGiu() {
        #expect(ScreenReader.keepApp(bundleID: "com.zalo.app", ownBundle: own))
        #expect(ScreenReader.keepApp(bundleID: "com.apple.Safari", ownBundle: own))
    }

    @Test func appMinhBiLoai() {
        #expect(!ScreenReader.keepApp(bundleID: own, ownBundle: own))
    }

    @Test func appNhayCamBiLoai() {
        #expect(!ScreenReader.keepApp(bundleID: "com.vietcombank.mobile", ownBundle: own))
    }

    @Test func cuaSoHeThongBiLoai() {
        #expect(!ScreenReader.keepApp(bundleID: "com.apple.dock", ownBundle: own))
        #expect(!ScreenReader.keepApp(bundleID: "com.apple.controlcenter", ownBundle: own))
        #expect(!ScreenReader.keepApp(bundleID: "com.apple.notificationcenterui", ownBundle: own))
        #expect(!ScreenReader.keepApp(bundleID: "com.apple.WindowManager", ownBundle: own))
    }

    @Test func bundleRongBiLoai() {
        #expect(!ScreenReader.keepApp(bundleID: "", ownBundle: own))
    }
}

/// Unit test cổng đổi-mới đa-cửa-sổ của AutoMonitor (hàm thuần).
struct WinSigTests {
    private let t1 = [UInt8](repeating: 10, count: 256)
    private let t2 = [UInt8](repeating: 200, count: 256)

    @Test func giongHetLaKhongDoi() {
        let s: [(UInt32, [UInt8])] = [(1, t1), (2, t2)]
        #expect(AutoMonitor.winsUnchanged(current: s, last: s))
    }

    @Test func doiAnhLaDoi() {
        let c: [(UInt32, [UInt8])] = [(1, t2)]
        let l: [(UInt32, [UInt8])] = [(1, t1)]
        #expect(!AutoMonitor.winsUnchanged(current: c, last: l))
    }

    @Test func doiTapIdLaDoi() {
        let c: [(UInt32, [UInt8])] = [(1, t1), (3, t2)]
        let l: [(UInt32, [UInt8])] = [(1, t1), (2, t2)]
        #expect(!AutoMonitor.winsUnchanged(current: c, last: l))
    }

    @Test func khacSoLuongLaDoi() {
        let c: [(UInt32, [UInt8])] = [(1, t1)]
        let l: [(UInt32, [UInt8])] = [(1, t1), (2, t2)]
        #expect(!AutoMonitor.winsUnchanged(current: c, last: l))
    }

    @Test func rongLaDoi() {
        let e: [(UInt32, [UInt8])] = []
        let c: [(UInt32, [UInt8])] = [(1, t1)]
        #expect(!AutoMonitor.winsUnchanged(current: e, last: e))
        #expect(!AutoMonitor.winsUnchanged(current: c, last: e))
    }
}

/// Unit test luật chốt chạy AI phân tích tự động.
struct AnalyzerGateTests {
    @Test func duDieuKienThiChay() {
        #expect(AutoAnalyzer.shouldAnalyze(stableSim: 0.9, stableSecs: 10, sinceRunSecs: 120, lastSim: 0.2))
    }

    @Test func chuaOnDinhThiCho() {
        #expect(!AutoAnalyzer.shouldAnalyze(stableSim: 0.4, stableSecs: 30, sinceRunSecs: 120, lastSim: 0.1))
        #expect(!AutoAnalyzer.shouldAnalyze(stableSim: 0.9, stableSecs: 5, sinceRunSecs: 120, lastSim: 0.1))
    }

    @Test func chayGanDayThiCho() {
        #expect(!AutoAnalyzer.shouldAnalyze(stableSim: 0.9, stableSecs: 30, sinceRunSecs: 45, lastSim: 0.1))
    }

    @Test func giongLanTruocThiBo() {
        #expect(!AutoAnalyzer.shouldAnalyze(stableSim: 0.9, stableSecs: 30, sinceRunSecs: 120, lastSim: 0.8))
    }
}

/// Unit test đổi điểm → pixel cho cấu hình chụp (SCK cấm 0×0).
struct PixelSizeTests {
    @Test func retinaGapDoi() {
        let (w, h) = ScreenReader.capturePixelSize(points: CGSize(width: 100, height: 50), scale: 2)
        #expect(w == 200 && h == 100)
    }

    @Test func toiThieuMotPixel() {
        let (w, h) = ScreenReader.capturePixelSize(points: CGSize(width: 0.4, height: 0), scale: 1)
        #expect(w == 1 && h == 1)
    }
}
