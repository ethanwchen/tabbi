import XCTest
import TabbiKitCore
@testable import Tabbi

/// AI Usage in the sandboxed App Store build: nothing is read before the
/// user picks a folder, a picked folder survives a relaunch as a bookmark,
/// and nothing ever looks for or runs a command line tool.
@MainActor
final class AIUsageSandboxTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    private let suite = "AIUsageSandboxTests-\(UUID().uuidString)"
    /// A defaults domain of the test's own, so no bookmark reaches the app's.
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    override func tearDownWithError() throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    private func store(_ folders: AIUsageFolderAccess, runMode: RunMode = .live,
                       environment: [String: String] = [:]) -> ClaudeUsageStore {
        // Default folders that would hold logs, to prove they are never read.
        ClaudeUsageStore(storage: EditionStorage(root: root.appendingPathComponent("app")), runMode: runMode,
                         transcripts: root.appendingPathComponent("home/.claude/projects"),
                         codexRoot: root.appendingPathComponent("home/.codex/sessions"),
                         folders: folders, defaults: defaults, environment: environment)
    }

    /// A Claude Code folder with one assistant message from today.
    private func makeClaudeFolder() throws -> URL {
        let claude = root.appendingPathComponent("home/.claude", isDirectory: true)
        let project = claude.appendingPathComponent("projects/-Users-sam-app", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let stamp = Date().formatted(Date.ISO8601FormatStyle())
        let line = #"{"type":"assistant","timestamp":"\#(stamp)","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":120,"output_tokens":30}}}"#
        // A finished line: the scanner waits for the newline.
        try Data((line + "\n").utf8).write(to: project.appendingPathComponent("session.jsonl"))
        return claude
    }

    func testNothingIsReadBeforeAFolderIsPicked() throws {
        _ = try makeClaudeFolder()
        let usage = store(AIUsageFolderAccess(runMode: .live, defaults: defaults))
        XCTAssertTrue(usage.needsFolder)
        XCTAssertNil(usage.stats)
        XCTAssertNil(usage.limits)
        usage.refresh()
        usage.panelDidAppear()
        XCTAssertFalse(usage.isFetching, "a refresh without a folder reads nothing")
        XCTAssertNil(usage.stats)
    }

    func testAPickedFolderIsReadAndKeptForTheNextLaunch() async throws {
        let claude = try makeClaudeFolder()
        let folders = AIUsageFolderAccess(runMode: .live, defaults: defaults)
        XCTAssertEqual(folders.keep(claude, for: .claudeCode), .chosen)
        XCTAssertEqual(folders.logRoot(for: .claudeCode)?.lastPathComponent, "projects")

        let usage = store(folders)
        XCTAssertFalse(usage.needsFolder)
        try await waitUntil { usage.stats?.today.messages == 1 }
        XCTAssertEqual(usage.stats?.today.tokens.total, 150)
        XCTAssertEqual(usage.stats?.daily.last, 150)
        XCTAssertNil(usage.limits, "only the claude CLI can report Claude's live limits")
        XCTAssertEqual(usage.cliStatus, .available, "the folder stands in for the CLI")

        // A relaunch resolves the saved bookmark.
        let relaunched = AIUsageFolderAccess(runMode: .live, defaults: defaults)
        XCTAssertEqual(relaunched.grants[.claudeCode]?.logRoot.lastPathComponent, "projects")
        relaunched.remove(.claudeCode)
        XCTAssertNil(AIUsageFolderAccess(runMode: .live, defaults: defaults).grants[.claudeCode], "Remove forgets it")
    }

    func testAFolderWithoutLogsIsRefused() throws {
        let documents = root.appendingPathComponent("home/Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let folders = AIUsageFolderAccess(runMode: .live, defaults: defaults)
        XCTAssertEqual(folders.keep(documents, for: .claudeCode), .wrongFolder)
        XCTAssertTrue(folders.grants.isEmpty)
    }

    func testTheUsersPickOfToolIsKept() throws {
        let usage = store(AIUsageFolderAccess(runMode: .live, defaults: defaults))
        XCTAssertEqual(usage.source, .claudeCode)
        usage.setSource(.codex)
        XCTAssertEqual(usage.source, .codex)
        XCTAssertTrue(usage.needsFolder)
        XCTAssertEqual(store(AIUsageFolderAccess(runMode: .live, defaults: defaults)).source, .codex)
    }

    func testDemoRunsShowSampleDataAndThePickerStateOnRequest() {
        let folders = AIUsageFolderAccess(runMode: .demo, defaults: defaults)
        let demo = store(folders, runMode: .demo)
        XCTAssertFalse(demo.needsFolder)
        XCTAssertEqual(demo.stats?.daily.count, 7)
        let picker = store(folders, runMode: .demo, environment: ["TABBI_USAGE_PREVIEW": "folder"])
        XCTAssertTrue(picker.needsFolder)
        XCTAssertEqual(folders.keep(root, for: .claudeCode), .cancelled, "demo runs never keep a folder")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date() + timeout
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
