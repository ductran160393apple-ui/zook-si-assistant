# Trợ lý AI đọc màn hình và chống lừa đảo

Ứng dụng macOS + Android: đọc nội dung trên màn hình, cảnh báo lừa đảo
ngay trên máy (0 token), nhờ AI tóm tắt/dịch/giải đề khi cần. Giao diện tiếng Việt.

## Tài liệu

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — kiến trúc: lõi sở hữu logic,
  nền tảng làm I/O, hợp đồng FFI, ranh giới riêng tư.
- [docs/SCORING_SPEC.md](docs/SCORING_SPEC.md) — đặc tả chấm điểm (§5.1):
  nhóm từ khóa, tổ hợp, ngưỡng, ví dụ chuẩn.

## Cấu trúc

- [core/](core/) — lõi Rust dùng chung qua UniFFI 0.28: chuẩn hóa tiếng Việt,
  luật từ khóa, trích link/SĐT/STK, chấm điểm tổ hợp, che PII, kiểm duyệt
  luật học được, kho case, client Messages API + lệnh Claude cô lập.
- [macos/](macos/) — app menu-bar (SwiftPM, macOS 14+): phím tắt Carbon
  (⌘⇧7/8/9/0, dự phòng ⌃⌥S/T/G/K), ScreenCaptureKit + Vision OCR, panel nổi
  NSPanel không cướp focus, cửa sổ debug 3 tab, `--selftest`.
  Binding Swift sinh từ bản build chưa strip vào `macos/Generated/`.
- [android/](android/) — app sideload (API 26+, Compose): AccessibilityService
  (debounce 600ms), NotificationListener, overlay cảnh báo đỏ, nút nổi AI,
  MediaProjection + ML Kit OCR dự phòng. Binding Kotlin ở
  `app/src/main/java/aiassist/uniffi/`.
- `Dockerfile` — build lõi + Android trong Docker (SDK 35, NDK 27.0.12077973,
  Gradle 8.10). Task `buildRust` tự chạy cargo-ndk 3 ABI.
- `scripts/regen-bindings.sh` — sinh lại binding Swift/Kotlin sau khi đổi FFI.

Nguyên tắc: chỉ Swift/Kotlin gọi vào lõi Rust; lõi là nơi duy nhất chấm điểm,
che PII, kiểm duyệt luật, dựng prompt và gọi HTTP AI.

## Backend AI (chọn trong menu, có ghi nhớ)

1. Claude Code CLI — mặc định, chạy cô lập (`--allowedTools ""`, `--no-mcp`,
   `--no-session-persistence`, `--no-user-settings`, thư mục tạm).
2. Muse/Meta qua API key — mới: `POST {base}/messages`, Bearer key
   (Keychain/Keystore, chỉ RAM), base URL + model cấu hình được.
3. Anthropic API qua key (menu macOS); 4. Gemini Argon (stub, ẩn khỏi UI).

Mức suy luận: thấp (tóm tắt/dịch), trung bình (phân tích), cao (giải đề).

## Kiểm thử

```bash
# Sandbox chặn ~/.cargo và socket: trỏ CARGO_HOME sang chỗ ghi được,
# test mock-API chạy gỡ sandbox một lần.
export CARGO_HOME=/tmp/cargo-home
cargo test      # 38 unit + 2 test server giả (Bearer/model/không rò SĐT)
cargo clippy --all-targets -- -D warnings   # phải sạch (tiêu chí nghiệm thu)

# Đổi FFI lõi → sinh lại binding trước khi build app:
./scripts/regen-bindings.sh

# macOS: build rồi selftest qua FFI thật (4 ví dụ 85/75/45/15 + PII +
# phân loại app + prompt/timeout + kho case + luật học + lệnh claude;
# vòng học local: tăng điểm, loại cụm trùng gốc, hoàn tác).
cd macos && swift build -Xlinker -L$PWD/../target/debug
export DYLD_LIBRARY_PATH=$PWD/../target/debug AIASSIST_DATA_DIR=/tmp/st-data
.build/debug/AiAssistant --selftest
.build/debug/AiAssistant --selftest-learn-local /tmp/learn-sample.json

# Android (cần Docker daemon):
docker build -t aiassist-builder .
docker run --rm -v "$PWD:/work" -v aiassist-cargo:/root/.cargo \
  -v aiassist-gradle:/root/.gradle \
  -e ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.0.12077973 aiassist-builder \
  bash -c 'cd /work/android && gradle assembleDebug'
# → android/app/build/outputs/apk/debug/app-debug.apk (đã gồm .so 3 ABI)
```

## Lưu ý macOS

Hệ thống không cho app tự bật hộp xin quyền Ghi màn hình: thêm app bằng nút
`+` trong Cài đặt. Chữ ký ad-hoc → cấp lại quyền mỗi lần build; bản phát hành
cần chứng chỉ cố định. Dữ liệu user ở `~/Library/Application Support/AiAssistant/`
(ghi đè bằng `AIASSIST_DATA_DIR` cho selftest).
