import XCTest
@testable import TabbiKitCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date {
    try! Date(text, strategy: Date.ISO8601FormatStyle())
}

private func turnContext(model: String, at timestamp: String = "2026-10-08T09:00:00.000Z") -> String {
    #"{"timestamp":"\#(timestamp)","type":"turn_context","payload":{"cwd":"/tmp","approval_policy":"on-request","model":"\#(model)","summary":"auto"}}"#
}

/// A `token_count` event as current Codex versions write it.
private func tokenCount(
    at timestamp: String, input: Int, cached: Int = 0, output: Int,
    limits: String? = #"{"primary":{"used_percent":42.0,"window_minutes":300,"resets_at":1791540000},"secondary":{"used_percent":76.5,"window_minutes":10080,"resets_at":1791900000}}"#
) -> String {
    let total = input + output
    let info = #"{"total_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output),"reasoning_output_tokens":0,"total_tokens":\#(total)},"last_token_usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2},"model_context_window":272000}"#
    return #"{"timestamp":"\#(timestamp)","type":"event_msg","payload":{"type":"token_count","info":\#(info),"rate_limits":\#(limits ?? "null")}}"#
}

private func session(_ lines: String...) -> Data {
    Data(lines.joined(separator: "\n").utf8)
}

final class CodexUsageLogTests: XCTestCase {
    private let now = date("2026-10-09T12:00:00Z")

    func testTurnsAreTheIncreasesOfTheSessionTotals() {
        let usage = CodexUsageLog.summarize(sessions: [session(
            turnContext(model: "gpt-5-codex"),
            #"{"timestamp":"2026-10-09T09:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"token_count"}]}}"#,
            tokenCount(at: "2026-10-09T09:00:05.000Z", input: 1_000, cached: 400, output: 200),
            // Codex repeats the event when only the limits change.
            tokenCount(at: "2026-10-09T09:00:06.000Z", input: 1_000, cached: 400, output: 200),
            tokenCount(at: "2026-10-09T09:01:00.000Z", input: 3_000, cached: 2_000, output: 500)
        )], now: now, calendar: utc)

        let today = usage.stats.today
        XCTAssertEqual(today.messages, 2)
        XCTAssertEqual(today.topModel, "gpt-5-codex")
        // Cached input is counted once, as a cache read, not also as input.
        XCTAssertEqual(today.tokens, ClaudeTokenUsage(input: 1_000, output: 500, cacheRead: 2_000))
        XCTAssertEqual(today.tokens.total, 3_500)
    }

    func testSplitsTodayFromTheWeekAndDropsOlderTurns() {
        let usage = CodexUsageLog.summarize(sessions: [
            session(turnContext(model: "gpt-5"),
                    tokenCount(at: "2026-10-01T10:00:00Z", input: 50, output: 50),
                    tokenCount(at: "2026-10-05T10:00:00Z", input: 150, output: 50)),
            session(turnContext(model: "gpt-5-codex"),
                    tokenCount(at: "2026-10-09T08:00:00Z", input: 10, output: 20)),
        ], now: now, calendar: utc)

        XCTAssertEqual(usage.stats.today.tokens.total, 30)
        XCTAssertEqual(usage.stats.lastSevenDays.tokens.total, 130)
        XCTAssertEqual(usage.stats.lastSevenDays.topModel, "gpt-5")
    }

    func testModelChangesMidSessionAreAttributed() {
        let usage = CodexUsageLog.summarize(sessions: [session(
            turnContext(model: "gpt-5"),
            tokenCount(at: "2026-10-09T09:00:00Z", input: 100, output: 0),
            turnContext(model: "gpt-5-codex"),
            tokenCount(at: "2026-10-09T09:05:00Z", input: 400, output: 0)
        )], now: now, calendar: utc)

        XCTAssertEqual(usage.stats.today.models.map(\.model), ["gpt-5-codex", "gpt-5"])
        XCTAssertEqual(usage.stats.today.models.map(\.tokens.total), [300, 100])
    }

    func testNewestLimitsWinWithTheirResetTimes() throws {
        let older = #"{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1791500000},"secondary":{"used_percent":20,"window_minutes":10080,"resets_at":1791900000}}"#
        let usage = CodexUsageLog.summarize(sessions: [
            session(tokenCount(at: "2026-10-09T11:00:00Z", input: 1, output: 1)),
            session(tokenCount(at: "2026-10-09T10:00:00Z", input: 1, output: 1, limits: older)),
        ], now: now, calendar: utc)

        let limits = try XCTUnwrap(usage.limits)
        XCTAssertEqual(limits.fetchedAt, date("2026-10-09T11:00:00Z"))
        XCTAssertEqual(limits.snapshot.fiveHour, ClaudeUsageWindow(utilization: 0.42, resetsAt: Date(timeIntervalSince1970: 1_791_540_000)))
        XCTAssertEqual(limits.snapshot.sevenDay?.utilization ?? 0, 0.765, accuracy: 0.0001)
    }

    func testReadsOlderLimitShapes() throws {
        let relative = #"{"primary":{"used_percent":30,"window_minutes":299,"resets_in_seconds":600},"secondary":null}"#
        let flat = #"{"primary_used_percent":55,"secondary_used_percent":12,"primary_to_secondary_ratio_percent":20}"#

        let relativeUsage = CodexUsageLog.summarize(
            sessions: [session(tokenCount(at: "2026-10-09T10:00:00Z", input: 1, output: 1, limits: relative))],
            now: now, calendar: utc
        )
        let fiveHour = try XCTUnwrap(relativeUsage.limits?.snapshot.fiveHour)
        XCTAssertEqual(fiveHour.resetsAt, date("2026-10-09T10:10:00Z"))
        XCTAssertNil(relativeUsage.limits?.snapshot.sevenDay)

        let flatUsage = CodexUsageLog.summarize(
            sessions: [session(tokenCount(at: "2026-10-09T10:00:00Z", input: 1, output: 1, limits: flat))],
            now: now, calendar: utc
        )
        XCTAssertEqual(flatUsage.limits?.snapshot.fiveHour, ClaudeUsageWindow(utilization: 0.55, resetsAt: nil))
        XCTAssertEqual(flatUsage.limits?.snapshot.sevenDay, ClaudeUsageWindow(utilization: 0.12, resetsAt: nil))
    }

    func testAPIKeySessionsHaveTokensButNoLimits() {
        let usage = CodexUsageLog.summarize(
            sessions: [session(tokenCount(at: "2026-10-09T10:00:00Z", input: 5, output: 5, limits: nil))],
            now: now, calendar: utc
        )
        XCTAssertNil(usage.limits)
        XCTAssertEqual(usage.stats.today.tokens.total, 10)
        XCTAssertEqual(usage.stats.today.topModel, CodexUsageLog.defaultModel)
    }

    func testIgnoresMalformedAndUnrelatedLines() {
        let usage = CodexUsageLog.summarize(sessions: [session(
            #"{"timestamp":"2026-10-09T10:00:00Z","type":"event_msg","payload":{"type":"token_count""#,
            #"{"timestamp":"2026-10-09T10:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}"#,
            "not json",
            ""
        )], now: now, calendar: utc)
        XCTAssertEqual(usage, CodexUsage(limits: nil, stats: ClaudeLocalStats.aggregate([], now: now, calendar: utc)))
    }

    func testReadsRecentSessionFilesFromDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("2026/10/09", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let recent = day.appendingPathComponent("rollout-a.jsonl")
        let old = day.appendingPathComponent("rollout-b.jsonl")
        try session(turnContext(model: "gpt-5-codex"), tokenCount(at: "2026-10-09T10:00:00Z", input: 7, output: 3))
            .write(to: recent)
        try session(tokenCount(at: "2026-10-09T10:00:00Z", input: 1_000, output: 0)).write(to: old)
        // A file untouched since before the window can't hold this week's turns.
        try FileManager.default.setAttributes([.modificationDate: date("2026-09-01T00:00:00Z")], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: recent.path)

        let usage = CodexUsageLog.read(root: root, now: now, calendar: utc)
        XCTAssertEqual(usage.stats.today.tokens.total, 10)
        XCTAssertNotNil(usage.limits)

        XCTAssertEqual(CodexUsageLog.read(root: root.appendingPathComponent("missing"), now: now), .empty)
    }

    func testRootFollowsCodexHome() {
        XCTAssertEqual(CodexUsageLog.defaultRoot(environment: ["CODEX_HOME": "/opt/codex"]).path, "/opt/codex/sessions")
        XCTAssertTrue(CodexUsageLog.defaultRoot(environment: [:]).path.hasSuffix("/.codex/sessions"))
    }
}
