import Foundation
import TabbiKitCore
import XCTest

final class SeasonalEventTests: XCTestCase {
    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0,
                      in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let halloween = SeasonalEvent(
        id: "halloween", name: "Halloween", tagline: "Spooky season.",
        start: SeasonalEventDay(month: 10, day: 17), end: SeasonalEventDay(month: 11, day: 2),
        rewards: [SeasonalEventReward(item: .accessory(.witchHat), focusMinutes: 90),
                  SeasonalEventReward(item: .accessory(.halo), focusMinutes: 300)]
    )

    private let winter = SeasonalEvent(
        id: "winter", name: "Winter Holidays", tagline: "Warm drinks, cozy focus.",
        start: SeasonalEventDay(month: 12, day: 14), end: SeasonalEventDay(month: 1, day: 3),
        rewards: [SeasonalEventReward(item: .accessory(.beanie), focusMinutes: 240)]
    )

    private let lunarNewYear = SeasonalEvent(
        id: "lunar-new-year", name: "Lunar New Year", tagline: "A fresh start.", calendar: .chinese,
        start: SeasonalEventDay(month: 1, day: 1), end: SeasonalEventDay(month: 1, day: 15),
        rewards: [SeasonalEventReward(item: .accessory(.tinyCrown), focusMinutes: 180)]
    )

    private func focus(_ minutes: Double, endingAt end: Date, source: ModuleID = "focus") -> ActivityRecord {
        ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                       end: end, quantity: minutes, unit: .minutes)
    }

    // MARK: Date windows

    func testWindowRunsFromLocalMidnightOfTheFirstDayThroughTheLastDay() {
        let calendar = calendar()
        let occurrence = halloween.occurrence(containing: date(2026, 10, 20, hour: 15, in: calendar), calendar: calendar)
        XCTAssertEqual(occurrence?.start, date(2026, 10, 17, in: calendar))
        XCTAssertEqual(occurrence?.end, date(2026, 11, 3, in: calendar))

        XCTAssertNotNil(halloween.occurrence(containing: date(2026, 10, 17, in: calendar), calendar: calendar))
        XCTAssertNotNil(halloween.occurrence(containing: date(2026, 11, 2, hour: 23, minute: 59, in: calendar),
                                             calendar: calendar))
        XCTAssertNil(halloween.occurrence(containing: date(2026, 10, 16, hour: 23, minute: 59, in: calendar),
                                          calendar: calendar))
        XCTAssertNil(halloween.occurrence(containing: date(2026, 11, 3, in: calendar), calendar: calendar))
        XCTAssertNil(halloween.occurrence(containing: date(2026, 7, 1, in: calendar), calendar: calendar))
    }

    func testWindowFollowsTheLocalTimeZone() {
        // The same instant: 03:00 on October 17 in Berlin is still October
        // 16 in New York, so the event has started in one and not the other.
        let berlin = calendar("Europe/Berlin")
        let instant = date(2026, 10, 17, hour: 3, in: berlin)
        XCTAssertNotNil(halloween.occurrence(containing: instant, calendar: berlin))
        XCTAssertNil(halloween.occurrence(containing: instant, calendar: calendar()))

        let tokyo = calendar("Asia/Tokyo")
        XCTAssertEqual(halloween.occurrence(containing: date(2026, 10, 25, in: tokyo), calendar: tokyo)?.start,
                       date(2026, 10, 17, in: tokyo))
    }

    func testWindowKeepsWholeDaysAcrossADaylightSavingChange() {
        // New York falls back on November 1, 2026: that day is 25 hours long.
        let calendar = calendar()
        let occurrence = halloween.occurrence(containing: date(2026, 11, 1, hour: 12, in: calendar), calendar: calendar)
        XCTAssertEqual(occurrence?.end, date(2026, 11, 3, in: calendar))
    }

    func testWindowWrapsOverNewYear() {
        let calendar = calendar()
        let december = winter.occurrence(containing: date(2026, 12, 31, hour: 22, in: calendar), calendar: calendar)
        let january = winter.occurrence(containing: date(2027, 1, 2, in: calendar), calendar: calendar)
        XCTAssertEqual(december, january)
        XCTAssertEqual(january?.start, date(2026, 12, 14, in: calendar))
        XCTAssertEqual(january?.end, date(2027, 1, 4, in: calendar))
        XCTAssertEqual(january?.id(calendar: calendar), "winter-2026")

        XCTAssertNil(winter.occurrence(containing: date(2027, 1, 4, in: calendar), calendar: calendar))
        XCTAssertNil(winter.occurrence(containing: date(2026, 12, 13, hour: 23, in: calendar), calendar: calendar))
    }

    func testLunarNewYearFollowsTheChineseCalendar() {
        let calendar = calendar()
        // Lunar New Year: February 6, 2027 and January 26, 2028.
        let first = lunarNewYear.occurrence(containing: date(2027, 2, 10, in: calendar), calendar: calendar)
        XCTAssertEqual(first?.start, date(2027, 2, 6, in: calendar))
        XCTAssertEqual(first?.end, date(2027, 2, 21, in: calendar))
        XCTAssertNil(lunarNewYear.occurrence(containing: date(2027, 2, 5, in: calendar), calendar: calendar))

        let second = lunarNewYear.nextOccurrence(after: date(2027, 3, 1, in: calendar), calendar: calendar)
        XCTAssertEqual(second?.start, date(2028, 1, 26, in: calendar))
    }

    func testNextOccurrenceComesBackNextYear() {
        let calendar = calendar()
        let next = halloween.nextOccurrence(after: date(2026, 10, 20, in: calendar), calendar: calendar)
        XCTAssertEqual(next?.start, date(2027, 10, 17, in: calendar))
        XCTAssertEqual(next?.id(calendar: calendar), "halloween-2027")
    }

    func testCatalogPutsTheEventEndingSoonestFirstAndFindsTheNextOne() {
        let calendar = calendar()
        let valentines = SeasonalEvent(
            id: "valentines", name: "Valentine's", tagline: "Love what you learn.",
            start: SeasonalEventDay(month: 2, day: 7), end: SeasonalEventDay(month: 2, day: 14),
            rewards: [SeasonalEventReward(item: .accessory(.roundGlasses), focusMinutes: 60)]
        )
        let catalog = SeasonalEventCatalog(events: [halloween, winter, lunarNewYear, valentines])
        let both = catalog.active(at: date(2027, 2, 10, in: calendar), calendar: calendar)
        XCTAssertEqual(both.map(\.event.id), ["valentines", "lunar-new-year"])
        XCTAssertEqual(catalog.active(at: date(2027, 3, 10, in: calendar), calendar: calendar), [])

        XCTAssertEqual(catalog.next(after: date(2027, 3, 10, in: calendar), calendar: calendar)?.event.id, "halloween")
        XCTAssertEqual(catalog.next(after: date(2026, 11, 10, in: calendar), calendar: calendar)?.event.id, "winter")
        XCTAssertEqual(catalog.event(offering: .accessory(.beanie))?.id, "winter")
        XCTAssertNil(catalog.event(offering: .accessory(.chefHat)))
    }

    // MARK: Earning

    func testOnlyFocusLoggedDuringTheRunCounts() throws {
        let calendar = calendar()
        let occurrence = try XCTUnwrap(halloween.occurrence(containing: date(2026, 10, 20, in: calendar),
                                                            calendar: calendar))
        let inside = focus(50, endingAt: date(2026, 10, 18, hour: 10, in: calendar))
        let records = [
            inside, inside,
            focus(45, endingAt: date(2026, 11, 2, hour: 23, in: calendar)),
            focus(200, endingAt: date(2026, 10, 16, hour: 23, in: calendar)),
            focus(200, endingAt: date(2026, 11, 3, hour: 1, in: calendar)),
            focus(30, endingAt: date(2025, 10, 20, in: calendar)),
            ActivityRecord(source: "focus", kind: .breakTaken, start: date(2026, 10, 19, in: calendar),
                           end: date(2026, 10, 19, hour: 1, in: calendar), quantity: 60, unit: .minutes),
            ActivityRecord(source: "anki", kind: .cardsReviewed, start: date(2026, 10, 19, in: calendar),
                           quantity: 80, unit: .cards),
        ]
        let progress = SeasonalEventProgress(occurrence: occurrence, records: records)
        XCTAssertEqual(progress.focusMinutes, 95)
        XCTAssertEqual(progress.earned, [.accessory(.witchHat)])
        XCTAssertEqual(progress.nextReward?.item, .accessory(.halo))
    }

    func testRewardsAreEarnedInOrderAndProgressReads() throws {
        let calendar = calendar()
        let occurrence = try XCTUnwrap(halloween.occurrence(containing: date(2026, 10, 20, in: calendar),
                                                            calendar: calendar))
        var progress = SeasonalEventProgress(occurrence: occurrence)
        XCTAssertEqual(progress.earned, [])
        XCTAssertEqual(progress.nextReward?.item, .accessory(.witchHat))
        XCTAssertEqual(progress.progress(of: halloween.rewards[0]).label, "0/90 min")

        progress.add(focus(75, endingAt: date(2026, 10, 18, hour: 9, in: calendar)))
        XCTAssertEqual(progress.progress(of: halloween.rewards[0]).label, "75/90 min")
        XCTAssertEqual(progress.progress(of: halloween.rewards[1]).label, "1/5 h")

        progress.add(focus(250, endingAt: date(2026, 10, 25, hour: 9, in: calendar)))
        XCTAssertEqual(progress.earned, [.accessory(.witchHat), .accessory(.halo)])
        XCTAssertNil(progress.nextReward)
        let headline = progress.progress(of: halloween.rewards[1])
        XCTAssertEqual(headline.label, "5/5 h")
        XCTAssertEqual(headline.fraction, 1)
        XCTAssertEqual(halloween.headline, .accessory(.halo))
    }

    func testAMissedItemStartsOverWhenTheEventReturns() throws {
        let calendar = calendar()
        let thisYear = try XCTUnwrap(halloween.occurrence(containing: date(2026, 10, 20, in: calendar),
                                                          calendar: calendar))
        let nextYear = try XCTUnwrap(halloween.nextOccurrence(after: thisYear.start, calendar: calendar))
        let records = [focus(200, endingAt: date(2026, 10, 20, in: calendar)),
                       focus(60, endingAt: date(2027, 10, 20, in: calendar))]
        XCTAssertEqual(SeasonalEventProgress(occurrence: thisYear, records: records).focusMinutes, 200)
        XCTAssertEqual(SeasonalEventProgress(occurrence: nextYear, records: records).focusMinutes, 60)
    }

    // MARK: Catalog file

    private func file(_ events: String, schema: String = "events.v1") -> Data {
        Data(#"{"schema": "\#(schema)", "events": [\#(events)]}"#.utf8)
    }

    private func event(id: String = "halloween", calendar: String = "gregorian",
                       start: String = #"{"month": 10, "day": 17}"#, end: String = #"{"month": 11, "day": 2}"#,
                       rewards: String = #"[{"item": "accessory.witchHat", "focusMinutes": 90}]"#) -> String {
        #"{"id": "\#(id)", "name": "Halloween", "tagline": "Spooky season.", "calendar": "\#(calendar)", "start": \#(start), "end": \#(end), "rewards": \#(rewards)}"#
    }

    func testDecodesAValidFile() throws {
        let catalog = try SeasonalEventCatalog.decode(file(event() + "," + event(
            id: "lunar-new-year", calendar: "chinese", start: #"{"month": 1, "day": 1}"#,
            end: #"{"month": 1, "day": 15}"#,
            rewards: #"[{"item": "accessory.beanie", "focusMinutes": 60}, {"item": "accessory.halo", "focusMinutes": 180}]"#
        )))
        XCTAssertEqual(catalog.events.map(\.id), ["halloween", "lunar-new-year"])
        XCTAssertEqual(catalog.events[0].rewards, [SeasonalEventReward(item: .accessory(.witchHat), focusMinutes: 90)])
        XCTAssertEqual(catalog.events[1].calendar, .chinese)
        XCTAssertEqual(catalog.events[1].headline, .accessory(.halo))
    }

    func testRejectsBadFiles() {
        func rejects(_ data: Data, _ path: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try SeasonalEventCatalog.decode(data), file: file, line: line) { error in
                guard case .invalidValue(let found, _) = error as? SeasonalEventCatalog.LoadError else {
                    return XCTFail("Unexpected error \(error)", file: file, line: line)
                }
                XCTAssertEqual(found, path, file: file, line: line)
            }
        }
        XCTAssertThrowsError(try SeasonalEventCatalog.decode(file(event(), schema: "events.v2"))) { error in
            XCTAssertEqual(error as? SeasonalEventCatalog.LoadError, .unsupportedSchema("events.v2"))
        }
        rejects(file(event(id: "Halloween")), "events[0].id")
        rejects(file(event() + "," + event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 60}]"#)),
                "events[1].id")
        rejects(file(event(start: #"{"month": 2, "day": 29}"#)), "events[0].start")
        rejects(file(event(end: #"{"month": 13, "day": 1}"#)), "events[0].end")
        rejects(file(event(calendar: "chinese", end: #"{"month": 1, "day": 30}"#)), "events[0].end")
        rejects(file(event(rewards: "[]")), "events[0].rewards")
        rejects(file(event(rewards: #"[{"item": "accessory.nope", "focusMinutes": 60}]"#)), "events[0].rewards[0].item")
        rejects(file(event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 0}]"#)),
                "events[0].rewards[0].focusMinutes")
        rejects(file(event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 150}]"#)),
                "events[0].rewards[0].focusMinutes")
        rejects(file(event(rewards: #"[{"item": "accessory.beanie", "focusMinutes": 60}, {"item": "accessory.halo", "focusMinutes": 60}]"#)),
                "events[0].rewards[1].focusMinutes")
        rejects(file(event() + "," + event(id: "fall")), "events[1].rewards[0].item")
    }
}
