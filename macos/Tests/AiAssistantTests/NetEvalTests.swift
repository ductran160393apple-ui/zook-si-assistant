import Foundation
import Testing

@testable import AiAssistant

/// Smoke test binding FFI cho lõi netmon (không chạm mạng thật).
struct NetEvalTests {
    @Test func danhGiaSnapshotTraVerdict() {
        let snap = #"{"window_secs":60,"apps":[{"name":"Chrome","rx_bytes":1000,"tx_bytes":30000000}]}"#
        let out = netEvaluate(snapshotJson: snap, lang: .vi)
        #expect(out.contains("\"suspicious\""))
        #expect(out.contains("Chrome"))
        #expect(netNeedsLlm(verdictJson: out))
    }

    @Test func snapshotRongAnToanKhongCanLlm() {
        let out = netEvaluate(snapshotJson: #"{"window_secs":60,"apps":[]}"#, lang: .vi)
        #expect(out.contains("\"safe\""))
        #expect(!netNeedsLlm(verdictJson: out))
    }

    @Test func promptLlmBocData() {
        let sys = netLlmSystemPrompt(lang: .vi)
        #expect(sys.contains("4 dòng"))
        let user = netLlmUserPrompt(verdictJson: #"{"level":"safe"}"#, lang: .en)
        #expect(user.contains("<EVENT>"))
    }
}
