import Foundation
import Testing

@testable import AiAssistant

/// Unit test cho giờ nhật ký và dòng xóa cảnh báo auto cũ.
struct LogTimeTests {
    @Test func gioDinhDangHHmmss() {
        // 01:02:03 UTC — chỉ assert khung giờ, không assert múi giờ máy.
        let d = Date(timeIntervalSince1970: 3723)
        let s = LogTime.string(from: d)
        #expect(s.count == 8)
        let parts = s.split(separator: ":")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { $0.count == 2 && Int($0) != nil })
    }

    @Test func dongAnToanDayDuSongNgu() {
        let d = Date(timeIntervalSince1970: 3723)
        let vi = AutoClear.scanLine(app: "com.foo.bar", score: 5, level: "safe", reasons: [], date: d, lang: .vi)
        #expect(vi.contains("An toàn (5/100)"))
        #expect(vi.contains("com.foo.bar"))
        #expect(vi.contains(LogTime.string(from: d)))
        let en = AutoClear.scanLine(app: "com.foo.bar", score: 5, level: "safe", reasons: [], date: d, lang: .en)
        #expect(en.contains("Safe (5/100)"))
        #expect(en.contains("com.foo.bar"))
    }

    @Test func cuaSoBaoVeKetQuaTay() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(!AutoClear.manualFresh(since: nil, now: now))
        #expect(AutoClear.manualFresh(since: Date(timeIntervalSince1970: 990), now: now))
        #expect(AutoClear.manualFresh(since: Date(timeIntervalSince1970: 971), now: now))
        #expect(!AutoClear.manualFresh(since: Date(timeIntervalSince1970: 970), now: now))
        #expect(!AutoClear.manualFresh(since: Date(timeIntervalSince1970: 900), now: now))
    }

    @Test func dongDangNgoKemLyDo() {
        let d = Date(timeIntervalSince1970: 3723)
        let vi = AutoClear.scanLine(app: "web", score: 45, level: "suspicious", reasons: ["Link lạ", "Hối thúc"], date: d, lang: .vi)
        #expect(vi.contains("ĐÁNG NGỜ (45/100)"))
        #expect(vi.contains("• Link lạ\n• Hối thúc"))
        let en = AutoClear.scanLine(app: "web", score: 45, level: "suspicious", reasons: ["Odd link"], date: d, lang: .en)
        #expect(en.contains("SUSPICIOUS (45/100)"))
        #expect(en.contains("• Odd link"))
    }
}
