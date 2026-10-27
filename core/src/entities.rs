//! Trích thực thể: URL, số điện thoại, số tài khoản + phân loại link.

use regex::Regex;
use std::sync::OnceLock;
use url::Url;

static URL_RE: OnceLock<Regex> = OnceLock::new();
static PHONE_RE: OnceLock<Regex> = OnceLock::new();
static STK_RE: OnceLock<Regex> = OnceLock::new();
static LONG_DIGIT_RE: OnceLock<Regex> = OnceLock::new();
static EMAIL_RE: OnceLock<Regex> = OnceLock::new();

fn url_re() -> &'static Regex {
    URL_RE.get_or_init(|| {
        // Có scheme/www... hoặc domain trần (vietcombank-xacthuc.top, bit.ly/abc).
        Regex::new(r#"(?i)\b((?:https?://|www\.)[^\s,;\"'<>\]\)]+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:/[^\s,;\"'<>\]\)]*)?)"#)
            .expect("url regex")
    })
}

pub(crate) fn phone_re() -> &'static Regex {
    PHONE_RE.get_or_init(|| Regex::new(r"\b0\d{9}\b").expect("phone regex"))
}

fn stk_re() -> &'static Regex {
    STK_RE.get_or_init(|| {
        Regex::new(r"(?i)\bstk\s*[:\-]?\s*(\d[\d\s.]{5,25}\d)").expect("stk regex")
    })
}

pub(crate) fn long_digit_re() -> &'static Regex {
    LONG_DIGIT_RE.get_or_init(|| Regex::new(r"\d{9,}").expect("long digit regex"))
}

pub(crate) fn email_re() -> &'static Regex {
    EMAIL_RE.get_or_init(|| {
        Regex::new(r"(?i)\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b").expect("email regex")
    })
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LinkKind {
    /// Link giả mạo thương hiệu được bảo vệ.
    BrandImpersonation(String),
    /// Link đáng ngờ khác: rút gọn, đuôi rủi ro, IP, punycode.
    Suspicious(String),
    /// Link thường.
    Normal,
}

fn host_of(raw: &str) -> Option<String> {
    let with_scheme = if raw.contains("://") { raw.to_string() } else { format!("http://{raw}") };
    Url::parse(&with_scheme).ok().map(|u| u.host_str().unwrap_or("").to_lowercase())
}

fn is_ip_host(host: &str) -> bool {
    host.parse::<std::net::IpAddr>().is_ok()
}

/// Phân loại một URL thô.
pub fn classify_link(raw: &str) -> LinkKind {
    let Some(host) = host_of(raw) else { return LinkKind::Normal };
    let host_nodot: String = host.strip_prefix("www.").unwrap_or(&host).to_string();

    // Giả mạo thương hiệu: host chứa token nhưng không phải domain chính thức.
    for brand in crate::rules::BRANDS {
        let token = brand.token.trim();
        if token.is_empty() || !host_nodot.contains(token) {
            continue;
        }
        let official = brand.official.iter().any(|o| host_nodot == *o || host_nodot.ends_with(&format!(".{o}")));
        if !official {
            return LinkKind::BrandImpersonation(format!(
                "Link giả mạo {token} ({host})"
            ));
        }
    }

    let short = crate::rules::SHORTENERS
        .iter()
        .any(|s| host_nodot == *s || host_nodot.ends_with(&format!(".{s}")));
    let risky_tld =
        crate::rules::RISKY_TLDS.iter().any(|t| host_nodot.ends_with(t));
    if short || risky_tld || is_ip_host(&host) || host.starts_with("xn--") || host.contains(".xn--") {
        let why = if short {
            "link rút gọn"
        } else if is_ip_host(&host) {
            "link dạng địa chỉ IP"
        } else if risky_tld {
            "đuôi tên miền rủi ro"
        } else {
            "tên miền mã hóa (punycode)"
        };
        return LinkKind::Suspicious(format!("{why} ({host})"));
    }
    LinkKind::Normal
}

/// Mọi URL trong văn bản.
pub fn extract_urls(text: &str) -> Vec<String> {
    url_re().find_iter(text).map(|m| m.as_str().trim_end_matches(['.', ',', ';', '!', '?', ')', ']', '"']).to_string()).collect()
}

/// Mọi SĐT 10 số bắt đầu bằng 0.
pub fn extract_phones(text: &str) -> Vec<String> {
    phone_re().find_iter(text).map(|m| m.as_str().to_string()).collect()
}

/// STK sau nhãn STK.
pub fn extract_stk(text: &str) -> Vec<String> {
    stk_re()
        .captures_iter(text)
        .filter_map(|c| c.get(1).map(|m| m.as_str().to_string()))
        .collect()
}

/// Dãy ≥ 9 chữ số (CCCD, thẻ...).
pub fn extract_long_digits(text: &str) -> Vec<String> {
    long_digit_re().find_iter(text).map(|m| m.as_str().to_string()).collect()
}

/// Mọi email.
pub fn extract_emails(text: &str) -> Vec<String> {
    email_re().find_iter(text).map(|m| m.as_str().to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brand_impersonation() {
        assert!(matches!(
            classify_link("https://vietcombank-xacthuc.top/login"),
            LinkKind::BrandImpersonation(_)
        ));
        assert!(matches!(classify_link("https://vietcombank.com.vn/ib"), LinkKind::Normal));
    }

    #[test]
    fn shortener_and_ip() {
        assert!(matches!(classify_link("http://bit.ly/abc"), LinkKind::Suspicious(_)));
        assert!(matches!(classify_link("http://192.168.1.1/x"), LinkKind::Suspicious(_)));
        assert!(matches!(classify_link("https://example.vn/tin"), LinkKind::Normal));
    }

    #[test]
    fn extract_phones_and_stk() {
        assert_eq!(extract_phones("goi 0912345678 nhe"), vec!["0912345678"]);
        assert!(extract_phones("goi 19001234").is_empty());
        assert_eq!(extract_stk("STK: 1234567890").len(), 1);
    }
}
