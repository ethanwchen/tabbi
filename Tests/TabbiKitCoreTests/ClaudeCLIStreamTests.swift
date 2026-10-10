import Foundation
import XCTest
@testable import TabbiKitCore

/// Runs `ClaudeCLI.stream` and `ClaudeLimitsProbe.run` against a fake `claude`:
/// a shell script that records its arguments, working directory and stdin
/// into its own folder, then prints canned stream-json. No real CLI, no
/// network, and every script finishes or is stopped by the code under test.
final class ClaudeCLIStreamTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCLIStreamTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private static let initLine = #"{"type":"system","subtype":"init","session_id":"s-1"}"#
    private static let deltaLine = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hel"}}}"#
    private static let assistantLine = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"},{"type":"tool_use","name":"x"},{"type":"text","text":" there"}]}}"#
    private static let resultLine = #"{"type":"result","subtype":"success","result":"Hello there","session_id":"s-1","is_error":false}"#
    private static let limitsLine = #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","unifiedWindows":{"five_hour":{"utilization":0.42,"resetsAt":1760000000},"seven_day":{"utilization":0.1}}}}"#

    // MARK: - Prompt mode

    func testPromptStreamParsesEveryLineInOrderAndSkipsNoise() async throws {
        let claude = try makeClaude(body: """
        printf '%s\\n' '\(Self.initLine)'
        echo 'not json at all'
        printf '%s\\n' '\(Self.deltaLine)'
        printf '%s\\n' '\(Self.assistantLine)'
        printf '%s' '\(Self.resultLine)'
        """)

        let events = try await Self.collect(ClaudeCLI.stream(executable: claude, prompt: "hi"))

        XCTAssertEqual(events, [
            .sessionStarted(sessionID: "s-1"),
            .other,
            .textDelta("Hel"),
            .assistantText("Hello there"),
            // The last line has no newline; it still arrives and parses.
            .result(ClaudeResult(text: "Hello there", sessionID: "s-1", isError: false)),
        ])
    }

    func testPromptGoesLastAfterDoubleDashVerbatim() async throws {
        let claude = try makeClaude(body: "printf '%s\\n' '\(Self.resultLine)'")
        let prompt = "--help\nit's \"quoted\" and $HOME stays literal"

        _ = try await Self.collect(ClaudeCLI.stream(
            executable: claude,
            prompt: prompt,
            extraArguments: ["--model", "haiku", "--resume", "s-1"]
        ))

        XCTAssertEqual(try recordedArguments(), [
            "-p", "--output-format", "stream-json", "--verbose",
            "--model", "haiku", "--resume", "s-1",
            "--", prompt,
        ])
    }

    func testRunsInTheTemporaryDirectorySoNoProjectSettingsApply() async throws {
        let claude = try makeClaude(body: "printf '%s\\n' '\(Self.resultLine)'")

        _ = try await Self.collect(ClaudeCLI.stream(executable: claude, prompt: "hi"))

        let cwd = try String(contentsOf: folder.appendingPathComponent("cwd"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // realpath, not resolvingSymlinksInPath: Foundation maps /private/var back to /var.
        let expected = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(expected) }
        XCTAssertEqual(cwd, String(cString: expected))
    }

    func testFailingCLIDeliversItsOutputThenThrowsWithStderr() async throws {
        let claude = try makeClaude(body: """
        printf '%s\\n' '\(Self.initLine)'
        echo '  Invalid API key. Please run /login  ' >&2
        exit 1
        """)

        var received: [ClaudeStreamEvent] = []
        do {
            for try await event in ClaudeCLI.stream(executable: claude, prompt: "hi") {
                received.append(event)
            }
            XCTFail("expected the stream to fail")
        } catch let failure as ProcessFailure {
            XCTAssertEqual(failure, ProcessFailure(status: 1, stderr: "Invalid API key. Please run /login"))
        }
        XCTAssertEqual(received, [.sessionStarted(sessionID: "s-1")])
    }

    func testMissingExecutableFailsInsteadOfHanging() async {
        let missing = folder.appendingPathComponent("no-such-claude")
        do {
            _ = try await Self.collect(ClaudeCLI.stream(executable: missing, prompt: "hi"))
            XCTFail("expected the stream to fail")
        } catch {
            XCTAssertFalse(error is ProcessFailure, "a launch error, not an exit status: \(error)")
        }
    }

    func testCancellingTheConsumerStopsTheProcess() async throws {
        let claude = try makeClaude(body: """
        printf '%s\\n' '\(Self.initLine)'
        exec /bin/sleep 30
        """)
        let stream = ClaudeCLI.stream(executable: claude, prompt: "hi")
        let (firstEvent, firstContinuation) = AsyncStream<ClaudeStreamEvent>.makeStream()

        let consumer = Task {
            for try await event in stream { firstContinuation.yield(event) }
        }
        var iterator = firstEvent.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first, .sessionStarted(sessionID: "s-1"))
        let pid = try recordedPID()
        XCTAssertTrue(Self.isAlive(pid), "the fake CLI is still running before the cancel")

        consumer.cancel()
        _ = await consumer.result

        try await Self.waitUntilGone(pid)
    }

    // MARK: - Input-line mode

    func testInputLineGoesToStdinAndNoPromptArgumentIsSent() async throws {
        let claude = try makeClaude(body: """
        cat > "$DIR/stdin"
        printf '%s\\n' '\(Self.resultLine)'
        """)
        let line = Data(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Café -p --"}]}}"#.utf8)
            + Data("\n".utf8)

        let events = try await Self.collect(ClaudeCLI.stream(
            executable: claude,
            inputLine: line,
            extraArguments: ["--include-partial-messages"]
        ))

        XCTAssertEqual(events, [.result(ClaudeResult(text: "Hello there", sessionID: "s-1", isError: false))])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("stdin")), line)
        XCTAssertEqual(try recordedArguments(), [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages",
        ])
    }

    func testInputLineLargerThanThePipeBufferIsDeliveredWhole() async throws {
        let claude = try makeClaude(body: """
        cat > "$DIR/stdin"
        printf '%s\\n' '\(Self.resultLine)'
        """)
        // About 1 MB, like a pasted screenshot as base64: far past the 64 KB pipe buffer.
        let payload = String(repeating: "A", count: 1_000_000)
        let line = Data(#"{"type":"user","data":"\#(payload)"}"#.utf8) + Data("\n".utf8)

        _ = try await Self.collect(ClaudeCLI.stream(executable: claude, inputLine: line))

        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("stdin")), line)
    }

    // MARK: - Limits probe end to end

    func testLimitsProbeReturnsTheFirstWindowAndStopsTheCLI() async throws {
        let claude = try makeClaude(body: """
        printf '%s\\n' '\(Self.initLine)'
        printf '%s\\n' '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}'
        printf '%s\\n' '\(Self.limitsLine)'
        exec /bin/sleep 30
        """)

        let snapshot = try await ClaudeLimitsProbe.run(executable: claude, timeout: .seconds(20))

        XCTAssertEqual(snapshot, ClaudeRateLimitSnapshot(
            status: "allowed",
            fiveHour: ClaudeUsageWindow(utilization: 0.42, resetsAt: Date(timeIntervalSince1970: 1_760_000_000)),
            sevenDay: ClaudeUsageWindow(utilization: 0.1, resetsAt: nil)
        ))
        XCTAssertEqual(try recordedArguments(), [
            "-p", "--output-format", "stream-json", "--verbose", "--model", "haiku", "--", "ok",
        ])
        // The probe never waits for the answer: the CLI is stopped right away.
        try await Self.waitUntilGone(try recordedPID())
    }

    func testLimitsProbeReportsAnErrorResult() async throws {
        let claude = try makeClaude(body: """
        printf '%s\\n' '{"type":"result","subtype":"error","result":"Not logged in","is_error":true}'
        """)

        do {
            _ = try await ClaudeLimitsProbe.run(executable: claude, timeout: .seconds(20))
            XCTFail("expected the probe to fail")
        } catch {
            XCTAssertEqual(error as? ClaudeLimitsProbe.Failure, .cliError("Not logged in"))
        }
    }

    func testLimitsProbeWithAnAPIKeyLoginReportsNoLimits() async throws {
        let claude = try makeClaude(body: """
        printf '%s\\n' '\(Self.initLine)'
        printf '%s\\n' '\(Self.resultLine)'
        """)

        do {
            _ = try await ClaudeLimitsProbe.run(executable: claude, timeout: .seconds(20))
            XCTFail("expected the probe to fail")
        } catch {
            XCTAssertEqual(error as? ClaudeLimitsProbe.Failure, .noLimitsReported)
        }
    }

    // MARK: - Helpers

    /// Writes an executable fake `claude` that records its arguments (NUL
    /// separated, so newlines in a prompt survive), its working directory and
    /// its pid, then runs `body` with `$DIR` set to the test folder.
    private func makeClaude(body: String) throws -> URL {
        let script = """
        #!/bin/sh
        DIR='\(folder.path)'
        printf '%s\\0' "$@" > "$DIR/args"
        pwd -P > "$DIR/cwd"
        echo $$ > "$DIR/pid"
        \(body)

        """
        let url = folder.appendingPathComponent("claude")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func recordedArguments() throws -> [String] {
        let data = try Data(contentsOf: folder.appendingPathComponent("args"))
        return data.split(separator: 0, omittingEmptySubsequences: false).dropLast()
            .map { String(decoding: $0, as: UTF8.self) }
    }

    private func recordedPID() throws -> pid_t {
        let text = try String(contentsOf: folder.appendingPathComponent("pid"), encoding: .utf8)
        return try XCTUnwrap(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func collect(
        _ stream: AsyncThrowingStream<ClaudeStreamEvent, Error>
    ) async throws -> [ClaudeStreamEvent] {
        var events: [ClaudeStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    /// Polls until `pid` no longer exists (Foundation reaps it once it exits).
    private static func waitUntilGone(_ pid: pid_t, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(10)
        while isAlive(pid) {
            if Date() > deadline {
                kill(pid, SIGKILL)
                XCTFail("the fake CLI (pid \(pid)) is still running", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
