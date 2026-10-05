import Foundation
import XCTest

/// Runs `scripts/check-style.sh` so `swift test` fails when a tracked file
/// gains an em dash or an emoji (the maintainer's writing rule in AGENTS.md).
final class WritingStyleTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runCheck(_ arguments: [String] = []) throws -> (status: Int32, output: String) {
        let script = repositoryRoot.appendingPathComponent("scripts/check-style.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = repositoryRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testTrackedFilesHaveNoEmDashesOrEmojis() throws {
        guard FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(".git").path) else {
            throw XCTSkip("Not running from a git checkout.")
        }
        let result = try runCheck()
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testCheckFlagsEmDashesAndEmojisButNotPlainSymbols() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WritingStyleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let clean = folder.appendingPathComponent("clean.md")
        try "Press \u{2318}K, then go \u{2192} next - done (10\u{2013}20 min).\n"
            .write(to: clean, atomically: true, encoding: .utf8)
        XCTAssertEqual(try runCheck([clean.path]).status, 0)

        let dirty = folder.appendingPathComponent("dirty.md")
        try "One \u{2014} two\nfine\nShip it \u{1F680}\n".write(to: dirty, atomically: true, encoding: .utf8)
        let result = try runCheck([dirty.path])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.output.contains("dirty.md:1: em dash"), result.output)
        XCTAssertTrue(result.output.contains("dirty.md:3: emoji U+1F680"), result.output)
        XCTAssertFalse(result.output.contains("dirty.md:2"), result.output)
    }
}
