// The Usage tab isn't in the App Store build (`ModuleList` leaves it out).
#if !APPSTORE
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Usage tab while Codex is the chosen AI: it reads Codex's own
/// session logs (never the claude CLI) for both its limits and its tokens.
@MainActor
final class AIUsageStoreTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCodexSourceShowsLimitsAndTokensFromItsLogs() async throws {
        let sessions = root.appendingPathComponent("sessions/2026/10/09", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let stamp = Date().formatted(Date.ISO8601FormatStyle())
        let lines = [
            #"{"timestamp":"\#(stamp)","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":200,"total_tokens":1200}},"rate_limits":{"primary":{"used_percent":42.0,"window_minutes":300,"resets_in_seconds":3600},"secondary":{"used_percent":76.0,"window_minutes":10080,"resets_in_seconds":86400}}}}"#,
        ]
        try Data(lines.joined(separator: "\n").utf8).write(to: sessions.appendingPathComponent("rollout-test.jsonl"))

        let store = ClaudeUsageStore(storage: EditionStorage(root: root.appendingPathComponent("app")), runMode: .live,
                                     source: .codex, codexRoot: root.appendingPathComponent("sessions"))
        XCTAssertEqual(store.source, .codex)
        try await waitUntil { store.stats != nil }

        XCTAssertEqual(store.stats?.today.tokens.total, 1_200)
        XCTAssertEqual(store.stats?.today.topModel, "gpt-5-codex")
        XCTAssertEqual(store.limits?.snapshot.fiveHour?.utilization ?? 0, 0.42, accuracy: 0.001)
        XCTAssertEqual(store.limits?.snapshot.sevenDay?.utilization ?? 0, 0.76, accuracy: 0.001)
        XCTAssertNil(store.probeError)
    }

    func testCodexWithoutLogsShowsNoLimitsAndNoTokens() async throws {
        let store = ClaudeUsageStore(storage: EditionStorage(root: root.appendingPathComponent("app")), runMode: .live,
                                     source: .codex, codexRoot: root.appendingPathComponent("missing"))
        try await waitUntil { store.stats != nil }
        XCTAssertNil(store.limits)
        XCTAssertEqual(store.stats?.today.tokens.total, 0)
    }

    func testCodexFolderNamesTheFolderItReads() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let store = ClaudeUsageStore(storage: EditionStorage(root: root), runMode: .demo,
                                     codexRoot: home.appendingPathComponent("work/codex/sessions"))
        XCTAssertEqual(store.codexFolder, "~/work/codex/sessions")
        let elsewhere = ClaudeUsageStore(storage: EditionStorage(root: root), runMode: .demo,
                                         codexRoot: URL(fileURLWithPath: "/opt/codex/sessions"))
        XCTAssertEqual(elsewhere.codexFolder, "/opt/codex/sessions")
    }

    func testDemoPreviewShowsCodexSampleData() {
        let store = ClaudeUsageStore(storage: EditionStorage(root: root), runMode: .demo,
                                     environment: ["TABBI_USAGE_PREVIEW": "codex"])
        XCTAssertEqual(store.source, .codex)
        XCTAssertEqual(store.stats?.today.topModel, "gpt-5-codex")
        XCTAssertNotNil(store.limits)
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date() + timeout
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
#endif
