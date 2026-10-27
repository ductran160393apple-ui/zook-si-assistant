# Đặc tả chấm điểm (§5.1) và yêu cầu liên quan

Nguồn thực thi duy nhất: `core/src/scoring.rs` + `rules.rs` + `entities.rs`
+ `learned.rs`. Mọi số dưới đây phải khớp code (kiểm bởi unit test
`scoring::tests` và `--selftest`).

## 1. Đầu vào và chuẩn hóa

- Đầu vào: text + `ScanContext` (app_id, remote_app_running, in_call,
  bank_app_open, blacklists, learned).
- Chuẩn hóa (`normalize`): chữ thường, bỏ dấu (cả NFD), gộp khoảng trắng.
- Khớp từ khóa: nguyên từ 2 biên (`contains_word`).

## 2. Nhóm từ khóa (mỗi nhóm tối đa 1 lần)

| Mã | Trọng số | Lý do |
|---|---|---|
| `co_quan` | 20 | Giả danh cơ quan chức năng |
| `hoi_thuc` | 20 | Hối thúc chuyển tiền gấp |
| `dieu_khien` | 20 | Yêu cầu cài app điều khiển từ xa |
| `otp` | 15 | Nhắc tới mã OTP/xác thực |
| `trung_thuong` | 15 | Chiêu trúng thưởng/quà tặng |
| `viec_lam` | 15 | Việc làm/đầu tư đáng ngờ |
| `giu_bi_mat` | 15 | Yêu cầu giữ bí mật |
| `dinh_danh` | 10 | Yêu cầu định danh/xác thực |

Cụm từ đầy đủ trong `rules.rs::GROUPS` (dạng không dấu).

## 3. Thực thể và link (+30 / +15 / +70)

- Giả mạo thương hiệu (host chứa token nhưng không phải domain chính
  thức): +30. Thương hiệu: 9 ngân hàng + momo/zalopay/vneid/dichvucong.
- Link đáng ngờ (rút gọn / đuôi rủi ro / IP / punycode): +15.
- Khớp blacklist (domain/SĐT/STK): +70 và tính là tín hiệu riêng.

## 4. Ngữ cảnh app

- App điều khiển từ xa đang chạy (cờ hoặc app trước mặt): +25.
- App nhạy cảm (ngân hàng/ví/mật khẩu/xác thực): **0 điểm, bỏ qua**.

## 5. Tổ hợp (cộng dồn, mỗi tổ hợp là 1 tín hiệu)

| Điều kiện | +Điểm |
|---|---|
| Điều khiển từ xa + app ngân hàng | 50 |
| Điều khiển từ xa + đang gọi | 30 |
| Giả danh cơ quan + hối thúc | 20 |
| OTP + (hối thúc/giả danh/link lạ) | 15 |
| Trúng thưởng + (OTP/link lạ) | 15 |
| Dụ cài app + (giả danh/hối thúc/định danh) | 15 |
| Định danh + link lạ | 15 |
| Giữ bí mật + (giả danh/hối thúc) | 10 |
| Việc làm + (hối thúc/STK) | 10 |
| Đang gọi + (giả danh/hối thúc) | 10 |

## 6. Luật học được

- Mỗi luật khớp cộng trọng số (kẹp 5–20 khi kiểm duyệt).
- Giới hạn: 300 luật, 8 cụm/luật, lý do ≤ 120 ký tự.
- Loại: cụm chung chung, trùng từ khóa gốc, trùng cụm luật khác,
  domain uy tín/bảo vệ/gov/edu, SĐT không phải 10 số đầu 0, đầu số 1800/1900.
- Luật học đơn lẻ không bao giờ vượt 30 nhờ chặn báo nhầm (§8).

## 7. Ngưỡng mức

| Điểm | Mức | Nhãn |
|---|---|---|
| ≥ 70 | dangerous | NGUY HIỂM |
| 35–69 | suspicious | ĐÁNG NGỜ |
| 0–34 | safe | AN TOÀN |

Điểm trần 100.

## 8. Chặn báo nhầm

Một loại tín hiệu duy nhất và không blacklist → điểm tối đa 30.

## 9. Ví dụ chuẩn (test khóa số)

| Text | Điểm | Lý giải |
|---|---|---|
| Công an + chuyển tiền gấp + giữ bí mật | 85 | 20+20+15 nhóm, 20+10 tổ hợp |
| Khóa tài khoản + link vietcombank-xacthuc.top | 75 | 20+10 nhóm, 30 giả mạo, 15 tổ hợp |
| Trúng thưởng + bit.ly | 45 | 15 nhóm, 15 link, 15 tổ hợp |
| OTP thật ("không chia sẻ") | 15 | 15 nhóm, 1 tín hiệu → an toàn |

## 10. Yêu cầu chức năng liên quan

- **FR-13**: mọi tác vụ AI (tóm tắt/dịch/giải đề/phân tích) luôn chạy
  kiểm tra lừa đảo kèm; điểm ≥ 35 hiện dải cảnh báo trên kết quả.
- Học: case ≤ 1500 ký tự, ≤ 1000 case, dedup Jaccard ≥ 0.8 cùng app;
  vòng học ≤ 60 case, ≤ 15 luật, snapshot 20 bản + hoàn tác.
- Che PII trước mọi text rời máy: STK→`[STK]`, SĐT→`[SĐT]`, dãy ≥9
  số→`[SỐ]`, email→`[EMAIL]`, tên→`[TÊN]`, địa chỉ→`[ĐỊA CHỈ]`,
  query URL bị cắt.
