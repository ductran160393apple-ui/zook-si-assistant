import Testing

@testable import AiAssistant

/// Unit test cho mặt icon menu-bar theo mức cảnh báo.
struct AlertFaceTests {
    @Test func bieuTuongTheoMuc() {
        #expect(AlertFace.symbol(level: "dangerous") == "exclamationmark.shield.fill")
        #expect(AlertFace.symbol(level: "suspicious") == "shield.fill")
        #expect(AlertFace.symbol(level: "safe") == "shield")
        #expect(AlertFace.symbol(level: "la") == "shield")
    }

    @Test func mauKhienTheoMuc() {
        #expect(AlertFace.shieldColorName(level: "dangerous") == "red")
        #expect(AlertFace.shieldColorName(level: "suspicious") == "orange")
        #expect(AlertFace.shieldColorName(level: "safe") == "none")
        #expect(AlertFace.shieldColorName(level: "la") == "none")
    }

    @Test func anhStatusCoKichThuocVaTemplateDung() {
        let d = AlertFace.statusImage(level: "dangerous")
        #expect(d.size.width > 0 && !d.isTemplate)
        let s = AlertFace.statusImage(level: "suspicious")
        #expect(s.size.width > 0 && !s.isTemplate)
        let ok = AlertFace.statusImage(level: "safe")
        #expect(ok.size.width > 0 && ok.isTemplate)
    }

    @Test func khungGlowCungKichThuocKhungThuong() {
        let base = AlertFace.statusImage(level: "dangerous")
        let glow = AlertFace.glowImage(level: "dangerous")
        #expect(glow.size == base.size && !glow.isTemplate)
    }
}
