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

    func testFocusShortcutsNameTheUsersOwnShortcuts() {
        let suggested = ConnectionGuide.focusShortcuts.walkthrough()
        XCTAssertEqual(suggested.steps.compactMap(\.copyable), ["Tabbi Focus On", "Tabbi Focus Off"])
        XCTAssertEqual(suggested.start, .openApp(.shortcuts))

        let custom = ConnectionGuide.focusShortcuts.walkthrough(onShortcut: "Quiet", offShortcut: "Loud")
        XCTAssertEqual(custom.steps.compactMap(\.copyable), ["Quiet", "Loud"])
    }

    func testPrimingLeadsToThePromptWithContinue() {
        for permission in permissions {
            let priming = permission.priming
            XCTAssertEqual(priming.button, "Continue")
            XCTAssertTrue(priming.message.contains("Click Allow"), "\(permission) doesn't say which button to click")
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
