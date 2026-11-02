import Testing

@testable import AiAssistant

/// Unit test cho màu chữ panel (MenuView cho chọn, các panel cùng dùng).
struct PanelColorTests {
    @Test func hexDoSangRGB() {
        let c = PanelColor.rgb(hex: "#FF0000")
        #expect(c?.r == 1.0)
        #expect(c?.g == 0.0)
        #expect(c?.b == 0.0)
    }

    @Test func hexKhongDauThangVanNhan() {
        let c = PanelColor.rgb(hex: "00ff00")
        #expect(c?.r == 0.0)
        #expect(c?.g == 1.0)
        #expect(c?.b == 0.0)
    }

    @Test func hexCatKhoangTrangThua() {
        #expect(PanelColor.rgb(hex: "  #0000FF\n")?.b == 1.0)
    }

    @Test func hexSaiTraNil() {
        #expect(PanelColor.rgb(hex: "") == nil)
        #expect(PanelColor.rgb(hex: "  ") == nil)
        #expect(PanelColor.rgb(hex: "#FFF") == nil)
        #expect(PanelColor.rgb(hex: "#GGGGGG") == nil)
        #expect(PanelColor.rgb(hex: "red") == nil)
        #expect(PanelColor.rgb(hex: "#11223344") == nil)
    }

    @Test func chotHexCatKhoangTrang() {
        #expect(PanelColor.commitHex(text: "  #FFCC00\n", current: "#000000") == "#FFCC00")
    }

    @Test func chotHexRongVeTuDong() {
        #expect(PanelColor.commitHex(text: "", current: "#000000") == "")
        #expect(PanelColor.commitHex(text: "   \n ", current: "#000000") == "")
    }

    @Test func chotHexSaiGiuNguyen() {
        #expect(PanelColor.commitHex(text: "red", current: "#000000") == "#000000")
        #expect(PanelColor.commitHex(text: "#FFF", current: "#007AFF") == "#007AFF")
        #expect(PanelColor.commitHex(text: "#GGGGGG", current: "") == "")
    }

    @Test func bangMauHopLe() {
        #expect(PanelColorRow.presets.count == 8)
        for p in PanelColorRow.presets {
            #expect(PanelColor.rgb(hex: p) != nil)
        }
    }
}
