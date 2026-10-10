import AppKit
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Drives `ClaudeAskSession`'s retry, New chat, delete and screenshot paths
/// against a scripted hosted API (no network), and reads the chat history
/// back from disk the way the next launch would.
@MainActor
final class ClaudeAskSessionHistoryTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ask-history-\(UUID().uuidString)")

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
        // Snapshot runs stage screenshots under a folder named after the edition root.
        try? FileManager.default.removeItem(at: stagingRoot)
    }

    // MARK: - Retry

    func testRetryAfterAnErrorSendsTheQuestionAgainAndSavesOneExchange() async throws {
        let api = ScriptedAPI([.status(500), .answer(["Use ", "backoff."])])
        let session = makeSession(api)
        session.ask("What retry policy should I use?")
        await waitUntil { !session.isStreaming && session.conversation.failure != nil }
        XCTAssertEqual(session.conversation.failure?.needsSetup, false, "a server error is retried, not set up")
        XCTAssertNil(session.setupNeeded)
        XCTAssertTrue(session.savedChats.isEmpty, "a failed exchange is never saved")

        session.retry()
        await waitUntil { !session.isStreaming }
        XCTAssertNil(session.conversation.failure)
        XCTAssertEqual(session.conversation.messages.map(\.text), ["What retry policy should I use?", "Use backoff."],
                       "the failed exchange is replaced, not repeated")
        XCTAssertEqual(api.requestCount, 2)
        XCTAssertEqual(try api.lastUserText(at: 0), "What retry policy should I use?")
        XCTAssertEqual(try api.lastUserText(at: 1), "What retry policy should I use?")

        XCTAssertEqual(session.savedChats.map(\.id), [session.conversation.chatID])
        let reloaded = makeSession(ScriptedAPI([]))
        XCTAssertEqual(reloaded.savedChats.first?.messages.map(\.text),
                       ["What retry policy should I use?", "Use backoff."])
    }

    func testRetryDoesNothingWithoutAFailure() async {
        let api = ScriptedAPI([.answer(["Done."])])
        let session = makeSession(api)
        session.retry()
        XCTAssertEqual(api.requestCount, 0, "nothing to retry in an empty chat")
        session.ask("Hi")
        await waitUntil { !session.isStreaming }
        session.retry()
        XCTAssertFalse(session.isStreaming)
        XCTAssertEqual(api.requestCount, 1, "an answered question is not sent again")
        XCTAssertEqual(session.conversation.messages.map(\.text), ["Hi", "Done."])
    }

    // MARK: - New chat, open, delete

    func testDeletingTheOpenChatWhileItStreamsClearsItAndIgnoresTheLateAnswer() async throws {
        let api = ScriptedAPI([.answer(["First answer."]), .held])
        let session = makeSession(api)
        session.ask("First question")
        await waitUntil { !session.isStreaming }
        let chat = try XCTUnwrap(session.savedChats.first)

        session.ask("Second question")
        await waitUntil { api.held != nil }
        api.held?.yield(Self.delta("Part"))
        await waitUntil { session.conversation.messages.last?.text == "Part" }

        session.delete(chat)
        XCTAssertFalse(session.isStreaming)
        XCTAssertTrue(session.conversation.isEmpty)
        XCTAssertNotEqual(session.conversation.chatID, chat.id, "the next question starts a new chat")
        XCTAssertTrue(session.savedChats.isEmpty)
        await waitUntil { api.heldTerminated }

        api.held?.yield(Self.delta(" late"))
        api.held?.yield(#"data: {"type":"message_stop"}"#)
        await drain()
        XCTAssertTrue(session.conversation.isEmpty, "the cancelled answer never writes into the new chat")
        XCTAssertTrue(makeSession(ScriptedAPI([])).savedChats.isEmpty, "the deleted chat is not saved again")
    }

    func testDeletingAnotherChatKeepsTheOpenOne() throws {
        let history = ClaudeAskHistory(storage: EditionStorage(root: folder))
        let older = chat("Older", updatedAt: Date(timeIntervalSinceNow: -3600))
        let newer = chat("Newer", updatedAt: Date())
        try history.save(older)
        try history.save(newer)
        let session = makeSession(ScriptedAPI([]))
        XCTAssertEqual(session.savedChats.map(\.id), [newer.id, older.id], "most recently answered first")

        session.open(older)
        session.delete(newer)
        XCTAssertEqual(session.conversation.chatID, older.id)
        XCTAssertEqual(session.conversation.messages.first?.text, "Older")
        XCTAssertEqual(session.savedChats.map(\.id), [older.id])
        XCTAssertNil(try history.load(newer.id))
    }

    func testDeleteAllChatsRemovesEveryChatButLeavesOtherFiles() throws {
        let storage = EditionStorage(root: folder)
        let history = ClaudeAskHistory(storage: storage)
        let first = chat("One", updatedAt: Date())
        try history.save(first)
        try history.save(chat("Two", updatedAt: Date()))
        let notes = history.directory.appendingPathComponent("notes.txt")
        try "keep me".write(to: notes, atomically: true, encoding: .utf8)
        let session = makeSession(ScriptedAPI([]))
        session.open(first)

        session.deleteAllChats()
        XCTAssertTrue(session.savedChats.isEmpty)
        XCTAssertTrue(session.conversation.isEmpty)
        XCTAssertNotEqual(session.conversation.chatID, first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path))
        XCTAssertTrue(makeSession(ScriptedAPI([])).savedChats.isEmpty)
    }

    func testNewChatWhileStreamingCancelsTheAnswerAndSavesNothing() async {
        let api = ScriptedAPI([.held])
        let session = makeSession(api)
        session.isShowingHistory = true
        session.ask("Long question")
        await waitUntil { api.held != nil }
        api.held?.yield(Self.delta("Half"))
        await waitUntil { session.conversation.messages.last?.text == "Half" }

        session.newChat()
        XCTAssertFalse(session.isStreaming)
        XCTAssertTrue(session.conversation.isEmpty)
        XCTAssertFalse(session.isShowingHistory)
        await waitUntil { api.heldTerminated }
        api.held?.yield(Self.delta(" more"))
        await drain()
        XCTAssertTrue(session.conversation.isEmpty)
        XCTAssertTrue(session.savedChats.isEmpty, "New chat drops the unfinished answer")
    }

    func testOpeningAnotherChatWhileStreamingSavesThePartialAnswerAsStopped() async throws {
        let saved = chat("Saved earlier", updatedAt: Date(timeIntervalSinceNow: -3600))
        try ClaudeAskHistory(storage: EditionStorage(root: folder)).save(saved)
        let api = ScriptedAPI([.held])
        let session = makeSession(api)
        session.ask("Explain backoff")
        await waitUntil { api.held != nil }
        api.held?.yield(Self.delta("Backoff waits"))
        await waitUntil { session.conversation.messages.last?.text == "Backoff waits" }
        let streamingID = session.conversation.chatID

        session.open(saved)
        XCTAssertFalse(session.isStreaming)
        XCTAssertEqual(session.conversation.chatID, saved.id)
        let partial = try XCTUnwrap(session.savedChats.first { $0.id == streamingID })
        XCTAssertEqual(partial.messages.map(\.text), ["Explain backoff", "Backoff waits"])
        XCTAssertEqual(partial.messages.last?.status, .stopped)
        await waitUntil { api.heldTerminated }
    }

    // MARK: - Screenshots

    func testAFailedQuestionKeepsItsScreenshotForRetryAndDropsItOnceAnswered() async throws {
        let api = ScriptedAPI([.status(500), .answer(["A gradient."])])
        let session = makeSession(api, runMode: RunMode(isSnapshot: true))
        session.showForSnapshot(.pendingScreenshot)
        let screenshot = try XCTUnwrap(session.pendingAttachments.first)
        XCTAssertTrue(stagedFileExists(screenshot))

        session.ask("What is on my screen?")
        XCTAssertTrue(session.pendingAttachments.isEmpty, "the screenshot went with the question")
        await waitUntil { !session.isStreaming && session.conversation.failure != nil }
        XCTAssertEqual(try api.imageCount(at: 0), 1)
        XCTAssertTrue(stagedFileExists(screenshot), "Retry still needs the screenshot")

        session.retry()
        await waitUntil { !session.isStreaming }
        XCTAssertNil(session.conversation.failure)
        XCTAssertEqual(try api.imageCount(at: 1), 1, "the retry sends the screenshot again")
        XCTAssertFalse(stagedFileExists(screenshot), "a run that saves nothing deletes it once answered")
    }

    func testRemovingAPendingScreenshotDeletesItsFile() throws {
        let session = makeSession(ScriptedAPI([]), runMode: RunMode(isSnapshot: true))
        session.showForSnapshot(.pendingScreenshot)
        let screenshot = try XCTUnwrap(session.pendingAttachments.first)
        XCTAssertNotNil(session.thumbnail(for: screenshot))

        session.removePending(screenshot)
        XCTAssertTrue(session.pendingAttachments.isEmpty)
        XCTAssertFalse(stagedFileExists(screenshot))
        XCTAssertNil(session.thumbnail(for: screenshot), "neither the cache nor the file is left")
    }

    func testNewChatDiscardsPendingScreenshots() throws {
        let session = makeSession(ScriptedAPI([]), runMode: RunMode(isSnapshot: true))
        session.showForSnapshot(.pendingScreenshot)
        let screenshot = try XCTUnwrap(session.pendingAttachments.first)
        session.newChat()
        XCTAssertTrue(session.pendingAttachments.isEmpty)
        XCTAssertFalse(stagedFileExists(screenshot))
    }

    // MARK: - Helpers

    private var stagingRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Ask Claude Screenshots", isDirectory: true)
            .appendingPathComponent(folder.lastPathComponent, isDirectory: true)
    }

    private func stagedFileExists(_ attachment: ClaudeAskAttachment) -> Bool {
        let files = FileManager.default.enumerator(at: stagingRoot, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.lastPathComponent } ?? []
        return files.contains(attachment.fileName)
    }

    /// A session asking Anthropic through `api`, saving into this test's folder.
    private func makeSession(_ api: ScriptedAPI, runMode: RunMode = .live) -> ClaudeAskSession {
        let suite = "ClaudeAskSessionHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(catalog: ModuleList.catalog, defaults: defaults, defaultKitID: "essentials",
                                     kitStore: nil, integratesWithSystem: false)
        settings.settings.ai.provider = .anthropic
        let keys = InMemoryAIKeyStore([.anthropic: "sk-test"])
        let factory = AIProviderFactory(keys: keys, sandboxed: false, locate: { _ in nil },
                                        transport: api.transport)
        let ai = AIService(settings: settings, keys: keys, sandboxed: false, factory: factory)
        return ClaudeAskSession(runMode: runMode, storage: EditionStorage(root: folder), ai: ai)
    }

    private func chat(_ question: String, updatedAt: Date) -> ClaudeAskChat {
        ClaudeAskChat(id: UUID(), createdAt: updatedAt, updatedAt: updatedAt, sessionID: nil, messages: [
            .init(role: .user, text: question),
            .init(role: .assistant, text: "Answer to \(question)"),
        ])
    }

    private static func delta(_ text: String) -> String {
        #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"\#(text)"}}"#
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    /// Gives a late event every chance to arrive before asserting it didn't.
    private func drain() async {
        for _ in 0..<10 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A hosted API that answers each request with the next scripted reply and
/// records what it was sent. A `.held` reply streams only what the test
/// yields, so a test can act while an answer is still arriving.
private final class ScriptedAPI: @unchecked Sendable {
    enum Reply {
        case answer([String])
        case status(Int)
        case held
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var requests: [URLRequest] = []
    private var heldContinuation: AsyncThrowingStream<String, Error>.Continuation?
    private var terminated = false

    init(_ replies: [Reply]) { self.replies = replies }

    var requestCount: Int { lock.withLock { requests.count } }
    var held: AsyncThrowingStream<String, Error>.Continuation? { lock.withLock { heldContinuation } }
    /// True once the session stopped reading the held stream.
    var heldTerminated: Bool { lock.withLock { terminated } }

    var transport: AIHTTPProvider.Transport {
        { [self] request in respond(to: request) }
    }

    private func respond(to request: URLRequest) -> AIHTTPResponse {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? .status(500) : replies.removeFirst()
        }
        switch reply {
        case .status(let status):
            return AIHTTPResponse(status: status, lines: AsyncThrowingStream { $0.finish() })
        case .answer(let parts):
            let lines = parts.map {
                #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"\#($0)"}}"#
            } + [#"data: {"type":"message_stop"}"#]
            return AIHTTPResponse(status: 200, lines: AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            })
        case .held:
            return AIHTTPResponse(status: 200, lines: AsyncThrowingStream { continuation in
                continuation.onTermination = { [self] _ in lock.withLock { terminated = true } }
                lock.withLock { heldContinuation = continuation }
            })
        }
    }

    private func body(at index: Int) throws -> [String: Any] {
        let request = try XCTUnwrap(lock.withLock { requests.indices.contains(index) ? requests[index] : nil })
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func lastUserContent(at index: Int) throws -> Any? {
        let messages = try XCTUnwrap(body(at: index)["messages"] as? [[String: Any]])
        return messages.last { $0["role"] as? String == "user" }?["content"]
    }

    /// The text of the request's newest user message.
    func lastUserText(at index: Int) throws -> String? {
        let content = try lastUserContent(at: index)
        if let text = content as? String { return text }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.first { $0["type"] as? String == "text" }?["text"] as? String
    }

    /// How many images the request's newest user message carries.
    func imageCount(at index: Int) throws -> Int {
        let blocks = try lastUserContent(at: index) as? [[String: Any]] ?? []
        return blocks.filter { $0["type"] as? String == "image" }.count
    }
}
