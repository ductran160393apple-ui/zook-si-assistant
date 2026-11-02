# SiAssistant — Screen-reading AI assistant & scam shield

**Topic:** "A Context-Aware Personal AI Assistant on Smart Devices:
Protecting Users and Supporting Everyday Life"

Cross-platform by design: one shared Rust core serves every screen the
user touches. The macOS app is fully supported today; Android is in
progress. The app reads on-screen content, warns about scams on-device
(0 tokens), and calls AI to summarize / translate / solve when needed.
Vietnamese UI.

3-minute demo video: `SiAssistant-demo-3min.mp4` (with `.srt` subtitles).

> 🌐 **Language:** English (below) · 🇻🇳 Tiếng Việt (nhấn để mở bên dưới)

<details>
<summary>🇻🇳 <b>Bản tiếng Việt</b> (click to expand)</summary>

**Đề tài:** "A Context-Aware Personal AI Assistant on Smart Devices:
Protecting Users and Supporting Everyday Life"

Đa nền tảng ngay từ thiết kế: một lõi Rust dùng chung phục vụ mọi màn
hình của người dùng. Hiện tại app macOS được hỗ trợ đầy đủ; Android đang
phát triển. Ứng dụng đọc nội dung trên màn hình, cảnh báo lừa đảo ngay
trên máy (0 token), nhờ AI tóm tắt / dịch / giải đề khi cần.
Giao diện tiếng Việt.

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
Hồ sơ dự thi: [docs/SUBMISSION.md](docs/SUBMISSION.md) (mô tả project
+ dùng sản phẩm Meta, tiếng Anh và tiếng Việt).

## Cấu trúc

- [core/](core/) — lõi Rust qua UniFFI 0.28: `scoring` (chấm điểm),
  `rules` (từ khóa, thương hiệu, danh sách app), `entities` (trích
  URL/SĐT/STK/email), `normalize` (chuẩn hóa tiếng Việt, Jaccard),
  `pii` (che PII), `learned` (kiểm duyệt luật học), `store` (kho case
  JSON-stateless), `backends` (prompt, Messages API, lệnh CLI).
- [macos/](macos/) — app menu-bar (SwiftPM, macOS 14+): phím tắt Carbon
  (⌘⇧7/8/9/0, dự phòng ⌃⌥S/T/G/K), panel nổi không cướp focus, cửa sổ
  debug 3 tab, `--selftest`. Binding Swift sinh vào `macos/Generated/`.
- [android/](android/) — app sideload (API 26+, Compose), đang phát
  triển, chưa test trên thiết bị: debounce 600ms, overlay cảnh báo đỏ,
  nút nổi AI. Binding Kotlin ở `app/src/main/java/aiassist/uniffi/`.
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
- Android (đang phát triển): chỉ cần Docker daemon (build trong
  container); bản phát hành được hỗ trợ hiện tại là app macOS.
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
# Android (cần Docker daemon; thử nghiệm, chưa test thiết bị)
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

</details>

## Features

- **Realtime offline scam protection:** scans screen text every second,
  scores 0–100 from keyword groups + entities (links/phones/bank
  accounts) + dangerous combos; ≥70 → red alert, 35–69 → suspicious.
- **Built-in RAG:** confirmed past cases vote on new text — paraphrased
  scam messages are still caught with no new keyword match.
- **Auto-learn loop:** collects pending cases, an agent proposes weighted
  rules, the core moderates each proposal; snapshots + undo supported.
- **One-hotkey AI tasks:** summarize, translate, solve, analyze — always
  bundled with a scam check (FR-13); PII double-redacted before leaving
  the device.
- **5 AI backends** (menu-selectable, remembered) — see below.

## Architecture

Principle: **only Swift/Kotlin call into the Rust core; the core is the
sole owner** of scoring, PII redaction, rule moderation, prompt building
and AI HTTP calls. Platforms do I/O only (capture, OCR, hotkeys,
overlays, file storage).

```text
macOS (Swift)                    Android (Kotlin)
ScreenCaptureKit + Vision        AccessibilityService + NotificationListener
Carbon hotkeys, menu-bar         ML Kit OCR (fallback), red overlay
Floating NSPanel                 AI floating button
        │ UniFFI                        │ UniFFI
        └──────────────┬────────────────┘
                       ▼
        ┌──────────────────────────────┐
        │ Rust core (aiassist-core)    │
        │ scoring · PII · learned rules│
        │ AI backends · case store     │
        └──────────────────────────────┘
```

Details: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (module ownership,
17-function FFI contract, data flows, privacy boundaries),
[docs/SCORING_SPEC.md](docs/SCORING_SPEC.md) (keyword groups, combos,
thresholds), [docs/HACKATHON_DEMO.md](docs/HACKATHON_DEMO.md) (5-minute
demo script + fixtures; the first two docs are in Vietnamese).
Submission Q&A: [docs/SUBMISSION.md](docs/SUBMISSION.md) (project
description + Meta products usage, English and Vietnamese).

## Layout

- [core/](core/) — shared Rust core via UniFFI 0.28: `scoring`,
  `rules` (keywords, brands, app lists), `entities` (URL/phone/account/
  email extraction), `normalize` (Vietnamese normalization, Jaccard),
  `pii` (redaction), `learned` (learned-rule moderation), `store`
  (JSON-stateless case store), `backends` (prompts, Messages API, CLI
  commands).
- [macos/](macos/) — menu-bar app (SwiftPM, macOS 14+): Carbon hotkeys
  (⌘⇧7/8/9/0, fallback ⌃⌥S/T/G/K), focus-stealing-free floating panel,
  3-tab debug window, `--selftest`. Swift bindings generated into
  `macos/Generated/`.
- [android/](android/) — sideload app (API 26+, Compose), in progress
  and not yet device-tested: 600ms debounce, red alert overlay, AI
  floating button. Kotlin bindings in `app/src/main/java/aiassist/uniffi/`.
- [diagrams/](diagrams/) — architecture, task-flow and auto-learn diagrams
  (`.mmd` + `.png`/`.svg`).
- `Dockerfile` — build core + Android in Docker (SDK 35,
  NDK 27.0.12077973, Gradle 8.10). The `buildRust` task runs cargo-ndk
  for 3 ABIs.
- `scripts/regen-bindings.sh` — regenerate Swift/Kotlin bindings after
  any FFI change.

## AI backends

1. **Muse/Meta via API key** — default: `POST {base}/messages`, key in
   Keychain/Keystore (RAM-only at call time), configurable base URL +
   model. Keys from dev.meta.ai (Model API section), default model
   `muse-spark-1.3`.
2. **Claude Code CLI** — isolated (`--allowedTools ""`, `--safe-mode`,
   `--strict-mcp-config`, `--no-session-persistence`, temp dir).
3. **Gemini CLI** (`gemini -p`, JSON; log in via the CLI first).
4. **Antigravity** (`agy -p`, JSON; shares the app login, no separate
   key). Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash`
5. **Anthropic API** via key (macOS menu).

Reasoning levels: low (summarize/translate), medium (analyze), high
(solve). Token prices (USD/MTok) are passed per call by the platform.

## Requirements

- macOS 14+, Xcode/Swift toolchain, stable Rust.
- Android (in progress): only a Docker daemon (builds inside the
  container); the macOS app is the supported release today.
- macOS permissions: Screen Recording + Accessibility — the OS doesn't
  let apps trigger the prompt themselves; add the app via the `+` button
  in Settings. Ad-hoc signature → re-grant after every build; releases
  need a fixed certificate.

## Build & run

```bash
# Regenerate bindings after any core FFI change:
/scripts/regen-bindings.sh

# macOS
cd macos && swift build -Xlinker -L$PWD/../target/debug
export DYLD_LIBRARY_PATH=$PWD/../target/debug AIASSIST_DATA_DIR=/tmp/st-data
.build/debug/AiAssistant --selftest   # checks over the real FFI
```

Diagnostics: `--probe-capture` (screen permission + OCR chars),
`--probe-ai <backend> <task> <model|-> <text>` (headless real AI),
`--probe-monitor <seconds>` (live monitor ticks),
log at `~/Library/Logs/SiAssitant/debug.log`.
User data lives in `~/Library/Application Support/AiAssistant/`
(override with `AIASSIST_DATA_DIR` for selftests).

```bash
# Android (needs Docker daemon; experimental, not device-tested)
docker build -t aiassist-builder .
docker run --rm -v "$PWD:/work" -v aiassist-cargo:/root/.cargo \
  -v aiassist-gradle:/root/.gradle \
  -e ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.0.12077973 aiassist-builder \
  bash -c 'cd /work/android && gradle assembleDebug'
# → android/app/build/outputs/apk/debug/app-debug.apk (bundled .so, 3 ABIs)
```

## Testing

```bash
# Sandbox blocks ~/.cargo and sockets: point CARGO_HOME somewhere writable
export CARGO_HOME=/tmp/cargo-home
cargo test -p aiassist-core --lib   # claude/gemini/agy commands, PII, scoring, bilingual, RAG...
cargo clippy --all-targets -- -D warnings   # must be clean (acceptance gate)

cd macos && swift test -Xlinker -L$PWD/../target/debug  # CLI parsers, verdicts, RAG FFI...
.build/debug/AiAssistant --selftest                     # 85/75/45/15 samples + PII + case store + learned rules
.build/debug/AiAssistant --selftest-learn-local /tmp/learn-sample.json  # mocked learning loop
```

## Privacy

1. Sensitive apps: blocked early at the platform (no read/capture) + the
   core scores 0.
2. Two-layer PII redaction: the platform redacts before AI calls, the
   core re-redacts inside `messages_call`/`store_add_case`.
3. Screenshots stay in RAM, never touch disk.
4. Keys live only in Keychain/Keystore + RAM; no logging of keys or raw
   prompts.
5. Cases are banned from agent search queries (learning-loop prompt).
