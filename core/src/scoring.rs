//! Chấm điểm rủi ro 0–100 theo đặc tả mục 5.1.
//!
//! Quy trình: chuẩn hóa → nhóm từ khóa (mỗi nhóm 1 lần) → thực thể →
//! ngữ cảnh app → tổ hợp → chặn báo nhầm → cộng luật học được.

use crate::entities::{self, LinkKind};
use crate::learned::LearnedRuleSet;
use crate::normalize::{contains_word, normalize};
use crate::rules::{self, GROUPS};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RiskLevel {
    Safe,
    Suspicious,
    Dangerous,
}

impl RiskLevel {
    pub fn of(score: u32) -> Self {
        if score >= 70 {
            Self::Dangerous
        } else if score >= 35 {
            Self::Suspicious
        } else {
            Self::Safe
        }
    }

    pub fn label_vi(&self) -> &'static str {
        match self {
            Self::Safe => "AN TOÀN",
            Self::Suspicious => "ĐÁNG NGỜ",
            Self::Dangerous => "NGUY HIỂM",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Blacklists {
    pub domains: HashSet<String>,
    pub phones: HashSet<String>,
    pub accounts: HashSet<String>,
}

#[derive(Debug, Clone, Default)]
pub struct ScanContext {
    /// Bundle id / package app đang ở phía trước (chuẩn hóa trong hàm).
    pub app_id: String,
    /// Có app điều khiển từ xa đang chạy.
    pub remote_app_running: bool,
    /// Có cuộc gọi đang diễn ra (không đọc số).
    pub in_call: bool,
    /// Có app ngân hàng đang mở (tổ hợp remote + bank).
    pub bank_app_open: bool,
    pub blacklists: Blacklists,
    pub learned: LearnedRuleSet,
    /// Ngôn ngữ lý do (mặc định Vi).
    pub lang: crate::AiLang,
    /// JSON kho case (CaseStore) cho RAG; rỗng = tắt RAG.
    pub rag_cases_json: String,
}

/// Chọn chuỗi theo ngôn ngữ giao diện.
fn t(lang: crate::AiLang, vi: &'static str, en: &'static str) -> &'static str {
    match lang {
        crate::AiLang::Vi => vi,
        crate::AiLang::En => en,
    }
}

#[derive(Debug, Clone)]
pub struct ScanResult {
    pub score: u32,
    pub level: RiskLevel,
    /// Lý do theo ngôn ngữ `ScanContext.lang`.
    pub reasons: Vec<String>,
}

fn has(id: &HashSet<String>, s: &str) -> bool {
    id.contains(s)
}

/// Chấm điểm một văn bản. Không bao giờ đọc app nhạy cảm — gọi trước bằng
/// [`crate::rules::is_sensitive_app`] ở lớp nền tảng; hàm này vẫn trả 0 điểm
/// nếu `app_id` nhạy cảm để phòng thủ theo chiều sâu.
pub fn scan(text: &str, ctx: &ScanContext) -> ScanResult {
    if rules::is_sensitive_app(&ctx.app_id) {
        return ScanResult { score: 0, level: RiskLevel::Safe, reasons: vec![] };
    }
    let lang = ctx.lang;
    let norm = normalize(text);
    let mut score: u32 = 0;
    let mut reasons: Vec<String> = Vec::new();
    let mut matched: HashSet<&'static str> = HashSet::new();
    // Số loại tín hiệu độc lập (cho chặn báo nhầm).
    let mut signals: u32 = 0;

    // 2. Nhóm từ khóa.
    for g in GROUPS {
        if g.phrases.iter().any(|p| contains_word(&norm, p)) {
            matched.insert(g.id);
            score += g.weight;
            reasons.push(g.reason_lang(lang).to_string());
            signals += 1;
        }
    }

    // 3. Thực thể link / blacklist.
    let mut strange_link = false;
    let mut brand_hit: Option<String> = None;
    for url in entities::extract_urls(text) {
        match entities::classify_link(&url, lang) {
            LinkKind::BrandImpersonation(w) => {
                brand_hit = Some(w);
                break;
            }
            LinkKind::Suspicious(_) => strange_link = true,
            LinkKind::Normal => {}
        }
    }
    let has_brand = brand_hit.is_some();
    if let Some(w) = brand_hit {
        score += 30;
        reasons.push(w);
        signals += 1;
    } else if strange_link {
        score += 15;
        reasons.push(t(lang, "Link đáng ngờ (rút gọn/đuôi lạ/IP)", "Suspicious link (shortened/odd TLD/IP)").to_string());
        signals += 1;
    }
    let mut blacklisted = false;
    for url in entities::extract_urls(text) {
        let host = url.to_lowercase();
        if ctx.blacklists.domains.iter().any(|d| host.contains(d)) {
            blacklisted = true;
        }
    }
    for p in entities::extract_phones(text) {
        if has(&ctx.blacklists.phones, &p) {
            blacklisted = true;
        }
    }
    for a in entities::extract_stk(text) {
        let digits: String = a.chars().filter(|c| c.is_ascii_digit()).collect();
        if has(&ctx.blacklists.accounts, &digits) {
            blacklisted = true;
        }
    }
    if blacklisted {
        score += 70;
        reasons.push(t(lang, "Khớp danh sách đen", "Blacklist match").to_string());
        signals += 1;
    }

    // 4. Ngữ cảnh app.
    let remote_ctx =
        ctx.remote_app_running || rules::is_remote_app(&ctx.app_id);
    if remote_ctx {
        score += 25;
        reasons.push(t(lang, "Có app điều khiển từ xa đang chạy", "A remote-control app is running").to_string());
        signals += 1;
    }

    // 5. Tổ hợp.
    let m = |id: &str| matched.contains(id);
    let mut combo = |cond: bool, w: u32, r: &str| {
        if cond {
            score += w;
            reasons.push(r.to_string());
            // Tổ hợp đã nổ nghĩa là có ≥ 2 loại tín hiệu cùng xuất hiện.
            signals += 1;
        }
    };
    combo(remote_ctx && ctx.bank_app_open, 50, t(lang, "Tổ hợp nguy hiểm: điều khiển từ xa + app ngân hàng", "Dangerous combo: remote control + bank app"));
    combo(remote_ctx && ctx.in_call, 30, t(lang, "Vừa gọi điện vừa điều khiển từ xa", "On a call while remote-controlling"));
    combo(m("co_quan") && m("hoi_thuc"), 20, t(lang, "Giả danh cơ quan + hối thúc chuyển tiền", "Authority impersonation + pressured transfer"));
    combo(m("otp") && (m("hoi_thuc") || m("co_quan") || has_brand || strange_link), 15, t(lang, "Đòi OTP kèm hối thúc/giả danh/link lạ", "OTP demand with pressure/impersonation/strange link"));
    combo(m("trung_thuong") && (m("otp") || has_brand || strange_link), 15, t(lang, "Trúng thưởng kèm link/OTP", "Prize with link/OTP"));
    combo(m("dieu_khien") && (m("co_quan") || m("hoi_thuc") || m("dinh_danh")), 15, t(lang, "Dụ cài app điều khiển kèm giả danh/hối thúc/định danh", "Luring remote-app install with impersonation/pressure/ID request"));
    combo(m("dinh_danh") && (has_brand || strange_link), 15, t(lang, "Định danh kèm link lạ", "ID request with strange link"));
    combo(m("giu_bi_mat") && (m("co_quan") || m("hoi_thuc")), 10, t(lang, "Giữ bí mật kèm giả danh/hối thúc", "Secrecy with impersonation/pressure"));
    combo(
        m("viec_lam") && (m("hoi_thuc") || !entities::extract_stk(text).is_empty()),
        10,
        t(lang, "Việc làm/đầu tư kèm hối thúc hoặc STK", "Job/investment with pressure or bank account"),
    );
    combo(ctx.in_call && (m("co_quan") || m("hoi_thuc")), 10, t(lang, "Cuộc gọi kèm giả danh/hối thúc", "Call with impersonation/pressure"));

    // 7. Luật học được: mỗi luật khớp cộng trọng số, tính là một tín hiệu.
    // (Tiền tố theo ngôn ngữ; nội dung luật là dữ liệu đã lưu, giữ nguyên.)
    let learned_prefix = t(lang, "Dấu hiệu đã học", "Learned signal");
    let learned_hits = ctx.learned.match_norm(&norm);
    for hit in &learned_hits {
        score += hit.weight;
        reasons.push(format!("{learned_prefix}: {}", hit.reason));
        signals += 1;
    }

    // 7b. RAG: case tương tự trong kho từng bị gán lừa đảo → cộng điểm.
    // Điều kiện: ≥ 2 phiếu, hoặc 1 phiếu rất giống (≥ 0.3). Chỉ parse kho
    // khi có verdict:true (kiểm tra rẻ trước), giới hạn 512KB chống JSON phình.
    if (ctx.rag_cases_json.contains("\"verdict\": true")
        || ctx.rag_cases_json.contains("\"verdict\":true"))
        && ctx.rag_cases_json.len() <= 524_288
    {
        let store = crate::store::CaseStore::from_json(&ctx.rag_cases_json);
        let (votes, best) = store.retrieve_scam_votes(&norm, 3, 0.12);
        if votes >= 2 || (votes == 1 && best >= 0.3) {
            score += 15;
            reasons.push(
                if lang == crate::AiLang::En {
                    format!("{votes} similar past case(s) were labeled scams")
                } else {
                    format!("{votes} case tương tự từng bị gắn lừa đảo")
                },
            );
            signals += 1;
        }
    }

    // 6. Chặn báo nhầm: một loại tín hiệu, không blacklist → tối đa 30.
    if signals <= 1 && !blacklisted {
        score = score.min(30);
    }

    let score = score.min(100);
    let level = RiskLevel::of(score);
    ScanResult { score, level, reasons }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx() -> ScanContext {
        ScanContext::default()
    }

    #[test]
    fn example_85_danger() {
        let r = scan(
            "Tôi là cán bộ công an yêu cầu chuyển tiền gấp vào tài khoản an toàn, không được tiết lộ cho ai biết",
            &ctx(),
        );
        assert_eq!(r.score, 85, "reasons: {:?}", r.reasons);
        assert_eq!(r.level, RiskLevel::Dangerous);
    }

    #[test]
    fn example_75_danger_brand_link() {
        let r = scan(
            "Tài khoản của bạn sẽ bị khóa, xác thực tài khoản tại vietcombank-xacthuc.top ngay",
            &ctx(),
        );
        assert_eq!(r.score, 75, "reasons: {:?}", r.reasons);
        assert_eq!(r.level, RiskLevel::Dangerous);
    }

    #[test]
    fn example_45_suspicious_prize() {
        let r = scan("Chúc mừng bạn đã trúng thưởng, nhận tại bit.ly/abc123", &ctx());
        assert_eq!(r.score, 45, "reasons: {:?}", r.reasons);
        assert_eq!(r.level, RiskLevel::Suspicious);
    }

    #[test]
    fn example_15_safe_real_otp() {
        let r = scan("Mã OTP của bạn là 123456. Không chia sẻ mã này cho bất kỳ ai.", &ctx());
        assert_eq!(r.score, 15, "reasons: {:?}", r.reasons);
        assert_eq!(r.level, RiskLevel::Safe);
    }

    #[test]
    fn normal_chat_scores_zero() {
        let r = scan("Mai 7h đá bóng xong đi ăn phở nhé", &ctx());
        assert_eq!(r.score, 0);
        assert_eq!(r.level, RiskLevel::Safe);
    }

    /// Kho RAG giả lập: 2 case lừa đảo gần giống query + 1 phủ định.
    fn rag_json() -> String {
        let mut s = crate::store::CaseStore::default();
        let a = crate::store::Case {
            text: "công an yêu cầu chuyển tiền gấp vào tài khoản an toàn nhé bạn ơi".into(),
            app_id: "com.zalo.app".into(),
            score: 85,
            verdict: Some(true),
            reasons: vec![],
        };
        let mut b = a.clone();
        b.text = "công an yêu cầu chuyển tiền gấp vào tài khoản an toàn nhé bạn à".into();
        let mut c = a.clone();
        c.text = "chúc mừng bạn đã trúng thưởng lớn hãy nhận quà ngay hôm nay".into();
        c.verdict = Some(false);
        s.cases.push(a);
        s.cases.push(b);
        s.cases.push(c);
        s.to_json()
    }

    #[test]
    fn rag_fires_on_labeled_similar_cases() {
        let query = "công an gọi đòi chuyển tiền gấp vào tài khoản an toàn";
        let no_rag = scan(query, &ctx());
        let mut c = ctx();
        c.rag_cases_json = rag_json();
        let with_rag = scan(query, &c);
        assert_eq!(with_rag.score, (no_rag.score + 15).min(100));
        assert!(with_rag.reasons.iter().any(|r| r.contains("case tương tự")), "{with_rag:?}");
        // EN: điểm như nhau, lý do tiếng Anh.
        let mut ce = ctx();
        ce.lang = crate::AiLang::En;
        ce.rag_cases_json = rag_json();
        let en = scan(query, &ce);
        assert_eq!(en.score, with_rag.score);
        assert!(en.reasons.iter().any(|r| r.contains("similar past")), "{en:?}");
    }

    #[test]
    fn rag_silent_without_labeled_votes() {
        // Không verdict:true → không parse, không cộng điểm.
        let mut c = ctx();
        c.rag_cases_json = r#"{"cases":[{"text":"x","app_id":"a","score":1}]}"#.into();
        let r = scan("công an gọi đòi chuyển tiền gấp vào tài khoản an toàn", &c);
        assert!(!r.reasons.iter().any(|x| x.contains("case tương tự")), "{r:?}");
        // JSON hỏng an toàn.
        c.rag_cases_json = "không phải json".into();
        let r2 = scan("công an gọi đòi chuyển tiền gấp vào tài khoản an toàn", &c);
        assert!(!r2.reasons.iter().any(|x| x.contains("case tương tự")));
    }

    #[test]
    fn single_signal_capped() {
        // Chỉ link rút gọn đơn lẻ → ≤ 30 dù khớp.
        let r = scan("Xem bài này hay nè http://bit.ly/abc", &ctx());
        assert!(r.score <= 30);
    }

    #[test]
    fn sensitive_app_scores_zero() {
        let mut c = ctx();
        c.app_id = "com.vietcombank.mobile".into();
        let r = scan("chuyển tiền gấp công an", &c);
        assert_eq!(r.score, 0);
    }

    #[test]
    fn dangerous_combo_remote_bank() {
        let mut c = ctx();
        c.remote_app_running = true;
        c.bank_app_open = true;
        let r = scan("xin chào", &c);
        assert!(r.score >= 70, "score={}", r.score);
    }

    #[test]
    fn reasons_follow_lang_same_score() {
        let text = "Chúc mừng bạn đã trúng thưởng, nhận tại bit.ly/abc123";
        let vi = scan(text, &ctx());
        let mut c = ctx();
        c.lang = crate::AiLang::En;
        let en = scan(text, &c);
        assert_eq!(vi.score, en.score);
        assert!(vi.reasons.iter().any(|r| r.contains("trúng thưởng")), "{:?}", vi.reasons);
        assert!(en.reasons.iter().any(|r| r.contains("Prize")), "{:?}", en.reasons);
        assert!(en.reasons.iter().any(|r| r.contains("shortened")), "{:?}", en.reasons);
    }
}
