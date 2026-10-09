import XCTest
import TabbiKitCore
@testable import Tabbi

/// Schedule's Day view stepped to yesterday and tomorrow, on the demo
/// calendar: which day the timeline shows, and what Plan does there.
@MainActor
final class ScheduleDayStepTests: XCTestCase {
    private let calendar = Calendar.current

    private func midnight(_ offset: Int, from store: ScheduleStore) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: store.now))!
    }

    func testTodayIsTheDefaultAndClosingThePanelGoesBackToIt() {
        let store = ScheduleStore(runMode: .demo)
        XCTAssertEqual(store.viewing, .today)
        XCTAssertEqual(store.dayLayout.day, midnight(0, from: store))
        store.setVisible(true)
        store.show(.tomorrow)
        XCTAssertEqual(store.viewing, .tomorrow)
        store.setVisible(false)
        XCTAssertEqual(store.viewing, .today)
    }

    func testYesterdayShowsWhatHappenedAndHasNothingToPlan() {
        let store = ScheduleStore(runMode: .demo)
        store.show(.yesterday)
        let layout = store.dayLayout
        XCTAssertEqual(layout.day, midnight(-1, from: store))
        XCTAssertFalse(layout.placed.isEmpty, "The demo has a calendar for yesterday")
        XCTAssertTrue(layout.placed.allSatisfy { calendar.isDate($0.item.start, inSameDayAs: layout.day) })
        XCTAssertEqual(layout.freeMinutes, 0)
        store.planDay()
        XCTAssertNil(store.draft, "Yesterday is over, so Plan does nothing there")
    }

    func testPlanOnTomorrowFillsTomorrowAroundItsEventsAndSteppingAwayDiscardsIt() throws {
        let store = ScheduleStore(runMode: .demo)
        store.show(.tomorrow)
        let tomorrow = midnight(1, from: store)
        XCTAssertEqual(store.dayLayout.day, tomorrow)
        XCTAssertGreaterThan(store.dayLayout.freeMinutes, 0, "Tomorrow's working day hasn't started")
        store.planDay()
        let draft = try XCTUnwrap(store.draft)
        XCTAssertFalse(draft.items.isEmpty)
        let events = store.items.filter { $0.kind != .proposed && !$0.isAllDay }
        for block in draft.items {
            XCTAssertTrue(calendar.isDate(block.start, inSameDayAs: tomorrow), "\(block.title) is planned for tomorrow")
            XCTAssertFalse(events.contains { $0.start < block.end && block.start < $0.end },
                           "\(block.title) doesn't overlap an event")
        }
        XCTAssertFalse(store.canRefine, "Claude's day prompt plans from now, so tomorrow's plan stays local")
        store.show(.today)
        XCTAssertNil(store.draft, "A plan belongs to the day it was made for")
    }
}
