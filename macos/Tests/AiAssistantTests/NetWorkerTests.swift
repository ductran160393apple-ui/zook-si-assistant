import Foundation
import Testing

@testable import AiAssistant

/// Unit test logic thuần của worker LLM (không gọi mạng).
struct NetWorkerTests {
    @Test func fingerprintOnDinhTheoNoiDung() {
        let a = NetLLMWorker.fingerprint(verdictJson: #"{"level":"suspicious","score":25,"top":[{"name":"Chrome"}]}"#)
        let b = NetLLMWorker.fingerprint(verdictJson: #"{"level":"suspicious","score":29,"top":[{"name":"Chrome"}]}"#)
        let c = NetLLMWorker.fingerprint(verdictJson: #"{"level":"dangerous","score":80,"top":[{"name":"Chrome"}]}"#)
        #expect(a == b)
        #expect(a != c)
        #expect(NetLLMWorker.fingerprint(verdictJson: "rác") == "unknown")
    }

    @Test func hangDoiChanTrungVaTran() {
        let j1 = NetLLMWorker.Job(fingerprint: "a", verdict: "{}")
        let j2 = NetLLMWorker.Job(fingerprint: "b", verdict: "{}")
        let (q1, d0) = NetLLMWorker.boundedEnqueue([], job: j1, limit: 1)
        #expect(q1.count == 1 && d0 == 0)
        let (q2, d1) = NetLLMWorker.boundedEnqueue(q1, job: j1, limit: 1)
        #expect(q2.count == 1 && d1 == 0)
        let (q3, d2) = NetLLMWorker.boundedEnqueue(q2, job: j2, limit: 1)
        #expect(q3.count == 1 && d2 == 1 && q3[0].fingerprint == "b")
    }
}
