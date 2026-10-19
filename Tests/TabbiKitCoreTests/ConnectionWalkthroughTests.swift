import XCTest
import TabbiKitCore

final class ConnectionWalkthroughTests: XCTestCase {
    private let banned = ["CLI", "API", "localhost", "port", "error", "TCC", "EventKit", "JSON", "HTTP", "\u{2014}"]

    private var permissions: [ConnectionPermission] {
        [.calendar, .notifications, .automation(.spotify), .automation(.music)]
    }

    private func assertPlain(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for term in banned {
            XCTAssertNil(text.range(of: "\\b\(term)\\b", options: .regularExpression),
                         "\u{201C}\(text)\u{201D} uses \(term)", file: file, line: line)
        }
    }

    func testEveryWalkthroughIsShortPlainAndStartsWithOneButton() {
        for guide in ConnectionGuide.allCases {
            let walkthrough = guide.walkthrough()
            XCTAssertFalse(walkthrough.steps.isEmpty, "\(guide) has no steps")
            XCTAssertLessThanOrEqual(walkthrough.steps.count, 3, "\(guide) is longer than three steps")
            for text in [walkthrough.title, walkthrough.intro, walkthrough.start.title] + walkthrough.steps.map(\.text) {
                assertPlain(text)
                XCTAssertLessThanOrEqual(text.count, 140, "\u{201C}\(text)\u{201D} is too long")
            }
        }
    }

    func testAnkiAddOnCopiesTheCodeAndOpensAnki() {
        let walkthrough = ConnectionGuide.ankiAddOn.walkthrough()
        XCTAssertEqual(walkthrough.start, .copyAndOpen(text: "2055492159", app: .anki))
        XCTAssertEqual(walkthrough.start.title, "Copy code and open Anki")
        XCTAssertTrue(walkthrough.steps.contains { $0.copyable == "2055492159" })
        XCTAssertTrue(walkthrough.steps[0].text.contains("Tools"))
        XCTAssertTrue(walkthrough.steps[1].text.contains("Get Add-ons"))
    }

    func testGoogleCalendarIsTwoStepsFromInternetAccounts() {
        let walkthrough = ConnectionGuide.googleCalendar.walkthrough()
        XCTAssertEqual(walkthrough.steps.count, 2)
        XCTAssertEqual(walkthrough.start, .openSettings(.internetAccounts))
        XCTAssertEqual(walkthrough.start.title, "Open Internet Accounts")
    }

    func testClaudeOffersTheInstallLineAndTheOfficialPage() {
        let install = ConnectionGuide.claudeInstall.walkthrough()
        XCTAssertEqual(install.start, .copyAndOpen(text: ClaudeConnectionState.installCommand, app: .terminal))
        XCTAssertTrue(install.steps.contains { $0.copyable == ClaudeConnectionState.installCommand })
        XCTAssertEqual(install.learnMore, ClaudeConnectionState.installPage)
        XCTAssertTrue(install.intro.contains("optional"))

        let signIn = ConnectionGuide.claudeSignIn.walkthrough()
        XCTAssertEqual(signIn.start, .copyAndOpen(text: "claude auth login", app: .terminal))
    }

    /// The installer puts claude in ~/.local/bin, which a fresh Terminal
    /// window often lacks on PATH, so the pasted line signs in by that
    /// path, and only once the install worked.
    func testClaudeInstallLineSignsInByThePathTheInstallerWrites() {
        XCTAssertEqual(ClaudeConnectionState.installCommand,
                       "curl -fsSL https://claude.ai/install.sh | bash && ~/.local/bin/claude auth login")
        let install = ConnectionGuide.claudeInstall.walkthrough()
        for step in install.steps {
            XCTAssertFalse(step.text.localizedCaseInsensitiveContains("type claude"), step.text)
        }
        XCTAssertTrue(install.steps.last?.text.contains("sign-in page") == true)
    }

    func testClaudeSignInRunsTheClaudeTabbiFoundByItsFullPath() {
        let local = URL(fileURLWithPath: "/Users/ana/.local/bin/claude")
        let signIn = ConnectionGuide.claudeSignIn.walkthrough(claudeExecutable: local)
        XCTAssertEqual(signIn.start, .copyAndOpen(text: "/Users/ana/.local/bin/claude auth login", app: .terminal))
        XCTAssertTrue(signIn.steps.contains { $0.copyable == "/Users/ana/.local/bin/claude auth login" })
        // Other guides don't change with it.
        XCTAssertEqual(ConnectionGuide.claudeInstall.walkthrough(claudeExecutable: local), ConnectionGuide.claudeInstall.walkthrough())
    }

    func testClaudeSignInQuotesPathsTheShellWouldSplit() {
        XCTAssertEqual(ClaudeConnectionState.signInCommand(executable: URL(fileURLWithPath: "/Users/Ana Lee/.local/bin/claude")),
                       "'/Users/Ana Lee/.local/bin/claude' auth login")
        XCTAssertEqual(ClaudeConnectionState.signInCommand(executable: URL(fileURLWithPath: "/Users/o'neil/.local/bin/claude")),
                       #"'/Users/o'\''neil/.local/bin/claude' auth login"#)
        XCTAssertEqual(ClaudeConnectionState.signInCommand(executable: nil), "claude auth login")
    }

    func testClaudeDiagnosisKeepsWhereClaudeIsOutOfTheSupportDetails() {
        let path = URL(fileURLWithPath: "/Users/ana/.local/bin/claude")
        let diagnosis = ClaudeConnectionState.signedOut.diagnosis(executable: path)
        XCTAssertEqual(diagnosis.executable, path)
        XCTAssertFalse(diagnosis.technical.contains("ana"))
        XCTAssertFalse(diagnosis.details(appVersion: "1", systemVersion: "26.0", checkedAt: Date()).contains("/Users/ana"))
        XCTAssertNil(ClaudeConnectionState.notInstalled.diagnosis(executable: path).executable)
    }

    func testFocusShortcutsNameTheUsersOwnShortcuts() {
        let suggested = ConnectionGuide.focusShortcuts.walkthrough()
        XCTAssertEqual(suggested.steps.compactMap(\.copyable), ["Tabbi Focus On", "Tabbi Focus Off"])
        XCTAssertEqual(suggested.start, .openApp(.shortcuts))

        let custom = ConnectionGuide.focusShortcuts.walkthrough(onShortcut: "Quiet", offShortcut: "Loud")
        XCTAssertEqual(custom.steps.compactMap(\.copyable), ["Quiet", "Loud"])
    }

    /// App Review guideline 5.1.1(iv): the button before a macOS prompt
    /// says Continue, Not now is beside it, and nothing tells the user
    /// which answer to give.
    func testPrimingLeadsToThePromptWithContinueAndNeverSteersTheAnswer() {
        for permission in permissions {
            let priming = permission.priming
            XCTAssertEqual(priming.button, "Continue")
            XCTAssertEqual(priming.notNow, "Not now")
            for text in [priming.title, priming.message] + priming.points {
                XCTAssertFalse(text.localizedCaseInsensitiveContains("allow"), "\(permission) steers the answer: \(text)")
            }
            XCTAssertTrue(priming.message.contains("System Settings"), "\(permission) doesn't say the answer can change")
            XCTAssertFalse(priming.points.isEmpty)
            for text in [priming.title, priming.message] + priming.points {
                assertPlain(text)
                XCTAssertLessThanOrEqual(text.count, 120, "\u{201C}\(text)\u{201D} is too long")
            }
        }
        XCTAssertTrue(ConnectionPermission.automation(.spotify).priming.message.contains("control Spotify"))
    }

    func testGuidesFinishWhenTheirRowIsDone() {
        let noGoogle = CalendarConnectionState(access: .fullAccess, accounts: ["iCloud"]).connectionStatus
        let google = CalendarConnectionState(access: .fullAccess, accounts: ["iCloud", "Google"]).connectionStatus
        let empty = CalendarConnectionState(access: .fullAccess, accounts: []).connectionStatus

        // Opened as the connected row's suggestion: done once Google shows up.
        XCTAssertFalse(noGoogle.finishes(.googleCalendar, openedAsSuggestion: true))
        XCTAssertTrue(google.finishes(.googleCalendar, openedAsSuggestion: true))
        // Opened to fix "No calendars yet": any account will do.
        XCTAssertFalse(empty.finishes(.googleCalendar, openedAsSuggestion: false))
        XCTAssertTrue(noGoogle.finishes(.googleCalendar, openedAsSuggestion: false))

        XCTAssertFalse(AnkiConnectionState.addOnMissing.connectionStatus.finishes(.ankiAddOn, openedAsSuggestion: false))
        XCTAssertTrue(AnkiConnectionState.ready.connectionStatus.finishes(.ankiAddOn, openedAsSuggestion: false))
    }
}
