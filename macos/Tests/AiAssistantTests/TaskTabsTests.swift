import Testing

@testable import AiAssistant

/// Unit test tách ô kết quả theo tab tay (Tóm tắt/Dịch/Giải đề/Kiểm tra
/// giữ riêng, không đè nhau) + màu mức panel cảnh báo auto.
struct TaskTabsTests {
    @Test func oTrongMacDinh() {
        let s = AppState()
        #expect(s.result(for: .summarize) == "")
        #expect(s.warning(for: .scamCheck) == "")
    }

    @Test func ghiKhongDeNhau() {
        let s = AppState()
        s.showTask(.summarize, result: "TOM TAT", warning: "")
        s.showTask(.scamCheck, result: "AN TOAN", warning: "NGUY HIEM")
        #expect(s.result(for: .summarize) == "TOM TAT")
        #expect(s.result(for: .scamCheck) == "AN TOAN")
        #expect(s.warning(for: .scamCheck) == "NGUY HIEM")
        #expect(s.selectedTask == .scamCheck)
    }

    @Test func canhBaoNilGiuLaiCu() {
        let s = AppState()
        s.showTask(.solve, result: "a", warning: "W")
        s.showTask(.solve, result: "b")
        #expect(s.result(for: .solve) == "b")
        #expect(s.warning(for: .solve) == "W")
    }

    @Test func analyzeVeSummarize() {
        let s = AppState()
        s.showTask(.analyze, result: "x")
        #expect(s.selectedTask == .summarize)
        #expect(s.result(for: .analyze) == "x")
    }

    @Test func bonTabTay() {
        #expect(ManualTabs.list.count == 4)
        #expect(!ManualTabs.list.contains(.analyze))
    }

    @Test func mauMucCanhBao() {
        #expect(WarningPanel.levelColorName(level: "dangerous") == "red")
        #expect(WarningPanel.levelColorName(level: "suspicious") == "orange")
        #expect(WarningPanel.levelColorName(level: "safe") == "green")
        #expect(WarningPanel.levelColorName(level: "la") == "green")
    }
}
