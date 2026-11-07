import Foundation
import Testing

@testable import AiAssistant

/// Unit test parser `nettop -P` bằng fixture chép từ output thật.
struct NetParserTests {
    // Fixture verbatim từ `nettop -l 1 -P -m tcp` (tên cắt 16 ký tự,
    // tên chứa chấm/cách, đơn vị B/KiB/MiB, dòng rác).
    static let fixture = """
        time interface state bytes_in bytes_out rx_dupe rx_ooo re-tx
        11:29:20.285497 apsd.602 5240 KiB 2177 KiB 0 B 0 B 0 B
        11:29:20.285499 kdc.861 0 B 0 B 0 B 0 B 0 B
        11:29:20.285505 io.tailscale.ip.3504 925 KiB 8600 KiB 11 KiB 0 B 101 KiB
        11:29:20.285513 Google Chrome H.17077 8953 KiB 2127 KiB 2386 B 31 B 7664 B
        11:29:20.285512 muse-bin-1.4.13.15137 17 MiB 110 MiB 0 B 0 B 18 KiB
        dòng rác không đúng định dạng
        """

    @Test func parseDungDonViVaTenKho() {
        let r = NetMonitor.parseNettop(Self.fixture)
        #expect(r["apsd"]?.rx == 5240 * 1024)
        #expect(r["apsd"]?.tx == 2177 * 1024)
        #expect(r["io.tailscale.ip"]?.rx == 925 * 1024)
        #expect(r["io.tailscale.ip"]?.tx == 8600 * 1024)
        #expect(r["Google Chrome H"]?.rx == 8953 * 1024)
        #expect(r["muse-bin-1.4.13"]?.tx == 110 * 1024 * 1024)
    }

    @Test func boDongTrangDongRac() {
        let r = NetMonitor.parseNettop(Self.fixture)
        #expect(r["kdc"] == nil)
        #expect(r.count == 4)
    }

    @Test func donViLaBiLoai() {
        #expect(NetMonitor.unitMult("KiB") == 1024)
        #expect(NetMonitor.unitMult("MiB") == 1024.0 * 1024.0)
        #expect(NetMonitor.unitMult("XB") == nil)
    }

    @Test func snapshotGiuNguyenTruong() {
        let s = NetMonitor.buildSnapshot(
            apps: [(name: "A", rx: 1, tx: 2)], totalRx: 3, totalTx: 4,
            windowSecs: 60, baseline: "rác"
        )
        #expect(s.contains("\"total_tx\":4"))
        #expect(s.contains("\"window_secs\":60"))
    }

    @Test func parseVerdictChiuLoi() {
        let v = NetMonitor.parseVerdict(#"{"level":"suspicious","score":25,"reasons":["X"],"top":[{"name":"A","rx_bytes":1,"tx_bytes":2}],"baseline":{}}"#)
        #expect(v?.level == "suspicious")
        #expect(v?.top.contains("A") == true)
        #expect(NetMonitor.parseVerdict("rác") == nil)
    }
}
