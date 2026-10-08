import XCTest
import EventKit
import TabbiKitCore
@testable import Tabbi

/// macOS terminates an app that asks for calendar access without a usage
/// description (a bare `swift run`, or this test bundle). Every request path
/// must notice that and report the calendar as unavailable instead of asking.
@MainActor
final class CalendarAccessGuardTests: XCTestCase {
    /// Xcode 27's `xctest` host declares a calendar usage description of its
    /// own, so there the guard rightly lets requests through; skip rather
    /// than fail, and rather than show a real calendar prompt.
    override func setUp() async throws {
        try XCTSkipIf(ConnectionProbes.canAskForCalendar,
                      "The test host declares NSCalendarsFullAccessUsageDescription")
    }

    func testTheTestBundleHasNoUsageDescription() {
        XCTAssertFalse(ConnectionProbes.canAskForCalendar)
    }

    func testTheSharedRequestDoesNotAskWithoutAUsageDescription() async {
        let asked = await ConnectionProbes.requestCalendarAccess(EKEventStore())
        XCTAssertFalse(asked)
    }

    func testTodayAndPlanMyDayReportTheCalendarUnavailable() async {
        let store = UpNextStore(runMode: .live)
        XCTAssertEqual(store.access, .unavailable)
        let access = await store.ensureAccess()
        XCTAssertEqual(access, .unavailable)
    }

    func testScheduleReportsTheCalendarUnavailable() {
        let store = ScheduleStore(runMode: .live)
        store.requestAccess()
        XCTAssertEqual(store.access, .unavailable)
    }
}
