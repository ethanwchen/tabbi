import XCTest
@testable import NotchKitCore

/// Builds a transcript line shaped like Claude Code's session JSONL.
private func assistantLine(
    id: String,
    model: String = "claude-opus-4-5-20251101",
    timestamp: String,
    input: Int = 1, output: Int = 2, cacheRead: Int = 3, cacheCreation: Int = 4
) -> String {
    #"{"parentUuid":"p","type":"assistant","message":{"model":"\#(model)","id":"\#(id)","role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output),"service_tier":"standard"}},"timestamp":"\#(timestamp)","sessionId":"s"}"#
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ text: String) -> Date {
    try! Date(text, strategy: Date.ISO8601FormatStyle())
}

final class ClaudeUsageRecordTests: XCTestCase {
    func testParsesAssistantUsage() {
        let record = ClaudeUsageRecord.parse(line: assistantLine(
            id: "msg_1", timestamp: "2026-10-01T12:30:00.250Z", input: 10, output: 20, cacheRead: 30, cacheCreation: 40
        ))
        XCTAssertEqual(record?.messageID, "msg_1")
        XCTAssertEqual(record?.model, "claude-opus-4-5-20251101")
        XCTAssertEqual(record?.usage, ClaudeTokenUsage(input: 10, output: 20, cacheRead: 30, cacheCreation: 40))
        XCTAssertEqual(record?.usage.total, 100)
        XCTAssertEqual(record!.timestamp.timeIntervalSince1970, date("2026-10-01T12:30:00Z").timeIntervalSince1970 + 0.25,
                       accuracy: 0.001)
    }

    func testAcceptsTimestampWithoutFractionalSeconds() {
        XCTAssertNotNil(ClaudeUsageRecord.parse(line: assistantLine(id: "m", timestamp: "2026-10-01T12:30:00Z")))
    }

    func testIgnoresNonAssistantMalformedAndSyntheticLines() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"assistant usage"}}"#,
            #"{"type":"assistant","message":{"usage":"#,
            "",
            "not json \"assistant\" \"usage\"",
            assistantLine(id: "m", model: "<synthetic>", timestamp: "2026-10-01T12:30:00Z"),
            assistantLine(id: "m", timestamp: "yesterday"),
        ]
        for line in lines { XCTAssertNil(ClaudeUsageRecord.parse(line: line), line) }
    }

    func testMissingUsageFieldsCountAsZero() {
        let line = #"{"type":"assistant","message":{"model":"claude-haiku-4-5","id":"m","usage":{"output_tokens":7}},"timestamp":"2026-10-01T00:00:00Z"}"#
        XCTAssertEqual(ClaudeUsageRecord.parse(line: line)?.usage, ClaudeTokenUsage(output: 7))
    }

    func testParsesBytesFromSliceOfLargerBuffer() {
        let line = assistantLine(id: "m", timestamp: "2026-10-01T12:30:00Z", output: 5)
        let buffer = Data(("{\"type\":\"user\"}\n" + line + "\n").utf8)
        let start = buffer.firstIndex(of: UInt8(ascii: "\n"))! + 1
        let slice = buffer[start..<(buffer.count - 1)]
        XCTAssertEqual(ClaudeUsageRecord.parse(bytes: slice), ClaudeUsageRecord.parse(line: line))
        XCTAssertEqual(ClaudeUsageRecord.parse(bytes: slice)?.usage.output, 5)
    }

    func testIgnoresContentFieldsItDoesNotNeed() {
        // Large or unusual content blocks must not affect parsing.
        let line = #"{"type":"assistant","message":{"model":"claude-opus-4-5","id":"m","content":[{"type":"tool_use","input":{"nested":[1,{"a":null}],"text":"\"usage\" \n"}}],"usage":{"input_tokens":1,"output_tokens":2,"server_tool_use":{"web_search_requests":0}}},"timestamp":"2026-10-01T00:00:00Z","toolUseResult":{"x":[true]}}"#
        XCTAssertEqual(ClaudeUsageRecord.parse(line: line)?.usage, ClaudeTokenUsage(input: 1, output: 2))
    }
}

final class ClaudeLocalStatsTests: XCTestCase {
    private func record(_ id: String, _ model: String, _ timestamp: String, tokens: Int) -> ClaudeUsageRecord {
        ClaudeUsageRecord(messageID: id, model: model, timestamp: date(timestamp),
                          usage: ClaudeTokenUsage(input: tokens))
    }

    func testSplitsTodayAndSevenDaysByModel() {
        let now = date("2026-10-01T15:00:00Z")
        let stats = ClaudeLocalStats.aggregate([
            record("a", "opus", "2026-10-01T09:00:00Z", tokens: 100),
            record("b", "opus", "2026-10-01T10:00:00Z", tokens: 50),
            record("c", "haiku", "2026-10-01T11:00:00Z", tokens: 500),
            record("d", "sonnet", "2026-09-30T23:59:59Z", tokens: 1000),
            record("e", "opus", "2026-09-25T00:00:00Z", tokens: 7), // first day of the window
            record("f", "opus", "2026-09-24T23:59:59Z", tokens: 9999), // just outside
            record("g", "opus", "2026-10-01T16:00:00Z", tokens: 9999), // in the future
        ], now: now, calendar: utc)

        XCTAssertEqual(stats.today.messages, 3)
        XCTAssertEqual(stats.today.tokens.total, 650)
        XCTAssertEqual(stats.today.topModel, "haiku")
        XCTAssertEqual(stats.today.models.map(\.model), ["haiku", "opus"])
        XCTAssertEqual(stats.today.models.last?.messages, 2)

        XCTAssertEqual(stats.lastSevenDays.messages, 5)
        XCTAssertEqual(stats.lastSevenDays.tokens.total, 1657)
        XCTAssertEqual(stats.lastSevenDays.topModel, "sonnet")
    }

    func testEmptyInputHasNoTopModel() {
        let stats = ClaudeLocalStats.aggregate([], now: Date(), calendar: utc)
        XCTAssertEqual(stats, .empty)
        XCTAssertNil(stats.today.topModel)
    }
}

final class ClaudeUsageLogScannerTests: XCTestCase {
    private var root: URL!
    private let now = date("2026-10-01T15:00:00Z")

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("project-a/session/subagents"), withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ lines: [String], to relativePath: String, trailingNewline: Bool = true) throws {
        let text = lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        try text.write(to: root.appendingPathComponent(relativePath), atomically: false, encoding: .utf8)
    }

    private func append(_ text: String, to relativePath: String) throws {
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent(relativePath))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func testScansNestedFilesAndDedupesContentBlockLines() async throws {
        try write([
            assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z"),
            assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z"), // second content block
            "{garbage",
            #"{"type":"user","message":{"content":"hi"}}"#,
        ], to: "project-a/one.jsonl")
        try write([assistantLine(id: "m2", model: "claude-haiku-4-5", timestamp: "2026-10-01T11:00:00Z")],
                  to: "project-a/session/subagents/agent.jsonl")
        try write([assistantLine(id: "m3", timestamp: "2026-10-01T11:00:00Z")], to: "project-a/notes.txt")

        let stats = await ClaudeUsageLogScanner(root: root).scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 2)
        XCTAssertEqual(stats.today.tokens.total, 20)
    }

    func testReadsOnlyAppendedBytesAndWaitsForPartialLines() async throws {
        try write([assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z")], to: "project-a/s.jsonl")
        // Small chunks exercise lines that straddle read boundaries.
        let scanner = ClaudeUsageLogScanner(root: root, chunkSize: 16)
        var stats = await scanner.scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 1)

        let next = assistantLine(id: "m2", timestamp: "2026-10-01T11:00:00Z")
        let splitIndex = next.index(next.startIndex, offsetBy: 40)
        try append(String(next[..<splitIndex]), to: "project-a/s.jsonl")
        stats = await scanner.scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 1, "partial line must not be consumed")

        try append(String(next[splitIndex...]) + "\n", to: "project-a/s.jsonl")
        stats = await scanner.scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 2)
    }

    func testRereadsFileThatShrank() async throws {
        try write((1...3).map { assistantLine(id: "m\($0)", timestamp: "2026-10-01T10:00:00Z") },
                  to: "project-a/s.jsonl")
        let scanner = ClaudeUsageLogScanner(root: root)
        _ = await scanner.scan(now: now, calendar: utc)

        try write([assistantLine(id: "m4", timestamp: "2026-10-01T12:00:00Z")], to: "project-a/s.jsonl")
        let stats = await scanner.scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 4)
    }

    func testDropsRecordsThatAgeOutOfTheWindow() async throws {
        try write([
            assistantLine(id: "old", timestamp: "2026-09-25T10:00:00Z"),
            assistantLine(id: "new", timestamp: "2026-10-01T10:00:00Z"),
        ], to: "project-a/s.jsonl")
        let scanner = ClaudeUsageLogScanner(root: root)
        var stats = await scanner.scan(now: now, calendar: utc)
        XCTAssertEqual(stats.lastSevenDays.messages, 2)

        stats = await scanner.scan(now: date("2026-10-02T09:00:00Z"), calendar: utc)
        XCTAssertEqual(stats.lastSevenDays.messages, 1)
        XCTAssertEqual(stats.today.messages, 0)
    }

    func testMissingRootYieldsEmptyStats() async {
        let scanner = ClaudeUsageLogScanner(root: root.appendingPathComponent("nope"))
        let stats = await scanner.scan(now: now, calendar: utc)
        XCTAssertEqual(stats, .empty)
    }

    func testSkipsFilesLastModifiedBeforeTheWindow() async throws {
        try write([assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z")], to: "project-a/old.jsonl")
        try FileManager.default.setAttributes(
            [.modificationDate: date("2026-09-20T00:00:00Z")],
            ofItemAtPath: root.appendingPathComponent("project-a/old.jsonl").path
        )
        let stats = await ClaudeUsageLogScanner(root: root).scan(now: now, calendar: utc)
        XCTAssertEqual(stats, .empty)
    }

    func testPersistedIndexSurvivesRelaunchWithoutRereadingFiles() async throws {
        let index = root.appendingPathComponent("index/scan-index.json")
        try write([assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z")], to: "project-a/a.jsonl")
        try write([assistantLine(id: "m2", timestamp: "2026-10-01T11:00:00Z")], to: "project-a/b.jsonl")
        _ = await ClaudeUsageLogScanner(root: root, indexURL: index).scan(now: now, calendar: utc)

        // An unreadable file proves the next launch never opens it again.
        let locked = root.appendingPathComponent("project-a/a.jsonl").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked) }
        try append(assistantLine(id: "m3", timestamp: "2026-10-01T12:00:00Z") + "\n", to: "project-a/b.jsonl")

        let stats = await ClaudeUsageLogScanner(root: root, indexURL: index).scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 3)
        XCTAssertEqual(stats.today.tokens.total, 30)
    }

    func testCorruptIndexFallsBackToAFullScan() async throws {
        let index = root.appendingPathComponent("scan-index.json")
        try Data("{not json".utf8).write(to: index)
        try write([assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z")], to: "project-a/a.jsonl")
        let stats = await ClaudeUsageLogScanner(root: root, indexURL: index).scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 1)
    }

    func testSkipsLinesLongerThanTheLimitAndKeepsReading() async throws {
        let filler = String(repeating: "x", count: ClaudeUsageLogScanner.maxLineLength + 10)
        try write([
            assistantLine(id: "m1", timestamp: "2026-10-01T10:00:00Z"),
            #"{"type":"user","text":"\#(filler)"}"#,
            assistantLine(id: "m2", timestamp: "2026-10-01T11:00:00Z"),
        ], to: "project-a/s.jsonl")
        let stats = await ClaudeUsageLogScanner(root: root).scan(now: now, calendar: utc)
        XCTAssertEqual(stats.today.messages, 2)
    }
}

final class ClaudeUsageFormatTests: XCTestCase {
    func testCompactTokens() {
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(0), "0")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(999), "999")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(1000), "1K")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(1250), "1.3K")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(12_340), "12.3K")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(123_456), "123K")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(999_400), "999K")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(999_950), "1M")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(1_200_000), "1.2M")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(3_400_000_000), "3.4B")
        XCTAssertEqual(ClaudeUsageFormat.compactTokens(-5), "0")
    }

    func testPercent() {
        XCTAssertEqual(ClaudeUsageFormat.percent(0.424), "42%")
        XCTAssertEqual(ClaudeUsageFormat.percent(1.05), "105%")
        XCTAssertEqual(ClaudeUsageFormat.percent(-0.1), "0%")
    }

    func testLevelThresholds() {
        XCTAssertEqual(ClaudeUsageLevel(utilization: 0.69), .normal)
        XCTAssertEqual(ClaudeUsageLevel(utilization: 0.70), .warning)
        XCTAssertEqual(ClaudeUsageLevel(utilization: 0.90), .warning)
        XCTAssertEqual(ClaudeUsageLevel(utilization: 0.91), .critical)
    }

    func testDuration() {
        XCTAssertEqual(ClaudeUsageFormat.duration(30), "<1m")
        XCTAssertEqual(ClaudeUsageFormat.duration(14 * 60), "14m")
        XCTAssertEqual(ClaudeUsageFormat.duration(2 * 3600 + 13 * 60 + 5), "2h 14m")
        XCTAssertEqual(ClaudeUsageFormat.duration(3 * 3600), "3h")
    }

    func testResetDescription() {
        let now = date("2026-10-01T15:00:00Z") // a Thursday
        let locale = Locale(identifier: "en_US_POSIX")
        func reset(_ offset: TimeInterval?) -> String? {
            ClaudeUsageFormat.resetDescription(resetsAt: offset.map { now + $0 }, now: now, calendar: utc, locale: locale)
        }
        XCTAssertNil(reset(nil))
        XCTAssertEqual(reset(-5), "resets now")
        XCTAssertEqual(reset(2 * 3600 + 14 * 60), "resets in 2h 14m")
        XCTAssertEqual(
            ClaudeUsageFormat.resetDescription(resetsAt: date("2026-10-08T09:00:00Z"), now: now, calendar: utc, locale: locale),
            "resets Thu 9:00\u{202F}AM"
        )
    }

    func testUpdatedDescription() {
        let now = date("2026-10-01T15:00:00Z")
        XCTAssertEqual(ClaudeUsageFormat.updatedDescription(fetchedAt: now - 20, now: now), "Updated just now")
        XCTAssertEqual(ClaudeUsageFormat.updatedDescription(fetchedAt: now - 180, now: now), "Updated 3m ago")
        XCTAssertEqual(ClaudeUsageFormat.updatedDescription(fetchedAt: now - 7200, now: now), "Updated 2h ago")
        XCTAssertEqual(ClaudeUsageFormat.updatedDescription(fetchedAt: now - 3 * 86400, now: now), "Updated 3d ago")
        XCTAssertEqual(ClaudeUsageFormat.updatedDescription(fetchedAt: now + 60, now: now), "Updated just now")
    }

    func testModelName() {
        XCTAssertEqual(ClaudeUsageFormat.modelName("claude-opus-4-5-20251101"), "Opus 4.5")
        XCTAssertEqual(ClaudeUsageFormat.modelName("claude-haiku-4-5"), "Haiku 4.5")
        XCTAssertEqual(ClaudeUsageFormat.modelName("claude-sonnet-4-20250514"), "Sonnet 4")
        XCTAssertEqual(ClaudeUsageFormat.modelName("claude-3-5-sonnet-20241022"), "Sonnet 3.5")
        XCTAssertEqual(ClaudeUsageFormat.modelName("claude-opus-4-6[1m]"), "Opus 4.6")
        XCTAssertEqual(ClaudeUsageFormat.modelName("gpt-x"), "gpt-x")
    }
}

final class ClaudeLimitsRecordTests: XCTestCase {
    func testRoundTripsThroughEncoding() {
        let record = ClaudeLimitsRecord(
            snapshot: ClaudeRateLimitSnapshot(
                status: "allowed",
                fiveHour: ClaudeUsageWindow(utilization: 0.42, resetsAt: Date(timeIntervalSince1970: 1_790_912_400)),
                sevenDay: nil
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_790_900_000)
        )
        XCTAssertEqual(ClaudeLimitsRecord(encoded: record.encoded()), record)
    }

    func testCorruptOrMissingDataDecodesToNil() {
        XCTAssertNil(ClaudeLimitsRecord(encoded: nil))
        XCTAssertNil(ClaudeLimitsRecord(encoded: Data("{".utf8)))
    }

    func testRefreshOnOpenOnlyWhenStale() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func record(age: TimeInterval) -> ClaudeLimitsRecord {
            ClaudeLimitsRecord(snapshot: ClaudeRateLimitSnapshot(status: nil, fiveHour: nil, sevenDay: nil),
                               fetchedAt: now - age)
        }
        XCTAssertFalse(ClaudeLimitsRecord.shouldRefreshOnOpen(nil, now: now))
        XCTAssertFalse(ClaudeLimitsRecord.shouldRefreshOnOpen(record(age: 9 * 60), now: now))
        XCTAssertTrue(ClaudeLimitsRecord.shouldRefreshOnOpen(record(age: 10 * 60), now: now))
    }
}

final class ClaudeLimitsProbeTests: XCTestCase {
    private let window = ClaudeUsageWindow(utilization: 0.3, resetsAt: nil)

    func testTakesFirstRateLimitWithAWindowAndStopsConsuming() async throws {
        let terminated = expectation(description: "stream terminated")
        let (events, continuation) = AsyncThrowingStream<ClaudeStreamEvent, Error>.makeStream()
        continuation.onTermination = { _ in terminated.fulfill() }
        continuation.yield(.sessionStarted(sessionID: "s"))
        continuation.yield(.rateLimit(ClaudeRateLimitSnapshot(status: "allowed", fiveHour: nil, sevenDay: nil)))
        continuation.yield(.rateLimit(ClaudeRateLimitSnapshot(status: "allowed", fiveHour: window, sevenDay: nil)))
        // The stream is never finished: the probe must stop on its own.

        let snapshot = try await ClaudeLimitsProbe.firstSnapshot(in: events, timeout: .seconds(5))
        XCTAssertEqual(snapshot.fiveHour, window)
        await fulfillment(of: [terminated], timeout: 2)
    }

    func testErrorResultFails() async {
        let (events, continuation) = AsyncThrowingStream<ClaudeStreamEvent, Error>.makeStream()
        continuation.yield(.result(ClaudeResult(text: "Not logged in", sessionID: nil, isError: true)))
        await assertProbe(events, throws: .cliError("Not logged in"))
    }

    func testStreamEndingWithoutLimitsFails() async {
        let (events, continuation) = AsyncThrowingStream<ClaudeStreamEvent, Error>.makeStream()
        continuation.yield(.assistantText("ok"))
        continuation.finish()
        await assertProbe(events, throws: .noLimitsReported)
    }

    func testTimesOut() async {
        let (events, _) = AsyncThrowingStream<ClaudeStreamEvent, Error>.makeStream()
        await assertProbe(events, timeout: .milliseconds(50), throws: .timedOut)
    }

    private func assertProbe(
        _ events: AsyncThrowingStream<ClaudeStreamEvent, Error>,
        timeout: Duration = .seconds(5),
        throws expected: ClaudeLimitsProbe.Failure,
        line: UInt = #line
    ) async {
        do {
            _ = try await ClaudeLimitsProbe.firstSnapshot(in: events, timeout: timeout)
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? ClaudeLimitsProbe.Failure, expected, line: line)
        }
    }
}
