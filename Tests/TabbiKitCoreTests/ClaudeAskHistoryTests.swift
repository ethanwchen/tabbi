import XCTest
import TabbiKitCore

final class ClaudeAskHistoryTests: XCTestCase {
    private var directory: URL!
    private var history: ClaudeAskHistory!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAskHistoryTests-\(UUID().uuidString)", isDirectory: true)
        history = ClaudeAskHistory(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func answered(_ prompt: String, _ answer: String, session: String? = "s1",
                          in conversation: inout ClaudeAskConversation) {
        conversation.begin(prompt: prompt)
        conversation.apply(.result(ClaudeResult(text: answer, sessionID: session, isError: false)))
    }

    // MARK: - Saving a conversation

    func testEmptyOrUnansweredConversationHasNothingToSave() {
        var conversation = ClaudeAskConversation()
        XCTAssertNil(conversation.savedChat())
        conversation.begin(prompt: "hi")
        conversation.fail(.claudeNotFound)
        XCTAssertNil(conversation.savedChat())
    }

    func testSavedChatKeepsFinishedExchangesAndDropsFailedOnes() throws {
        var conversation = ClaudeAskConversation(startedAt: start)
        answered("first", "A1", in: &conversation)
        conversation.begin(prompt: "second")
        conversation.apply(.result(ClaudeResult(text: "boom", sessionID: "s1", isError: true)))

        let chat = try XCTUnwrap(conversation.savedChat(updatedAt: start.addingTimeInterval(60)))
        XCTAssertEqual(chat.id, conversation.chatID)
        XCTAssertEqual(chat.createdAt, start)
        XCTAssertEqual(chat.updatedAt, start.addingTimeInterval(60))
        XCTAssertEqual(chat.sessionID, "s1")
        XCTAssertEqual(chat.messages.map(\.text), ["first", "A1"])
    }

    func testStreamingAnswerIsSavedAsStoppedAndEmptyOneIsLeftOut() throws {
        var conversation = ClaudeAskConversation()
        answered("first", "A1", in: &conversation)
        conversation.begin(prompt: "second")
        XCTAssertEqual(try XCTUnwrap(conversation.savedChat()).messages.count, 2)

        conversation.apply(.textDelta("Part"))
        let chat = try XCTUnwrap(conversation.savedChat())
        XCTAssertEqual(chat.messages.map(\.text), ["first", "A1", "second", "Part"])
        XCTAssertEqual(chat.messages.last?.status, .stopped)
    }

    func testRestoringContinuesTheChatWithItsSession() throws {
        var original = ClaudeAskConversation(startedAt: start)
        answered("What is Swift?", "A language.", session: "abc", in: &original)
        let chat = try XCTUnwrap(original.savedChat(updatedAt: start))

        var restored = ClaudeAskConversation(restoring: chat)
        XCTAssertEqual(restored.chatID, chat.id)
        XCTAssertEqual(restored.sessionID, "abc")
        XCTAssertEqual(restored.phase, .idle)
        XCTAssertEqual(restored.messages.map(\.text), ["What is Swift?", "A language."])
        XCTAssertEqual(Set(restored.messages.map(\.id)).count, 2)

        XCTAssertEqual(restored.begin(prompt: "Who made it?"), "Who made it?")
        XCTAssertEqual(Set(restored.messages.map(\.id)).count, 4)
        XCTAssertEqual(restored.savedChat(updatedAt: start)?.id, chat.id)
    }

    func testResetStartsANewChat() {
        var conversation = ClaudeAskConversation(startedAt: start)
        let first = conversation.chatID
        conversation.reset(at: start.addingTimeInterval(10))
        XCTAssertNotEqual(conversation.chatID, first)
        XCTAssertEqual(conversation.startedAt, start.addingTimeInterval(10))
    }

    func testTitleIsTheFirstQuestionOnOneShortLine() {
        func chat(_ question: String) -> ClaudeAskChat {
            ClaudeAskChat(id: UUID(), createdAt: start, updatedAt: start, sessionID: nil,
                          messages: [.init(role: .user, text: question), .init(role: .assistant, text: "ok")])
        }
        XCTAssertEqual(chat("Explain\n  this   code").title, "Explain this code")
        let long = chat(String(repeating: "word ", count: 30)).title
        XCTAssertLessThanOrEqual(long.count, 60)
        XCTAssertTrue(long.hasSuffix("\u{2026}"))
        XCTAssertEqual(ClaudeAskChat(id: UUID(), createdAt: start, updatedAt: start,
                                     sessionID: nil, messages: []).title, "Untitled chat")
    }

    // MARK: - History on disk

    func testSaveListLoadAndDelete() throws {
        XCTAssertEqual(history.chats(), [])
        var older = ClaudeAskConversation(startedAt: start)
        answered("older", "1", in: &older)
        var newer = ClaudeAskConversation(startedAt: start)
        answered("newer", "2", session: nil, in: &newer)
        let olderChat = try XCTUnwrap(older.savedChat(updatedAt: start.addingTimeInterval(5)))
        let newerChat = try XCTUnwrap(newer.savedChat(updatedAt: start.addingTimeInterval(50)))
        try history.save(olderChat)
        try history.save(newerChat)

        XCTAssertEqual(history.chats(), [newerChat, olderChat])
        XCTAssertEqual(try history.load(olderChat.id), olderChat)

        try history.delete(olderChat.id)
        try history.delete(olderChat.id)
        XCTAssertEqual(history.chats(), [newerChat])
        XCTAssertNil(try history.load(olderChat.id))
    }

    func testSavingAgainReplacesTheChat() throws {
        var conversation = ClaudeAskConversation(startedAt: start)
        answered("one", "1", in: &conversation)
        try history.save(XCTUnwrap(conversation.savedChat(updatedAt: start)))
        answered("two", "2", in: &conversation)
        try history.save(XCTUnwrap(conversation.savedChat(updatedAt: start.addingTimeInterval(1))))
        XCTAssertEqual(history.chats().map { $0.messages.count }, [4])
    }

    func testFilesAreVersionedAndCorruptOnesAreSkipped() throws {
        var conversation = ClaudeAskConversation(startedAt: start)
        answered("kept", "yes", in: &conversation)
        let chat = try XCTUnwrap(conversation.savedChat(updatedAt: start))
        try history.save(chat)
        XCTAssertEqual(VersionedJSON.version(of: try Data(contentsOf: history.fileURL(for: chat.id))),
                       ClaudeAskHistory.schema.current)

        let corrupt = history.fileURL(for: UUID())
        try Data("not json".utf8).write(to: corrupt)
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: unrelated)
        XCTAssertEqual(history.chats(), [chat])

        try history.deleteAll()
        XCTAssertEqual(history.chats(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testFileNameDecidesTheChatID() throws {
        var conversation = ClaudeAskConversation(startedAt: start)
        answered("copied", "yes", in: &conversation)
        let chat = try XCTUnwrap(conversation.savedChat(updatedAt: start))
        try history.save(chat)
        let copyID = UUID()
        try FileManager.default.copyItem(at: history.fileURL(for: chat.id), to: history.fileURL(for: copyID))
        XCTAssertEqual(try history.load(copyID)?.id, copyID)
        XCTAssertEqual(Set(history.chats().map(\.id)), [chat.id, copyID])
    }

    func testVersionZeroDocumentStillLoads() throws {
        let id = UUID()
        let legacy = """
        {"id":"\(id.uuidString)","createdAt":"2027-01-15T08:00:00Z","updatedAt":"2027-01-15T08:01:00Z",
         "messages":[{"role":"user","text":"hi","status":"complete"},
                     {"role":"assistant","text":"hello","status":"complete"}]}
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: history.fileURL(for: id))
        let chat = try XCTUnwrap(history.load(id))
        XCTAssertNil(chat.sessionID)
        XCTAssertEqual(chat.title, "hi")
    }
}
