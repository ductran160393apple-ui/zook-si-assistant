//! Định nghĩa luật gốc: nhóm từ khóa, thương hiệu, app nhạy cảm, danh sách generic.
//! Mọi cụm từ ở đây đã ở dạng chuẩn hóa (không dấu) để khớp trực tiếp.

/// Một nhóm từ khóa: tính tối đa một lần, kể cả khi nhiều cụm cùng khớp.
pub struct KeywordGroup {
    /// Mã nhóm, dùng cho tổ hợp.
    pub id: &'static str,
    /// Trọng số khi nhóm khớp.
    pub weight: u32,
    /// Lý do tiếng Việt hiển thị cho người dùng.
    pub reason: &'static str,
    /// Lý do tiếng Anh (cùng ý với `reason`).
    pub reason_en: &'static str,
    /// Các cụm từ (dạng chuẩn hóa, khớp nguyên từ).
    pub phrases: &'static [&'static str],
}

pub const GROUPS: &[KeywordGroup] = &[
    KeywordGroup {
        id: "co_quan",
        weight: 20,
        reason: "Giả danh cơ quan chức năng (công an, tòa án, thuế...)",
        reason_en: "Impersonating authorities (police, courts, tax...)",
        phrases: &[
            "cong an",
            "can bo cong an",
            "co quan dieu tra",
            "toan an",
            "vien kiem sat",
            "cuc thue",
            "chi cuc thue",
            "bao hiem xa hoi",
            "so giao thong",
            "cu tri",
            "vien truong",
            "thu truong",
        ],
    },
    KeywordGroup {
        id: "hoi_thuc",
        weight: 20,
        reason: "Hối thúc chuyển tiền gấp",
        reason_en: "Pressuring urgent money transfer",
        phrases: &[
            "chuyen tien",
            "chuyen khoan",
            "chuyen gap",
            "tai khoan an toan",
            "tai khoan dinh danh",
            "khan cap",
            "ngay lap tuc",
            "trong vong",
            "se bi khoa",
            "bi khoa",
            "qua han",
            "nop phat",
            "dong phat",
        ],
    },
    KeywordGroup {
        id: "dieu_khien",
        weight: 20,
        reason: "Yêu cầu cài app điều khiển từ xa",
        reason_en: "Asking to install a remote-control app",
        phrases: &[
            "anydesk",
            "teamviewer",
            "ultraviewer",
            "remote desktop",
            "dieu khien tu xa",
            "dieu khien may",
            "cai app",
            "cai ung dung",
            "cap quyen dieu khien",
            "doc ma dieu khien",
            "cho phep truy cap",
        ],
    },
    KeywordGroup {
        id: "otp",
        weight: 15,
        reason: "Nhắc tới mã OTP/xác thực",
        reason_en: "Mentioning OTP/authentication codes",
        phrases: &[
            "otp",
            "ma otp",
            "ma xac nhan",
            "ma xac thuc",
            "gui ma",
            "doc ma",
            "cung cap ma",
            "cho xin ma",
        ],
    },
    KeywordGroup {
        id: "trung_thuong",
        weight: 15,
        reason: "Chiêu trúng thưởng/qua tặng",
        reason_en: "Prize/giveaway bait",
        phrases: &[
            "trung thuong",
            "chuc mung ban",
            "chuc mung quy khach",
            "nhan thuong",
            "nhan qua",
            "qua tang mien phi",
            "tri an khach hang",
            "vong quay may man",
        ],
    },
    KeywordGroup {
        id: "viec_lam",
        weight: 15,
        reason: "Việc làm/đầu tư đáng ngờ",
        reason_en: "Suspicious job/investment offer",
        phrases: &[
            "viec nhe luong cao",
            "kiem tien online",
            "dau tu sinh loi",
            "loi nhuan cao",
            "bao dam loi nhuan",
            "nap tien de",
            "lam nhiem vu",
            "an hoa hong",
        ],
    },
    KeywordGroup {
        id: "giu_bi_mat",
        weight: 15,
        reason: "Yêu cầu giữ bí mật, không tiết lộ",
        reason_en: "Demanding secrecy, no disclosure",
        phrases: &[
            "giu bi mat",
            "tuyet doi bi mat",
            "khong duoc tiet lo",
            "khong duoc noi",
            "khong noi voi ai",
            "khong cho ai biet",
            "bi mat dieu tra",
            "dang dieu tra",
        ],
    },
    KeywordGroup {
        id: "dinh_danh",
        weight: 10,
        reason: "Yêu cầu định danh/xác thực tài khoản",
        reason_en: "Requesting ID/account verification",
        phrases: &[
            "xac thuc",
            "xac minh danh tinh",
            "dinh danh",
            "dinh danh dien tu",
            "cap nhat sinh trac",
            "cccd",
            "can cuoc",
        ],
    },
];

/// Thương hiệu được bảo vệ: token xuất hiện trong host + domain chính thức.
pub struct Brand {
    pub token: &'static str,
    pub official: &'static [&'static str],
}

pub const BRANDS: &[Brand] = &[
    Brand { token: "vietcombank", official: &["vietcombank.com.vn"] },
    Brand { token: "vietinbank", official: &["vietinbank.vn"] },
    Brand { token: "bidv", official: &["bidv.com.vn"] },
    Brand { token: "agribank", official: &["agribank.com.vn"] },
    Brand { token: "techcombank", official: &["techcombank.com"] },
    Brand { token: "mbbank", official: &["mbbank.com.vn"] },
    Brand { token: "acb", official: &["acb.com.vn"] },
    Brand { token: "vpbank", official: &["vpbank.com.vn"] },
    Brand { token: "sacombank", official: &["sacombank.com.vn"] },
    Brand { token: "momo", official: &["momo.vn"] },
    Brand { token: "zalopay", official: &["zalopay.vn"] },
    Brand { token: "vneid", official: &["vneid.gov.vn"] },
    Brand { token: "dichvucong", official: &["dichvucong.gov.vn"] },
];

/// Tên miền rút gọn link thường bị lợi dụng.
pub const SHORTENERS: &[&str] = &[
    "bit.ly", "tinyurl.com", "goo.gl", "t.co", "ow.ly", "is.gd", "cutt.ly", "rebrand.ly",
    "shorturl.at",
];

/// Đuôi tên miền rủi ro cao.
pub const RISKY_TLDS: &[&str] =
    &[".top", ".xyz", ".club", ".buzz", ".gq", ".ml", ".tk", ".cf", ".work", ".click", ".link"];

/// Tên miền chính thống không bao giờ bị chặn bởi luật học được.
pub const REPUTABLE_DOMAINS: &[&str] = &[
    "google.com",
    "facebook.com",
    "zalo.me",
    "zalo.vn",
    "apple.com",
    "microsoft.com",
    "gov.vn",
    "edu.vn",
];

/// Tên miền thật của ngân hàng/thương hiệu (hậu tố) — luật học được không được chặn.
pub const PROTECTED_SUFFIXES: &[&str] = &[
    "vietcombank.com.vn",
    "vietinbank.vn",
    "bidv.com.vn",
    "agribank.com.vn",
    "techcombank.com",
    "mbbank.com.vn",
    "acb.com.vn",
    "vpbank.com.vn",
    "sacombank.com.vn",
    "momo.vn",
    "zalopay.vn",
];

/// Cụm từ chung chung — luật học được không được nhận.
pub const GENERIC_PHRASES: &[&str] = &[
    "ngan hang",
    "tai khoan",
    "thanh toan",
    "chuyen tien",
    "dang nhap",
    "mat khau",
    "khach hang",
    "dich vu",
];

/// Từ khóa gốc — luật học được không được trùng.
pub fn root_phrase_set() -> Vec<String> {
    GROUPS.iter().flat_map(|g| g.phrases.iter().map(|p| p.to_string())).collect()
}

/// App nhạy cảm: không bao giờ đọc (so khớp không phân biệt hoa thường, chứa).
pub const SENSITIVE_APPS: &[&str] = &[
    "vietcombank",
    "vietinbank",
    "bidv",
    "agribank",
    "techcombank",
    "mbbank",
    "acb",
    "vpbank",
    "sacombank",
    "momo",
    "zalopay",
    "vneid",
    "1password",
    "bitwarden",
    "lastpass",
    "keepass",
    "dashlane",
    "authenticator",
    "authy",
    "google authenticator",
];

/// App điều khiển từ xa đã biết.
pub const REMOTE_APPS: &[&str] =
    &["anydesk", "teamviewer", "ultraviewer", "remotepc", "splashtop", "rustdesk", "airmirror"];

/// App ngân hàng/ví/định danh: nguồn duy nhất cho cờ bank_app_open
/// (trước đây mỗi nền tảng giữ một bản sao).
pub const BANK_APPS: &[&str] = &[
    "vietcombank",
    "vietinbank",
    "bidv",
    "agribank",
    "techcombank",
    "mbbank",
    "acb",
    "vpbank",
    "sacombank",
    "momo",
    "zalopay",
    "vneid",
];

impl KeywordGroup {
    /// Lý do theo ngôn ngữ giao diện.
    pub fn reason_lang(&self, lang: crate::AiLang) -> &'static str {
        match lang {
            crate::AiLang::Vi => self.reason,
            crate::AiLang::En => self.reason_en,
        }
    }
}

/// true nếu app thuộc danh sách nhạy cảm.
pub fn is_sensitive_app(app_id: &str) -> bool {
    let a = app_id.to_lowercase();
    SENSITIVE_APPS.iter().any(|s| a.contains(s))
}

/// true nếu app là app điều khiển từ xa đã biết.
pub fn is_remote_app(app_id: &str) -> bool {
    let a = app_id.to_lowercase();
    REMOTE_APPS.iter().any(|s| a.contains(s))
}

/// true nếu app là ngân hàng/ví/định danh đã biết.
pub fn is_bank_app(app_id: &str) -> bool {
    let a = app_id.to_lowercase();
    BANK_APPS.iter().any(|s| a.contains(s))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sensitive_match_case_insensitive() {
        assert!(is_sensitive_app("com.VIETCOMBANK.mobile"));
        assert!(is_sensitive_app("Bitwarden"));
        assert!(!is_sensitive_app("com.zalo.app"));
    }

    #[test]
    fn remote_apps_detected() {
        assert!(is_remote_app("com.anydesk.anydeskandroid"));
        assert!(!is_remote_app("com.zalo.app"));
    }

    #[test]
    fn bank_apps_detected() {
        assert!(is_bank_app("com.vietcombank.mobile"));
        assert!(is_bank_app("vn.momo.platform"));
        assert!(!is_bank_app("com.zalo.app"));
    }
}
