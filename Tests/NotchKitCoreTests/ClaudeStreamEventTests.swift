import XCTest
@testable import NotchKitCore

final class ClaudeStreamEventTests: XCTestCase {
    func testRateLimitEventParsesBothWindows() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1790912400,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.05,"resetsAt":1790912400},"seven_day":{"utilization":0.04,"resetsAt":1791460800}}},"session_id":"s"}"#
        guard case .rateLimit(let snapshot) = ClaudeStreamEvent.parse(line: line) else {
            return XCTFail("expected rateLimit")
        }
        XCTAssertEqual(snapshot.status, "allowed")
        XCTAssertEqual(snapshot.fiveHour?.utilization, 0.05)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1790912400))
        XCTAssertEqual(snapshot.sevenDay?.utilization, 0.04)
    }

    func testRateLimitWithoutWindowsHasNilWindows() {
        let line = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: line),
            .rateLimit(ClaudeRateLimitSnapshot(status: "allowed", fiveHour: nil, sevenDay: nil))
        )
    }

    func testSystemInitCarriesSessionID() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc"}"#
        XCTAssertEqual(ClaudeStreamEvent.parse(line: line), .sessionStarted(sessionID: "abc"))
    }

    func testAssistantMessageJoinsTextBlocksAndSkipsToolUse() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hel"},{"type":"tool_use","name":"x"},{"type":"text","text":"lo"}]}}"#
        XCTAssertEqual(ClaudeStreamEvent.parse(line: line), .assistantText("Hello"))
    }

    func testTextDelta() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}}"#
        XCTAssertEqual(ClaudeStreamEvent.parse(line: line), .textDelta("Hi"))
    }

    func testResultSuccessAndError() {
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: #"{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"s1"}"#),
            .result(ClaudeResult(text: "ok", sessionID: "s1", isError: false))
        )
        XCTAssertEqual(
            ClaudeStreamEvent.parse(line: #"{"type":"result","subtype":"error_max_turns","session_id":"s1"}"#),
            .result(ClaudeResult(text: nil, sessionID: "s1", isError: true))
        )
    }

    func testGarbageIsOther() {
        XCTAssertEqual(ClaudeStreamEvent.parse(line: "not json"), .other)
        XCTAssertEqual(ClaudeStreamEvent.parse(line: #"{"no":"type"}"#), .other)
        XCTAssertEqual(ClaudeStreamEvent.parse(line: #"{"type":"user"}"#), .other)
    }
}
