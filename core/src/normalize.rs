//! Chuẩn hóa tiếng Việt: chữ thường, bỏ dấu (kể cả NFD), gộp khoảng trắng.
//! Mọi khớp từ khóa trong lõi đều chạy trên dạng chuẩn hóa + khớp nguyên từ.

/// Bỏ dấu một ký tự tiếng Việt (dạng dựng sẵn) về ASCII.
fn strip_char(c: char) -> Option<char> {
    let base = match c {
        'à' | 'á' | 'ạ' | 'ả' | 'ã' | 'â' | 'ầ' | 'ấ' | 'ậ' | 'ẩ' | 'ẫ' | 'ă' | 'ằ' | 'ắ' | 'ặ'
        | 'ẳ' | 'ẵ' => 'a',
        'è' | 'é' | 'ẹ' | 'ẻ' | 'ẽ' | 'ê' | 'ề' | 'ế' | 'ệ' | 'ể' | 'ễ' => 'e',
        'ì' | 'í' | 'ị' | 'ỉ' | 'ĩ' => 'i',
        'ò' | 'ó' | 'ọ' | 'ỏ' | 'õ' | 'ô' | 'ồ' | 'ố' | 'ộ' | 'ổ' | 'ỗ' | 'ơ' | 'ờ' | 'ớ' | 'ợ'
        | 'ở' | 'ỡ' => 'o',
        'ù' | 'ú' | 'ụ' | 'ủ' | 'ũ' | 'ư' | 'ừ' | 'ứ' | 'ự' | 'ử' | 'ữ' => 'u',
        'ỳ' | 'ý' | 'ỵ' | 'ỷ' | 'ỹ' => 'y',
        'đ' => 'd',
        _ => return None,
    };
    Some(base)
}

fn is_combining_mark(c: char) -> bool {
    matches!(c, '\u{300}'..='\u{36f}')
}

/// Chuẩn hóa văn bản: thường hóa, bỏ dấu, gộp khoảng trắng.
pub fn normalize(text: &str) -> String {
    let lower = text.to_lowercase();
    let mut ascii = String::with_capacity(lower.len());
    for c in lower.chars() {
        if is_combining_mark(c) {
            continue;
        }
        match strip_char(c) {
            Some(b) => ascii.push(b),
            None => ascii.push(c),
        }
    }
    ascii.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn is_word_char(c: char) -> bool {
    c.is_alphanumeric() || c == '_'
}

/// Khớp nguyên từ: cụm từ phải xuất hiện với biên từ hai đầu.
pub fn contains_word(haystack: &str, needle: &str) -> bool {
    if needle.is_empty() {
        return false;
    }
    let h: Vec<char> = haystack.chars().collect();
    let n: Vec<char> = needle.chars().collect();
    if n.len() > h.len() {
        return false;
    }
    for i in 0..=(h.len() - n.len()) {
        if h[i..i + n.len()] == n[..] {
            let left_ok = i == 0 || !is_word_char(h[i - 1]);
            let right_ok = i + n.len() == h.len() || !is_word_char(h[i + n.len()]);
            if left_ok && right_ok {
                return true;
            }
        }
    }
    false
}

/// Tương đồng Jaccard theo tập từ (dùng dedup case, ngưỡng 0.8).
pub fn jaccard(a: &str, b: &str) -> f64 {
    use std::collections::HashSet;
    let sa: HashSet<&str> = a.split_whitespace().collect();
    let sb: HashSet<&str> = b.split_whitespace().collect();
    if sa.is_empty() && sb.is_empty() {
        return 1.0;
    }
    let inter = sa.intersection(&sb).count() as f64;
    let union = sa.union(&sb).count() as f64;
    if union == 0.0 { 1.0 } else { inter / union }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lowercase_and_strip_precomposed() {
        assert_eq!(normalize("CÔNG AN Nhân Dân"), "cong an nhan dan");
    }

    #[test]
    fn strip_nfd_combining_marks() {
        // "công" dựng từ o + U+0302 + U+0323
        assert_eq!(normalize("co\u{302}ng"), "cong");
    }

    #[test]
    fn collapse_whitespace() {
        assert_eq!(normalize("chuyen   tien\tgap"), "chuyen tien gap");
    }

    #[test]
    fn whole_word_only() {
        assert!(contains_word("cong an den", "cong an"));
        assert!(!contains_word("cong anh", "cong an"));
        assert!(!contains_word("tan cong an ninh", "cong an ninh x"));
    }
}
