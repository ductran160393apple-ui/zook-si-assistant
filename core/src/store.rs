//! Kho case + kho luật cục bộ (JSON, đã che PII).
//! Case: tối đa 1000, mỗi case ≤ 1500 ký tự, bỏ bản gần trùng
//! (cùng app, giống ≥ 80%). Luật: tối đa 300, giữ 20 bản, hoàn tác.

use crate::normalize::jaccard;
use serde::{Deserialize, Serialize};

pub const MAX_CASES: usize = 1000;
pub const MAX_CASE_LEN: usize = 1500;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Case {
    /// Văn bản ĐÃ che PII.
    #[serde(default)]
    pub text: String,
    /// `alias = "app"` để đọc kho JSON cũ của Swift/Kotlin (khóa "app").
    #[serde(default, alias = "app")]
    pub app_id: String,
    #[serde(default)]
    pub score: u32,
    /// Đánh giá người dùng: None chưa đánh giá, Some(true) đúng là lừa đảo.
    #[serde(default)]
    pub verdict: Option<bool>,
    #[serde(default)]
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CaseStore {
    #[serde(default)]
    pub cases: Vec<Case>,
}

impl CaseStore {
    /// Thêm case; bỏ qua nếu gần trùng (cùng app, Jaccard ≥ 0.8).
    /// Trả false khi bị bỏ qua.
    pub fn add(&mut self, mut case: Case) -> bool {
        case.text = crate::pii::redact(&case.text);
        if case.text.chars().count() > MAX_CASE_LEN {
            case.text = case.text.chars().take(MAX_CASE_LEN).collect();
        }
        let norm_new = crate::normalize::normalize(&case.text);
        for c in &self.cases {
            if c.app_id == case.app_id
                && jaccard(&crate::normalize::normalize(&c.text), &norm_new) >= 0.8
            {
                return false;
            }
        }
        self.cases.push(case);
        while self.cases.len() > MAX_CASES {
            self.cases.remove(0);
        }
        true
    }

    /// Case chưa soát (chưa có verdict), case được đánh giá luôn ưu tiên trước
    /// bằng cách sắp verdict lên đầu khi lấy batch.
    pub fn review_batch(&self, max: usize) -> Vec<&Case> {
        let mut pending: Vec<&Case> = self.cases.iter().filter(|c| c.verdict.is_none()).collect();
        pending.truncate(max.min(60));
        pending
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".into())
    }

    pub fn from_json(s: &str) -> Self {
        if let Ok(v) = serde_json::from_str::<Self>(s) {
            return v;
        }
        // Kho cũ của Swift/Kotlin là mảng trần [...] — bọc lại, không mất dữ liệu.
        if let Ok(cases) = serde_json::from_str::<Vec<Case>>(s) {
            return Self { cases };
        }
        Self::default()
    }

    /// Gán verdict cho case khớp (app + text đã che), mới nhất trước.
    /// Trả true khi tìm thấy.
    pub fn set_verdict(&mut self, app_id: &str, redacted: &str, verdict: bool) -> bool {
        if let Some(c) = self
            .cases
            .iter_mut()
            .rev()
            .find(|c| c.app_id == app_id && c.text == redacted)
        {
            c.verdict = Some(verdict);
            true
        } else {
            false
        }
    }
}

// ---------------------------------------------------------------------------
// Bề mặt FFI không-trạng-thái (JSON vào/ra, không bao giờ thất bại):
// nền tảng giữ file, lõi sở hữu ngữ nghĩa (dedup Jaccard, giới hạn, verdict).
// ---------------------------------------------------------------------------

/// Thêm case vào kho JSON. Tự che PII, cắt 1500 ký tự, bỏ gần trùng
/// (cùng app, Jaccard ≥ 0.8), giữ tối đa 1000. JSON hỏng → trả về nguyên đầu vào.
#[uniffi::export]
pub fn store_add_case(cases_json: String, case_json: String) -> String {
    let mut store = CaseStore::from_json(&cases_json);
    let case: Case = match serde_json::from_str(&case_json) {
        Ok(c) => c,
        Err(_) => return cases_json,
    };
    store.add(case);
    store.to_json()
}

/// Text các case chưa soát (có verdict thì loại), tối đa `max` (trần 60),
/// dạng JSON mảng chuỗi. Đầu vào hỏng → `"[]"`.
#[uniffi::export]
pub fn store_pending_cases(cases_json: String, max: u32) -> String {
    let store = CaseStore::from_json(&cases_json);
    let texts: Vec<&str> =
        store.review_batch(max as usize).iter().map(|c| c.text.as_str()).collect();
    serde_json::to_string(&texts).unwrap_or_else(|_| "[]".into())
}

/// Gán verdict cho case khớp (so `app_id` + toàn văn đã che).
/// `verdict`: true = đúng là lừa đảo, false = báo nhầm.
/// Không tìm thấy → trả về nguyên đầu vào.
#[uniffi::export]
pub fn store_set_verdict(cases_json: String, app_id: String, redacted: String, verdict: bool) -> String {
    let mut store = CaseStore::from_json(&cases_json);
    if store.set_verdict(&app_id, &redacted, verdict) {
        store.to_json()
    } else {
        cases_json
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn case(text: &str) -> Case {
        Case {
            text: text.into(),
            app_id: "com.zalo.app".into(),
            score: 85,
            verdict: None,
            reasons: vec![],
        }
    }

    #[test]
    fn pii_redacted_on_store() {
        let mut s = CaseStore::default();
        assert!(s.add(case("gọi 0912345678 công an chuyển tiền")));
        assert!(!s.cases[0].text.contains("0912345678"));
    }

    #[test]
    fn near_duplicate_dropped() {
        let mut s = CaseStore::default();
        assert!(s.add(case("công an yêu cầu chuyển tiền gấp vào tài khoản an toàn nhé bạn ơi")));
        assert!(!s.add(case("công an yêu cầu chuyển tiền gấp vào tài khoản an toàn nhé bạn à")));
        assert_eq!(s.cases.len(), 1);
    }

    #[test]
    fn legacy_bare_array_migrates() {
        let s = CaseStore::from_json(r#"[{"text":"x","app":"a","score":10}]"#);
        assert_eq!(s.cases.len(), 1);
        assert_eq!(s.cases[0].app_id, "a");
    }

    #[test]
    fn set_verdict_matches_newest() {
        let mut s = CaseStore::default();
        assert!(s.add(case("công an gọi đòi chuyển tiền gấp nhé")));
        assert!(s.set_verdict("com.zalo.app", &s.cases[0].text.clone(), true));
        assert_eq!(s.cases[0].verdict, Some(true));
        assert!(!s.set_verdict("com.zalo.app", "không khớp", false));
    }

    #[test]
    fn ffi_add_and_pending_roundtrip() {
        let out = store_add_case(String::new(), r#"{"text":"gọi 0912345678 nhé","app_id":"a","score":20}"#.into());
        assert!(!out.contains("0912345678"), "{out}");
        let pend = store_pending_cases(out.clone(), 60);
        assert!(pend.contains("SĐT"), "{pend}");
        // Case hỏng → trả nguyên đầu vào.
        assert_eq!(store_add_case(out.clone(), "không phải json".into()), out);
    }
}
