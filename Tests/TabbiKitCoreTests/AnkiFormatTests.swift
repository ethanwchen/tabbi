import XCTest
@testable import TabbiKitCore

final class AnkiFormatTests: XCTestCase {
    private let today = AnkiDay(year: 2026, month: 10, day: 2)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func history(_ counts: [Int]) -> [AnkiDayCount] {
        counts.enumerated().map { AnkiDayCount(day: today.adding(days: $0.offset - (counts.count - 1)), count: $0.element) }
    }

    func testHeatLevelsScaleToTheBusiestDay() {
        XCTAssertEqual(AnkiFormat.heatLevels(for: history([0, 100, 200, 300, 400])), [0, 1, 2, 3, 4])
    }

    func testAnyReviewIsAtLeastTheLightestShade() {
        XCTAssertEqual(AnkiFormat.heatLevels(for: history([1, 1_000])), [1, 4])
    }

    func testHeatLevelsWithNoReviewsAreAllEmpty() {
        XCTAssertEqual(AnkiFormat.heatLevels(for: history([0, 0, 0])), [0, 0, 0])
        XCTAssertEqual(AnkiFormat.heatLevels(for: []), [])
    }

    func testStreakLabel() {
        XCTAssertEqual(AnkiFormat.streak(12), "12-day streak")
        XCTAssertEqual(AnkiFormat.streak(1), "1-day streak")
        XCTAssertEqual(AnkiFormat.streak(0), "No streak yet")
    }

    func testDayHelpNamesRecentDaysAndPluralizes() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(AnkiFormat.dayHelp(AnkiDayCount(day: today, count: 112), today: today, calendar: utc, locale: locale),
                       "Today · 112 reviews")
        XCTAssertEqual(AnkiFormat.dayHelp(AnkiDayCount(day: today.adding(days: -1), count: 1), today: today, calendar: utc, locale: locale),
                       "Yesterday · 1 review")
        XCTAssertEqual(AnkiFormat.dayHelp(AnkiDayCount(day: today.adding(days: -2), count: 0), today: today, calendar: utc, locale: locale),
                       "Wed, Sep 30 · No reviews")
    }

    func testProgressHelp() {
        let demo = AnkiSummary.demo()
        XCTAssertEqual(AnkiFormat.progressHelp(demo),
                       "\(demo.reviewedToday) of \(demo.reviewedToday + demo.dueTotal) cards reviewed today")
        let done = AnkiSummary(deckStats: [], reviewedToday: 40, reviewsByDay: [], reviews: [],
                               now: Date(), today: today)
        XCTAssertEqual(AnkiFormat.progressHelp(done), "All 40 cards done for today")
        let idle = AnkiSummary(deckStats: [], reviewedToday: 0, reviewsByDay: [], reviews: [],
                               now: Date(), today: today)
        XCTAssertEqual(AnkiFormat.progressHelp(idle), "Nothing due today")
    }

    func testAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(AnkiFormat.age(now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(AnkiFormat.age(now.addingTimeInterval(-9 * 60), now: now), "9m ago")
        XCTAssertEqual(AnkiFormat.age(now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(AnkiFormat.age(now.addingTimeInterval(-2 * 86_400), now: now), "2d ago")
        XCTAssertEqual(AnkiFormat.age(now.addingTimeInterval(60), now: now), "just now", "clock skew never reads negative")
    }

    func testPreviewStateNames() {
        XCTAssertEqual(AnkiConnectionState(previewName: "addOnMissing"), .addOnMissing)
        XCTAssertEqual(AnkiConnectionState(previewName: "notrunning"), .notRunning)
        XCTAssertEqual(AnkiConnectionState(previewName: "apikey"), .needsPermission(.apiKeyRequired))
        XCTAssertEqual(AnkiConnectionState(previewName: "permission"), .needsPermission(.permissionDenied))
        XCTAssertEqual(AnkiConnectionState(previewName: "problem"), .problem(.timeout))
        XCTAssertNil(AnkiConnectionState(previewName: "bogus"))
    }
}
