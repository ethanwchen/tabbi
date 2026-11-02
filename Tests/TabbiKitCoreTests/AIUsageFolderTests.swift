import XCTest
@testable import TabbiKitCore

/// The sandboxed AI Usage reads the folder the user picks: the tool's own
/// folder or the logs folder inside it.
final class AIUsageFolderTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for path in [".claude/projects/-Users-sam-app", ".codex/sessions/2026/10/01", "Documents"] {
            try FileManager.default.createDirectory(at: home.appendingPathComponent(path), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testSuggestsTheToolsOwnFolderInTheRealHome() {
        XCTAssertEqual(AIUsageFolder.suggested(for: .claudeCode, home: home).lastPathComponent, ".claude")
        XCTAssertEqual(AIUsageFolder.suggested(for: .codex, home: home).lastPathComponent, ".codex")
        // Never the app's container, which holds no logs.
        XCTAssertFalse(AIUsageFolder.realHome.path.contains("/Library/Containers/"))
    }

    func testAcceptsTheToolFolderOrTheLogsFolderInside() {
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        XCTAssertEqual(AIUsageFolder.logRoot(forPicked: claude, source: .claudeCode)?.lastPathComponent, "projects")
        XCTAssertEqual(AIUsageFolder.logRoot(forPicked: claude.appendingPathComponent("projects"), source: .claudeCode)?.path,
                       claude.appendingPathComponent("projects").path)
        let codex = home.appendingPathComponent(".codex", isDirectory: true)
        XCTAssertEqual(AIUsageFolder.logRoot(forPicked: codex, source: .codex)?.lastPathComponent, "sessions")
        XCTAssertEqual(AIUsageFolder.logRoot(forPicked: codex.appendingPathComponent("sessions"), source: .codex)?.lastPathComponent,
                       "sessions")
    }

    func testRefusesAFolderWithoutTheToolsLogs() {
        XCTAssertNil(AIUsageFolder.logRoot(forPicked: home.appendingPathComponent("Documents"), source: .claudeCode))
        XCTAssertNil(AIUsageFolder.logRoot(forPicked: home.appendingPathComponent(".codex"), source: .claudeCode))
        XCTAssertNil(AIUsageFolder.logRoot(forPicked: home.appendingPathComponent(".claude"), source: .codex))
        XCTAssertNil(AIUsageFolder.logRoot(forPicked: home.appendingPathComponent("missing/projects"), source: .claudeCode))
    }

    func testShowsTheHomeFolderAsATilde() {
        XCTAssertEqual(AIUsageFolder.displayPath(home.appendingPathComponent(".claude"), home: home), "~/.claude")
        XCTAssertEqual(AIUsageFolder.displayPath(home, home: home), "~")
        XCTAssertEqual(AIUsageFolder.displayPath(URL(fileURLWithPath: "/Volumes/Work/.claude"), home: home), "/Volumes/Work/.claude")
    }
}
