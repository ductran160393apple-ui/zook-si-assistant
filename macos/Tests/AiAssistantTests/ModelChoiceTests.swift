import Testing

@testable import AiAssistant

/// Unit test cho logic chọn model của popup menu (ModelPickerRow dùng các
/// hàm thuần này; bản thân hàng SwiftUI do người dùng kiểm bằng mắt).
struct ModelChoiceTests {
    private let known = ["muse-spark-1.3", "muse-spark-1.2"]

    @Test func modelQuenThuocChonTrucTiep() {
        #expect(ModelChoice.selection(model: "muse-spark-1.2", known: known) == "muse-spark-1.2")
    }

    @Test func modelLaRoiVaoOTuNhap() {
        #expect(ModelChoice.selection(model: "model-moi-9.9", known: known) == ModelChoice.customTag)
    }

    @Test func modelRongRoiVaoOTuNhap() {
        #expect(ModelChoice.selection(model: "", known: known) == ModelChoice.customTag)
        #expect(ModelChoice.selection(model: "  ", known: known) == ModelChoice.customTag)
    }

    @Test func chotOTuNhapCatKhoangTrang() {
        #expect(ModelChoice.commit(text: "  muse-spark-9.9\n", defaultModel: "d") == "muse-spark-9.9")
    }

    @Test func chotOTuNhapBoTrongVeMacDinh() {
        #expect(ModelChoice.commit(text: "", defaultModel: "muse-spark-1.3") == "muse-spark-1.3")
        #expect(ModelChoice.commit(text: "   \n ", defaultModel: "opus") == "opus")
    }

    @Test func danhSachModelHopLe() {
        #expect(!MetaModels.list.isEmpty)
        #expect(!ClaudeModels.list.isEmpty)
        #expect(!AgyModels.list.isEmpty)
        // Phần tử đầu là mặc định (khớp AppState).
        #expect(MetaModels.list[0] == "muse-spark-1.3")
        #expect(ClaudeModels.list[0] == "opus")
        #expect(AgyModels.list[0] == "gemini-4-argon-medium")
        // Khớp `agy models` trên máy (13 model, tháng 10/2026).
        #expect(AgyModels.list.count == 13)
        #expect(AgyModels.list.contains("claude-sonnet-5-5-high"))
        #expect(AgyModels.list.contains("gpt-oss-120b-medium"))
        // Tag "Tự nhập" không đụng bất kỳ model ID nào.
        for m in MetaModels.list + ClaudeModels.list + AgyModels.list {
            #expect(m != ModelChoice.customTag)
        }
    }
}
