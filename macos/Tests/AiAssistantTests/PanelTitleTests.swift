import Testing

@testable import AiAssistant

/// Unit test cho tên song ngữ (header panel + tên backend).
struct PanelTitleTests {
    @Test func tenTacVuTiengViet() {
        #expect(PanelTitle.name(task: .summarize, lang: .vi) == "Tóm tắt")
        #expect(PanelTitle.name(task: .translate, lang: .vi) == "Dịch")
        #expect(PanelTitle.name(task: .solve, lang: .vi) == "Giải đề")
        #expect(PanelTitle.name(task: .analyze, lang: .vi) == "Phân tích")
        #expect(PanelTitle.name(task: .scamCheck, lang: .vi) == "Kiểm tra lừa đảo")
    }

    @Test func tenTacVuTiengAnh() {
        #expect(PanelTitle.name(task: .summarize, lang: .en) == "Summarize")
        #expect(PanelTitle.name(task: .translate, lang: .en) == "Translate")
        #expect(PanelTitle.name(task: .solve, lang: .en) == "Solve")
        #expect(PanelTitle.name(task: .analyze, lang: .en) == "Analyze")
        #expect(PanelTitle.name(task: .scamCheck, lang: .en) == "Scam check")
    }

    @Test func tenBackendSongNgu() {
        #expect(BackendID.metaApi.displayName(.vi) == "Muse/Meta (API key, mặc định)")
        #expect(BackendID.metaApi.displayName(.en) == "Muse/Meta (API key, default)")
        #expect(BackendID.anthropic.displayName(.vi) == "Anthropic API (dự phòng)")
        #expect(BackendID.anthropic.displayName(.en) == "Anthropic API (fallback)")
        // Tên trung tính giữ nguyên cả hai ngôn ngữ.
        for b in [BackendID.claudeCode, .geminiCli, .antigravity] {
            #expect(b.displayName(.vi) == b.displayName(.en))
        }
    }
}
