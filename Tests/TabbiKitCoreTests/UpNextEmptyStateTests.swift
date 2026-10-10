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

    func testAnotherDayIsEmptyOnlyWithoutAnyTimedEvent() {
        XCTAssertNil(UpNextEmptyState.granted(on: .tomorrow, upcoming: 2, eventsThatDay: 2, hasAccounts: true))
        XCTAssertEqual(UpNextEmptyState.granted(on: .tomorrow, upcoming: 0, eventsThatDay: 0, hasAccounts: true),
                       .freeTomorrow)
        XCTAssertEqual(UpNextEmptyState.granted(on: .yesterday, upcoming: 0, eventsThatDay: 0, hasAccounts: true),
                       .freeYesterday)
        // Yesterday's events are all over, but that's no "day done" there: they're listed.
        XCTAssertNil(UpNextEmptyState.granted(on: .yesterday, upcoming: 3, eventsThatDay: 3, hasAccounts: true))
        XCTAssertEqual(UpNextEmptyState.granted(on: .tomorrow, upcoming: 0, eventsThatDay: 0, hasAccounts: false),
                       .noAccounts)
    }

    func testTodayStillMeansWhatIsLeft() {
        XCTAssertEqual(UpNextEmptyState.granted(on: .today, upcoming: 0, eventsThatDay: 4, hasAccounts: true), .dayDone)
        XCTAssertEqual(UpNextEmptyState.granted(on: .today, upcoming: 0, eventsThatDay: 0, hasAccounts: true), .freeDay)
    }

    func testOtherDaysEmptyStatesNameTheirDay() {
        let tomorrow = UpNextEmptyState(.freeTomorrow, upNextEvents: "meetings and calls", appName: "Tabbi")
        let yesterday = UpNextEmptyState(.freeYesterday, upNextEvents: "meetings and calls", appName: "Tabbi")
        XCTAssertTrue(tomorrow.detail.contains("tomorrow"))
        XCTAssertTrue(yesterday.detail.contains("yesterday"))
        XCTAssertNil(tomorrow.action)
        XCTAssertNil(yesterday.action)
    }
}
