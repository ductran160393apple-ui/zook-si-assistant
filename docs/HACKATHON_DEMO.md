# SiAssistant — Hackathon Demo Script

**Topic:** A Context-Aware Personal AI Assistant on Smart Devices:
Protecting Users and Supporting Everyday Life
**Format:** live demo, ~5 minutes + Q&A. Present in English; app UI can
toggle Vietnamese/English live.

## 0. Pre-demo checklist (do 15 min before)

- [ ] Grant Screen Recording + Accessibility; quit duplicate menu icons
  (footer shows build `CFBundleVersion` — confirm the new one).
- [ ] Backend = Meta API, model `muse-spark-1.3`, key in Keychain.
  Backup backend: Antigravity (`agy`, no key needed) in case of quota.
- [ ] Run `.build/debug/AiAssistant --selftest` → expect `SELFTEST: ĐẠT`.
- [ ] If agy quota is exhausted, run `--probe-ai` once to capture a fresh
  log as backup evidence; keep a 60s screen recording as plan B.
- [ ] Prepare 3 windows: a long article, a chat with a scam message
  (fixtures below), a math/document question.

## 1. Hook (0:00–0:30) — say

> "Every day, people lose money to one convincing message — a fake bank
> officer, a prize link, an OTP request. Meanwhile AI assistants sit in a
> separate tab, blind to what's on your screen. SiAssistant fixes both:
> it sees your current screen with your permission, helps with everyday
> tasks, and guards you against scams in realtime — on macOS and Android
> from one shared Rust core."

Show: menu-bar icon + hotkeys overlay.

## 2. Everyday life (0:30–2:00) — show

| Time | Do | Say |
|------|----|-----|
| 0:30 | Hotkey on long article → **Summarize** panel | "3–6 bullets plus a Watch-out section — deadlines, amounts, actions." |
| 1:00 | Hotkey on English paragraph → **Translate** | "One keypress, keeps names, numbers, links." |
| 1:30 | Hotkey on math question → **Solve** | "Step-by-step with an Answer line; flags uncertain OCR." |

Point out: translucent panels (content behind stays visible), opaque
header, per-panel text color, everything timestamped, follow-up via
**Analyze**.

## 3. Protection (2:00–4:00) — the core act

1. **Realtime trip (2:00).** Switch to the chat window containing the
   scam fixture. Within ~1s the auto-monitor scans (1s tick + instant
   app-switch trigger): icon turns red, panel pops with score + reasons.
   > "No click needed. Rules catch impersonation + pressure + strange
   > link in milliseconds, fully offline."
2. **AI cross-check (2:40).** Panel shows the pending line
   ("re-checking via agent, costs tokens"), then the Muse verdict
   block: Summary → fixed Verdict (`DANGEROUS`) → Reasons → **Action**
   ("do not transfer, block the number, report to the bank").
   > "One low-token prompt, four fixed sections — the model gives a
   > directive, not an essay."
3. **Memory (3:20).** Press "Confirm scam" on fixture A, then on a
   second wording (fixture A2). Rescan a paraphrased variant (fixture
   B): score jumps +15 with reason "2 similar past cases were labeled
   scams" — even though B matches no new keyword.
   > "That's the RAG layer — past verdicts vote on new text, so
   > reworded scams still get caught."

Fixtures (both VI + EN ready):

- A: `Tôi là cán bộ công an, yêu cầu chuyển tiền gấp vào tài khoản an
  toàn. Không được tiết lộ. Xác thực tại vietcombank-xacthuc.top`
- A2: `Tôi là cán bộ công an yêu cầu chuyển tiền gấp vào tài khoản an
  toàn, không được tiết lộ cho ai biết`
- B (paraphrase): `Anh là công an đây, chuyển gấp vào tài khoản an toàn
  giúp anh nhé, giữ bí mật, link xác thực bit.ly/abc123`

## 4. Learning flywheel (4:00–4:30) — show

- Open Debug → Rules tab: learned rules with weights, snapshots, undo.
- Menu → Auto-learn: Off / Every 6h / Every 24h.
  > "Cases pile up with one click; the agent distills them into weighted
  > rules on a schedule, every proposal validated by the core. Nothing
  > the model invents can break scoring."

## 5. Close (4:30–5:00) — say

> "One Rust core, two platforms. Local-first for speed and privacy —
> PII is redacted before anything leaves the device — with Muse Spark
> as the reasoning backend. Next: on-device embeddings for the RAG
> layer and scam-call audio cues on Android. Thank you."

Architecture one-liner for the slide: Screen/OCR → PII redact →
rules + RAG + learned → Muse cross-check → panel + icon + log.

## 6. If things go wrong (don't improvise — switch)

- **agy/Meta quota hit:** say so, switch backend live in the popup
  (takes 5s), or play the backup recording.
- **No screen permission on stage machine:** run `--probe-monitor 20`
  + `--probe-ai` in terminal — same code path, timestamped output.
- **Panel hidden behind windows:** Debug → bring-to-front; build
  number in the footer proves the right binary.

## 7. Likely judge questions (30s answers)

- **Privacy?** PII redaction runs before any AI call; keys live only in
  Keychain/Keystore + RAM; rules/RAG/learned store are local JSON.
- **Token cost?** Offline layers decide first; AI fires only on
  dangerous hits (deduped 2 min) with a capped Low-effort prompt.
- **Why 5 backends?** Resilience + user choice; Meta/Muse Spark is the
  default, CLI backends reuse existing logins (no extra keys).
- **Why Rust core?** One scoring truth via UniFFI for macOS + Android;
  53 Rust + 49 Swift tests, selftest in the shipped bundle.
- **What fails today?** RAG is keyword-Jaccard (embeddings next);
  Android build is code-reviewed, device-tested next.
