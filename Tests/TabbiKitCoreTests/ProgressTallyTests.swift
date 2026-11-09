import Foundation
import TabbiKitCore
import XCTest

/// The Goals section counts what the activity log holds, each record once.
final class ProgressTallyTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func focus(_ minutes: Double, on day: Date, source: ModuleID = "focus", outcome: StudyPhaseOutcome? = .completed,
                       method: String? = nil, friends: Int? = nil) -> ActivityRecord {
        var metadata: [String: String] = [:]
        if let outcome { metadata[ActivityMetadata.outcome] = outcome.rawValue }
        if let method { metadata[ActivityMetadata.method] = method }
        if let friends { metadata[PartySessionCompletion.friendsKey] = String(friends) }
        return ActivityRecord(source: source, kind: .focusCompleted, start: day.addingTimeInterval(-minutes * 60),
                              end: day, quantity: minutes, unit: .minutes, metadata: metadata)
    }

    func testFocusCountsMinutesSessionsAndStudyDays() {
        let monday = date(2026, 11, 2)
        var tally = ProgressTally()
        tally.add(focus(25, on: monday), calendar: calendar)
        tally.add(focus(10, on: monday, outcome: .skipped), calendar: calendar)
        tally.add(focus(4, on: date(2026, 11, 3)), calendar: calendar)
        XCTAssertEqual(tally.total(of: .focusHours), 39)
        XCTAssertEqual(tally.total(of: .sessions), 2, "a skipped stretch adds minutes, not a session")
        XCTAssertEqual(tally.total(of: .studyDays), 1, "4 minutes are not a study day")
        XCTAssertEqual(tally.studyDays, [PlannerDayKey(date: monday, calendar: calendar)])
    }

    func testTheSameRecordCountsOnce() {
        let record = focus(30, on: date(2026, 11, 2))
        var tally = ProgressTally(records: [record, record], calendar: calendar)
        tally.add(record, calendar: calendar)
        XCTAssertEqual(tally.total(of: .focusHours), 30)
        XCTAssertEqual(tally.total(of: .sessions), 1)
    }

    func testOnlyNamedMethodsCount() {
        let day = date(2026, 11, 2)
        let tally = ProgressTally(records: [
            focus(25, on: day, method: "pomodoro"), focus(25, on: day, method: "pomodoro"),
            focus(52, on: day, method: StudyMethodKind.fiftyTwoSeventeen.rawValue),
            focus(10, on: day, method: StudyMethodKind.timer.rawValue),
            focus(10, on: day, method: StudyMethodKind.custom.rawValue),
            focus(10, on: day, method: "lecture"),
        ], calendar: calendar)
        XCTAssertEqual(tally.total(of: .methods), 2)
    }

    func testPartyCountsSessionsThatRanToTheEndWithAFriend() {
        let day = date(2026, 11, 2)
        let tally = ProgressTally(records: [
            focus(25, on: day, source: .party, friends: 2),
            focus(25, on: day.addingTimeInterval(60), source: .party, friends: 0),
            focus(10, on: day.addingTimeInterval(120), source: .party, outcome: .skipped, friends: 3),
            focus(25, on: day.addingTimeInterval(180), source: "focus", friends: 3),
        ], calendar: calendar)
        XCTAssertEqual(tally.total(of: .party), 1)
    }

    func testCardsTasksMovesAndWater() {
        let day = date(2026, 11, 2)
        let tally = ProgressTally(records: [
            ActivityRecord(source: .anki, kind: .cardsReviewed, start: day, quantity: 120, unit: .cards),
            ActivityRecord(source: .anki, kind: .cardsReviewed, start: day, quantity: -5, unit: .cards),
            ActivityRecord(source: .planner, kind: .taskCompleted, start: day, quantity: 1, subject: "a"),
            ActivityRecord(source: .planner, kind: .taskCompleted, start: day.addingTimeInterval(60), quantity: 1,
                           subject: "a"),
            ActivityRecord(source: .planner, kind: .taskCompleted, start: day, quantity: 1, subject: "b"),
            ActivityRecord(source: "leetcode", kind: .taskCompleted, start: day),
            WaterTally.move(.stretch, at: day), WaterTally.move(.breathe, at: day),
            WaterTally.water(at: day), WaterTally.water(at: day),
            ActivityRecord(source: .closet, kind: WaterTally.waterKind, start: day, quantity: 3, unit: WaterTally.glass),
            ActivityRecord(source: "focus", kind: .breakTaken, start: day, quantity: 5, unit: .minutes),
        ], calendar: calendar)
        XCTAssertEqual(tally.total(of: .cards), 120)
        XCTAssertEqual(tally.total(of: .tasks), 3, "a task checked twice counts once; one without an id counts too")
        XCTAssertEqual(tally.total(of: .breakMoves), 2)
        XCTAssertEqual(tally.total(of: .water), 5)
        XCTAssertEqual(tally.total(of: .focusHours), 0, "a break is no focus")
    }

    func testSteadyWeeksNeedThreeStudyDaysInAMondayWeek() {
        var records: [ActivityRecord] = []
        // Nov 2 to 8 is a Monday-to-Sunday week: three study days.
        for day in [2, 4, 8] { records.append(focus(20, on: date(2026, 11, day))) }
        // Nov 9 to 15: two study days only.
        for day in [9, 15] { records.append(focus(20, on: date(2026, 11, day))) }
        // Nov 16 to 22: four, one under the floor that makes a study day.
        for day in [16, 17, 18] { records.append(focus(20, on: date(2026, 11, day))) }
        records.append(focus(3, on: date(2026, 11, 19)))
        let tally = ProgressTally(records: records, calendar: calendar)
        XCTAssertEqual(tally.steadyWeeks(calendar: calendar), 2)
    }

    func testFirstDayOfEachTrack() {
        let early = date(2026, 9, 3), late = date(2026, 10, 7)
        let tally = ProgressTally(records: [
            focus(30, on: late),
            ActivityRecord(source: .anki, kind: .cardsReviewed, start: early, quantity: 5, unit: .cards),
        ], calendar: calendar)
        XCTAssertEqual(tally.firstDay(of: .cards), PlannerDayKey(date: early, calendar: calendar))
        XCTAssertEqual(tally.firstDay(of: .focusHours), PlannerDayKey(date: late, calendar: calendar))
        XCTAssertNil(tally.firstDay(of: .water))
    }

    func testMonthTotalsCountOnlyThatMonth() {
        let tally = ProgressTally(records: [focus(30, on: date(2026, 10, 31, hour: 23)), focus(20, on: date(2026, 11, 1, hour: 1))],
                                  calendar: calendar)
        let november = MonthKey(date: date(2026, 11, 15), calendar: calendar)
        XCTAssertEqual(tally.total(of: .focusHours) { november.contains($0) }, 20)
    }
}

/// The gentle streak is the longest run the Streak section ever counted.
final class GentleStreakTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }()

    private func day(_ offset: Int, from start: Date) -> PlannerDayKey {
        PlannerDayKey(date: calendar.date(byAdding: .day, value: offset, to: start)!, calendar: calendar)
    }

    func testAFreeFreezeBridgesOneMissedDayAWeek() {
        // Sunday Nov 1, 2026 starts a week (firstWeekday 1).
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        // Study every day but Wednesday the 4th, for two weeks.
        let days = (0..<14).filter { $0 != 3 }.map { day($0, from: start) }
        let today = calendar.date(byAdding: .day, value: 14, to: start)!
        XCTAssertEqual(GentleStreak.longest(studyDays: days, today: today, calendar: calendar), 13)
    }

    func testTwoMissesInAWeekEndTheRunButTheLongestStays() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        // A 10 day run, then two misses in one week, then 3 days.
        let days = (0..<10).map { day($0, from: start) } + (12..<15).map { day($0, from: start) }
        let today = calendar.date(byAdding: .day, value: 20, to: start)!
        XCTAssertEqual(GentleStreak.longest(studyDays: days, today: today, calendar: calendar), 10)
    }

    func testAnExtraFreezeBoughtBeforeTheMissKeepsTheRun() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        // Misses on the 3rd and 4th (same week): the free freeze covers one.
        let days = (0..<9).filter { $0 != 2 && $0 != 3 }.map { day($0, from: start) }
        let today = calendar.date(byAdding: .day, value: 9, to: start)!
        XCTAssertEqual(GentleStreak.longest(studyDays: days, today: today, calendar: calendar), 5)
        let bought = [calendar.date(byAdding: .day, value: 1, to: start)!]
        XCTAssertEqual(GentleStreak.longest(studyDays: days, freezePurchases: bought, today: today, calendar: calendar), 7)
    }

    func testTodayCountsOnceStudied() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let today = calendar.date(byAdding: .day, value: 2, to: start)!
        let days = (0..<3).map { day($0, from: start) }
        XCTAssertEqual(GentleStreak.longest(studyDays: days, today: today, calendar: calendar), 3)
        XCTAssertEqual(GentleStreak.longest(studyDays: [], today: today, calendar: calendar), 0)
    }

    /// While a run is going, its length is the Streak section's.
    func testMatchesTheStreakSectionWhileARunGoesOn() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
        var generator = ProgressTestRandom(seed: 7)
        let days = (0..<60).filter { _ in Double.random(in: 0..<1, using: &generator) < 0.85 }.map { day($0, from: start) }
        let freezes = [calendar.date(byAdding: .day, value: 20, to: start)!]
        var longestSoFar = 0
        for offset in 0..<60 {
            let today = calendar.date(byAdding: .day, value: offset, to: start)!
            let streak = StudyStreak(studyDays: days, freezePurchases: freezes, today: today, calendar: calendar)
            longestSoFar = max(longestSoFar, streak.length)
            XCTAssertEqual(GentleStreak.longest(studyDays: days, freezePurchases: freezes, today: today, calendar: calendar),
                           longestSoFar, "day \(offset)")
        }
    }
}

/// A small deterministic generator for property tests.
private struct ProgressTestRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
