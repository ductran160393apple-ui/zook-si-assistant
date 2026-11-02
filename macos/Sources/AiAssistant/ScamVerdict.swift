import Foundation

/// Kết hợp chấm điểm luật máy + kiểm chéo AI cho tác vụ kiểm tra lừa đảo.
/// Toàn hàm thuần (có unit test). Mức: 0 an toàn, 1 đáng ngờ, 2 nguy hiểm.
enum ScamVerdict {
    /// Trần ký tự gửi AI (tối ưu token input).
    static let maxAiChars = 2000
    /// Dưới ngưỡng này thì luật máy đủ, khỏi gọi AI.
    static let minAiChars = 100

    /// Có đáng gọi AI không (nội dung quá ngắn thì bỏ qua).
    static func shouldCallAi(text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= minAiChars
    }

    /// Mức AI đọc từ dòng kết luận (quét cả từ khóa Việt + Anh để không
    /// phụ thuộc ngôn ngữ trả lời).
    static func aiLevel(text: String) -> Int {
        let t = text.uppercased()
        if t.contains("NGUY HIỂM") || t.contains("DANGEROUS") { return 2 }
        if t.contains("ĐÁNG NGỜ") || t.contains("SUSPICIOUS") { return 1 }
        return 0
    }

    /// Mức theo điểm luật máy (ngưỡng 35/70, khớp lõi Rust).
    static func rulesLevel(score: UInt32) -> Int {
        score >= 70 ? 2 : score >= 35 ? 1 : 0
    }

    /// Text lỗi AiRunner (không phải kết luận AI) thì bỏ qua, tránh báo sai.
    static func isError(text: String) -> Bool {
        text.hasPrefix("Lỗi") || text.hasPrefix("Error")
    }

    /// Mức cuối = max(luật, AI) để tránh bỏ sót; escalated khi AI cao hơn luật.
    static func combine(rulesScore: UInt32, aiLevel: Int) -> (level: Int, escalated: Bool) {
        let r = rulesLevel(score: rulesScore)
        return (max(r, aiLevel), aiLevel > r)
    }

    /// Tên mức theo ngôn ngữ giao diện.
    static func levelName(level: Int, lang: AppLang) -> String {
        switch (level, lang) {
        case (2, .en): return "DANGEROUS"
        case (2, _): return "NGUY HIỂM"
        case (1, .en): return "SUSPICIOUS"
        case (1, _): return "ĐÁNG NGỜ"
        case (_, .en): return "SAFE"
        default: return "AN TOÀN"
        }
    }

    /// Dòng trạng thái trong lúc chờ AI kiểm chéo (cho biết tốn token).
    static func pendingLine(lang: AppLang) -> String {
        lang == .en
            ? "⏳ Re-checking via AI (uses tokens)…"
            : "⏳ Đang kiểm tra lại qua AI (tốn token)…"
    }

    /// Nội dung panel khi monitor tự động báo động: lý do luật ở trên,
    /// kết quả AI kiểm chéo gắn phía dưới.
    static func autoCombined(rules: [String], aiText: String) -> String {
        let head = rules.map { "• \($0)" }.joined(separator: "\n")
        return "\(head)\n\n---\n\(aiText)"
    }

    /// Soạn kết quả: chữ AI (tóm tắt + kết luận) + dòng chốt song ngữ.
    static func compose(aiText: String, rulesScore: UInt32, finalLevel: Int, escalated: Bool, lang: AppLang) -> String {
        let verdict = lang == .en
            ? "Overall verdict: \(levelName(level: finalLevel, lang: lang)) (rule score \(rulesScore)/100)."
            : "Kết luận chung: \(levelName(level: finalLevel, lang: lang)) (luật máy \(rulesScore)/100)."
        let extra = escalated
            ? (lang == .en ? "\nThe AI spotted suspicious signs the rules missed." : "\nAI phát hiện thêm dấu hiệu mà luật máy bỏ sót.")
            : ""
        return "\(aiText)\n\n---\n\(verdict)\(extra)"
    }
}
