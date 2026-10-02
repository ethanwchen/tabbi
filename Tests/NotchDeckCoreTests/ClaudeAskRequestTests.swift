import XCTest
import NotchDeckCore

final class ClaudeAskRequestTests: XCTestCase {
    func testFirstQuestionStreamsPartialsWithAFastModelAndNoTools() {
        let arguments = ClaudeAskRequest.extraArguments()
        XCTAssertTrue(arguments.contains("--include-partial-messages"))
        XCTAssertEqual(value(after: "--model", in: arguments), "sonnet")
        XCTAssertEqual(value(after: "--tools", in: arguments), "")
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertFalse(arguments.contains("--resume"))
    }

    func testFollowUpResumesTheSession() {
        let arguments = ClaudeAskRequest.extraArguments(resuming: "abc-123")
        XCTAssertEqual(value(after: "--resume", in: arguments), "abc-123")
        XCTAssertEqual(value(after: "--tools", in: arguments), "")
    }

    func testEmptySessionIDDoesNotResume() {
        XCTAssertFalse(ClaudeAskRequest.extraArguments(resuming: "").contains("--resume"))
    }

    func testProcessFailureBecomesFirstStderrLine() async {
        let error = await failure(of: "echo; echo '  Error: not logged in  ' >&2; echo 'at foo' >&2; exit 3")
        XCTAssertEqual(ClaudeAskFailure(error: error), .process(detail: "Error: not logged in"))
    }

    func testSilentProcessFailureMentionsTheStatus() async {
        let error = await failure(of: "exit 7")
        XCTAssertEqual(
            ClaudeAskFailure(error: error),
            .process(detail: "Claude exited unexpectedly (status 7).")
        )
    }

    func testOtherErrorsUseTheirDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file doesn't exist."])
        XCTAssertEqual(ClaudeAskFailure(error: error), .process(detail: "The file doesn't exist."))
    }

    func testDemoConversationIsAFinishedExchangeThatCanFollowUp() {
        let demo = ClaudeAskConversation.demo
        XCTAssertEqual(demo.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(demo.messages.last?.status, .complete)
        XCTAssertFalse(demo.messages.last?.text.isEmpty ?? true)
        XCTAssertEqual(demo.phase, .idle)
        XCTAssertNotNil(demo.sessionID)
    }

    // MARK: - Helpers

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Runs a shell script through `StreamingProcess` and returns the error it throws.
    private func failure(of script: String) async -> Error {
        let lines = StreamingProcess.lines(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
        do {
            for try await _ in lines {}
        } catch {
            return error
        }
        XCTFail("expected the process to fail")
        return NSError(domain: "test", code: 0)
    }
}
