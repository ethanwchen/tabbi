import XCTest
import TabbiKitCore

final class ClaudeAskConversationTests: XCTestCase {
    private func answer(_ conversation: ClaudeAskConversation) -> ClaudeAskMessage? {
        conversation.messages.last(where: { $0.role == .assistant })
    }

    func testBeginAddsUserAndStreamingAssistantMessages() {
        var conversation = ClaudeAskConversation()
        XCTAssertEqual(conversation.begin(prompt: "  What is 2+2?\n"), "What is 2+2?")
        XCTAssertTrue(conversation.isStreaming)
        XCTAssertEqual(conversation.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(conversation.messages[0].text, "What is 2+2?")
        XCTAssertEqual(answer(conversation)?.status, .streaming)
        XCTAssertEqual(answer(conversation)?.text, "")
    }

    func testBlankPromptOrBusyConversationIsRejected() {
        var conversation = ClaudeAskConversation()
        XCTAssertNil(conversation.begin(prompt: "  \n "))
        XCTAssertTrue(conversation.isEmpty)
        conversation.begin(prompt: "one")
        XCTAssertNil(conversation.begin(prompt: "two"))
        XCTAssertEqual(conversation.messages.count, 2)
    }

    func testDeltasAccumulateAndResultReplacesPartialText() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.sessionStarted(sessionID: "s1"))
        conversation.apply(.textDelta("Hel"))
        conversation.apply(.textDelta("lo"))
        XCTAssertEqual(answer(conversation)?.text, "Hello")
        XCTAssertEqual(answer(conversation)?.status, .streaming)

        conversation.apply(.result(ClaudeResult(text: "Hello there!", sessionID: "s1", isError: false)))
        XCTAssertEqual(answer(conversation)?.text, "Hello there!")
        XCTAssertEqual(answer(conversation)?.status, .complete)
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertEqual(conversation.sessionID, "s1")
    }

    func testCompleteAssistantMessageSupersedesDeltas() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.textDelta("Hel"))
        conversation.apply(.assistantText("Hello"))
        XCTAssertEqual(answer(conversation)?.text, "Hello")
        conversation.apply(.textDelta("More"))
        XCTAssertEqual(answer(conversation)?.text, "Hello\n\nMore")
    }

    func testResultWithoutTextKeepsStreamedText() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.textDelta("Streamed"))
        conversation.apply(.result(ClaudeResult(text: nil, sessionID: nil, isError: false)))
        XCTAssertEqual(answer(conversation)?.text, "Streamed")
        XCTAssertEqual(answer(conversation)?.status, .complete)
    }

    func testErrorResultBecomesFailureWithSummarizedDetail() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.result(ClaudeResult(text: "\nAPI Error: overloaded\nstack…", sessionID: "s1", isError: true)))
        XCTAssertEqual(conversation.phase, .failed(.process(detail: "API Error: overloaded")))
        XCTAssertEqual(answer(conversation)?.status, .failed)
        XCTAssertEqual(conversation.sessionID, "s1")
    }

    func testErrorResultWithoutTextGetsGenericDetail() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.result(ClaudeResult(text: nil, sessionID: nil, isError: true)))
        guard case .failed(.process(let detail)) = conversation.phase else { return XCTFail("expected failure") }
        XCTAssertFalse(detail.isEmpty)
    }

    func testFollowUpKeepsSessionAndHistory() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "first")
        conversation.apply(.sessionStarted(sessionID: "s1"))
        conversation.apply(.result(ClaudeResult(text: "A1", sessionID: "s1", isError: false)))
        XCTAssertEqual(conversation.begin(prompt: "second"), "second")
        XCTAssertEqual(conversation.sessionID, "s1")
        conversation.apply(.textDelta("A2"))
        XCTAssertEqual(conversation.messages.map(\.text), ["first", "A1", "second", "A2"])
        XCTAssertEqual(Set(conversation.messages.map(\.id)).count, 4)
    }

    func testFinishWithoutResultKeepsTextOrFails() {
        var withText = ClaudeAskConversation()
        withText.begin(prompt: "hi")
        withText.apply(.textDelta("partial"))
        withText.finish()
        XCTAssertEqual(withText.phase, .idle)
        XCTAssertEqual(answer(withText)?.status, .complete)

        var empty = ClaudeAskConversation()
        empty.begin(prompt: "hi")
        empty.finish()
        guard case .failed(.process) = empty.phase else { return XCTFail("expected failure") }
    }

    func testCancelKeepsPartialTextAndIgnoresLateEvents() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.textDelta("Part"))
        conversation.cancel()
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertEqual(answer(conversation)?.status, .stopped)
        conversation.apply(.textDelta("ial"))
        conversation.finish()
        XCTAssertEqual(answer(conversation)?.text, "Part")
        XCTAssertEqual(answer(conversation)?.status, .stopped)
    }

    func testRetryRemovesFailedExchangeAndReturnsPrompt() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "ok")
        conversation.apply(.result(ClaudeResult(text: "fine", sessionID: "s1", isError: false)))
        conversation.begin(prompt: "boom")
        conversation.fail(.process(detail: "exit 1"))
        XCTAssertEqual(conversation.takeRetryQuestion(), ClaudeAskQuestion(text: "boom"))
        XCTAssertEqual(conversation.messages.map(\.text), ["ok", "fine"])
        XCTAssertEqual(conversation.phase, .idle)
        XCTAssertNil(conversation.takeRetryQuestion())
    }

    func testClaudeNotFoundFailureMarksAnswerFailed() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.fail(.claudeNotFound)
        XCTAssertEqual(conversation.phase, .failed(.claudeNotFound))
        XCTAssertEqual(answer(conversation)?.status, .failed)
        XCTAssertEqual(conversation.failure, .claudeNotFound)
    }

    func testFailureClearsWhenTheNextQuestionStarts() {
        var conversation = ClaudeAskConversation()
        XCTAssertNil(conversation.failure)
        conversation.begin(prompt: "hi")
        conversation.fail(.process(detail: "exit 1"))
        XCTAssertEqual(conversation.failure, .process(detail: "exit 1"))
        conversation.begin(prompt: "again")
        XCTAssertNil(conversation.failure)
    }

    func testResetStartsFreshWithNewIDs() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.apply(.sessionStarted(sessionID: "s1"))
        let oldIDs = Set(conversation.messages.map(\.id))
        conversation.reset()
        XCTAssertTrue(conversation.isEmpty)
        XCTAssertNil(conversation.sessionID)
        XCTAssertEqual(conversation.phase, .idle)
        conversation.begin(prompt: "again")
        XCTAssertTrue(oldIDs.isDisjoint(with: conversation.messages.map(\.id)))
    }

    func testSummarizeTakesFirstLineAndTruncates() {
        XCTAssertNil(ClaudeAskConversation.summarize(nil))
        XCTAssertNil(ClaudeAskConversation.summarize(" \n "))
        XCTAssertEqual(ClaudeAskConversation.summarize("\n  boom \nmore"), "boom")
        let long = String(repeating: "x", count: 300)
        let summary = ClaudeAskConversation.summarize(long, limit: 20)
        XCTAssertEqual(summary?.count, 20)
        XCTAssertEqual(summary?.hasSuffix("…"), true)
    }
}
