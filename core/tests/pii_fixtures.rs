//! Chuẩn đo trích PII tiếng Việt trên fixture project.
//!
//! - Bảng LABELED: regex hiện tại PHẢI che (baseline, phải xanh).
//! - Bảng UNLABELED_GAP: regex hiện tại còn lọt (ghim hành vi để so khi
//!   thêm pre-filter Apple Foundation Models / Ollama — mục tiêu lật các
//!   case này thành che mà không vỡ bảng LABELED).

use aiassist_core::pii::redact;

struct Case {
    name: &'static str,
    input: &'static str,
    /// Các bí mật không được lọt ra output.
    secrets: &'static [&'static str],
    /// Các mốc phải xuất hiện trong output.
    markers: &'static [&'static str],
}

const LABELED: &[Case] = &[
    Case {
        name: "sdt",
        input: "Gọi tôi theo số 0912345678 nhé",
        secrets: &["0912345678"],
        markers: &["[SĐT]"],
    },
    Case {
        name: "stk_co_nhan",
        input: "Chuyển vào STK: 123 456 7890 giúp mình",
        secrets: &["123 456 7890"],
        markers: &["[STK]"],
    },
    Case {
        name: "cccd_day_so_dai",
        input: "cccd 001234567890 của tôi đây",
        secrets: &["001234567890"],
        markers: &["[SỐ]"],
    },
    Case {
        name: "email",
        input: "mail cho tôi a.b-c9@x.vn nhé",
        secrets: &["a.b-c9@x.vn"],
        markers: &["[EMAIL]"],
    },
    Case {
        name: "ten_co_nhan",
        input: "Tên: Nguyễn Văn An, gọi lại giúp",
        secrets: &["Nguyễn Văn An"],
        markers: &["[TÊN]"],
    },
    Case {
        name: "dia_chi_co_nhan",
        input: "Địa chỉ: 12 Nguyễn Huệ, Quận 1",
        secrets: &["12 Nguyễn Huệ"],
        markers: &["[ĐỊA CHỈ]"],
    },
    Case {
        name: "ten_co_dau_day_du",
        input: "Chị: Trần Thị Bích, em gửi nhé",
        secrets: &["Trần Thị Bích"],
        markers: &["[TÊN]"],
    },
    Case {
        name: "noi_o_co_dau",
        input: "Nơi ở: 45 Lê Lợi, Hà Nội",
        secrets: &["45 Lê Lợi"],
        markers: &["[ĐỊA CHỈ]"],
    },
    Case {
        name: "query_url_bi_xoa",
        input: "xem hàng tại https://shop.vn/p?token=abc123&uid=9#anh",
        secrets: &["token=abc123"],
        markers: &["https://shop.vn/p"],
    },
    Case {
        name: "tin_nhan_scam_tron",
        input: "Tôi là công an gọi 0912345678 chuyển tiền gấp vào STK 9988776655",
        secrets: &["0912345678", "9988776655"],
        markers: &["[SĐT]", "[STK]"],
    },
    Case {
        name: "stk_khong_nhan_duoc_day_so_dai_do",
        input: "chuyển vào 9988776655 giúp anh",
        secrets: &["9988776655"],
        markers: &["[SỐ]"],
    },
];

/// Khoảng trống đã biết: không nhãn → regex hiện tại lọt. Mục tiêu FM.
const UNLABELED_GAP: &[(&str, &str, &str)] = &[
    ("ten_khong_nhan", "Nguyễn Văn An vừa chuyển tiền xong", "Nguyễn Văn An"),
    ("dia_chi_khong_nhan", "Nhà tôi ở 12 Nguyễn Huệ, Quận 1 nhé", "12 Nguyễn Huệ"),
    ("sdt_cach_quang", "gọi số 0912 345 678 giúp tôi", "0912 345 678"),
    ("otp_6_so", "Mã OTP của bạn là 123456", "123456"),
];

#[test]
fn baseline_labeled_duoc_che() {
    for c in LABELED {
        let out = redact(c.input);
        for s in c.secrets {
            assert!(!out.contains(s), "[{}] lọt bí mật {s:?}: {out:?}", c.name);
        }
        for m in c.markers {
            assert!(out.contains(m), "[{}] thiếu mốc {m:?}: {out:?}", c.name);
        }
    }
    eprintln!("baseline: {}/{} case có nhãn được che", LABELED.len(), LABELED.len());
}

#[test]
fn gap_khong_nhan_hien_van_lot() {
    // Ghim hành vi hiện tại (đỏ = regex đã tự che được → cập nhật bảng).
    for (name, input, secret) in UNLABELED_GAP {
        let out = redact(input);
        assert!(
            out.contains(secret),
            "[{name}] regex đã che được?! chuyển case này sang LABELED: {out:?}"
        );
    }
    eprintln!("khoảng trống FM: {} case chưa che", UNLABELED_GAP.len());
}
