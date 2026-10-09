import XCTest
@testable import TabbiKitCore

final class DurationFormatTests: XCTestCase {
    func testMinutesUnderAnHourUseTheWord() {
        XCTAssertEqual(DurationFormat.minutes(-5), "0 min")
        XCTAssertEqual(DurationFormat.minutes(0), "0 min")
        XCTAssertEqual(DurationFormat.minutes(45), "45 min")
        XCTAssertEqual(DurationFormat.minutes(59), "59 min")
    }

    func testHoursAreCompact() {
        XCTAssertEqual(DurationFormat.minutes(60), "1h")
        XCTAssertEqual(DurationFormat.minutes(75), "1h 15m")
        XCTAssertEqual(DurationFormat.minutes(120), "2h")
        XCTAssertEqual(DurationFormat.minutes(125), "2h 5m")
    }

    func testSecondsRoundUpToTheMinute() {
        XCTAssertEqual(DurationFormat.seconds(0), "<1 min")
        XCTAssertEqual(DurationFormat.seconds(30), "<1 min")
        XCTAssertEqual(DurationFormat.seconds(60), "1 min")
        XCTAssertEqual(DurationFormat.seconds(61), "2 min")
        XCTAssertEqual(DurationFormat.seconds(2 * 3600 + 13 * 60 + 5), "2h 14m")
    }

    func testCountdown() {
        XCTAssertEqual(DurationFormat.countdown(minutes: 12), "in 12 min")
        XCTAssertEqual(DurationFormat.countdown(minutes: 60), "in 1h")
        XCTAssertEqual(DurationFormat.countdown(minutes: 94), "in 1h 34m")
    }

    func testQuantityWritesMinutesAsADuration() {
        XCTAssertEqual(DurationFormat.quantity(75, unit: DurationFormat.minuteUnit), "1h 15m")
        XCTAssertEqual(DurationFormat.quantity(30, unit: "min"), "30 min")
        XCTAssertEqual(DurationFormat.quantity(320, unit: "cards"), "320 cards")
    }
}
