import XCTest
import TabbiKitCore

final class UpNextEmptyStateTests: XCTestCase {
    // MARK: - Choosing a state

    func testEventsAheadNeedNoEmptyState() {
        XCTAssertNil(UpNextEmptyState.granted(upcoming: 2, eventsToday: 4, hasAccounts: false))
    }

    func testFinishedDaySaysTheRestIsYours() {
        XCTAssertEqual(UpNextEmptyState.granted(upcoming: 0, eventsToday: 3, hasAccounts: false), .dayDone)
    }

    func testEmptyDayWithAnAccountIsAFreeDay() {
        XCTAssertEqual(UpNextEmptyState.granted(upcoming: 0, eventsToday: 0, hasAccounts: true), .freeDay)
    }

    func testEmptyDayWithOnlyLocalCalendarsSuggestsAddingAnAccount() {
        XCTAssertEqual(UpNextEmptyState.granted(upcoming: 0, eventsToday: 0, hasAccounts: false), .noAccounts)
    }

    // MARK: - Wording and actions

    func testFirstRunExplainsGoogleCalendarsInTheKitsWords() {
        let state = UpNextEmptyState(.notAsked, upNextEvents: "lectures, labs, and shifts", appName: "Tabbi")
        XCTAssertEqual(state.action, .requestAccess)
        XCTAssertTrue(state.detail.contains("lectures, labs, and shifts"))
        XCTAssertTrue(state.detail.contains("Google"))
        XCTAssertTrue(state.detail.contains("Internet Accounts"))
        XCTAssertTrue(state.actionHelp.contains("Tabbi"))
    }

    func testNoAccountsOpensInternetAccounts() {
        let state = UpNextEmptyState(.noAccounts, upNextEvents: "meetings and calls", appName: "Tabbi")
        XCTAssertEqual(state.action, .openInternetAccounts)
        XCTAssertEqual(state.actionTitle, "Internet Accounts")
        XCTAssertTrue(state.detail.contains("meetings and calls"))
        XCTAssertTrue(state.detail.contains("Google"))
    }

    func testDeniedLinksToPrivacySettings() {
        let state = UpNextEmptyState(.denied, upNextEvents: "meetings and calls", appName: "Tabbi")
        XCTAssertEqual(state.action, .openPrivacySettings)
        XCTAssertTrue(state.detail.contains("Tabbi"))
    }

    func testUnavailableCalendarSendsUserToConnections() {
        let state = UpNextEmptyState(.unavailable, upNextEvents: "meetings and calls", appName: "Tabbi")
        XCTAssertEqual(state.action, .openConnections)
        XCTAssertEqual(state.actionTitle, "Connect calendar")
        XCTAssertTrue(state.detail.contains("meetings and calls"))
        // The user is already in the app; never tell them to open it.
        XCTAssertFalse(state.detail.contains("Open the"))
    }

    func testInformationalStatesHaveNoButton() {
        for situation in [UpNextEmptyState.Situation.freeDay, .dayDone] {
            let state = UpNextEmptyState(situation, upNextEvents: "meetings and calls", appName: "Tabbi")
            XCTAssertNil(state.action, "\(situation)")
            XCTAssertTrue(state.actionTitle.isEmpty, "\(situation)")
            XCTAssertFalse(state.title.isEmpty, "\(situation)")
        }
    }
}
