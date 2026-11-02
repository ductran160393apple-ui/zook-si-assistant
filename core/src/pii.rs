//! Che thông tin cá nhân (PII). Bất biến của lõi: mọi văn bản rời máy
//! đều đi qua [`redact`]; lớp giao diện không thể bỏ qua vì backend AI
//! chỉ nhận đầu vào đã che (xem `backends`).

use crate::entities::{email_re, long_digit_re, phone_re};
use regex::Regex;
use std::sync::OnceLock;

static STK_LABELED_RE: OnceLock<Regex> = OnceLock::new();
static NAME_RE: OnceLock<Regex> = OnceLock::new();
static ADDR_RE: OnceLock<Regex> = OnceLock::new();
static QUERY_RE: OnceLock<Regex> = OnceLock::new();

// SĐT/dãy số/email dùng chung regex của entities (một nguồn duy nhất).
fn stk_re() -> &'static Regex {
    STK_LABELED_RE.get_or_init(|| {
        Regex::new(r"(?i)\b(stk|số tài khoản|so tai khoan)\s*[:\-]?\s*[\d\s.]{6,30}").expect("pii stk")
    })
}
fn name_re() -> &'static Regex {
    NAME_RE.get_or_init(|| {
        Regex::new(
            r"\b(?i:(ten|tên|ho ten|họ tên|ten khach hang|tên khách hàng|anh|chi|chị|ong|ông|ba|bà|em))\s*[:\-]?\s+([A-ZÀ-Ỹ][a-zà-ỹ]+(\s+[A-ZÀ-Ỹ][a-zà-ỹ]+){1,4})",
        )
        .expect("pii name")
    })
}
fn addr_re() -> &'static Regex {
    ADDR_RE.get_or_init(|| {
        Regex::new(r"(?i)\b(dia chi|địa chỉ|noi o|nơi ở|tam tru|tạm trú|thuong tru|thường trú)\s*[:\-]?\s*[^,.;\n]{4,120}")
            .expect("pii addr")
    })
}
fn query_re() -> &'static Regex {
    QUERY_RE.get_or_init(|| Regex::new(r"(\?[^#\s]*)").expect("pii query"))
}

/// Che PII trong văn bản. Thứ tự quan trọng: STK có nhãn → SĐT → dãy số dài
/// → email → tên → địa chỉ → query URL.
pub fn redact(text: &str) -> String {
    let s = stk_re().replace_all(text, "[STK]");
    let s = phone_re().replace_all(&s, "[SĐT]");
    let s = long_digit_re().replace_all(&s, "[SỐ]");
    let s = email_re().replace_all(&s, "[EMAIL]");
    let s = name_re().replace_all(&s, "[TÊN]");
    let s = addr_re().replace_all(&s, "[ĐỊA CHỈ]");
    query_re().replace_all(&s, "").into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phone_never_leaves() {
        let out = redact("gọi tôi 0912345678 nhé");
        assert!(!out.contains("0912345678"), "{out}");
        assert!(out.contains("[SĐT]"));
    }

    #[test]
    fn stk_labeled_and_long_digits() {
        assert!(redact("STK: 123 456 7890").contains("[STK]"));
        let out = redact("cccd 001234567890");
        assert!(!out.contains("001234567890"), "{out}");
    }

    #[test]
    fn email_and_query_stripped() {
        let out = redact("mail a@b.com xem https://x.vn/p?token=abc#frag");
        assert!(!out.contains("a@b.com"), "{out}");
        assert!(!out.contains("token=abc"), "{out}");
        assert!(out.contains("https://x.vn/p"), "{out}");
    }
}
