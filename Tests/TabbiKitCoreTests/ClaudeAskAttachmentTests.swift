import XCTest
import TabbiKitCore

final class ClaudeAskAttachmentTests: XCTestCase {
    private var root: URL!
    private var history: ClaudeAskHistory!
    private var store: ClaudeAskAttachmentStore!
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeAskAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        history = ClaudeAskHistory(directory: root.appendingPathComponent("Claude Chats"))
        store = ClaudeAskAttachmentStore(stagingDirectory: root.appendingPathComponent("Staging"), history: history)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func exists(_ url: URL?) -> Bool {
        url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    // MARK: - Sizing

    func testLargeCapturesAreScaledToTheLongEdgeKeepingTheirShape() {
        XCTAssertTrue(ClaudeAskAttachment.fittedPixelSize(width: 3024, height: 1964) == (1568, 1018))
        XCTAssertTrue(ClaudeAskAttachment.fittedPixelSize(width: 1000, height: 4000) == (392, 1568))
    }

    func testSmallCapturesAreNeverScaledUp() {
        XCTAssertTrue(ClaudeAskAttachment.fittedPixelSize(width: 800, height: 600) == (800, 600))
        XCTAssertTrue(ClaudeAskAttachment.fittedPixelSize(width: 0, height: 0) == (1, 1))
        XCTAssertTrue(ClaudeAskAttachment.fittedPixelSize(width: 20_000, height: 1) == (1568, 1))
    }

    // MARK: - CLI input

    func testInputLineIsOneUserMessageWithImagesBeforeTheText() throws {
        let line = try ClaudeAskRequest.inputLine(prompt: "What is this?", images: [png, Data([9])])
        XCTAssertEqual(line.last, UInt8(ascii: "\n"))
        XCTAssertEqual(line.filter { $0 == UInt8(ascii: "\n") }.count, 1)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "user")
        let message = try XCTUnwrap(json["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
        let content = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "image", "text"])
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual((source["data"] as? String).flatMap { Data(base64Encoded: $0) }, png)
        XCTAssertNil(content[0]["text"])
        XCTAssertEqual(content[2]["text"] as? String, "What is this?")
        XCTAssertNil(content[2]["source"])
    }

    func testProcessReadsTheInputOnStdin() async throws {
        let input = try ClaudeAskRequest.inputLine(prompt: "hi", images: [Data(repeating: 7, count: 300_000)])
        var lines: [String] = []
        for try await line in StreamingProcess.lines(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [],
                                                     input: input) {
            lines.append(line)
        }
        XCTAssertEqual(lines, [String(decoding: input.dropLast(), as: UTF8.self)])
    }

    func testProcessThatIgnoresItsInputFinishesNormally() async throws {
        var lines: [String] = []
        let input = Data(repeating: 1, count: 2_000_000)
        for try await line in StreamingProcess.lines(executable: URL(fileURLWithPath: "/bin/sh"),
                                                     arguments: ["-c", "echo done"], input: input) {
            lines.append(line)
        }
        XCTAssertEqual(lines, ["done"])
    }

    // MARK: - Files

    func testStagedCaptureMovesBesideItsChatWhenKept() throws {
        let chatID = UUID()
        let attachment = try store.stage(pngData: png, pixelWidth: 40, pixelHeight: 30)
        XCTAssertEqual(attachment.pixelWidth, 40)
        let staged = try XCTUnwrap(store.url(for: attachment, in: chatID))
        XCTAssertEqual(staged.deletingLastPathComponent().lastPathComponent, "Staging")
        XCTAssertEqual(store.data(for: attachment, in: chatID), png)

        try store.keep([attachment], in: chatID)
        let kept = try XCTUnwrap(store.url(for: attachment, in: chatID))
        XCTAssertEqual(kept.deletingLastPathComponent(), history.attachmentsDirectory(for: chatID))
        XCTAssertFalse(exists(staged))
        XCTAssertEqual(store.data(for: attachment, in: chatID), png)

        // Keeping again (the chat is saved after every answer) changes nothing.
        try store.keep([attachment], in: chatID)
        XCTAssertEqual(store.data(for: attachment, in: chatID), png)
        store.discard([attachment])
        XCTAssertTrue(exists(kept))
    }

    func testDiscardAndClearStagingDeleteUnsavedCaptures() throws {
        let first = try store.stage(pngData: png, pixelWidth: 1, pixelHeight: 1)
        let second = try store.stage(pngData: png, pixelWidth: 1, pixelHeight: 1)
        store.discard([first])
        XCTAssertNil(store.url(for: first, in: UUID()))
        XCTAssertNotNil(store.url(for: second, in: UUID()))
        store.clearStaging()
        XCTAssertNil(store.url(for: second, in: UUID()))
    }

    func testWithoutAHistoryCapturesStayStagedUntilDiscarded() throws {
        let store = ClaudeAskAttachmentStore(stagingDirectory: root.appendingPathComponent("Staging"), history: nil)
        let attachment = try store.stage(pngData: png, pixelWidth: 1, pixelHeight: 1)
        try store.keep([attachment], in: UUID())
        XCTAssertNotNil(store.url(for: attachment, in: UUID()))
        store.discard([attachment])
        XCTAssertNil(store.url(for: attachment, in: UUID()))
    }

    func testDeletingChatsDeletesTheirScreenshots() throws {
        let kept = UUID(), deleted = UUID()
        for chatID in [kept, deleted] {
            try history.save(ClaudeAskChat(id: chatID, createdAt: Date(), updatedAt: Date(), sessionID: nil,
                                           messages: [.init(role: .user, text: "q"), .init(role: .assistant, text: "a")]))
            try store.keep([try store.stage(pngData: png, pixelWidth: 1, pixelHeight: 1)], in: chatID)
        }
        try history.delete(deleted)
        XCTAssertFalse(exists(history.attachmentsDirectory(for: deleted)))
        XCTAssertTrue(exists(history.attachmentsDirectory(for: kept)))

        let unrelated = history.directory.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try history.deleteAll()
        XCTAssertFalse(exists(history.attachmentsDirectory(for: kept)))
        XCTAssertTrue(history.chats().isEmpty)
        XCTAssertTrue(exists(unrelated))
    }

    // MARK: - Conversation and history

    func testScreenshotsStayWithTheirQuestionThroughSaveAndRestore() throws {
        let shot = ClaudeAskAttachment(pixelWidth: 1568, pixelHeight: 980)
        var conversation = ClaudeAskConversation()
        XCTAssertNil(conversation.begin(prompt: "  ", attachments: [shot]))
        conversation.begin(prompt: "What is this error?", attachments: [shot])
        conversation.apply(.result(ClaudeResult(text: "A typo.", sessionID: "s1", isError: false)))
        XCTAssertEqual(conversation.messages.map(\.attachments), [[shot], []])

        let chat = try XCTUnwrap(conversation.savedChat())
        XCTAssertEqual(chat.attachments, [shot])
        try history.save(chat)
        let loaded = try XCTUnwrap(history.load(chat.id))
        XCTAssertEqual(loaded.messages.first?.attachments, [shot])
        XCTAssertEqual(ClaudeAskConversation(restoring: loaded).messages.first?.attachments, [shot])
    }

    func testRetryKeepsTheScreenshots() {
        let shot = ClaudeAskAttachment(pixelWidth: 10, pixelHeight: 10)
        var conversation = ClaudeAskConversation()
        conversation.begin(prompt: "Why?", attachments: [shot])
        conversation.fail(.claudeNotFound)
        XCTAssertEqual(conversation.takeRetryQuestion(), ClaudeAskQuestion(text: "Why?", attachments: [shot]))
    }

    func testMessagesWithoutScreenshotsAreWrittenAndReadAsBefore() throws {
        let encoded = try JSONEncoder().encode(ClaudeAskChat.Message(role: .user, text: "hi"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["attachments"])

        let old = Data(#"{"role":"user","text":"hi","status":"complete"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ClaudeAskChat.Message.self, from: old).attachments, [])
    }
}
