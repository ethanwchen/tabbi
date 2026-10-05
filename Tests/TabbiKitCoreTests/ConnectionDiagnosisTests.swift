import XCTest
import TabbiKitCore

final class ConnectionDiagnosisTests: XCTestCase {
    private let banned = ["CLI", "API", "localhost", "port", "error", "TCC", "EventKit", "JSON", "HTTP", "\u{2014}"]

    private var everyDiagnosis: [ConnectionDiagnosis] {
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
        return anki.map(\.diagnosis) + calendar.map(\.diagnosis) + claude.map(\.diagnosis) + music.map(\.diagnosis)
            + NotificationAccess.allCases.map(\.diagnosis) + focus.map(\.diagnosis) + party.map(\.diagnosis)
    }

    func testChecksAgreeWithTheLight() {
        for diagnosis in everyDiagnosis {
            let label = "\(diagnosis.kind) \(diagnosis.technical)"
            XCTAssertFalse(diagnosis.checks.isEmpty, "\(label) has no checks")
            switch diagnosis.status.light {
            case .connected:
                XCTAssertNil(diagnosis.firstFailure, "\(label) is connected but a check failed")
                XCTAssertFalse(diagnosis.checks.contains { $0.outcome == .skipped }, "\(label) skipped a check")
            case .checking:
                XCTAssertNil(diagnosis.firstFailure, "\(label) is still checking but a check failed")
                XCTAssertTrue(diagnosis.checks.contains { $0.outcome == .skipped }, "\(label) should show a check running")
            case .needsStep, .notSetUp, .notInstalled:
                XCTAssertNotNil(diagnosis.firstFailure, "\(label) has a problem but no check explains it")
            }
        }
    }

    func testEveryAnswerIsPlainAndShort() {
        for diagnosis in everyDiagnosis {
            for text in [diagnosis.verdict] + diagnosis.checks.flatMap({ [$0.question, $0.answer] }) {
                for term in banned {
                    XCTAssertNil(text.range(of: "\\b\(term)\\b", options: .regularExpression),
                                 "\u{201C}\(text)\u{201D} uses \(term)")
                }
                XCTAssertLessThanOrEqual(text.count, 160, "\u{201C}\(text)\u{201D} is too long")
            }
        }
    }

    func testChecksAfterAFailureAreSkipped() {
        let checks = AnkiConnectionState.notRunning.diagnosis.checks
        XCTAssertEqual(checks.map(\.outcome), [.passed, .failed, .skipped, .skipped, .skipped, .skipped])
        XCTAssertEqual(checks[1].question, "Is Anki open?")
        XCTAssertEqual(checks[2].answer, ConnectionCheck.notReached)
    }

    func testAnkiStartingShowsTheAddOnCheckStillRunning() {
        let checks = AnkiConnectionState.starting.diagnosis.checks
        XCTAssertEqual(checks[2].outcome, .skipped)
        XCTAssertEqual(checks[2].answer, ConnectionCheck.stillChecking)
    }

    func testAnkiProfilePickerIsTheLastCheck() {
        let diagnosis = AnkiConnectionState.problem(.collectionUnavailable).diagnosis
        XCTAssertEqual(diagnosis.firstFailure?.question, "Can Tabbi see your cards?")
        XCTAssertTrue(diagnosis.firstFailure?.answer.contains("profile") ?? false)
    }

    func testBothShortcutsAreCheckedEvenWhenOneIsMissing() {
        let state = FocusShortcutsState(onName: "Quiet", offName: "Loud", installed: ["Loud"])
        XCTAssertEqual(state.diagnosis.checks.map(\.outcome), [.failed, .passed])
        XCTAssertTrue(state.diagnosis.checks[0].question.contains("Quiet"))
    }

    func testMissingGoogleCalendarIsOnlyANote() {
        let diagnosis = CalendarConnectionState(access: .fullAccess, accounts: ["iCloud"]).diagnosis
        XCTAssertTrue(diagnosis.status.isConnected)
        XCTAssertEqual(diagnosis.checks.last?.outcome, .note)
    }

    func testDetailsNameVersionsAndChecksButNoAccountNames() throws {
        let diagnosis = CalendarConnectionState(access: .fullAccess, accounts: ["me@gmail.com", "iCloud"]).diagnosis
        let checkedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T09:30:00Z"))
        let details = diagnosis.details(appVersion: "Version 1.2 (34)", systemVersion: "15.1",
                                        checkedAt: checkedAt, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(details.contains("Connection: Calendar"))
        XCTAssertTrue(details.contains("Status: Connected (Calendar is connected)"))
        XCTAssertTrue(details.contains("Checked: 2026-10-05 09:30"))
        XCTAssertTrue(details.contains("Tabbi: Version 1.2 (34)"))
        XCTAssertTrue(details.contains("macOS: 15.1"))
        XCTAssertTrue(details.contains("State: calendar.fullAccess accounts=2 google=true"))
        XCTAssertTrue(details.contains("[ok] Does your Mac have any calendars? Yes, from 2 accounts."))
        XCTAssertFalse(details.contains("me@gmail.com"))
        XCTAssertFalse(details.contains("\u{2014}"))
    }

    func testVerdictLeadsWithTheProblem() {
        XCTAssertEqual(ClaudeConnectionState.signedOut.diagnosis.verdict,
                       "Sign in to Claude. Claude is installed. Sign in once and Tabbi can use it.")
        XCTAssertTrue(NotificationAccess.allowed.diagnosis.verdict.hasPrefix("Everything checks out."))
    }

    func testDemoDiagnosesMatchDemoStatuses() {
        for kind in ConnectionKind.allCases {
            XCTAssertEqual(kind.demoDiagnosis.kind, kind)
            XCTAssertEqual(kind.demoDiagnosis.status, kind.demoStatus)
        }
    }
}
