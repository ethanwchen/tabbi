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

    func testLostSessionDropsTheSessionAndReturnsTheQuestionOnce() {
        let screenshot = ClaudeAskAttachment(pixelWidth: 10, pixelHeight: 10)
        var conversation = ClaudeAskConversation(restoring: ClaudeAskChat(
            id: UUID(), createdAt: Date(), updatedAt: Date(), sessionID: "gone",
            messages: [.init(role: .user, text: "ok"), .init(role: .assistant, text: "fine")]
        ))
        conversation.begin(prompt: "more", attachments: [screenshot])
        conversation.fail(.process(detail: "No conversation found with session ID: gone"))
        XCTAssertEqual(conversation.takeQuestionForLostSession(),
                       ClaudeAskQuestion(text: "more", attachments: [screenshot]))
        XCTAssertNil(conversation.sessionID)
        XCTAssertEqual(conversation.messages.map(\.text), ["ok", "fine"])

        conversation.begin(prompt: "more")
        conversation.fail(.process(detail: "No conversation found with session ID: gone"))
        XCTAssertNil(conversation.takeQuestionForLostSession())
        XCTAssertNotNil(conversation.failure)
    }

    func testALostSessionIsAskedAgainWithTheChatSoFar() throws {
        var conversation = ClaudeAskConversation(restoring: ClaudeAskChat(
            id: UUID(), createdAt: Date(), updatedAt: Date(), sessionID: "gone", sessionProvider: .claudeCLI,
            messages: [.init(role: .user, text: "Retry policy?"), .init(role: .assistant, text: "Back off and retry.")]
        ))
        conversation.begin(prompt: "And jitter?")
        let resumed = conversation.request(prompt: "And jitter?", provider: .claudeCLI)
        XCTAssertEqual(resumed.resumeSessionID, "gone")
        XCTAssertEqual(resumed.messages, [.user("And jitter?")], "the session still has the chat")
        conversation.fail(.process(detail: "No conversation found with session ID: gone"))
        let question = try XCTUnwrap(conversation.takeQuestionForLostSession())

        conversation.begin(prompt: question.text)
        let seeded = conversation.request(prompt: question.text, provider: .claudeCLI)
        XCTAssertNil(seeded.resumeSessionID)
        XCTAssertEqual(seeded.messages, [.user("Retry policy?"), .assistant("Back off and retry."), .user("And jitter?")])
        XCTAssertEqual(conversation.messages.last(where: { $0.role == .user })?.text, "And jitter?",
                       "the bubble shows only what the user typed")

        conversation.apply(.sessionStarted("fresh"), from: .claudeCLI)
        conversation.apply(.finished(text: "Add randomness."), from: .claudeCLI)
        conversation.begin(prompt: "Thanks")
        let next = conversation.request(prompt: "Thanks", provider: .claudeCLI)
        XCTAssertEqual(next.resumeSessionID, "fresh", "the new session carries on by itself")
        XCTAssertEqual(next.messages, [.user("Thanks")])
    }

    func testANewChatSendsTheQuestionAsTypedWithItsScreenshots() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi")
        let request = conversation.request(prompt: "Hi", images: [Data([1])], provider: .openAI, system: "Be brief.")
        XCTAssertEqual(request.messages, [.user("Hi", images: [Data([1])])])
        XCTAssertEqual(request.system, "Be brief.")
        XCTAssertEqual(request.model, "", "the provider fills in the user's model")
    }

    func testAnotherProviderNeverResumesASessionItDoesNotHold() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Retry policy?")
        conversation.apply(.sessionStarted("claude-1"), from: .claudeCLI)
        conversation.apply(.finished(text: "Back off."), from: .claudeCLI)
        conversation.begin(prompt: "Jitter?")

        for provider in [AIProviderID.codexCLI, .gemini, .ollama] {
            let request = conversation.request(prompt: "Jitter?", provider: provider)
            XCTAssertNil(request.resumeSessionID, "\(provider)")
            XCTAssertEqual(request.messages, [.user("Retry policy?"), .assistant("Back off."), .user("Jitter?")])
        }
    }

    func testTheHistoryKeepsTheLatestExchangesWithinTheLimit() {
        var conversation = ClaudeAskConversation(restoring: ClaudeAskChat(
            id: UUID(), createdAt: Date(), updatedAt: Date(), sessionID: nil,
            messages: [.init(role: .user, text: String(repeating: "a", count: 50)), .init(role: .assistant, text: "old"),
                       .init(role: .user, text: "recent"), .init(role: .assistant, text: "latest")]
        ))
        conversation.begin(prompt: "Next")
        let request = conversation.request(prompt: "Next", provider: .anthropic, transcriptLimit: 30)
        XCTAssertEqual(request.messages, [.user("recent"), .assistant("latest"), .user("Next")],
                       "a whole exchange goes, never half of one")
    }

    func testProviderEventsStreamIntoTheAnswer() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi")
        conversation.apply(.textDelta("Hel"), from: .ollama)
        XCTAssertEqual(conversation.messages.last?.text, "Hel")
        XCTAssertTrue(conversation.isStreaming)
        conversation.apply(.textDelta("lo"), from: .ollama)
        conversation.apply(.finished(text: nil), from: .ollama)
        XCTAssertEqual(conversation.messages.last?.text, "Hello")
        XCTAssertEqual(conversation.messages.last?.status, .complete)
        XCTAssertNil(conversation.sessionID, "an API has no session")

        conversation.begin(prompt: "Again")
        conversation.apply(.textDelta("draft"), from: .codexCLI)
        conversation.apply(.finished(text: "Final answer"), from: .codexCLI)
        XCTAssertEqual(conversation.messages.last?.text, "Final answer", "the reported answer wins")
    }

    func testAnEmptyAnswerFailsNamingTheAssistant() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi")
        conversation.apply(.finished(text: nil), from: .gemini)
        XCTAssertEqual(conversation.failure, .process(detail: "Gemini ended without answering."))
    }

    func testEachAnswerRemembersWhoWasAsked() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi", provider: .ollama)
        conversation.fail(.process(detail: "Ollama is not running."))
        conversation.begin(prompt: "Again", provider: .gemini)
        let answers = conversation.messages.filter { $0.role == .assistant }
        XCTAssertEqual(answers.map(\.provider), [.ollama, .gemini])
        XCTAssertEqual(answers.first?.status, .failed)
        XCTAssertNil(conversation.messages.first?.provider, "questions name no provider")
    }

    func testTheSessionsToolIsSavedAndRestored() throws {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi")
        conversation.apply(.sessionStarted("codex-1"), from: .codexCLI)
        conversation.apply(.finished(text: "Hello"), from: .codexCLI)
        let chat = try XCTUnwrap(conversation.savedChat())
        XCTAssertEqual(chat.sessionProvider, .codexCLI)
        let restored = ClaudeAskConversation(restoring: chat)
        XCTAssertEqual(restored.sessionProvider, .codexCLI)
        XCTAssertEqual(restored.sessionID, "codex-1")
    }

    func testAnotherProvidersAnswerDropsTheToolsSession() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi")
        conversation.apply(.result(ClaudeResult(text: "Hello", sessionID: "s1", isError: false)))
        conversation.begin(prompt: "And the API?")
        conversation.apply(.textDelta("Sure"), from: .anthropic)
        conversation.apply(.finished(text: nil), from: .anthropic)
        XCTAssertNil(conversation.sessionID)
        XCTAssertNil(conversation.sessionProvider)

        conversation.begin(prompt: "Back to Claude Code")
        let request = conversation.request(prompt: "Back to Claude Code", provider: .claudeCLI)
        XCTAssertNil(request.resumeSessionID, "the old session never saw the API's exchange")
        XCTAssertEqual(request.messages.map(\.text), ["Hi", "Hello", "And the API?", "Sure", "Back to Claude Code"])
    }

    func testTheSameToolsAnswerKeepsItsSession() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Hi")
        conversation.apply(.sessionStarted("codex-1"), from: .codexCLI)
        conversation.apply(.finished(text: "Hello"), from: .codexCLI)
        conversation.begin(prompt: "More")
        conversation.apply(.sessionStarted("codex-1"), from: .codexCLI)
        conversation.apply(.textDelta("Yes"), from: .codexCLI)
        conversation.apply(.finished(text: nil), from: .codexCLI)
        XCTAssertEqual(conversation.sessionID, "codex-1")
    }

    func testOtherFailuresKeepTheSession() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "ok")
        conversation.apply(.result(ClaudeResult(text: "fine", sessionID: "s1", isError: false)))
        conversation.begin(prompt: "boom")
        conversation.fail(.process(detail: "exit 1"))
        XCTAssertNil(conversation.takeQuestionForLostSession())
        XCTAssertEqual(conversation.sessionID, "s1")
        XCTAssertEqual(conversation.failure, .process(detail: "exit 1"))
    }

    func testClaudeNotFoundFailureMarksAnswerFailed() {
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "hi")
        conversation.fail(.notInstalled(.claudeCLI))
        XCTAssertEqual(conversation.phase, .failed(.notInstalled(.claudeCLI)))
        XCTAssertEqual(answer(conversation)?.status, .failed)
        XCTAssertEqual(conversation.failure, .notInstalled(.claudeCLI))
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
