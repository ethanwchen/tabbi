import XCTest
import TabbiKitCore

final class CatWisdomTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// `hour`:00 on the `day`th day after a fixed Monday (2026-10-05, UTC).
    private func time(day: Int, hour: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + day, hour: hour))!
    }

    private func session(day: Int, hour: Int = 14, previous: Date? = nil, streak: Int = 1, minutes: Int = 60,
                         outcome: CatWisdomSession.Outcome = .completed) -> CatWisdomSession {
        CatWisdomSession(outcome: outcome, end: time(day: day, hour: hour), previousCompletion: previous,
                         streakDays: streak, totalFocusMinutes: minutes)
    }

    private var yes = FixedRandom(fraction: 0.0)
    private var no = FixedRandom(fraction: 0.9)

    func testFirstSessionOfTheDayShowsADailyLineHalfTheTime() {
        var schedule = CatWisdomSchedule()
        let line = schedule.line(for: session(day: 1, previous: time(day: 0)), calendar: calendar, using: &yes)
        XCTAssertEqual(line?.kind, .firstOfDay)
        XCTAssertTrue(CatWisdom.daily.contains(line?.text ?? ""))

        var other = CatWisdomSchedule()
        XCTAssertNil(other.line(for: session(day: 1, previous: time(day: 0)), calendar: calendar, using: &no))
    }

    func testAtMostOneLinePerDayAndNoneForLaterSessions() {
        var schedule = CatWisdomSchedule()
        XCTAssertNotNil(schedule.line(for: session(day: 1, previous: time(day: 0)), calendar: calendar, using: &yes))
        let later = session(day: 1, hour: 16, previous: time(day: 1))
        XCTAssertNil(schedule.line(for: later, calendar: calendar, using: &yes))

        // A later session on a day whose first session drew no line stays quiet too.
        var quiet = CatWisdomSchedule()
        XCTAssertNil(quiet.line(for: session(day: 1, previous: time(day: 0)), calendar: calendar, using: &no))
        XCTAssertNil(quiet.line(for: later, calendar: calendar, using: &yes))
    }

    func testRoughlyThreeToFourLinesAWeek() {
        var schedule = CatWisdomSchedule()
        var random = SplitMix(state: 5)
        var shown = 0
        let days = 700
        for day in 1...days {
            for hour in [10, 14, 17] {
                let previous = hour == 10 ? time(day: day - 1, hour: 17) : time(day: day, hour: hour - 3)
                if schedule.line(for: session(day: day, hour: hour, previous: previous), calendar: calendar,
                                 using: &random) != nil {
                    shown += 1
                }
            }
        }
        let perWeek = Double(shown) / Double(days) * 7
        XCTAssertGreaterThan(perWeek, 3.0)
        XCTAssertLessThan(perWeek, 4.0)
    }

    func testPriorityMilestoneThenComebackThenFirstOfDay() {
        var schedule = CatWisdomSchedule()
        _ = schedule.line(for: session(day: 0, streak: 6, minutes: 100), calendar: calendar, using: &no)

        // A comeback that also reaches 10 hours: the milestone wins.
        let both = session(day: 4, previous: time(day: 0), streak: 1, minutes: 600)
        XCTAssertEqual(schedule.line(for: both, calendar: calendar, using: &no)?.kind, .milestone(.tenHours))

        // Another comeback, nothing new reached: the comeback line.
        let comeback = session(day: 8, previous: time(day: 4), streak: 1, minutes: 660)
        let line = schedule.line(for: comeback, calendar: calendar, using: &no)
        XCTAssertEqual(line?.kind, .comeback)
        XCTAssertTrue(CatWisdom.comeback.contains(line?.text ?? ""))
    }

    func testComebackNeedsTwoFullDaysAway() {
        var schedule = CatWisdomSchedule()
        // Last session Monday, nothing Tuesday, back Wednesday: not a comeback.
        let line = schedule.line(for: session(day: 2, previous: time(day: 0)), calendar: calendar, using: &no)
        XCTAssertNil(line)
        let thursday = session(day: 3, previous: time(day: 0))
        XCTAssertEqual(schedule.line(for: thursday, calendar: calendar, using: &no)?.kind, .comeback)
    }

    func testMilestonesShowOnceEach() {
        var schedule = CatWisdomSchedule()
        _ = schedule.line(for: session(day: 0, streak: 1, minutes: 30), calendar: calendar, using: &no)
        var seen: [CatWisdomKind] = []
        for day in 1...200 {
            let line = schedule.line(for: session(day: day, previous: time(day: day - 1), streak: day + 1,
                                                  minutes: 30 + day * 60),
                                     calendar: calendar, using: &no)
            if let line { seen.append(line.kind) }
        }
        XCTAssertEqual(seen, [.milestone(.sevenDayStreak), .milestone(.tenHours), .milestone(.thirtyDayStreak),
                              .milestone(.fiftyHours), .milestone(.lastSquare)])
    }

    func testMilestonesReachedBeforeTheFirstLookStayQuiet() {
        var schedule = CatWisdomSchedule()
        let veteran = session(day: 1, previous: time(day: 0), streak: 40, minutes: 70 * 60)
        XCTAssertNil(schedule.line(for: veteran, calendar: calendar, using: &no))
        let next = session(day: 2, previous: time(day: 1), streak: 41, minutes: 71 * 60)
        XCTAssertNil(schedule.line(for: next, calendar: calendar, using: &no))
        let hundred = session(day: 3, previous: time(day: 2), streak: 42, minutes: 100 * 60)
        XCTAssertEqual(schedule.line(for: hundred, calendar: calendar, using: &no)?.kind, .milestone(.lastSquare))
    }

    func testNoRepeatsUntilThePoolIsUsedUp() {
        var schedule = CatWisdomSchedule()
        var random = SplitMix(state: 9)
        var lines: [String] = []
        var day = 1
        while lines.count < CatWisdom.daily.count * 2 {
            if let line = schedule.line(for: session(day: day, previous: time(day: day - 1)), calendar: calendar,
                                        using: &random) {
                lines.append(line.text)
            }
            day += 1
        }
        let first = Array(lines.prefix(CatWisdom.daily.count))
        let second = Array(lines.suffix(CatWisdom.daily.count))
        XCTAssertEqual(Set(first), Set(CatWisdom.daily))
        XCTAssertEqual(Set(second), Set(CatWisdom.daily))
        XCTAssertNotEqual(first.last, second.first)
    }

    func testRotationSurvivesARestart() throws {
        var schedule = CatWisdomSchedule()
        var random = SplitMix(state: 1)
        var lines: [String] = []
        var day = 1
        while lines.count < CatWisdom.daily.count {
            if lines.count == 5 {
                let data = try CatWisdomSchedule.schema.encode(schedule)
                schedule = try CatWisdomSchedule.schema.decode(CatWisdomSchedule.self, from: data)
            }
            if let line = schedule.line(for: session(day: day, previous: time(day: day - 1)), calendar: calendar,
                                        using: &random) {
                lines.append(line.text)
            }
            day += 1
        }
        XCTAssertEqual(Set(lines).count, CatWisdom.daily.count)
    }

    func testLateNightAtMostOnceAWeek() {
        var schedule = CatWisdomSchedule()
        let first = schedule.line(for: session(day: 1, hour: 23, previous: time(day: 0)), calendar: calendar,
                                  using: &no)
        XCTAssertEqual(first?.kind, .lateNight)
        XCTAssertEqual(first?.text, CatWisdom.lateNight)
        for day in 2...7 {
            let line = schedule.line(for: session(day: day, hour: 23, previous: time(day: day - 1)),
                                     calendar: calendar, using: &no)
            XCTAssertNil(line, "day \(day)")
        }
        let nextWeek = schedule.line(for: session(day: 8, hour: 23, previous: time(day: 7)), calendar: calendar,
                                     using: &no)
        XCTAssertEqual(nextWeek?.kind, .lateNight)
    }

    func testEarlyStopIsGentleAndCountsTowardTheDailyCap() {
        var schedule = CatWisdomSchedule()
        let stopped = session(day: 1, previous: time(day: 0), outcome: .stoppedWithPoints)
        let line = schedule.line(for: stopped, calendar: calendar, using: &yes)
        XCTAssertEqual(line, CatWisdomLine(kind: .earlyStop, text: CatWisdom.earlyStop))
        let later = session(day: 1, hour: 16, previous: time(day: 0))
        XCTAssertNil(schedule.line(for: later, calendar: calendar, using: &yes))
    }

    func testToggleOffShowsNothingAndBringsNoBacklog() {
        var schedule = CatWisdomSchedule()
        for day in 1...10 {
            let line = schedule.line(for: session(day: day, previous: time(day: day - 1), streak: day,
                                                  minutes: day * 60),
                                     enabled: false, calendar: calendar, using: &yes)
            XCTAssertNil(line)
        }
        // Turned back on: the 7-day streak and 10 hours passed while off stay quiet.
        let line = schedule.line(for: session(day: 11, previous: time(day: 10), streak: 11, minutes: 11 * 60),
                                 calendar: calendar, using: &yes)
        XCTAssertEqual(line?.kind, .firstOfDay)
    }

    func testRecapLineComesFromTheDailyPoolAndIsStableForAWeek() {
        let line = CatWisdom.recapLine(forWeekStarting: time(day: 0), calendar: calendar)
        XCTAssertTrue(CatWisdom.daily.contains(line))
        XCTAssertEqual(line, CatWisdom.recapLine(forWeekStarting: time(day: 0, hour: 20), calendar: calendar))
        XCTAssertNotEqual(line, CatWisdom.recapLine(forWeekStarting: time(day: 7), calendar: calendar))
    }
}
