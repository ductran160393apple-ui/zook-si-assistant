//! AiAssistant core — lõi Rust dùng chung qua UniFFI.
//! Nơi duy nhất: chấm điểm lừa đảo, che PII, kiểm duyệt luật học được.

pub mod backends;
pub mod entities;
pub mod learned;
pub mod normalize;
pub mod pii;
pub mod rules;
pub mod scoring;
pub mod store;

pub use scoring::{RiskLevel, ScanContext, ScanResult};

/// Ngôn ngữ trả lời/lý do (theo ngôn ngữ giao diện người dùng chọn).
/// Mặc định Vi để tương thích hành vi cũ.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, uniffi::Enum)]
pub enum AiLang {
    #[default]
    Vi,
    En,
}

uniffi::setup_scaffolding!("aiassist_core");

// ---------------------------------------------------------------------------
// Bề mặt UniFFI (Swift/Kotlin chỉ được gọi các hàm này).
// Toàn bộ còn lại của backend AI/store/learn nằm trong chính module của nó
// (backends/store/learned) — xem docs/ARCHITECTURE.md.
// ---------------------------------------------------------------------------

#[derive(uniffi::Record)]
pub struct FfiScanResult {
    pub score: u32,
    /// "safe" | "suspicious" | "dangerous".
    pub level: String,
    pub reasons: Vec<String>,
}

#[derive(uniffi::Record)]
pub struct FfiScanFlags {
    pub remote_app_running: bool,
    pub in_call: bool,
    pub bank_app_open: bool,
    /// JSON LearnedRuleSet (rỗng = không dùng luật học được).
    pub learned_json: String,
    /// JSON Blacklists {"domains":[],"phones":[],"accounts":[]} (rỗng = trống).
    pub blacklist_json: String,
    /// JSON kho case (CaseStore) cho RAG (rỗng = tắt RAG).
    pub cases_json: String,
}

/// Kết quả dạng JSON cho moderate_rule khi lỗi (giữ FFI không-thất-bại).
fn err_json(msg: String) -> String {
    serde_json::json!({"error": msg}).to_string()
}

fn parse_blacklists(json: &str) -> scoring::Blacklists {
    #[derive(serde::Deserialize, Default)]
    struct In {
        #[serde(default)]
        domains: Vec<String>,
        #[serde(default)]
        phones: Vec<String>,
        #[serde(default)]
        accounts: Vec<String>,
    }
    if json.trim().is_empty() {
        return scoring::Blacklists::default();
    }
    let v: In = serde_json::from_str(json).unwrap_or_default();
    scoring::Blacklists {
        domains: v.domains.into_iter().collect(),
        phones: v.phones.into_iter().collect(),
        accounts: v.accounts.into_iter().collect(),
    }
}

/// Quét một văn bản. Lõi tự từ chối app nhạy cảm (điểm 0).
/// Không thất bại: JSON hỏng được coi như rỗng. `lang` chọn ngôn ngữ lý do.
#[uniffi::export]
pub fn scan_text(text: String, app_id: String, flags: FfiScanFlags, lang: AiLang) -> FfiScanResult {
    let learned: learned::LearnedRuleSet = if flags.learned_json.trim().is_empty() {
        learned::LearnedRuleSet::default()
    } else {
        serde_json::from_str(&flags.learned_json).unwrap_or_default()
    };
    let ctx = ScanContext {
        app_id,
        remote_app_running: flags.remote_app_running,
        in_call: flags.in_call,
        bank_app_open: flags.bank_app_open,
        blacklists: parse_blacklists(&flags.blacklist_json),
        learned,
        lang,
        rag_cases_json: flags.cases_json,
    };
    let r = scoring::scan(&text, &ctx);
    let level = match r.level {
        RiskLevel::Safe => "safe",
        RiskLevel::Suspicious => "suspicious",
        RiskLevel::Dangerous => "dangerous",
    }
    .to_string();
    FfiScanResult { score: r.score, level, reasons: r.reasons }
}

/// Che PII. Backend AI chỉ nhận đầu ra của hàm này.
#[uniffi::export]
pub fn redact_text(text: String) -> String {
    pii::redact(&text)
}

/// true nếu app nhạy cảm (không bao giờ đọc). Nguồn duy nhất cho
/// lớp chặn sớm của mọi nền tảng.
#[uniffi::export]
pub fn is_sensitive_app(app_id: String) -> bool {
    rules::is_sensitive_app(&app_id)
}

/// true nếu app điều khiển từ xa đã biết (nguồn duy nhất).
#[uniffi::export]
pub fn is_remote_app(app_id: String) -> bool {
    rules::is_remote_app(&app_id)
}

/// true nếu app ngân hàng/ví/định danh (nguồn duy nhất cho bank_app_open).
#[uniffi::export]
pub fn is_bank_app(app_id: String) -> bool {
    rules::is_bank_app(&app_id)
}

/// Kiểm duyệt một luật học được (JSON). Trả JSON luật đã chuẩn hóa,
/// hoặc {"error": "..."} khi bị loại.
#[uniffi::export]
pub fn moderate_rule(rule_json: String) -> String {
    let parsed: Result<learned::LearnedRule, _> = serde_json::from_str(&rule_json);
    match parsed {
        Err(e) => err_json(format!("rule_json sai: {e}")),
        Ok(rule) => match learned::moderate(rule) {
            Err(e) => err_json(e),
            Ok(ok) => serde_json::to_string(&ok).unwrap_or_else(|e| err_json(e.to_string())),
        },
    }
}
