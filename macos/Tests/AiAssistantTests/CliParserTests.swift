import Testing

@testable import AiAssistant

/// Unit test cho parser đầu ra của backend CLI (Claude Code, Antigravity).
/// Fixture "thật" là payload nguyên văn thu trên máy dev (agy 1.4.8, claude
/// CLI), chỉ rút gọn conversation_id/session_id cho gọn; fixture "tái dựng"
/// ghi rõ trong tên test.
struct CliParserTests {
    // MARK: - Fixture thật: agy (antigravity.google/cli, --output-format json)

    /// agy thành công, CLI tự chọn model (thu 27/10/2026).
    private let agySuccess = #"{"conversation_id":"2a0f9abe","status":"SUCCESS","response":"OK\n","duration_seconds":8.748395,"num_turns":1,"usage":{"input_tokens":7753,"output_tokens":5,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":7758}}"#

    /// agy hết quota, model gemini-4-argon-medium (thu 27/10/2026).
    private let agyQuota = #"{"conversation_id":"0b482593","status":"ERROR","response":"","error":"Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 20h6m6s.","duration_seconds":0,"num_turns":1,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0}}"#

    /// agy model không tồn tại (thu 27/10/2026).
    private let agyBadModel = #"{"conversation_id":"","status":"ERROR","response":"","error":"invalid model selection (--model \"BOGUS-MODEL-XYZ-123\" --effort \"\"): model BOGUS-MODEL-XYZ-123 is not recognized as a known model or custom model in settings\nAvailable models:\n  Gemini 4 Argon (Medium)","duration_seconds":0,"num_turns":0,"usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0}}"#

    // MARK: - Fixture thật: claude -p --output-format json

    /// claude bị org tắt quyền subscription (thu 27/10/2026, nguyên văn).
    private let claudeOrgDisabled = #"{"duration_api_ms":0,"stop_reason":"stop_sequence","session_id":"fa30f63f","total_cost_usd":0,"usage":{"output_tokens_details":{"thinking_tokens":0},"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard","fallback_credit":null},"modelUsage":{},"permission_denials":[],"terminal_reason":"api_error","fast_mode_state":"off","fast_mode_disabled_reason":"sdk_opt_in_required","subagent_stats":{"spawned":0,"requested":{"background":0,"foreground":0,"unset":0},"started_in_background":0,"max_depth":0,"spawned_by_subagents":0,"completed":0,"failed":0,"killed":{"parent":0,"user":0,"system":0},"refused":{"depth_limit":0,"concurrency_limit":0,"budget":0},"by_type":{}},"safety_stops":0,"is_error":true,"num_turns":1,"subtype":"success","api_error_status":403,"api_error_code":"oauth_not_allowed_for_organization","api_error_origin":"first_party","result":"Your organization has disabled Claude subscription access for Claude Code · Use an Anthropic API key instead, or ask your admin to enable access","type":"result","duration_ms":348,"uuid":"74fa26fa","queued_turn_count":0,"result_index":0}"#

    /// claude thành công, tái dựng tối thiểu theo đúng schema CLI
    /// {result, is_error, usage} (không có mẫu SUCCESS thật: tài khoản
    /// dev bị org tắt quyền).
    private let claudeSuccessShape = #"{"result":"OK","is_error":false,"usage":{"input_tokens":10,"output_tokens":3}}"#

    // MARK: - agy

    @Test func agySuccessThat() {
        let out = AiRunner.parseAgyOutput(agySuccess)
        #expect(out.text == "OK\n")
        #expect(out.tokens == "in 7753 · out 5")
    }

    @Test func agyQuotaThat() {
        let out = AiRunner.parseAgyOutput(agyQuota)
        #expect(out.text.hasPrefix("Lỗi agy: Individual quota reached"))
        #expect(out.text.contains("Resets in"))
        #expect(out.tokens == "")
    }

    @Test func agyModelSaiThat() {
        let out = AiRunner.parseAgyOutput(agyBadModel)
        #expect(out.text.contains("invalid model selection"))
        #expect(out.text.contains("Gemini 4 Argon (Medium)"))
        #expect(out.tokens == "")
    }

    @Test func agyThanhCongNhungRong() {
        let out = AiRunner.parseAgyOutput(#"{"status":"SUCCESS","response":""}"#)
        #expect(out.text == "(agy không trả về nội dung văn bản.)")
    }

    @Test func agyKhongPhaiJsonGiuNguyen() {
        let out = AiRunner.parseAgyOutput("dòng text thô")
        #expect(out.text == "dòng text thô")
        #expect(out.tokens == "ước tính")
    }

    // MARK: - claude

    @Test func claudeOrgTatQuyenThat() {
        let out = AiRunner.parseClaudeOutput(claudeOrgDisabled)
        #expect(out.text == "Lỗi Claude: Your organization has disabled Claude subscription access for Claude Code · Use an Anthropic API key instead, or ask your admin to enable access")
        #expect(out.tokens == "")
    }

    @Test func claudeThanhCongTheoSchema() {
        let out = AiRunner.parseClaudeOutput(claudeSuccessShape)
        #expect(out.text == "OK")
        #expect(out.tokens == "in 10 · out 3 · lõi ước tính")
    }

    @Test func claudeKetQuaRong() {
        let out = AiRunner.parseClaudeOutput(#"{"result":"","is_error":false,"usage":{}}"#)
        #expect(out.text == "(AI không trả về nội dung văn bản.)")
    }

    @Test func claudeKhongPhaiJsonGiuNguyen() {
        let out = AiRunner.parseClaudeOutput("text thô từ CLI")
        #expect(out.text == "text thô từ CLI")
        #expect(out.tokens == "ước tính")
    }

    // MARK: - gemini (parser chung khoan dung nhiều khóa)

    @Test func geminiUuTienKhoaResponse() {
        #expect(AiRunner.parseGenericCliOutput(#"{"response":"R","text":"T"}"#).text == "R")
        #expect(AiRunner.parseGenericCliOutput(#"{"text":"T","output":"O"}"#).text == "T")
        #expect(AiRunner.parseGenericCliOutput(#"{"output":"O","result":"X"}"#).text == "O")
        #expect(AiRunner.parseGenericCliOutput(#"{"result":"X"}"#).text == "X")
    }

    @Test func geminiBoQuaKhoaRong() {
        #expect(AiRunner.parseGenericCliOutput(#"{"response":"","text":"T"}"#).text == "T")
    }

    @Test func geminiKhongPhaiJsonGiuNguyen() {
        #expect(AiRunner.parseGenericCliOutput("text thô").text == "text thô")
    }
}
