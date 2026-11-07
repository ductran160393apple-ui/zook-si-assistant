# Kiến trúc SiAssitant

Trợ lý AI đọc màn hình và chống lừa đảo (macOS + Android, giao diện tiếng Việt).
Tài liệu này là đề xuất kiến trúc chuẩn sau đợt review 2026-10-27:
**lõi Rust sở hữu toàn bộ logic**, Swift/Kotlin chỉ làm I/O nền tảng.

## 1. Tổng quan

```
┌─────────────────────────┐         ┌─────────────────────────┐
│ macOS (Swift)           │         │ Android (Kotlin)        │
│ ScreenCaptureKit+Vision │         │ AccessibilityService +  │
│ Carbon hotkeys          │         │ NotificationListener +  │
│ menu-bar, NSPanel       │         │ ML Kit OCR (dự phòng)   │
│ Process `claude`        │         │ overlay, nút nổi AI     │
└────────────┬────────────┘         └────────────┬────────────┘
             │ UniFFI                    UniFFI │
             └────────────┬─────────────────────┘
                          ▼
             ┌─────────────────────────┐
             │ Lõi Rust (aiassist-core)│
             │ chấm điểm · PII · luật  │
             │ AI backend · store      │
             │ netmon (verdict mạng)   │
             └─────────────────────────┘
```

## 2. Nguyên tắc sở hữu

| Mối quan tâm | Chủ sở hữu | Ghi chú |
|---|---|---|
| Chấm điểm lừa đảo | Lõi (`scoring`, `rules`, `entities`) | Đặc tả: `docs/SCORING_SPEC.md` |
| Che PII | Lõi (`pii`) | Mọi text rời máy đều qua `redact` |
| Kiểm duyệt + thêm luật học | Lõi (`learned`) | `moderate_rule`, `learn_add_rule` |
| Dedup case, verdict, pending | Lõi (`store`) | Jaccard ≥ 0.8, JSON-stateless qua FFI |
| Prompt, timeout, trần token | Lõi (`backends`) | `system_prompt`, `task_timeout_secs`, `task_max_tokens` |
| HTTP Messages API + retry | Lõi (`backends`) | `messages_call` (blocking) |
| Lệnh CLI một phát (`claude`/`gemini`/`agy`) | Lõi dựng, Swift thực thi | `*_command_args` |
| Danh sách app (nhạy cảm/remote/bank) | Lõi (`rules`) | `is_*_app` — nguồn duy nhất |
| Verdict traffic mạng + prompt LLM hiệu đính | Lõi (`netmon`) | Ngưỡng/spike/baseline; LLM local (Ollama), không cloud |
| Thu thập counter mạng (nettop/TrafficStats/getifaddrs) | Nền tảng | Swift/Kotlin, chỉ byte up/down |
| Thu thập chữ, UI, hotkey, overlay | Nền tảng | Swift/Kotlin |
| Lưu file (cases/rules/versions) | Nền tảng | Lõi chỉ xử lý JSON, không giữ file |
| API key | Keychain (macOS) / EncryptedSharedPreferences (Android) | Chỉ vào RAM khi gọi |
| Thực thi tiến trình | Swift (`Process`) | Lõi không spawn process |

Cấm: copy prompt/danh sách app/regex PII sang nền tảng; mọi bản sao là bug.

## 3. Module lõi (`core/src/`)

| Module | Trách nhiệm |
|---|---|
| `lib.rs` | Khai báo FFI: scan/redact/moderate + phân loại app |
| `scoring.rs` | Chấm điểm 0–100 + tổ hợp + chặn báo nhầm |
| `rules.rs` | Nhóm từ khóa, thương hiệu, app lists, generic/reputable |
| `entities.rs` | Trích URL/SĐT/STK/email + phân loại link; regex dùng chung |
| `normalize.rs` | Chuẩn hóa tiếng Việt + khớp nguyên từ + Jaccard |
| `pii.rs` | Che PII (dùng chung regex entities) |
| `learned.rs` | Kiểm duyệt + thêm luật học |
| `store.rs` | Kho case (JSON-stateless qua FFI) |
| `backends.rs` | AI backend: prompt, Messages API, lệnh CLI |
| `netmon.rs` | Verdict traffic (ngưỡng + spike + EMA baseline) + prompt/gọi LLM hiệu đính |

## 4. Hợp đồng FFI (22 hàm, xem `scripts/regen-bindings.sh`)

Quét/che/kiểm duyệt: `scan_text`, `redact_text`, `moderate_rule`.
Phân loại app: `is_sensitive_app`, `is_remote_app`, `is_bank_app`.
AI: `system_prompt`, `wrap_input`, `estimate_tokens`, `task_timeout_secs`,
`task_max_tokens`, `messages_call` (BLOCKING — gọi ngoài luồng UI),
`claude_command_args`.
Kho: `store_add_case`, `store_pending_cases`, `store_set_verdict`,
`learn_add_rule` (JSON vào/ra, không bao giờ panic qua FFI).
Mạng: `net_evaluate` (snapshot → verdict + baseline mới),
`net_needs_llm` (cổng verdict khả nghi), `net_llm_system_prompt`,
`net_llm_user_prompt`, `net_llm_call` (BLOCKING — gọi ngoài luồng UI,
chỉ trỏ Ollama local).

Định dạng file (nền tảng giữ, lõi đọc/ghi qua JSON):

- `cases.json`: `{"cases": [{"text","app_id","score","verdict","reasons"}]}`
  (đọc khoan dung cả mảng trần `[...]` và khóa cũ `"app"`).
- `learned-rules.json`: `{"rules": [{"id","reason","weight","phrases",
  "domains","phones","enabled"}]}`.

## 5. Luồng dữ liệu

Quét (0 token):

```
chữ màn hình → scan_text ─┬─ app nhạy cảm → 0, bỏ qua
                           ├─ 35–69 → ĐÁNG NGỜ (log + dải cảnh báo)
                           └─ ≥70 → NGUY HIỂM (cảnh báo + overlay đỏ)
```

Tác vụ AI (FR-13: luôn chạy kiểm tra lừa đảo kèm):

```
chữ màn hình → redact (nền tảng) → lõi dựng prompt / gọi API
→ lõi che lại lần 2 → backend → text + token về UI
```

Vòng học (macOS):

```
pending (chưa verdict, ≤60) → agent (nền, timeout 300s, hủy được)
→ learn_add_rule từng đề xuất → snapshot → ghi luật → báo cáo + token
```

Giám sát mạng (2 tầng, tick 60s riêng):

```
counter up/down → net_evaluate ─┬─ safe → chỉ lưu baseline
                                └─ suspicious/dangerous → net_needs_llm
                                   → worker LLM local (debounce + cache 6h
                                     + backoff) → hiệu đính verdict
```

## 6. Ranh giới riêng tư

1. App nhạy cảm: chặn sớm ở nền tảng (không đọc/chụp) + lõi trả 0 điểm.
2. PII che 2 lớp: nền tảng che trước khi gọi AI, lõi che lại trong
   `messages_call`/`store_add_case`.
3. Ảnh chụp màn hình chỉ ở RAM, không ghi đĩa.
4. Key chỉ ở Keychain/Keystore + RAM; không log key/prompt thô.
5. Case trong query tìm kiếm của agent bị cấm (prompt vòng học).
6. Giám sát mạng chỉ đếm byte up/down theo app + tổng máy — không
   host/DNS/payload; số liệu mạng không bao giờ vào prompt AI cloud
   (LLM hiệu đính chỉ chạy local qua Ollama).

## 7. Backend AI theo nền tảng

| Backend | macOS | Android |
|---|---|---|
| Meta Messages API (key, mặc định) | Có | Có (duy nhất) |
| Claude Code CLI | Có | Không |
| Gemini CLI (`gemini -p`, JSON) | Có | Không |
| Antigravity (`agy -p`, JSON, chung login app) | Có | Không |
| Anthropic Messages API (key) | Có | Không |

Giá token (USD/MTok) do nền tảng truyền vào mỗi cuộc gọi (Meta
1.25/4.25 (Muse Spark standard), Anthropic 0.003/0.015).
Chuẩn giao thức: [Messages API](https://dev.meta.ai/docs/protocols/messages)
(Anthropic-compatible), model mặc định muse-spark-1.3 theo cookbook chính thức.

## 8. Binding và build

- Sinh lại sau mỗi lần đổi FFI: `./scripts/regen-bindings.sh`
  (cần `uniffi-bindgen =0.28.3`, script tự cài).
- Swift: bản chuẩn `macos/Generated/`; bản copy cho SwiftPM
  `macos/Sources/AiAssistant/AiAssistCoreFFI.swift` + header
  `macos/CAiAssistCore/` (gitignore, regen tự chép).
- Kotlin: `android/app/src/main/java/aiassist/uniffi/` (commit cùng source).
- Android `.so`: task Gradle `buildRust` sinh trong Docker, không commit.

## 9. Quy ước kiểm thử

- Rust: `cargo test` (unit inline + `core/tests/mock_api.rs`),
  `cargo clippy --all-targets -- -D warnings` phải sạch.
- macOS: `swift build` + `--selftest` (FFI thật) +
  `--selftest-learn-local` (vòng học giả).
- Android: `gradle assembleDebug` trong Docker (xem README).
