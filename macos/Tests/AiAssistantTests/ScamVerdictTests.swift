import Testing

@testable import AiAssistant

/// Unit test cho logic kết hợp luật máy + AI kiểm chéo.
struct ScamVerdictTests {
    @Test func aiLevelDocTatCaBienThe() {
        #expect(ScamVerdict.aiLevel(text: "Kết luận: NGUY HIỂM") == 2)
        #expect(ScamVerdict.aiLevel(text: "Verdict: DANGEROUS") == 2)
        #expect(ScamVerdict.aiLevel(text: "Kết luận: ĐÁNG NGỜ") == 1)
        #expect(ScamVerdict.aiLevel(text: "Verdict: SUSPICIOUS") == 1)
        #expect(ScamVerdict.aiLevel(text: "Kết luận: AN TOÀN") == 0)
        #expect(ScamVerdict.aiLevel(text: "Verdict: SAFE") == 0)
        // Chữ thường vẫn nhận (so khớp không phân biệt hoa thường).
        #expect(ScamVerdict.aiLevel(text: "verdict: dangerous") == 2)
        // Nguy hiểm thắng khi cả hai cùng xuất hiện.
        #expect(ScamVerdict.aiLevel(text: "SUSPICIOUS ... DANGEROUS") == 2)
    }

    @Test func aiLevelBoQuaLoiVaChuThuong() {
        #expect(ScamVerdict.aiLevel(text: "Lỗi agy: Individual quota reached") == 0)
        #expect(ScamVerdict.aiLevel(text: "Error meta: boom") == 0)
        #expect(ScamVerdict.aiLevel(text: "Tóm tắt nội dung...") == 0)
    }

    @Test func phatHienTextLoi() {
        #expect(ScamVerdict.isError(text: "Lỗi agy: quota"))
        #expect(ScamVerdict.isError(text: "Error meta: x"))
        #expect(!ScamVerdict.isError(text: "Tóm tắt: ..."))
    }

    @Test func nguongLuatMay() {
        #expect(ScamVerdict.rulesLevel(score: 0) == 0)
        #expect(ScamVerdict.rulesLevel(score: 34) == 0)
        #expect(ScamVerdict.rulesLevel(score: 35) == 1)
        #expect(ScamVerdict.rulesLevel(score: 69) == 1)
        #expect(ScamVerdict.rulesLevel(score: 70) == 2)
        #expect(ScamVerdict.rulesLevel(score: 100) == 2)
    }

    @Test func ketHopLayMucCaoHon() {
        #expect(ScamVerdict.combine(rulesScore: 20, aiLevel: 0) == (0, false))
        #expect(ScamVerdict.combine(rulesScore: 20, aiLevel: 2) == (2, true))
        #expect(ScamVerdict.combine(rulesScore: 80, aiLevel: 0) == (2, false))
        #expect(ScamVerdict.combine(rulesScore: 45, aiLevel: 2) == (2, true))
        #expect(ScamVerdict.combine(rulesScore: 45, aiLevel: 1) == (1, false))
    }

    @Test func nguongGoiAi() {
        #expect(!ScamVerdict.shouldCallAi(text: ""))
        #expect(!ScamVerdict.shouldCallAi(text: "   \n "))
        #expect(!ScamVerdict.shouldCallAi(text: String(repeating: "a", count: 99)))
        #expect(ScamVerdict.shouldCallAi(text: String(repeating: "a", count: 100)))
    }

    @Test func tenMucSongNgu() {
        #expect(ScamVerdict.levelName(level: 2, lang: .vi) == "NGUY HIỂM")
        #expect(ScamVerdict.levelName(level: 2, lang: .en) == "DANGEROUS")
        #expect(ScamVerdict.levelName(level: 1, lang: .vi) == "ĐÁNG NGỜ")
        #expect(ScamVerdict.levelName(level: 1, lang: .en) == "SUSPICIOUS")
        #expect(ScamVerdict.levelName(level: 0, lang: .vi) == "AN TOÀN")
        #expect(ScamVerdict.levelName(level: 0, lang: .en) == "SAFE")
    }

    @Test func dongChoAiBaoTonToken() {
        let vi = ScamVerdict.pendingLine(lang: .vi)
        #expect(vi.contains("kiểm tra lại") && vi.contains("tốn token"))
        let en = ScamVerdict.pendingLine(lang: .en)
        #expect(en.contains("Re-checking") && en.contains("tokens"))
    }

    @Test func gopLuatVaAiChoBaoDongTuDong() {
        let s = ScamVerdict.autoCombined(rules: ["Hối thúc chuyển tiền", "Link lạ"], aiText: "Tóm tắt AI...")
        #expect(s.hasPrefix("• Hối thúc chuyển tiền\n• Link lạ\n\n---\n"))
        #expect(s.hasSuffix("Tóm tắt AI..."))
    }

    @Test func soanKetQuaDayDu() {
        let vi = ScamVerdict.compose(aiText: "Tóm tắt...", rulesScore: 20, finalLevel: 2, escalated: true, lang: .vi)
        #expect(vi.contains("Tóm tắt..."))
        #expect(vi.contains("Kết luận chung: NGUY HIỂM (luật máy 20/100)."))
        #expect(vi.contains("bỏ sót"))
        let en = ScamVerdict.compose(aiText: "Summary...", rulesScore: 80, finalLevel: 2, escalated: false, lang: .en)
        #expect(en.contains("Overall verdict: DANGEROUS (rule score 80/100)."))
        #expect(!en.contains("spotted"))
    }
}
