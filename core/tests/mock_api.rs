//! Test với server giả: đường Meta/Anthropic Messages API phải gửi đúng
//! header Bearer, đúng model, và KHÔNG BAO GIỜ chứa số điện thoại gốc.

use aiassist_core::backends::{call_messages_api, AiTaskKind, MessagesCall};
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
    })
    .expect("gọi mock phải thành công");
    assert_eq!(res.backend, "meta");

    let seen = rx.recv_timeout(std::time::Duration::from_secs(5)).expect("mock nhận request");
    assert!(seen.head.to_lowercase().contains("authorization: bearer test-key-123"), "{}", seen.head);
    assert!(seen.body.contains("meta-llama-3.1-70b"), "{}", seen.body);
    assert!(seen.body.contains("[SĐT]"), "{}", seen.body);
    assert!(!seen.body.contains("0912345678"), "RÒ RỈ SĐT: {}", seen.body);
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
    })
    .expect("gọi mock phải thành công");
    let seen = rx.recv_timeout(std::time::Duration::from_secs(5)).expect("mock nhận request");
    assert!(seen.head.to_lowercase().contains("anthropic-version: 2023-06-01"), "{}", seen.head);
    assert!(!seen.body.contains("1234567890"), "RÒ RỈ STK: {}", seen.body);
}
