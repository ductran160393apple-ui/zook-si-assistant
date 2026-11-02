# SiAssistant — Trợ lý AI đọc màn hình & chống lừa đảo

Ứng dụng macOS + Android: đọc nội dung trên màn hình, cảnh báo lừa đảo
ngay trên máy (0 token), nhờ AI tóm tắt / dịch / giải đề khi cần.
Giao diện tiếng Việt, một lõi Rust dùng chung cho cả hai nền tảng.

Video demo 3 phút: `SiAssistant-demo-3min.mp4` (kèm phụ đề `.srt`).

## Tính năng

- **Chống lừa đảo realtime, offline:** quét chữ trên màn hình mỗi giây,
  chấm điểm 0–100 từ nhóm từ khóa + thực thể (link/SĐT/STK) + tổ hợp
  nguy hiểm; ≥70 → cảnh báo đỏ, 35–69 → đáng ngờ.
- **RAG nội bộ:** các case đã xác nhận bỏ phiếu cho text mới —
  tin lừa đảo viết lại (paraphrase) vẫn bị bắt dù không khớp từ khóa mới.
- **Vòng học tự động:** gom case chờ duyệt, agent đề xuất luật có trọng số,
  lõi kiểm duyệt từng đề xuất, hỗ trợ snapshot + hoàn tác.
- **Tác vụ AI một phím:** tóm tắt, dịch, giải đề, phân tích — luôn kèm
  kiểm tra lừa đảo (FR-13), PII che 2 lớp trước khi rời máy.
- **5 backend AI** (chọn trong menu, có ghi nhớ) — xem bên dưới.

## Kiến trúc

Nguyên tắc: **chỉ Swift/Kotlin gọi vào lõi Rust; lõi là nơi duy nhất**
chấm điểm, che PII, kiểm duyệt luật, dựng prompt và gọi HTTP AI.
Nền tảng chỉ làm I/O (chụp màn hình, OCR, hotkey, overlay, lưu file).

```text
macOS (Swift)                    Android (Kotlin)
ScreenCaptureKit + Vision        AccessibilityService + NotificationListener
Carbon hotkeys, menu-bar         ML Kit OCR (dự phòng), overlay đỏ
NSPanel nổi                      nút nổi AI
        │ UniFFI                        │ UniFFI
        └──────────────┬────────────────┘
                       ▼
        ┌──────────────────────────────┐
        │ Lõi Rust (aiassist-core)     │
        │ chấm điểm · PII · luật học   │
        │ AI backend · kho case        │
        └──────────────────────────────┘
```

Chi tiết: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (sở hữu module,
hợp đồng FFI 17 hàm, luồng dữ liệu, ranh giới riêng tư),
[docs/SCORING_SPEC.md](docs/SCORING_SPEC.md) (nhóm từ khóa, tổ hợp,
ngưỡng, ví dụ chuẩn), [docs/HACKATHON_DEMO.md](docs/HACKATHON_DEMO.md)
(kịch bản demo 5 phút + fixtures).

## Cấu trúc

- [core/](core/) — lõi Rust qua UniFFI 0.28: `scoring` (chấm điểm),
  `rules` (từ khóa, thương hiệu, danh sách app), `entities` (trích
  URL/SĐT/STK/email), `normalize` (chuẩn hóa tiếng Việt, Jaccard),
  `pii` (che PII), `learned` (kiểm duyệt luật học), `store` (kho case
  JSON-stateless), `backends` (prompt, Messages API, lệnh CLI).
- [macos/](macos/) — app menu-bar (SwiftPM, macOS 14+): phím tắt Carbon
  (⌘⇧7/8/9/0, dự phòng ⌃⌥S/T/G/K), panel nổi không cướp focus, cửa sổ
  debug 3 tab, `--selftest`. Binding Swift sinh vào `macos/Generated/`.
- [android/](android/) — app sideload (API 26+, Compose): debounce 600ms,
  overlay cảnh báo đỏ, nút nổi AI. Binding Kotlin ở
  `app/src/main/java/aiassist/uniffi/`.
- [diagrams/](diagrams/) — sơ đồ kiến trúc, luồng task, auto-learn
  (`.mmd` + `.png`/`.svg`).
- `Dockerfile` — build lõi + Android trong Docker (SDK 35,
  NDK 27.0.12077973, Gradle 8.10). Task `buildRust` tự chạy cargo-ndk 3 ABI.
- `scripts/regen-bindings.sh` — sinh lại binding Swift/Kotlin sau khi đổi FFI.

## Backend AI

1. **Muse/Meta qua API key** — mặc định: `POST {base}/messages`,
   key lưu Keychain/Keystore (chỉ vào RAM khi gọi), base URL + model
   cấu hình được. Key tạo ở dev.meta.ai (mục Model API),
   model mặc định `muse-spark-1.3`.
2. **Claude Code CLI** — chạy cô lập (`--allowedTools ""`, `--safe-mode`,
   `--strict-mcp-config`, `--no-session-persistence`, thư mục tạm).
3. **Gemini CLI** (`gemini -p`, JSON; đăng nhập Google trong CLI trước).
4. **Antigravity** (`agy -p`, JSON; dùng chung phiên đăng nhập app,
   không cần key riêng). Cài: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
5. **Anthropic API** qua key (menu macOS).

Mức suy luận: thấp (tóm tắt/dịch), trung bình (phân tích), cao (giải đề).
Giá token (USD/MTok) do nền tảng truyền vào mỗi cuộc gọi.

## Yêu cầu

- macOS 14+, Xcode/Swift toolchain, Rust stable.
- Android: chỉ cần Docker daemon (build trong container).
- Quyền macOS: Ghi màn hình (Screen Recording) + Accessibility —
  hệ thống không cho app tự bật hộp xin quyền, thêm app bằng nút `+`
  trong Cài đặt. Chữ ký ad-hoc → cấp lại quyền mỗi lần build;
  bản phát hành cần chứng chỉ cố định.

## Build & chạy

```bash
# Đổi FFI lõi → sinh lại binding trước khi build app:
/scripts/regen-bindings.sh

# macOS
cd macos && swift build -Xlinker -L$PWD/../target/debug
export DYLD_LIBRARY_PATH=$PWD/../target/debug AIASSIST_DATA_DIR=/tmp/st-data
.build/debug/AiAssistant --selftest   # kiểm tra FFI thật
```

Chẩn đoán: `--probe-capture` (quyền màn hình + ký tự OCR),
`--probe-ai <backend> <task> <model|-> <text>` (AI thật headless),
`--probe-monitor <giây>` (nhịp monitor live),
log: `~/Library/Logs/SiAssitant/debug.log`.
Dữ liệu user ở `~/Library/Application Support/AiAssistant/`
(ghi đè bằng `AIASSIST_DATA_DIR` cho selftest).

```bash
# Android (cần Docker daemon)
docker build -t aiassist-builder .
docker run --rm -v "$PWD:/work" -v aiassist-cargo:/root/.cargo \
  -v aiassist-gradle:/root/.gradle \
  -e ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.0.12077973 aiassist-builder \
  bash -c 'cd /work/android && gradle assembleDebug'
# → android/app/build/outputs/apk/debug/app-debug.apk (đã gồm .so 3 ABI)
```

## Kiểm thử

```bash
# Sandbox chặn ~/.cargo và socket: trỏ CARGO_HOME sang chỗ ghi được
export CARGO_HOME=/tmp/cargo-home
cargo test -p aiassist-core --lib   # unit: lệnh claude/gemini/agy, PII, scoring, song ngữ, RAG...
cargo clippy --all-targets -- -D warnings   # phải sạch (tiêu chí nghiệm thu)

cd macos && swift test -Xlinker -L$PWD/../target/debug  # parser CLI, model, verdict, RAG FFI...
.build/debug/AiAssistant --selftest                     # 4 ví dụ 85/75/45/15 + PII + kho case + luật học
.build/debug/AiAssistant --selftest-learn-local /tmp/learn-sample.json  # vòng học giả
```

## Riêng tư

1. App nhạy cảm: chặn sớm ở nền tảng (không đọc/chụp) + lõi trả 0 điểm.
2. PII che 2 lớp: nền tảng che trước khi gọi AI, lõi che lại trong
   `messages_call`/`store_add_case`.
3. Ảnh chụp màn hình chỉ ở RAM, không ghi đĩa.
4. Key chỉ ở Keychain/Keystore + RAM; không log key/prompt thô.
5. Case trong query tìm kiếm của agent bị cấm (prompt vòng học).
