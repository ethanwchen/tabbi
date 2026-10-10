import XCTest
import TabbiKitCore

final class ClaudeAskFailureTests: XCTestCase {
    func testProviderErrorsBecomeSetupOrTheirOwnWords() {
        XCTAssertEqual(ClaudeAskFailure(error: AIProviderError.notInstalled, provider: .codexCLI), .notInstalled(.codexCLI))
        XCTAssertEqual(ClaudeAskFailure(error: AIProviderError.missingAPIKey, provider: .openAI), .needsKey(.openAI))
        XCTAssertEqual(ClaudeAskFailure(error: AIProviderError.unreachable(detail: nil), provider: .ollama),
                       .process(detail: "Ollama is not running. Open Ollama and try again."))
        XCTAssertTrue(ClaudeAskFailure.needsKey(.openAI).needsSetup)
        XCTAssertFalse(ClaudeAskFailure.process(detail: "x").needsSetup)
    }

    func testSetupWordsNameTheProvider() {
        XCTAssertEqual(ClaudeAskFailure.notInstalled(.geminiCLI).setupTitle, "Set up Gemini to ask questions")
        XCTAssertEqual(ClaudeAskFailure.notInstalled(.geminiCLI).setupAction, "Set up Gemini")
        XCTAssertEqual(ClaudeAskFailure.needsKey(.anthropic).setupTitle, "Add your Claude API key")
        XCTAssertEqual(ClaudeAskFailure.noProvider.setupAction, "Choose AI")
        XCTAssertEqual(ClaudeAskFailure.process(detail: "boom").title(assistant: "Codex"), "Codex couldn't answer")
        XCTAssertEqual(ClaudeAskFailure.process(detail: "boom").detail, "boom")
    }

    func testProcessFailureBecomesFirstStderrLine() async {
        let error = await failure(of: "echo; echo '  Error: not logged in  ' >&2; echo 'at foo' >&2; exit 3")
        XCTAssertEqual(ClaudeAskFailure(error: error, provider: .claudeCLI), .process(detail: "Error: not logged in"))
    }

    func testSilentProcessFailureMentionsTheStatus() async {
        let error = await failure(of: "exit 7")
        XCTAssertEqual(
            ClaudeAskFailure(error: error, provider: .claudeCLI),
            .process(detail: "Claude exited unexpectedly (status 7).")
        )
    }

    func testOtherErrorsUseTheirDescription() {
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "The file doesn't exist."])
        XCTAssertEqual(ClaudeAskFailure(error: error, provider: .claudeCLI), .process(detail: "The file doesn't exist."))
    }

    func testDemoConversationIsAFinishedExchangeThatCanFollowUp() {
        let demo = ClaudeAskConversation.demo
        XCTAssertEqual(demo.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertTrue(demo.messages.allSatisfy { $0.status == .complete })
        XCTAssertFalse(demo.messages.last?.text.isEmpty ?? true)
        XCTAssertEqual(demo.phase, .idle)
        XCTAssertNotNil(demo.sessionID)
    }

    // MARK: - Helpers

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
