import XCTest
@testable import NotchKitCore

final class ModuleIDTests: XCTestCase {
    func testNextAndPreviousWrap() {
        XCTAssertEqual(ModuleID.spotify.next, .system)
        XCTAssertEqual(ModuleID.claudeAsk.next, .spotify)
        XCTAssertEqual(ModuleID.spotify.previous, .claudeAsk)
    }
}

final class ClaudeCLITests: XCTestCase {
    func testOverrideWinsWhenExecutable() {
        let url = ClaudeCLI.locate(environment: [ClaudeCLI.overrideVariable: "/bin/sh"], loginShellLookup: { nil })
        XCTAssertEqual(url?.path, "/bin/sh")
    }

    func testNonExecutableOverrideFallsThroughToShellLookup() {
        let url = ClaudeCLI.locate(
            environment: [ClaudeCLI.overrideVariable: "/nonexistent/claude"],
            fileManager: EmptyFileManager(),
            loginShellLookup: { "/bin/sh" }
        )
        XCTAssertEqual(url?.path, "/bin/sh")
    }
}

/// Reports only real system binaries as executable, so home-dir candidates are skipped.
private final class EmptyFileManager: FileManager {
    override func isExecutableFile(atPath path: String) -> Bool {
        path.hasPrefix("/bin/") && super.isExecutableFile(atPath: path)
    }
}

final class ClaudeCLIPathOverrideTests: XCTestCase {
    func testSettingsOverrideBeatsEnvironmentOverride() {
        let url = ClaudeCLI.locate(
            pathOverride: "/bin/sh",
            environment: [ClaudeCLI.overrideVariable: "/bin/zsh"],
            loginShellLookup: { nil }
        )
        XCTAssertEqual(url?.path, "/bin/sh")
    }

    func testNonExecutableSettingsOverrideFallsBackToEnvironment() {
        let url = ClaudeCLI.locate(
            pathOverride: "/nonexistent/claude",
            environment: [ClaudeCLI.overrideVariable: "/bin/zsh"],
            loginShellLookup: { nil }
        )
        XCTAssertEqual(url?.path, "/bin/zsh")
    }

    func testUserPathOverrideIsTheDefault() {
        ClaudeCLI.userPathOverride = "/bin/sh"
        defer { ClaudeCLI.userPathOverride = nil }
        let url = ClaudeCLI.locate(environment: [ClaudeCLI.overrideVariable: "/bin/zsh"], loginShellLookup: { nil })
        XCTAssertEqual(url?.path, "/bin/sh")
    }
}
