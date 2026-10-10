import XCTest
@testable import TabbiKitCore

final class SeasonalEventGreetingTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func ids(_ runs: [SeasonalEventOccurrence]) -> [String] {
        runs.map { $0.id(calendar: calendar) }
    }

    func testEachRunIsGreetedOnceAndNothingBetweenEvents() {
        var greeting = SeasonalEventGreeting()
        XCTAssertEqual(greeting.greet(at: date(2026, 10, 10, hour: 9), calendar: calendar), [])
        XCTAssertEqual(ids(greeting.greet(at: date(2026, 10, 17, hour: 9), calendar: calendar)), ["halloween-2026"])
        XCTAssertEqual(greeting.greet(at: date(2026, 10, 17, hour: 10), calendar: calendar), [])
        XCTAssertEqual(greeting.greet(at: date(2026, 10, 31, hour: 22), calendar: calendar), [])
        XCTAssertEqual(greeting.due(at: date(2026, 10, 25), calendar: calendar), [])
    }

    func testNextYearsRunIsGreetedAgainAndOldRunsAreDropped() {
        var greeting = SeasonalEventGreeting()
        greeting.greet(at: date(2026, 10, 20), calendar: calendar)
        greeting.greet(at: date(2026, 12, 20), calendar: calendar)
        XCTAssertEqual(greeting.greetedRuns, ["winter-holidays-2026"])
        XCTAssertEqual(ids(greeting.greet(at: date(2027, 10, 17, hour: 8), calendar: calendar)), ["halloween-2027"])
    }

    func testAWinterRunOverNewYearIsGreetedOnlyOnce() {
        var greeting = SeasonalEventGreeting()
        XCTAssertEqual(ids(greeting.greet(at: date(2026, 12, 31, hour: 23), calendar: calendar)),
                       ["winter-holidays-2026"])
        XCTAssertEqual(greeting.greet(at: date(2027, 1, 2), calendar: calendar), [])
    }

    func testOverlappingEventsShareOneMomentAndALaterOneStillGetsItsOwn() {
        var greeting = SeasonalEventGreeting()
        // Lunar New Year 2027 starts Feb 6; Valentine's Week starts inside it.
        XCTAssertEqual(ids(greeting.greet(at: date(2027, 2, 6, hour: 9), calendar: calendar)), ["lunar-new-year-2027"])
        XCTAssertEqual(ids(greeting.greet(at: date(2027, 2, 8, hour: 9), calendar: calendar)), ["valentines-2027"])

        var late = SeasonalEventGreeting()
        XCTAssertEqual(ids(late.greet(at: date(2027, 2, 10), calendar: calendar)),
                       ["valentines-2027", "lunar-new-year-2027"])
    }

    func testNextCheckIsTheStartOfTheNextRun() {
        XCTAssertEqual(SeasonalEventGreeting.nextCheck(after: date(2026, 10, 10, hour: 12), calendar: calendar),
                       date(2026, 10, 17))
        XCTAssertEqual(SeasonalEventGreeting.nextCheck(after: date(2026, 10, 17, hour: 12), calendar: calendar),
                       date(2026, 12, 14))
    }

    func testTheSaveRoundTripsAndReadsADamagedListAsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("events.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(try SeasonalEventGreeting.load(from: url))

        var greeting = SeasonalEventGreeting()
        greeting.greet(at: date(2026, 10, 20), calendar: calendar)
        try greeting.write(to: url)
        XCTAssertEqual(try SeasonalEventGreeting.load(from: url), greeting)
        let json = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\""))

        let damaged = Data(#"{"schemaVersion": 1, "greetedRuns": 7}"#.utf8)
        let read = try SeasonalEventGreeting.schema.decode(SeasonalEventGreeting.self, from: damaged)
        XCTAssertEqual(read.greetedRuns, [])
    }
}
