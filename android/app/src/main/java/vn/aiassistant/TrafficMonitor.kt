package vn.aiassistant

import android.content.Context
import android.content.pm.PackageManager
import android.net.TrafficStats
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

// Giám sát traffic mạng Android, gương của NetMonitor macOS: gom counter
// per-UID (TrafficStats, không cần quyền đặc biệt) + tổng máy, lõi Rust chấm
// verdict qua FFI netEvaluate, worker LLM hiệu đính sau. Tick 60s riêng.
// Chỉ đếm bytes — không host/DNS/payload, không bao giờ vào prompt AI cloud.
object TrafficMonitor {
    data class Verdict(
        val level: String,
        val score: Int,
        val reasons: List<String>,
        val top: String,
        val raw: String,
    )

    const val INTERVAL_SECS = 60L
    private const val BASELINE_FILE = "net-baseline.json"

    var running = false
        private set
    var last: Verdict? = null
        private set
    var lastScanText = "Chưa quét"
        private set
    var llmVerdict = ""
        private set
    private val historyBacking = mutableListOf<String>()
    val history: List<String> get() = historyBacking.toList()

    /** Gọi trên luồng chính mỗi khi có verdict mới (UI observe). */
    var onUpdate: (() -> Unit)? = null

    var llmEnabled = false
    var llmBaseUrl = "http://127.0.0.1:11434"
    var llmModel = "qwen2.5:3b"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null
    private var prevUid: Map<Int, Pair<Long, Long>>? = null
    private var prevTotal: Pair<Long, Long>? = null
    private var lastTick = 0L
    private val uidNameCache = HashMap<Int, String>()
    private val worker = NetLlmWorker()

    fun start(ctx: Context) {
        if (running) return
        running = true
        val app = ctx.applicationContext
        worker.onVerdict = { text ->
            scope.launch(Dispatchers.Main) {
                llmVerdict = text
                onUpdate?.invoke()
            }
        }
        job = scope.launch {
            capture(app) // Tick đầu: lập nền.
            prevTotal = totals()
            lastTick = System.currentTimeMillis()
            withContext(Dispatchers.Main) {
                lastScanText = "Đang chạy, tick đầu lập nền…"
                onUpdate?.invoke()
            }
            while (isActive && running) {
                delay(INTERVAL_SECS * 1000)
                try {
                    scanOnce(app)
                } catch (_: Exception) {
                }
            }
        }
    }

    fun stop() {
        running = false
        job?.cancel()
        job = null
    }

    fun scanNow(ctx: Context) {
        scope.launch {
            try {
                scanOnce(ctx.applicationContext)
            } catch (_: Exception) {
            }
        }
    }

    private suspend fun scanOnce(app: Context) {
        val curr = capture(app)
        val tot = totals()
        val prev = prevUid
        val prevT = prevTotal
        val now = System.currentTimeMillis()
        prevUid = curr
        prevTotal = tot
        if (prev == null || prevT == null || lastTick == 0L) {
            lastTick = now
            noteMain(app, "Tick đầu, lập nền (${curr.size} UID)")
            return
        }
        val elapsed = (now - lastTick) / 1000.0
        lastTick = now
        if (elapsed > 300) return // Ngủ/gap dài: bỏ tick, lập nền mới.
        val deltas = ArrayList<Triple<String, Long, Long>>()
        for ((uid, v) in curr) {
            val p = prev[uid] ?: Pair(0L, 0L)
            val rx = if (v.first >= p.first) v.first - p.first else v.first
            val tx = if (v.second >= p.second) v.second - p.second else v.second
            if (rx + tx == 0L) continue
            deltas.add(Triple(uidName(app, uid), rx, tx))
        }
        val dRx = if (tot.first >= prevT.first) tot.first - prevT.first else tot.first
        val dTx = if (tot.second >= prevT.second) tot.second - prevT.second else tot.second
        val snap = buildSnapshot(deltas, dRx, dTx, elapsed, loadBaseline(app))
        val raw = try {
            uniffi.aiassist_core.netEvaluate(snap, uniffi.aiassist_core.AiLang.VI)
        } catch (_: Exception) {
            return
        }
        val v = parseVerdict(raw) ?: return
        saveBaseline(app, v.baselineJson)
        withContext(Dispatchers.Main) {
            last = v.verdict
            lastScanText = "Mới quét: ${v.verdict.level} ${v.verdict.score}/100"
            val line = "${v.verdict.level} ${v.verdict.score} — ${v.verdict.reasons.joinToString("; ").ifEmpty { "yên" }}"
            historyBacking.add(0, line)
            while (historyBacking.size > 50) historyBacking.removeAt(historyBacking.size - 1)
            onUpdate?.invoke()
            if (v.verdict.level == "dangerous") {
                OverlayManager.showDanger(app, v.verdict.score, v.verdict.reasons)
            }
        }
        if (runNeedsLlm(raw)) {
            worker.enqueue(raw, NetLlmWorker.Config(llmEnabled, llmBaseUrl, llmModel))
        }
    }

    private suspend fun noteMain(app: Context, text: String) {
        withContext(Dispatchers.Main) {
            lastScanText = text
            onUpdate?.invoke()
        }
    }

    private fun totals(): Pair<Long, Long> = Pair(
        TrafficStats.getTotalRxBytes().coerceAtLeast(0),
        TrafficStats.getTotalTxBytes().coerceAtLeast(0),
    )

    /** Gom bytes theo UID qua gói đã cài (không cần quyền đặc biệt). */
    private fun capture(app: Context): Map<Int, Pair<Long, Long>> {
        val out = HashMap<Int, Pair<Long, Long>>()
        try {
            @Suppress("DEPRECATION")
            val pkgs = app.packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
            for (a in pkgs) {
                val rx = TrafficStats.getUidRxBytes(a.uid)
                val tx = TrafficStats.getUidTxBytes(a.uid)
                if (rx <= 0 && tx <= 0) continue
                val e = out[a.uid]
                out[a.uid] = Pair(
                    (e?.first ?: 0) + rx.coerceAtLeast(0),
                    (e?.second ?: 0) + tx.coerceAtLeast(0),
                )
            }
        } catch (_: Exception) {
        }
        return out
    }

    private fun uidName(app: Context, uid: Int): String {
        uidNameCache[uid]?.let { return it }
        val name = try {
            app.packageManager.getPackagesForUid(uid)?.firstOrNull() ?: "uid-$uid"
        } catch (_: Exception) {
            "uid-$uid"
        }
        uidNameCache[uid] = name
        return name
    }

    // MARK: - Snapshot / verdict (gương NetMonitor Swift)

    fun buildSnapshot(
        apps: List<Triple<String, Long, Long>>,
        totalRx: Long,
        totalTx: Long,
        windowSecs: Double,
        baseline: String,
    ): String {
        val base = try {
            JSONObject(baseline)
        } catch (_: Exception) {
            JSONObject()
        }
        val arr = JSONArray()
        for (a in apps) {
            arr.put(JSONObject().put("name", a.first).put("rx_bytes", a.second).put("tx_bytes", a.third))
        }
        return JSONObject()
            .put("window_secs", windowSecs)
            .put("apps", arr)
            .put("total_rx", totalRx)
            .put("total_tx", totalTx)
            .put("baseline", base)
            .toString()
    }

    internal data class Parsed(val verdict: Verdict, val baselineJson: String)

    internal fun parseVerdict(json: String): Parsed? {
        val o = try {
            JSONObject(json)
        } catch (_: Exception) {
            return null
        }
        val level = o.optString("level", "").ifEmpty { return null }
        val score = o.optInt("score", 0)
        val reasons = ArrayList<String>()
        val rj = o.optJSONArray("reasons")
        if (rj != null) for (i in 0 until rj.length()) reasons.add(rj.optString(i))
        val tops = ArrayList<String>()
        val tj = o.optJSONArray("top")
        if (tj != null) for (i in 0 until minOf(8, tj.length())) {
            val t = tj.optJSONObject(i) ?: continue
            tops.add("${t.optString("name", "?")}: ↑${t.optLong("tx_bytes")} ↓${t.optLong("rx_bytes")}")
        }
        val base = o.optJSONObject("baseline")?.toString() ?: "{}"
        return Parsed(Verdict(level, score, reasons, tops.joinToString("\n"), json), base)
    }

    private fun runNeedsLlm(verdictJson: String): Boolean =
        try {
            uniffi.aiassist_core.netNeedsLlm(verdictJson)
        } catch (_: Exception) {
            false
        }

    // MARK: - Baseline

    private fun loadBaseline(app: Context): String = try {
        File(app.filesDir, BASELINE_FILE).takeIf { it.exists() }?.readText() ?: "{}"
    } catch (_: Exception) {
        "{}"
    }

    private fun saveBaseline(app: Context, json: String) {
        try {
            File(app.filesDir, BASELINE_FILE).writeText(json)
        } catch (_: Exception) {
        }
    }
}
