import Foundation
import Testing

@testable import AiAssistant

/// Unit test cho lịch học tự động + RAG qua FFI thật (không chạm màn hình).
struct LearnAutoTests {
    @Test func khoangCachDungSo() {
        #expect(LearnAuto.off.interval == nil)
        #expect(LearnAuto.h6.interval == TimeInterval(6 * 3600))
        #expect(LearnAuto.h24.interval == TimeInterval(24 * 3600))
    }

    @Test func docGiaTriCuAnToan() {
        #expect((LearnAuto(rawValue: "6h") ?? .off) == .h6)
        #expect((LearnAuto(rawValue: "la") ?? .off) == .off)
        #expect((LearnAuto(rawValue: "off") ?? .h6) == .off)
    }

    @Test func nhanSongNgu() {
        #expect(!LearnAuto.h6.label.isEmpty)
        #expect(LearnAuto.allCases.count == 3)
    }

    @Test func batTatLichKhongLoi() {
        let state = AppState()
        state.learnAuto = .h6
        state.applyLearnAuto()
        #expect(LearnScheduler.isAuto)
        state.learnAuto = .off
        state.applyLearnAuto()
        #expect(!LearnScheduler.isAuto)
    }

    /// RAG end-to-end qua FFI: kho 2 case lừa đảo tương tự → +15 điểm.
    @Test func ragCongDiemQuaFFI() {
        let q = "công an gọi đòi chuyển tiền gấp vào tài khoản an toàn"
        let plain = scanText(text: q, appId: "test",
                             flags: FfiScanFlags(remoteAppRunning: false, inCall: false,
                                                 bankAppOpen: false, learnedJson: "", blacklistJson: "", casesJson: ""),
                             lang: .vi)
        let store = """
        {"cases":[{"text":"công an yêu cầu chuyển tiền gấp vào tài khoản an toàn nhé bạn ơi","app_id":"t","score":85,"verdict":true,"reasons":[]},{"text":"công an yêu cầu chuyển tiền gấp vào tài khoản an toàn nhé bạn à","app_id":"t","score":85,"verdict":true,"reasons":[]}]}
        """
        let ragged = scanText(text: q, appId: "test",
                              flags: FfiScanFlags(remoteAppRunning: false, inCall: false,
                                                  bankAppOpen: false, learnedJson: "", blacklistJson: "", casesJson: store),
                              lang: .vi)
        #expect(ragged.score == min(plain.score + 15, 100))
        #expect(ragged.reasons.contains(where: { $0.contains("case tương tự") }))
    }
}
