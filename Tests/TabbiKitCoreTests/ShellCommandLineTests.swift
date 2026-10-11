import Foundation
import XCTest
@testable import TabbiKitCore

final class ShellCommandLineTests: XCTestCase {
    func testPlainWordsStayReadable() {
        XCTAssertEqual(ShellCommandLine.running(URL(fileURLWithPath: "/opt/homebrew/bin/codex"), arguments: ["login"]),
                       "/opt/homebrew/bin/codex login")
        XCTAssertEqual(ShellCommandLine.quoted("/Users/ana/.local/bin/claude"), "/Users/ana/.local/bin/claude")
    }

    func testWordsTheShellWouldReadDifferentlyAreQuoted() {
        XCTAssertEqual(ShellCommandLine.quoted("/Users/Ana Lee/bin/claude"), "'/Users/Ana Lee/bin/claude'")
        XCTAssertEqual(ShellCommandLine.quoted("o'neil"), #"'o'\''neil'"#)
        XCTAssertEqual(ShellCommandLine.quoted("~/bin"), "'~/bin'")
        XCTAssertEqual(ShellCommandLine.quoted(""), "''")
    }

    /// zsh (the Mac's default) and bash read every quoted word back as it
    /// was, whatever it holds.
    func testShellsReadQuotedWordsBackUnchanged() throws {
        let words = ["/Users/Ana Lee/.local/bin/claude", "/Users/o'neil/bin/claude", #"/tmp/$HOME `x` "y" \z;&|*?!#()"#,
                     "/Users/Jos\u{E9}/bin/claude", "-n", ""]
        let shells = [("/bin/zsh", ["-f", "-c"]), ("/bin/bash", ["--norc", "-c"])]
        for (shell, options) in shells {
            for word in words {
                let script = "printf '%s' \(ShellCommandLine.quoted(word))"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = options + [script]
                let pipe = Pipe()
                process.standardOutput = pipe
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                XCTAssertEqual(String(data: data, encoding: .utf8), word, "\(shell) read \(script) differently")
            }
        }
    }
}
