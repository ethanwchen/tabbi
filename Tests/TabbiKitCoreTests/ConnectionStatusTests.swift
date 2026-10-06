import XCTest
import TabbiKitCore

final class ConnectionStatusTests: XCTestCase {
    // MARK: Every state

    private var everyStatus: [ConnectionStatus] {
        let anki: [AnkiConnectionState] = [
            .checking, .notInstalled, .notRunning, .starting, .addOnMissing,
            .needsPermission(.permissionDenied), .needsPermission(.apiKeyRequired), .addOnOutdated, .ready,
            .problem(.collectionUnavailable), .problem(.timeout), .problem(.transport("refused")),
        ]
        let calendar = CalendarAccess.allCases.flatMap { access in
            [[], ["iCloud"], ["iCloud", "Google"]].map { CalendarConnectionState(access: access, accounts: $0) }
        }
        let claude: [ClaudeConnectionState] = [.checking, .notInstalled, .signedOut, .ready]
        let music = [ConnectionApp.spotify, .music].flatMap { app in
            [false, true].flatMap { installed in
                AutomationPermission.allCases.flatMap { permission in
                    [false, true].map {
                        MusicConnectionState(app: app, isInstalled: installed, permission: permission, grantedBefore: $0)
                    }
                }
            }
        }
        let focus = [nil, [], ["Tabbi Focus On"], ["Tabbi Focus On", "Tabbi Focus Off"]].map {
            FocusShortcutsState(onName: "Tabbi Focus On", offName: "Tabbi Focus Off", installed: $0.map(Set.init))
        }
        let party: [PartyConnectionState] = [.notSetUp, .connecting, .offline, .connected(friendCode: "PUFF-42")]
        return anki.map(\.connectionStatus) + calendar.map(\.connectionStatus) + claude.map(\.connectionStatus)
            + music.map(\.connectionStatus) + NotificationAccess.allCases.map(\.connectionStatus)
            + focus.map(\.connectionStatus) + party.map(\.connectionStatus)
    }

    func testEveryProblemHasExactlyOneNextButton() {
        for status in everyStatus {
            switch status.light {
            case .connected, .checking:
                XCTAssertNil(status.action, "\(status.headline) should need no fix")
            case .needsStep, .notSetUp:
                XCTAssertNotNil(status.action, "\(status.headline) needs a next button")
            case .notInstalled:
                // Apple Music ships with macOS, so it can't be offered for download.
                if status.headline != "Music isn't on this Mac" {
                    XCTAssertNotNil(status.action, "\(status.headline) needs a next button")
                }
            }
        }
    }

    func testCopyAvoidsJargonAndDashes() {
        let banned = ["CLI", "API", "localhost", "port", "error", "TCC", "EventKit", "JSON", "HTTP", "\u{2014}"]
        for status in everyStatus {
            let words = [status.headline, status.detail, status.action?.title, status.suggestion?.title].compactMap { $0 }
            for text in words {
                for term in banned {
                    XCTAssertFalse(text.range(of: "\\b\(term)\\b", options: .regularExpression) != nil,
                                   "\u{201C}\(text)\u{201D} uses \(term)")
                }
                XCTAssertLessThanOrEqual(text.count, 120, "\u{201C}\(text)\u{201D} is too long for one row")
            }
        }
    }

    func testSystemSettingsLinksOpenSystemSettings() {
        for link in SystemSettingsLink.allCases {
            XCTAssertEqual(link.url.scheme, "x-apple.systempreferences")
        }
    }

    func testButtonTitles() {
        XCTAssertEqual(ConnectionAction.download(.anki).title, "Get Anki")
        XCTAssertEqual(ConnectionAction.openApp(.spotify).title, "Open Spotify")
        XCTAssertEqual(ConnectionAction.showGuide(.googleCalendar).title, "Add Google Calendar")
        XCTAssertEqual(ConnectionAction.askPermission(.calendar).title, "Connect")
        XCTAssertEqual(ConnectionLight.needsStep.title, "Needs one step")
    }

    // MARK: Anki

    func testAnkiStepsLeadFromNothingToConnected() {
        XCTAssertEqual(AnkiConnectionState.notInstalled.connectionStatus.action, .download(.anki))
        XCTAssertEqual(AnkiConnectionState.notRunning.connectionStatus.action, .openApp(.anki))
        XCTAssertEqual(AnkiConnectionState.addOnMissing.connectionStatus.light, .notSetUp)
        XCTAssertEqual(AnkiConnectionState.addOnMissing.connectionStatus.action, .showGuide(.ankiAddOn))
        XCTAssertEqual(AnkiConnectionState.addOnOutdated.connectionStatus.action, .showGuide(.ankiAddOnUpdate))
        XCTAssertEqual(AnkiConnectionState.needsPermission(.permissionDenied).connectionStatus.action, .showGuide(.ankiAccess))
        XCTAssertEqual(AnkiConnectionState.starting.connectionStatus.light, .checking)
        XCTAssertTrue(AnkiConnectionState.ready.connectionStatus.isConnected)
    }

    func testAnkiLooksForBothBundleIDs() {
        XCTAssertEqual(Set(ConnectionApp.anki.bundleIDs), ["net.ankiweb.dtop", "net.ankiweb.anki"])
    }

    func testAnkiProfilePickerOpensAnki() {
        XCTAssertEqual(AnkiConnectionState.problem(.collectionUnavailable).connectionStatus.action, .openApp(.anki))
        XCTAssertEqual(AnkiConnectionState.problem(.timeout).connectionStatus.action, .checkAgain)
    }

    // MARK: Calendar

    func testCalendarAccessSteps() {
        XCTAssertEqual(CalendarConnectionState(access: .notDetermined).connectionStatus.action, .askPermission(.calendar))
        for access in [CalendarAccess.denied, .restricted, .writeOnly] {
            let status = CalendarConnectionState(access: access, accounts: ["iCloud"]).connectionStatus
            XCTAssertEqual(status.light, .needsStep)
            XCTAssertEqual(status.action, .openSettings(.calendarPrivacy))
        }
    }

    func testCalendarNeverOffersConnectWhenThisCopyCannotAsk() {
        // macOS terminates a build without a calendar usage description
        // when it asks, so there is no Connect button to press.
        let status = CalendarConnectionState(access: .notDetermined, canAsk: false).connectionStatus
        XCTAssertEqual(status.light, .needsStep)
        XCTAssertNotEqual(status.action, .askPermission(.calendar))
        XCTAssertEqual(status.headline, "This copy can't use the calendar")
        let diagnosis = CalendarConnectionState(access: .notDetermined, canAsk: false).diagnosis
        XCTAssertEqual(diagnosis.firstFailure?.answer, "No. This copy of Tabbi can't ask for it.")
        // Once access is decided, the usual states apply.
        XCTAssertEqual(CalendarConnectionState(access: .denied, canAsk: false).connectionStatus.action,
                       .openSettings(.calendarPrivacy))
    }

    func testCalendarWithoutAccountsGuidesToAddOne() {
        let status = CalendarConnectionState(access: .fullAccess, accounts: []).connectionStatus
        XCTAssertEqual(status.light, .needsStep)
        XCTAssertEqual(status.action, .showGuide(.googleCalendar))
    }

    func testCalendarSuggestsGoogleOnlyWhenMissing() {
        let icloud = CalendarConnectionState(access: .fullAccess, accounts: ["iCloud"]).connectionStatus
        XCTAssertTrue(icloud.isConnected)
        XCTAssertNil(icloud.action)
        XCTAssertEqual(icloud.suggestion, .showGuide(.googleCalendar))
        let google = CalendarConnectionState(access: .fullAccess, accounts: ["iCloud", "Google"]).connectionStatus
        XCTAssertNil(google.suggestion)
    }

    func testGoogleAccountDetection() {
        XCTAssertTrue(CalendarConnectionState.isGoogleAccount("Google"))
        XCTAssertTrue(CalendarConnectionState.isGoogleAccount("med.student@gmail.com"))
        XCTAssertTrue(CalendarConnectionState.isGoogleAccount("Old@GoogleMail.com"))
        XCTAssertFalse(CalendarConnectionState.isGoogleAccount("iCloud"))
        XCTAssertFalse(CalendarConnectionState.isGoogleAccount("Exchange"))
        XCTAssertFalse(CalendarConnectionState.isGoogleAccount("Subscribed Calendars"))
    }

    // MARK: Claude

    func testClaudeSignInProbeParsing() {
        let signedIn = """
        {
          "loggedIn": true,
          "authMethod": "claude.ai",
          "email": "someone@example.com"
        }
        """
        XCTAssertEqual(ClaudeSignIn.parse(authStatusOutput: signedIn), .signedIn)
        XCTAssertEqual(ClaudeSignIn.parse(authStatusOutput: #"{"loggedIn": false}"#), .signedOut)
        XCTAssertEqual(ClaudeSignIn.parse(authStatusOutput: "warning: update available\n{\"loggedIn\":false}\n"), .signedOut)
        XCTAssertEqual(ClaudeSignIn.parse(authStatusOutput: "error: unknown command 'auth'"), .unknown)
        XCTAssertEqual(ClaudeSignIn.parse(authStatusOutput: #"{"loggedIn": "yes"}"#), .unknown)
        XCTAssertEqual(ClaudeSignIn.parse(authStatusOutput: ""), .unknown)
    }

    func testClaudeStates() {
        XCTAssertEqual(ClaudeConnectionState.resolve(isInstalled: false, signIn: .signedIn), .notInstalled)
        XCTAssertEqual(ClaudeConnectionState.resolve(isInstalled: true, signIn: nil), .checking)
        XCTAssertEqual(ClaudeConnectionState.resolve(isInstalled: true, signIn: .signedOut), .signedOut)
        XCTAssertEqual(ClaudeConnectionState.resolve(isInstalled: true, signIn: .signedIn), .ready)
        XCTAssertEqual(ClaudeConnectionState.resolve(isInstalled: true, signIn: .unknown), .ready)
        XCTAssertEqual(ClaudeConnectionState.notInstalled.connectionStatus.action, .showGuide(.claudeInstall))
        XCTAssertEqual(ClaudeConnectionState.signedOut.connectionStatus.action, .showGuide(.claudeSignIn))
        XCTAssertTrue(ClaudeConnectionState.notInstalled.connectionStatus.detail.contains("works without it"))
    }

    // MARK: Music

    func testMusicPermissionSteps() {
        func status(_ permission: AutomationPermission, installed: Bool = true, before: Bool = false) -> ConnectionStatus {
            MusicConnectionState(app: .spotify, isInstalled: installed, permission: permission, grantedBefore: before).connectionStatus
        }
        XCTAssertEqual(status(.granted, installed: false).action, .download(.spotify))
        XCTAssertEqual(status(.notAsked).action, .askPermission(.automation(.spotify)))
        XCTAssertEqual(status(.appClosed).light, .notSetUp)
        XCTAssertTrue(status(.appClosed, before: true).isConnected)
        XCTAssertEqual(status(.denied).action, .openSettings(.automationPrivacy))
        XCTAssertTrue(status(.granted).isConnected)
    }

    // MARK: Notifications

    func testNotificationSteps() {
        XCTAssertEqual(NotificationAccess.notDetermined.connectionStatus.action, .askPermission(.notifications))
        XCTAssertEqual(NotificationAccess.denied.connectionStatus.action, .openSettings(.notifications))
        XCTAssertTrue(NotificationAccess.allowed.connectionStatus.isConnected)
    }

    // MARK: Do Not Disturb

    func testShortcutsListParsing() {
        let output = "Tabbi Focus On\n  Tabbi Focus Off  \n\nMorning Routine\n"
        XCTAssertEqual(FocusShortcutsState.parseList(output), ["Tabbi Focus On", "Tabbi Focus Off", "Morning Routine"])
        XCTAssertEqual(FocusShortcutsState.parseList(""), [])
    }

    func testFocusShortcutSteps() {
        func state(_ installed: Set<String>?) -> FocusShortcutsState {
            FocusShortcutsState(onName: "Tabbi Focus On", offName: "Tabbi Focus Off", installed: installed)
        }
        XCTAssertEqual(state(nil).connectionStatus.light, .checking)
        XCTAssertEqual(state([]).connectionStatus.light, .notSetUp)
        XCTAssertEqual(state([]).missing, ["Tabbi Focus On", "Tabbi Focus Off"])
        let half = state(["Tabbi Focus On"])
        XCTAssertEqual(half.connectionStatus.light, .needsStep)
        XCTAssertTrue(half.connectionStatus.detail.contains("Tabbi Focus Off"))
        XCTAssertTrue(state(["Tabbi Focus On", "Tabbi Focus Off", "Other"]).connectionStatus.isConnected)
    }

    // MARK: Party

    func testPartyStates() {
        XCTAssertEqual(PartyConnectionState.resolve(.connected, friendCode: "PUFF-42", hasChosenName: false), .notSetUp)
        XCTAssertEqual(PartyConnectionState.resolve(.connecting, friendCode: nil, hasChosenName: true), .connecting)
        XCTAssertEqual(PartyConnectionState.resolve(.unreachable(.unreachable), friendCode: nil, hasChosenName: true), .offline)
        XCTAssertEqual(PartyConnectionState.resolve(.connected, friendCode: nil, hasChosenName: true), .connecting)
        XCTAssertEqual(PartyConnectionState.resolve(.connected, friendCode: "PUFF-42", hasChosenName: true),
                       .connected(friendCode: "PUFF-42"))
        XCTAssertEqual(PartyConnectionState.notSetUp.connectionStatus.action, .setUp)
        XCTAssertTrue(PartyConnectionState.connected(friendCode: "PUFF-42").connectionStatus.detail.contains("PUFF-42"))
    }

    func testConnectedPartyOffersToCopyItsFriendCode() {
        let status = PartyConnectionState.connected(friendCode: "PUFF-42").connectionStatus
        XCTAssertNil(status.action)
        XCTAssertEqual(status.suggestion, .copyFriendCode("PUFF-42"))
        XCTAssertEqual(status.suggestion?.title, "Copy friend code")
    }

    func testPartySetupNeedsARealName() {
        XCTAssertNil(PartySetup.name(from: ""))
        XCTAssertNil(PartySetup.name(from: "   \n"))
        XCTAssertNil(PartySetup.name(from: "\u{200B}"))
        XCTAssertEqual(PartySetup.name(from: "  Sam "), "Sam")
        let long = String(repeating: "a", count: PartySettings.maxNameLength + 10)
        XCTAssertEqual(PartySetup.name(from: long)?.count, PartySettings.maxNameLength)
    }

    func testPartySetupCopyIsPlain() {
        let copy = [PartySetup.title, PartySetup.intro, PartySetup.nameLabel, PartySetup.namePlaceholder,
                    PartySetup.petLabel, PartySetup.petNote, PartySetup.start, PartySetup.readyTitle,
                    PartySetup.readyIntro]
        for line in copy {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            for word in ["account name", "server", "API", "register", "token"] {
                XCTAssertFalse(line.localizedCaseInsensitiveContains(word), "\(line) says \(word)")
            }
        }
    }
}
