import XCTest
import NotchDeckCore

final class ClaudePathCheckTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudePathCheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func script(_ name: String, body: String, executable: Bool = true) throws -> String {
        let url = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        return url.path
    }

    func testParsesClaudeCodeVersionLine() {
        XCTAssertEqual(ClaudePathCheck.parseVersion("2.1.4 (Claude Code)\n"), "2.1.4")
        XCTAssertEqual(ClaudePathCheck.parseVersion("  1.0.120 (Claude Code)"), "1.0.120")
    }

    func testRejectsOutputThatIsNotClaudeCode() {
        XCTAssertNil(ClaudePathCheck.parseVersion(""))
        XCTAssertNil(ClaudePathCheck.parseVersion("v20.11.0"))
        XCTAssertNil(ClaudePathCheck.parseVersion("claude: command not found"))
        XCTAssertNil(ClaudePathCheck.parseVersion("2..1 (Claude Code)"))
    }

    func testWorkingOverrideReportsItsVersion() throws {
        let path = try script("claude", body: "echo '2.1.4 (Claude Code)'")
        let result = ClaudePathCheck.run(override: path, locate: { _ in XCTFail("must not auto-discover"); return nil })
        XCTAssertEqual(result, .found(path: path, version: "2.1.4", isOverride: true))
        XCTAssertTrue(result.isSuccess)
    }

    func testMissingOverrideIsReportedNotReplaced() {
        let path = directory.appendingPathComponent("nope").path
        let result = ClaudePathCheck.run(override: path, locate: { _ in URL(fileURLWithPath: "/usr/bin/true") })
        XCTAssertEqual(result, .missing(path: path))
        XCTAssertFalse(result.isSuccess)
    }

    func testDirectoryAndNonExecutableOverridesAreRejected() throws {
        XCTAssertEqual(ClaudePathCheck.run(override: directory.path), .notExecutable(path: directory.path))
        let path = try script("claude", body: "echo '2.1.4 (Claude Code)'", executable: false)
        XCTAssertEqual(ClaudePathCheck.run(override: path), .notExecutable(path: path))
    }

    func testBinaryThatIsNotClaudeIsRejected() throws {
        let failing = try script("failing", body: "exit 3")
        XCTAssertEqual(ClaudePathCheck.run(override: failing), .notClaude(path: failing))
        let other = try script("other", body: "echo 'v20.11.0'")
        XCTAssertEqual(ClaudePathCheck.run(override: other), .notClaude(path: other))
    }

    func testWithoutOverrideUsesAutoDiscovery() {
        let found = URL(fileURLWithPath: "/opt/homebrew/bin/claude")
        let result = ClaudePathCheck.run(
            override: nil,
            locate: { override in XCTAssertNil(override); return found },
            version: { _ in "2.0.0" }
        )
        XCTAssertEqual(result, .found(path: found.path, version: "2.0.0", isOverride: false))
        XCTAssertEqual(ClaudePathCheck.run(override: nil, locate: { _ in nil }), .notFound)
    }
}
