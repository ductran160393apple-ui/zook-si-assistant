//! Luật học được: đề xuất của agent AI phải qua kiểm duyệt của lõi
//! trước khi áp dụng. Agent chỉ được tắt luật đã học, không sửa/tắt luật gốc.

use crate::normalize::{contains_word, normalize};
use serde::{Deserialize, Serialize};

pub const MAX_LEARNED_RULES: usize = 300;
pub const MAX_PHRASES_PER_RULE: usize = 8;
pub const MIN_WEIGHT: u32 = 5;
pub const MAX_WEIGHT: u32 = 20;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LearnedRule {
    pub id: String,
    /// Lý do tiếng Việt (≤ 120 ký tự).
    pub reason: String,
    /// Trọng số, kẹp 5–20.
    pub weight: u32,
    /// Cụm từ (lưu dạng gốc, khớp trên dạng chuẩn hóa).
    pub phrases: Vec<String>,
    /// Tên miền đề xuất chặn.
    pub domains: Vec<String>,
    /// SĐT đề xuất chặn (10 số, đầu 0).
    pub phones: Vec<String>,
    /// Đang bật hay đã bị tắt (agent chỉ được tắt).
    pub enabled: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LearnedRuleSet {
    pub rules: Vec<LearnedRule>,
}

#[derive(Debug, Clone)]
pub struct LearnedHit {
    pub id: String,
    pub reason: String,
    pub weight: u32,
}

/// Kiểm duyệt một đề xuất luật. Trả về luật đã chuẩn hóa (kẹp trọng số)
/// hoặc chuỗi lý do loại bỏ.
pub fn moderate(mut rule: LearnedRule) -> Result<LearnedRule, String> {
    if rule.id.trim().is_empty() {
        return Err("thiếu id".into());
    }
    if rule.reason.chars().count() > 120 {
        return Err(format!("lý do quá dài: {}", rule.id));
    }
    rule.weight = rule.weight.clamp(MIN_WEIGHT, MAX_WEIGHT);

    let roots = crate::rules::root_phrase_set();
    let mut clean_phrases: Vec<String> = Vec::new();
    for p in &rule.phrases {
        let n = normalize(p);
        let words: Vec<&str> = n.split_whitespace().collect();
        if n.chars().count() < 6 || n.chars().count() > 80 {
            continue;
        }
        if words.len() < 2 {
            continue;
        }
        if crate::rules::GENERIC_PHRASES.contains(&n.as_str()) {
            continue;
        }
        if roots.iter().any(|r| r == &n) {
            continue; // trùng từ khóa gốc
        }
        if clean_phrases.contains(&n) {
            continue;
        }
        clean_phrases.push(n);
        if clean_phrases.len() >= MAX_PHRASES_PER_RULE {
            break;
        }
    }
    rule.phrases = clean_phrases;

    rule.domains = rule
        .domains
        .into_iter()
        .map(|d| d.trim().to_lowercase())
        .filter(|d| {
            !d.is_empty()
                && !d.contains(' ')
                && d.contains('.')
                && !crate::rules::REPUTABLE_DOMAINS.iter().any(|r| d == r || d.ends_with(&format!(".{r}")))
                && !d.ends_with(".gov.vn")
                && !d.ends_with(".edu.vn")
                && !crate::rules::PROTECTED_SUFFIXES.iter().any(|p| d == p || d.ends_with(&format!(".{p}")))
        })
        .collect();

    rule.phones = rule
        .phones
        .into_iter()
        .map(|p| p.trim().to_string())
        .filter(|p| {
            p.len() == 10
                && p.starts_with('0')
                && p.chars().all(|c| c.is_ascii_digit())
                && !p.starts_with("1800")
                && !p.starts_with("1900")
        })
        .collect();

    if rule.phrases.is_empty() && rule.domains.is_empty() && rule.phones.is_empty() {
        return Err(format!("luật {} không còn nội dung hợp lệ sau kiểm duyệt", rule.id));
    }
    Ok(rule)
}

impl LearnedRuleSet {
    /// Thêm luật đã qua kiểm duyệt (kiểm tra trùng id + giới hạn 300).
    pub fn add(&mut self, rule: LearnedRule) -> Result<(), String> {
        let rule = moderate(rule)?;
        if self.rules.iter().any(|r| r.id == rule.id) {
            return Err(format!("trùng id {}", rule.id));
        }
        if self.rules.len() >= MAX_LEARNED_RULES {
            return Err("đã đạt tối đa 300 luật".into());
        }
        // Không trùng cụm với luật khác.
        for other in &self.rules {
            for p in &rule.phrases {
                if other.phrases.iter().any(|q| q == p) {
                    return Err(format!("cụm {p} trùng luật {}", other.id));
                }
            }
        }
        self.rules.push(rule);
        Ok(())
    }

    /// Các luật đang bật khớp văn bản đã chuẩn hóa.
    pub fn match_norm(&self, norm: &str) -> Vec<LearnedHit> {
        let mut hits = Vec::new();
        for r in &self.rules {
            if !r.enabled {
                continue;
            }
            let phrase_hit = r.phrases.iter().any(|p| contains_word(norm, p));
            let domain_hit = r.domains.iter().any(|d| norm.contains(d.as_str()));
            let phone_hit = r.phones.iter().any(|p| norm.contains(p.as_str()));
            if phrase_hit || domain_hit || phone_hit {
                hits.push(LearnedHit { id: r.id.clone(), reason: r.reason.clone(), weight: r.weight });
            }
        }
        hits
    }
}

/// Thêm một luật đề xuất vào kho JSON: kiểm duyệt + chống trùng id/cụm +
/// trần 300. Trả kho JSON mới, hoặc `{"error": "..."}` khi bị loại.
/// Nền tảng snapshot file trước khi ghi để hoàn tác.
#[uniffi::export]
pub fn learn_add_rule(rules_json: String, rule_json: String) -> String {
    let mut set: LearnedRuleSet =
        serde_json::from_str(&rules_json).unwrap_or_default();
    let rule: LearnedRule = match serde_json::from_str(&rule_json) {
        Ok(r) => r,
        Err(e) => return serde_json::json!({"error": format!("rule_json sai: {e}")}).to_string(),
    };
    match set.add(rule) {
        Ok(()) => serde_json::to_string_pretty(&set).unwrap_or(rules_json),
        Err(e) => serde_json::json!({"error": e}).to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule() -> LearnedRule {
        LearnedRule {
            id: "L1".into(),
            reason: "Chiêu mới".into(),
            weight: 99,
            phrases: vec!["hoan tien hoc phi".into()],
            domains: vec![],
            phones: vec![],
            enabled: true,
        }
    }

    #[test]
    fn weight_clamped_and_accepted() {
        let r = moderate(rule()).expect("phải nhận");
        assert_eq!(r.weight, 20);
    }

    #[test]
    fn generic_and_root_phrases_dropped() {
        let mut q = rule();
        q.phrases = vec!["ngân hàng".into(), "công an".into(), "hoan tien hoc phi".into()];
        let r = moderate(q).expect("phải nhận");
        assert_eq!(r.phrases, vec!["hoan tien hoc phi"]);
    }

    #[test]
    fn reputable_domains_and_hotlines_rejected() {
        let mut q = rule();
        q.phrases = vec![];
        q.domains = vec!["google.com".into(), "evil.top".into(), "acb.com.vn".into()];
        q.phones = vec!["18001234".into(), "19001008".into(), "0912345678".into()];
        let r = moderate(q).expect("phải nhận");
        assert_eq!(r.domains, vec!["evil.top"]);
        assert_eq!(r.phones, vec!["0912345678"]);
    }

    #[test]
    fn empty_after_moderation_rejected() {
        let mut q = rule();
        q.phrases = vec!["ngân hàng".into()];
        assert!(moderate(q).is_err());
    }

    #[test]
    fn ffi_add_rejects_duplicate_phrase() {
        let one = r#"{"id":"L1","reason":"Chiêu mới","weight":99,"phrases":["hoan tien hoc phi"],"domains":[],"phones":[],"enabled":true}"#;
        let kho = learn_add_rule(String::new(), one.into());
        assert!(kho.contains("\"L1\""), "{kho}");
        let dup = r#"{"id":"L2","reason":"Khác","weight":10,"phrases":["hoan tien hoc phi"],"domains":[],"phones":[],"enabled":true}"#;
        let out = learn_add_rule(kho, dup.into());
        assert!(out.contains("error"), "{out}");
    }

    #[test]
    fn learned_hit_adds_score_but_never_dangerous_alone() {
        let mut set = LearnedRuleSet::default();
        set.add(rule()).unwrap();
        let norm = normalize("thông báo hoàn tiền học phí cho sinh viên");
        let hits = set.match_norm(&norm);
        assert_eq!(hits.len(), 1);
        let ctx = crate::scoring::ScanContext { learned: set, ..Default::default() };
        let r = crate::scoring::scan("thông báo hoàn tiền học phí cho sinh viên", &ctx);
        assert!(r.score <= 30, "score={}", r.score);
        assert!(r.score > 0);
    }
}
