import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Drives `ClaudeAskSession` against a stand-in `claude` script, the way
/// the panel does, to check how a reopened chat continues.
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
        let session = ClaudeAskSession(runMode: .live, storage: EditionStorage(root: folder))
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

    func testOpeningTheStreamingChatFromHistoryKeepsItsAnswerRunning() async throws {
        try installFakeClaude(answer: """
        echo '{"type":"system","subtype":"init","session_id":"live"}'
        echo '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Partial"}}}'
        sleep 30
        """)
        let session = ClaudeAskSession(runMode: .live, storage: EditionStorage(root: folder))
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
