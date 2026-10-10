// These tests drive a stand-in claude CLI, which the sandboxed App Store
// build never runs; AppStoreEditionFeatureTests covers Ask there.
#if !APPSTORE
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Drives `ClaudeAskSession` the way the panel does, against a stand-in
/// `claude` script or a mocked API, to check what is sent and how a
/// reopened chat continues.
@MainActor
final class ClaudeAskSessionTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ask-\(UUID().uuidString)")
    private var previousOverride: String?

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        previousOverride = ClaudeCLI.userPathOverride
    }

    override func tearDown() async throws {
        ClaudeCLI.userPathOverride = previousOverride
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes a fake `claude` that refuses `--resume gone` like the real CLI
    /// does for a deleted session, saves each stdin it gets, and otherwise
    /// runs `answer` (shell lines that print stream-json).
    private func installFakeClaude(answer: String) throws {
        let script = folder.appendingPathComponent("claude")
        try """
        #!/bin/sh
        for arg in "$@"; do
          if [ "$prev" = "--resume" ] && [ "$arg" = "gone" ]; then
            echo "No conversation found with session ID: gone" >&2
            exit 1
          fi
          prev="$arg"
        done
        count=$(ls "\(folder.path)" | grep -c '^input-')
        cat > "\(folder.path)/input-$count.json"
        \(answer)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        ClaudeCLI.userPathOverride = script.path
    }

    private var sentInputs: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix("input-") }.sorted().compactMap {
            try? String(contentsOf: folder.appendingPathComponent($0), encoding: .utf8)
        }
    }

    private func savedChat(sessionID: String) -> ClaudeAskChat {
        ClaudeAskChat(id: UUID(), createdAt: Date(), updatedAt: Date(), sessionID: sessionID, messages: [
            .init(role: .user, text: "What retry policy should I use?"),
            .init(role: .assistant, text: "Exponential backoff."),
        ])
    }

    /// Settings with `provider` picked. A store applies its saved `claude`
    /// path, so the stand-in script's path is saved in it.
    private func makeAI(_ provider: AIProviderID?, keys: InMemoryAIKeyStore = InMemoryAIKeyStore(),
                        locate: AIProviderFactory.Locate? = nil,
                        transport: AIHTTPProvider.Transport? = nil) -> AIService {
        let claudePath = ClaudeCLI.userPathOverride
        let suite = "ClaudeAskSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(catalog: ModuleList.catalog, defaults: defaults, defaultKitID: "essentials",
                                     kitStore: nil, integratesWithSystem: false)
        settings.settings.claudePathOverride = claudePath
        settings.settings.ai.choose(provider)
        let factory = locate == nil && transport == nil ? nil : AIProviderFactory(
            keys: keys, sandboxed: false, locate: locate ?? AIProviderFactory.defaultLocate,
            transport: transport ?? AIHTTPProvider.urlSession()
        )
        return AIService(settings: settings, keys: keys, sandboxed: false, factory: factory)
    }

    private func makeSession(_ ai: AIService) -> ClaudeAskSession {
        ClaudeAskSession(runMode: .live, storage: EditionStorage(root: folder), ai: ai)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testAChatWhoseSessionIsGoneGoesOnInANewSessionWithItsTranscript() async throws {
        try installFakeClaude(answer: """
        echo '{"type":"system","subtype":"init","session_id":"fresh"}'
        echo '{"type":"result","subtype":"success","is_error":false,"result":"Add jitter too.","session_id":"fresh"}'
        """)
        let session = makeSession(makeAI(.claudeCLI))
        session.open(savedChat(sessionID: "gone"))
        session.ask("And what about jitter?")
        await waitUntil { !session.isStreaming }

        XCTAssertNil(session.conversation.failure)
        XCTAssertEqual(session.conversation.messages.map(\.text), [
            "What retry policy should I use?", "Exponential backoff.", "And what about jitter?", "Add jitter too.",
        ])
        XCTAssertEqual(session.conversation.sessionID, "fresh")
        let input = try XCTUnwrap(sentInputs.last)
        XCTAssertTrue(input.contains("What retry policy should I use?"), "the new session gets the chat so far")
        XCTAssertTrue(input.contains("Exponential backoff."))
        XCTAssertTrue(input.contains("And what about jitter?"))
    }

    func testNothingIsSentBeforeAProviderIsPicked() async {
        let session = makeSession(makeAI(nil))
        session.prepare()
        XCTAssertEqual(session.setupNeeded, .noProvider)
        session.ask("Hello?")
        XCTAssertFalse(session.isStreaming)
        XCTAssertEqual(session.conversation.failure, .noProvider)
        XCTAssertTrue(sentInputs.isEmpty)
    }

    func testAnAPIProviderWithoutAKeyAsksForOne() {
        let session = makeSession(makeAI(.openAI))
        session.prepare()
        XCTAssertEqual(session.setupNeeded, .needsKey(.openAI))
    }

    func testAMissingToolIsExplainedWhenItIsUsed() async {
        let session = makeSession(makeAI(.codexCLI, locate: { _ in nil }))
        session.ask("Hi")
        await waitUntil { !session.isStreaming }
        XCTAssertEqual(session.conversation.failure, .notInstalled(.codexCLI))
        XCTAssertEqual(session.setupNeeded, .notInstalled(.codexCLI))
    }

    func testAHostedAPIGetsTheWholeChatAsMessages() async throws {
        let keys = InMemoryAIKeyStore([.anthropic: "sk-test"])
        let sent = SentRequests()
        let ai = makeAI(.anthropic, keys: keys, transport: { request in
            sent.append(request)
            let lines = [
                #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Add "}}"#,
                #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"jitter."}}"#,
                #"data: {"type":"message_stop"}"#,
            ]
            return AIHTTPResponse(status: 200, lines: AsyncThrowingStream { continuation in
                for line in lines { continuation.yield(line) }
                continuation.finish()
            })
        })
        let session = makeSession(ai)
        session.open(savedChat(sessionID: "claude-code-session"))
        session.ask("And what about jitter?")
        await waitUntil { !session.isStreaming }

        XCTAssertNil(session.conversation.failure)
        XCTAssertEqual(session.conversation.messages.last?.text, "Add jitter.")
        let body = try XCTUnwrap(sent.all.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"],
                       "the API keeps no session, so the chat so far goes along")
        XCTAssertEqual(json["system"] as? String, ClaudeAskConversation.instructions)
        XCTAssertEqual(json["model"] as? String, AIProviderID.anthropic.defaultModel)
    }

    func testAProviderErrorShowsItsOwnWords() async {
        let keys = InMemoryAIKeyStore([.gemini: "bad"])
        let ai = makeAI(.gemini, keys: keys, transport: { _ in
            AIHTTPResponse(status: 403, lines: AsyncThrowingStream { $0.finish() })
        })
        let session = makeSession(ai)
        session.ask("Hi")
        await waitUntil { !session.isStreaming }
        XCTAssertEqual(session.conversation.failure,
                       .process(detail: AIProviderError.invalidAPIKey.message(for: .gemini)))
    }

    func testOpeningTheStreamingChatFromHistoryKeepsItsAnswerRunning() async throws {
        try installFakeClaude(answer: """
        echo '{"type":"system","subtype":"init","session_id":"live"}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Partial"}}}'
        sleep 30
        """)
        let session = makeSession(makeAI(.claudeCLI))
        let chat = savedChat(sessionID: "live")
        session.open(chat)
        session.ask("Go on")
        await waitUntil { session.conversation.messages.last?.text == "Partial" }

        session.isShowingHistory = true
        session.open(chat)
        XCTAssertFalse(session.isShowingHistory)
        XCTAssertTrue(session.isStreaming, "reopening the open chat doesn't stop its answer")
        XCTAssertEqual(session.conversation.messages.map(\.text).suffix(2), ["Go on", "Partial"])
        session.stop()
        XCTAssertEqual(session.conversation.messages.last?.status, .stopped)
    }
}

/// Requests a mocked transport received, read back on the main actor.
private final class SentRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var all: [URLRequest] { lock.withLock { requests } }
}
#endif
