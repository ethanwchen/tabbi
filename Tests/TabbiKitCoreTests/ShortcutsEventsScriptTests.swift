import XCTest
@testable import TabbiKitCore

/// The App Store build runs the Do Not Disturb shortcuts through Shortcuts
/// Events over Apple Events; these are the scripts it sends and how their
/// errors read.
final class ShortcutsEventsScriptTests: XCTestCase {
    func testRunsTheNamedShortcutInShortcutsEventsWithATimeout() {
        let script = ShortcutsEventsScript.run("Tabbi Focus On")
        XCTAssertTrue(script.contains(#"tell application id "com.apple.shortcuts.events" to run shortcut "Tabbi Focus On""#), script)
        XCTAssertTrue(script.contains("with timeout of 15 seconds"))
        XCTAssertTrue(ShortcutsEventsScript.listNames.contains("name of every shortcut"))
        XCTAssertTrue(ShortcutsEventsScript.listNames.contains(ShortcutsEventsScript.bundleIdentifier))
    }

    func testANameCanNeverEndTheStringEarly() {
        XCTAssertEqual(ShortcutsEventsScript.quoted(#"Say "hi""#), #""Say \"hi\"""#)
        XCTAssertEqual(ShortcutsEventsScript.quoted(#"a\b"#), #""a\\b""#)
        XCTAssertEqual(ShortcutsEventsScript.quoted(#"x" & do shell script "y"#), #""x\" & do shell script \"y""#)
        XCTAssertEqual(ShortcutsEventsScript.quoted("Fokus \u{1F319}"), "\"Fokus \u{1F319}\"")
    }

    func testErrorsReadAsTheRunnerOutcomes() {
        XCTAssertEqual(ShortcutsEventsScript.result(errorNumber: nil, message: nil, name: "On"), .succeeded)
        XCTAssertEqual(ShortcutsEventsScript.result(errorNumber: -1743, message: "Not authorized", name: "On"), .notAllowed)
        XCTAssertEqual(ShortcutsEventsScript.result(errorNumber: -1728, message: "Can't get shortcut", name: "On"),
                       .notFound(name: "On"))
        XCTAssertEqual(ShortcutsEventsScript.result(errorNumber: -1712, message: nil, name: "On"), .timedOut)
        XCTAssertEqual(ShortcutsEventsScript.result(errorNumber: -600, message: nil, name: "On"), .unavailable)
        XCTAssertEqual(ShortcutsEventsScript.result(errorNumber: -1, message: " The shortcut failed. ", name: "On"),
                       .failed(message: "The shortcut failed."))
    }
}
