//! Test với server giả: đường Meta/Anthropic Messages API phải gửi đúng
//! header Bearer, đúng model, và KHÔNG BAO GIỜ chứa số điện thoại gốc.

use aiassist_core::AiLang;
use aiassist_core::backends::{call_messages_api, AiError, AiResponse, AiTaskKind, MessagesCall};
use std::io::{Read, Write};
use std::net::TcpListener;

struct Seen {
    head: String,
    body: String,
}

fn spawn_mock() -> (String, std::sync::mpsc::Receiver<Seen>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock");
    let addr = listener.local_addr().expect("addr").to_string();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().expect("accept");
        let mut buf = vec![0u8; 65536];
        let n = stream.read(&mut buf).expect("read");
        let raw = String::from_utf8_lossy(&buf[..n]).into_owned();
        let (head, body) = match raw.split_once("\r\n\r\n") {
            Some((h, b)) => (h.to_string(), b.to_string()),
            None => (raw.clone(), String::new()),
        };
        tx.send(Seen { head, body }).expect("send");
        let resp = "{\"content\":[{\"text\":\"ok\"}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5}}";
        let out = format!(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            resp.len(),
            resp
        );
        stream.write_all(out.as_bytes()).expect("write");
    });
    (format!("http://{addr}"), rx)
}

#[test]
fn meta_path_sends_bearer_model_and_redacted_body() {
    let (base, rx) = spawn_mock();
    let res = call_messages_api(&MessagesCall {
        base_url: &base,
        api_key: "test-key-123",
        anthropic_version: None,
        model: "meta-llama-3.1-70b",
        task: AiTaskKind::Solve,
        raw_text: "gọi tôi 0912345678 để xác thực tài khoản",
        price_in_per_mtok: 1.0,
        price_out_per_mtok: 2.0,
        backend_name: "meta",
        lang: AiLang::Vi,
    })
    .expect("gọi mock phải thành công");
    assert_eq!(res.backend, "meta");

    let seen = rx.recv_timeout(std::time::Duration::from_secs(5)).expect("mock nhận request");
    assert!(seen.head.to_lowercase().contains("authorization: bearer test-key-123"), "{}", seen.head);
    assert!(seen.body.contains("meta-llama-3.1-70b"), "{}", seen.body);
    assert!(seen.body.contains("[SĐT]"), "{}", seen.body);
    assert!(!seen.body.contains("0912345678"), "RÒ RỈ SĐT: {}", seen.body);
}

/// Server giả phục vụ một chuỗi response (mỗi kết nối một phần tử) và ghi
/// lại mọi request: dùng cho các test retry, effort và trần max_tokens.
fn spawn_mock_seq(bodies: Vec<&'static str>) -> (String, std::sync::mpsc::Receiver<Seen>) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind mock");
    let addr = listener.local_addr().expect("addr").to_string();
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        for body in bodies {
            let Ok((mut stream, _)) = listener.accept() else { break };
            let mut buf = vec![0u8; 65536];
            let Ok(n) = stream.read(&mut buf) else { break };
            let raw = String::from_utf8_lossy(&buf[..n]).into_owned();
            let (head, req_body) = match raw.split_once("\r\n\r\n") {
                Some((h, b)) => (h.to_string(), b.to_string()),
                None => (raw.clone(), String::new()),
            };
            let _ = tx.send(Seen { head, body: req_body });
            let out = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                body.len(),
                body
            );
            if stream.write_all(out.as_bytes()).is_err() {
                break;
            }
        }
    });
    (format!("http://{addr}"), rx)
}

fn call_mock(base: &str) -> Result<AiResponse, AiError> {
    call_mock_version(base, None)
}

fn call_mock_version(base: &str, version: Option<&str>) -> Result<AiResponse, AiError> {
    call_messages_api(&MessagesCall {
        base_url: base,
        api_key: "test-key",
        anthropic_version: version,
        model: "mock-model",
        task: AiTaskKind::Summarize,
        raw_text: "text kiểm tra",
        price_in_per_mtok: 1.0,
        price_out_per_mtok: 2.0,
        backend_name: "meta",
        lang: AiLang::Vi,
    })
}

fn recv_seen(rx: &std::sync::mpsc::Receiver<Seen>) -> Seen {
    rx.recv_timeout(std::time::Duration::from_secs(5)).expect("mock nhận request")
}

/// Hồi quy: HTTP 200 với `content: []` không được thành `Ok("")` (UI sẽ
/// báo chung chung "no text") mà phải là Err retryable kèm stop_reason.
#[test]
fn empty_content_array_is_detailed_retryable_error() {
    let empty = r#"{"content":[],"stop_reason":"max_tokens"}"#;
    let (base, _) = spawn_mock_seq(vec![empty, empty, empty]);
    let err = call_mock(&base).expect_err("content rỗng phải lỗi");
    assert!(err.retryable, "lỗi rỗng phải retryable: {err:?}");
    assert!(err.message.contains("max_tokens"), "thiếu stop_reason: {}", err.message);
    assert!(err.message.contains("không có nội dung text"), "thiếu mô tả: {}", err.message);
}

/// Hồi quy: response chỉ gồm block phi-text (ví dụ reasoning) phải lỗi
/// kèm loại block, thay vì lặng lẽ gom được chuỗi rỗng.
#[test]
fn thinking_only_blocks_are_detailed_error() {
    let thinking =
        r#"{"content":[{"type":"thinking","thinking":"hmm"}],"stop_reason":"end_turn"}"#;
    let (base, _) = spawn_mock_seq(vec![thinking, thinking, thinking]);
    let err = call_mock(&base).expect_err("block phi-text phải lỗi");
    assert!(err.message.contains("thinking"), "thiếu loại block: {}", err.message);
    assert!(err.message.contains("end_turn"), "thiếu stop_reason: {}", err.message);
}

/// Rỗng thoáng qua phải tự khỏi bằng retry nội: lần 1 rỗng, lần 2 có text.
#[test]
fn empty_then_text_recovers_via_retry() {
    let ok = r#"{"content":[{"type":"text","text":"xin chào"}],"usage":{"input_tokens":10,"output_tokens":5}}"#;
    let (base, _) = spawn_mock_seq(vec![r#"{"content":[]}"#, ok]);
    let res = call_mock(&base).expect("retry phải khỏi khi lần 2 có text");
    assert_eq!(res.text, "xin chào");
}

/// Muse Spark luôn reasoning và reasoning chiếm chung trần max_tokens:
/// request Meta phải xin effort thấp + trần hào phóng để chừa chỗ cho text.
#[test]
fn meta_request_sets_effort_and_generous_cap() {
    let ok = r#"{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":10,"output_tokens":5}}"#;
    let (base, rx) = spawn_mock_seq(vec![ok]);
    call_mock(&base).expect("mock phải thành công");
    let seen = recv_seen(&rx);
    assert!(seen.body.contains(r#""output_config":{"effort":"low"}"#), "{}", seen.body);
    assert!(seen.body.contains(r#""max_tokens":2048"#), "{}", seen.body);
}

/// Claude thật không hiểu `output_config` → đường Anthropic không được gửi.
#[test]
fn anthropic_request_omits_output_config() {
    let ok = r#"{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":10,"output_tokens":5}}"#;
    let (base, rx) = spawn_mock_seq(vec![ok]);
    call_mock_version(&base, Some("2023-06-01")).expect("mock phải thành công");
    let seen = recv_seen(&rx);
    assert!(!seen.body.contains("output_config"), "{}", seen.body);
}

/// Đói max_tokens (chỉ còn redacted_thinking) → nới trần gấp đôi và khỏi.
#[test]
fn max_tokens_starvation_doubles_cap_and_recovers() {
    let starved = r#"{"content":[{"type":"redacted_thinking","data":"e30="}],"stop_reason":"max_tokens","usage":{"input_tokens":100,"output_tokens":2048}}"#;
    let ok = r#"{"content":[{"type":"text","text":"xin chào"}],"usage":{"input_tokens":100,"output_tokens":20}}"#;
    let (base, rx) = spawn_mock_seq(vec![starved, ok]);
    let res = call_mock(&base).expect("nới trần phải khỏi");
    assert_eq!(res.text, "xin chào");
    let r1 = recv_seen(&rx);
    let r2 = recv_seen(&rx);
    assert!(r1.body.contains(r#""max_tokens":2048"#), "lần 1: {}", r1.body);
    assert!(r2.body.contains(r#""max_tokens":4096"#), "lần 2: {}", r2.body);
}

/// Đói bền vững cả 3 lần → Err chi tiết kèm loại block + token đã dùng.
#[test]
fn persistent_starvation_errors_with_detail() {
    let starved = r#"{"content":[{"type":"redacted_thinking","data":"e30="}],"stop_reason":"max_tokens","usage":{"input_tokens":100,"output_tokens":2048}}"#;
    let (base, rx) = spawn_mock_seq(vec![starved, starved, starved]);
    let err = call_mock(&base).expect_err("đói bền vững phải lỗi");
    assert!(err.retryable, "{err:?}");
    assert!(err.message.contains("redacted_thinking"), "{}", err.message);
    assert!(err.message.contains("max_tokens"), "{}", err.message);
    assert!(err.message.contains("in 100 · out 2048"), "{}", err.message);
    for expected in [2048, 4096, 8192] {
        let seen = recv_seen(&rx);
        assert!(
            seen.body.contains(&format!(r#""max_tokens":{expected}"#)),
            "trần {expected}: {}",
            seen.body
        );
    }
}

#[test]
fn anthropic_path_sends_version_header() {
    let (base, rx) = spawn_mock();
    call_messages_api(&MessagesCall {
        base_url: &base,
        api_key: "sk-ant-test",
        anthropic_version: Some("2023-06-01"),
        model: "claude-test",
        task: AiTaskKind::Summarize,
        raw_text: "STK: 1234567890 cần kiểm tra",
        price_in_per_mtok: 3.0,
        price_out_per_mtok: 15.0,
        backend_name: "anthropic",
        lang: AiLang::Vi,
    })
    .expect("gọi mock phải thành công");
    let seen = rx.recv_timeout(std::time::Duration::from_secs(5)).expect("mock nhận request");
    assert!(seen.head.to_lowercase().contains("anthropic-version: 2023-06-01"), "{}", seen.head);
    assert!(!seen.body.contains("1234567890"), "RÒ RỈ STK: {}", seen.body);
}
