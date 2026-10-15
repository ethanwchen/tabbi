import Foundation
import TabbiKitCore
import XCTest

/// Pins what the activity log adds up to: the study days and minutes per
/// day (`PetMilestoneProgress`), the study streak with its freezes and
/// milestones (`StudyStreak`, `StreakMilestone`), the Closet's study chart
/// (`StudyHeatmap`) and the weekly recaps with their cheer and stats
/// (`WeeklyRecap`, `RecapWeek`, `RecapStat`), to the golden fixture
/// `shared/fixtures/streaks-recap/streaks-recap.json`.
///
/// Each case is a recorded activity log read on a fixed day in a named time
/// zone, so the Windows port replays the same records and must show the same
/// streak, chart and recap. Run with `TABBI_RECORD_FIXTURES=1` to rewrite it
/// after an intended change.
final class StreaksRecapGoldenTests: XCTestCase {
    func testStreaksRecapMatchesGoldenFixture() throws {
        let url = StreaksRecapGoldenFixture.url
        let current = StreaksRecapGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(StreaksRecapGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Streak and recap constants changed")
        XCTAssertEqual(stored.milestones, current.milestones, "Streak milestones changed")
        XCTAssertEqual(stored.cases.map(\.name), current.cases.map(\.name))
        for (old, new) in zip(stored.cases, current.cases) {
            XCTAssertEqual(old.input, new.input, old.name)
            XCTAssertEqual(old.output.progress, new.output.progress, "Case \(old.name), progress")
            XCTAssertEqual(old.output.streak, new.output.streak, "Case \(old.name), streak")
            XCTAssertEqual(old.output.heatmap, new.output.heatmap, "Case \(old.name), heatmap")
            XCTAssertEqual(old.output.recaps.containingWeek, new.output.recaps.containingWeek, "Case \(old.name), week")
            XCTAssertEqual(old.output.recaps.latestReadyWeek, new.output.recaps.latestReadyWeek,
                           "Case \(old.name), latest ready week")
            XCTAssertEqual(old.output.recaps.weeks.map(\.week), new.output.recaps.weeks.map(\.week), old.name)
            for (oldRecap, newRecap) in zip(old.output.recaps.weeks, new.output.recaps.weeks) {
                XCTAssertEqual(oldRecap, newRecap, "Case \(old.name), recap of \(oldRecap.week)")
            }
            XCTAssertEqual(old.output, new.output, "Case \(old.name)")
        }
        XCTAssertEqual(stored, current, "Streaks and recaps no longer match \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(StreaksRecapGoldenFixture.self,
                                              from: Data(contentsOf: StreaksRecapGoldenFixture.url))
        XCTAssertEqual(StreaksRecapGoldenFixture.milestones(lengths: stored.milestones.checks.map(\.length),
                                                           steps: stored.milestones.steps.map { ($0.from, $0.to) }),
                       stored.milestones)
        for item in stored.cases {
            XCTAssertEqual(StreaksRecapGoldenFixture.evaluate(item.input), item.output, item.name)
        }
    }
}

/// Activity logs read on fixed days, with the streak, chart and recaps they
/// give, and the streak milestone rules.
struct StreaksRecapGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.streaks-recap.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/streaks-recap/streaks-recap.json")
    }

    /// Recap stats name weekdays and group digits in this locale.
    static let locale = Locale(identifier: "en_US")

    struct Constants: Codable, Equatable {
        var freeFreezesPerWeek: Int
        var freezePrice: Int
        var maxHeldFreezes: Int
        var minutesForStudyDay: Double
        var milestoneDays: [Int]
        var heatmapLevelCount: Int
        var heatmapLevelThresholds: [Int]
        var heatmapLabeledWeekdays: [Int]
        var recapReadyHour: Int
        var lightWeekMinutes: Int
        var pointsPerMinute: Int
        var minimumMinutes: Int
        var completionBonus: Int
        var bonusMinutes: Int
        var sharedBonusPerFriend: Int
        var maxSharedBonus: Int
        var partyFriendsKey: String
        var stockLocale: String
    }

    struct MilestoneCheck: Codable, Equatable {
        var length: Int
        var isMilestone: Bool
    }

    /// A streak seen at `from` (null: no baseline yet) and then at `to`.
    struct MilestoneStep: Codable, Equatable {
        var from: Int?
        var to: Int
        var reached: Int?
    }

    struct Milestones: Codable, Equatable {
        var checks: [MilestoneCheck]
        var steps: [MilestoneStep]
    }

    /// One activity record, as in the activity log fixture: times are
    /// seconds since 1970.
    struct Record: Codable, Equatable {
        var id: String
        var source: String
        var kind: String
        var start: Double
        var end: Double?
        var quantity: Double?
        var unit: String?
        var subject: String?
        var metadata: [String: String]

        var activityRecord: ActivityRecord {
            ActivityRecord(id: UUID(uuidString: id)!, source: ModuleID(rawValue: source), kind: ActivityKind(rawValue: kind),
                           start: Date(timeIntervalSince1970: start), end: end.map { Date(timeIntervalSince1970: $0) },
                           quantity: quantity, unit: unit.map { ActivityUnit(rawValue: $0) }, subject: subject,
                           metadata: metadata)
        }
    }

    struct Input: Codable, Equatable {
        /// An IANA name; every day is a local day in it.
        var timeZone: String
        /// The calendar's first weekday (1 is Sunday, 2 is Monday): it sets
        /// the free freeze's week and the chart's columns, not recap weeks.
        var firstWeekday: Int
        var today: Double
        var records: [Record]
        /// When each extra freeze was bought.
        var freezePurchases: [Double]
        /// How many days the streak's day strip shows.
        var recentDays: Int
        /// How many columns the chart has.
        var heatmapWeeks: Int
        /// The columns a month label needs.
        var monthLabelMinimumWeeks: Int
        /// How many recaps to build, ending with the latest ready week.
        var recapWeeks: Int
    }

    struct DayMinutes: Codable, Equatable {
        var day: String
        var minutes: Double
    }

    struct Progress: Codable, Equatable {
        /// Focused minutes per local day, every day with any, oldest first.
        var minutesByDay: [DayMinutes]
        var studyDays: [String]
        var longestStreak: Int
        var currentStreak: Int
    }

    struct StripDay: Codable, Equatable {
        var day: String
        /// `studied`, `frozen`, `missed` or `today`.
        var state: String
    }

    struct Streak: Codable, Equatable {
        var length: Int
        var studiedToday: Bool
        var isActive: Bool
        var needsStudyToday: Bool
        var frozenDays: [String]
        var freeFreezeAvailable: Bool
        var extraFreezes: Int
        var canBuyFreeze: Bool
        var freezesReady: Int
        var recentDays: [StripDay]
        /// The streak read a day earlier at the same time, and the milestone
        /// reached by growing from it to `length`.
        var lengthYesterday: Int
        var milestoneReached: Int?
    }

    struct HeatDay: Codable, Equatable {
        var day: String
        var minutes: Int
        var level: Int
        var isToday: Bool
    }

    struct HeatWeek: Codable, Equatable {
        var start: String
        /// Seven days from the first weekday; null after today.
        var days: [HeatDay?]
        var minutes: Int
        var studiedDays: Int
    }

    struct MonthLabel: Codable, Equatable {
        var week: Int
        var start: String
    }

    struct Heatmap: Codable, Equatable {
        var today: String
        var weekdays: [Int]
        var weeks: [HeatWeek]
        var lastThirtyDaysMinutes: Int
        var bestDay: HeatDay?
        var monthLabels: [MonthLabel]
    }

    struct BestDay: Codable, Equatable {
        var day: String
        var minutes: Int
    }

    struct Stat: Codable, Equatable {
        var kind: String
        var value: String
    }

    struct Recap: Codable, Equatable {
        var week: String
        var end: String
        var readyDate: Double
        var minutesByDay: [Int]
        var sessions: Int
        var cardsReviewed: Int
        var tasksDone: Int
        var points: Int
        var longestStreak: Int
        var focusMinutes: Int
        var isEmpty: Bool
        var bestDay: BestDay?
        /// Compared with the case's other recaps.
        var cheer: String
        var stats: [Stat]
    }

    struct Recaps: Codable, Equatable {
        var containingWeek: String
        var latestReadyWeek: String
        /// Oldest first, ending with `latestReadyWeek`.
        var weeks: [Recap]
    }

    struct Output: Codable, Equatable {
        var progress: Progress
        var streak: Streak
        var heatmap: Heatmap
        var recaps: Recaps
    }

    struct Case: Codable, Equatable {
        var name: String
        var input: Input
        var output: Output
    }

    var schema = Self.schemaName
    var version = 1
    var constants: Constants
    var milestones: Milestones
    var cases: [Case]

    static func current() -> StreaksRecapGoldenFixture {
        StreaksRecapGoldenFixture(
            constants: Constants(
                freeFreezesPerWeek: StreakFreezeRules.freePerWeek, freezePrice: StreakFreezeRules.price,
                maxHeldFreezes: StreakFreezeRules.maxHeld, minutesForStudyDay: PetMilestoneProgress.minutesForStudyDay,
                milestoneDays: StreakMilestone.days, heatmapLevelCount: StudyHeatmap.levelCount,
                heatmapLevelThresholds: StudyHeatmap.levelThresholds,
                heatmapLabeledWeekdays: StudyHeatmap.labeledWeekdays.sorted(),
                recapReadyHour: RecapWeek.defaultReadyHour, lightWeekMinutes: RecapCheer.lightWeekMinutes,
                pointsPerMinute: PetPointsRules.pointsPerMinute, minimumMinutes: PetPointsRules.minimumMinutes,
                completionBonus: PetPointsRules.completionBonus, bonusMinutes: PetPointsRules.bonusMinutes,
                sharedBonusPerFriend: PetPointsRules.sharedBonusPerFriend, maxSharedBonus: PetPointsRules.maxSharedBonus,
                partyFriendsKey: PartySessionCompletion.friendsKey, stockLocale: locale.identifier
            ),
            milestones: milestones(lengths: milestoneLengths, steps: milestoneSteps),
            cases: sampleCases().map { Case(name: $0.0, input: $0.1, output: evaluate($0.1)) }
        )
    }

    // MARK: Running

    static func milestones(lengths: [Int], steps: [(Int?, Int)]) -> Milestones {
        Milestones(
            checks: lengths.map { MilestoneCheck(length: $0, isMilestone: StreakMilestone.isMilestone($0)) },
            steps: steps.map { MilestoneStep(from: $0.0, to: $0.1, reached: StreakMilestone.reached(from: $0.0, to: $0.1)) }
        )
    }

    static func zoneCalendar(_ timeZone: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func evaluate(_ input: Input) -> Output {
        let calendar = zoneCalendar(input.timeZone, firstWeekday: input.firstWeekday)
        let today = Date(timeIntervalSince1970: input.today)
        let records = input.records.map(\.activityRecord)
        let purchases = input.freezePurchases.map { Date(timeIntervalSince1970: $0) }

        let progress = PetMilestoneProgress(records: records, calendar: calendar)
        let streak = StudyStreak(studyDays: progress.studyDays, freezePurchases: purchases, today: today, calendar: calendar)
        let yesterday = StudyStreak(studyDays: progress.studyDays, freezePurchases: purchases,
                                    today: calendar.date(byAdding: .day, value: -1, to: today)!, calendar: calendar)
        let heatmap = StudyHeatmap(minutesByDay: progress.minutesByDay, weeks: input.heatmapWeeks, today: today,
                                   calendar: calendar)

        let latest = RecapWeek.latestReady(at: today, calendar: calendar)
        let weeks = (0..<input.recapWeeks).reversed().map { latest.adding(weeks: -$0, calendar: calendar) }
        let recaps = weeks.map { WeeklyRecap(week: $0, records: records, calendar: calendar) }

        return Output(
            progress: Progress(
                minutesByDay: progress.minutesByDay.keys.sorted().map {
                    DayMinutes(day: $0.rawValue, minutes: progress.minutesByDay[$0] ?? 0)
                },
                studyDays: progress.studyDays.map(\.rawValue),
                longestStreak: progress.longestStreak(calendar: calendar),
                currentStreak: progress.currentStreak(today: today, calendar: calendar)
            ),
            streak: Streak(
                length: streak.length, studiedToday: streak.studiedToday, isActive: streak.isActive,
                needsStudyToday: streak.needsStudyToday, frozenDays: streak.frozenDays.map(\.rawValue).sorted(),
                freeFreezeAvailable: streak.freeFreezeAvailable, extraFreezes: streak.extraFreezes,
                canBuyFreeze: streak.canBuyFreeze, freezesReady: streak.freezesReady,
                recentDays: streak.recentDays(input.recentDays, calendar: calendar).map {
                    StripDay(day: $0.day.rawValue, state: stateName($0.state))
                },
                lengthYesterday: yesterday.length,
                milestoneReached: StreakMilestone.reached(from: yesterday.length, to: streak.length)
            ),
            heatmap: Heatmap(
                today: heatmap.today.rawValue,
                weekdays: heatmap.weekdays,
                weeks: heatmap.weeks.map { week in
                    HeatWeek(start: week.start.rawValue, days: week.days.map { $0.map(heatDay) }, minutes: week.minutes,
                             studiedDays: week.studiedDays)
                },
                lastThirtyDaysMinutes: heatmap.lastThirtyDaysMinutes,
                bestDay: heatmap.bestDay.map(heatDay),
                monthLabels: heatmap.monthLabels(minimumWeeks: input.monthLabelMinimumWeeks).map {
                    MonthLabel(week: $0.week, start: $0.start.rawValue)
                }
            ),
            recaps: Recaps(
                containingWeek: RecapWeek(containing: today, calendar: calendar).start.rawValue,
                latestReadyWeek: latest.start.rawValue,
                weeks: recaps.map { recap($0, among: recaps, calendar: calendar) }
            )
        )
    }

    private static func stateName(_ state: StreakDay.State) -> String {
        switch state {
        case .studied: return "studied"
        case .frozen: return "frozen"
        case .missed: return "missed"
        case .today: return "today"
        }
    }

    private static func heatDay(_ day: StudyHeatmap.Day) -> HeatDay {
        HeatDay(day: day.key.rawValue, minutes: day.minutes, level: day.level, isToday: day.isToday)
    }

    private static func recap(_ recap: WeeklyRecap, among recaps: [WeeklyRecap], calendar: Calendar) -> Recap {
        Recap(
            week: recap.week.start.rawValue,
            end: recap.week.end(calendar: calendar).rawValue,
            readyDate: recap.week.readyDate(calendar: calendar).timeIntervalSince1970,
            minutesByDay: recap.minutesByDay,
            sessions: recap.sessions,
            cardsReviewed: recap.cardsReviewed,
            tasksDone: recap.tasksDone,
            points: recap.points,
            longestStreak: recap.longestStreak,
            focusMinutes: recap.focusMinutes,
            isEmpty: recap.isEmpty,
            bestDay: recap.bestDay(calendar: calendar).map { BestDay(day: $0.day.rawValue, minutes: $0.minutes) },
            cheer: recap.cheer(comparedTo: recaps, calendar: calendar).rawValue,
            stats: recap.stats(calendar: calendar, locale: locale).map { Stat(kind: $0.kind.rawValue, value: $0.value) }
        )
    }

    // MARK: Samples

    private static let milestoneLengths = [
        -1, 0, 1, 6, 7, 8, 13, 14, 15, 30, 50, 99, 100, 101, 200, 300, 364, 365, 366, 400, 500, 700, 730, 800, 1000, 1095,
    ]

    private static let milestoneSteps: [(Int?, Int)] = [
        (nil, 7), (nil, 0), (6, 7), (7, 7), (7, 8), (8, 6), (7, 0), (0, 1), (0, 7), (5, 15), (13, 31), (29, 30),
        (364, 400), (0, 365), (699, 731), (10, 0),
    ]

    /// Seconds since 1970 of a wall-clock time in `calendar`'s zone.
    private static func at(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0,
                           second: Int = 0, year: Int = 2026) -> Double {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute,
                                           second: second))!.timeIntervalSince1970
    }

    private static func id(_ group: Int, _ number: Int) -> String {
        String(format: "00000000-0000-4000-8000-%04d%08d", group, number)
    }

    private static func focus(_ id: String, end: Double, minutes: Double, source: String = "focus",
                              outcome: String? = "completed", friends: Int? = nil, unit: String? = "min") -> Record {
        var metadata: [String: String] = [:]
        if let outcome { metadata["outcome"] = outcome }
        if let friends { metadata["friends"] = String(friends) }
        return Record(id: id, source: source, kind: "focus.completed", start: end - minutes * 60, end: end,
                      quantity: minutes, unit: unit, subject: nil, metadata: metadata)
    }

    private static func cards(_ id: String, end: Double, count: Double) -> Record {
        Record(id: id, source: "anki", kind: "cards.reviewed", start: end - 600, end: end, quantity: count,
               unit: "cards", subject: nil, metadata: [:])
    }

    private static func task(_ id: String, at time: Double, subject: String?) -> Record {
        Record(id: id, source: "planner", kind: "task.completed", start: time, end: nil, quantity: nil, unit: nil,
               subject: subject, metadata: [:])
    }

    private static func rest(_ id: String, end: Double, minutes: Double) -> Record {
        Record(id: id, source: "focus", kind: "break.taken", start: end - minutes * 60, end: end, quantity: minutes,
               unit: "min", subject: nil, metadata: [:])
    }

    /// A 25-minute focus ending at 10:00 on each `(month, day)`.
    private static func daily(_ group: Int, _ calendar: Calendar, _ days: [(Int, Int)], minutes: Double = 25,
                              hour: Int = 10) -> [Record] {
        days.enumerated().map { index, day in
            focus(id(group, 1000 + index), end: at(calendar, day.0, day.1, hour), minutes: minutes)
        }
    }

    private static func october(_ days: [Int]) -> [(Int, Int)] { days.map { (10, $0) } }

    private static func input(_ calendar: Calendar, today: Double, records: [Record], purchases: [Double] = [],
                              heatmapWeeks: Int = 4, recapWeeks: Int = 2) -> Input {
        Input(timeZone: calendar.timeZone.identifier, firstWeekday: calendar.firstWeekday, today: today,
              records: records, freezePurchases: purchases, recentDays: 14, heatmapWeeks: heatmapWeeks,
              monthLabelMinimumWeeks: 2, recapWeeks: recapWeeks)
    }

    static func sampleCases() -> [(String, Input)] {
        // October 2026 in New York, weeks from Monday: Mondays are the 5th,
        // 12th and 19th.
        let newYork = zoneCalendar("America/New_York", firstWeekday: 2)
        let newYorkSunday = zoneCalendar("America/New_York", firstWeekday: 1)
        let london = zoneCalendar("Europe/London", firstWeekday: 2)
        let sydney = zoneCalendar("Australia/Sydney", firstWeekday: 2)
        let kolkata = zoneCalendar("Asia/Kolkata", firstWeekday: 1)
        let utc = zoneCalendar("UTC", firstWeekday: 2)

        // Studied Monday 12th, Tuesday 13th and Thursday 15th; Wednesday 14th
        // and Friday 16th missed.
        let twoMisses = daily(6, newYork, october([12, 13, 15]))
        // Monday 5th to Friday 9th, the weekend missed, Monday 12th.
        let weekendOff = daily(11, newYork, october([5, 6, 7, 8, 9, 12]))

        return [
            ("empty-log", input(newYork, today: at(newYork, 10, 14, 15), records: [])),
            ("consecutive-days-through-today", input(newYork, today: at(newYork, 10, 14, 20),
                                                     records: daily(2, newYork, october(Array(8...14))))),
            ("today-not-studied-yet", input(newYork, today: at(newYork, 10, 14, 8),
                                            records: daily(3, newYork, october(Array(8...13))))),
            ("missed-yesterday-is-frozen", input(newYork, today: at(newYork, 10, 15, 9),
                                                 records: daily(4, newYork, october([12, 13])))),
            ("second-miss-in-a-week-broke-the-streak-yesterday", input(newYork, today: at(newYork, 10, 17, 12),
                                                                       records: twoMisses)),
            ("second-miss-in-a-week-is-today-so-still-open", input(newYork, today: at(newYork, 10, 16, 21),
                                                                   records: twoMisses)),
            ("extra-freeze-covers-the-second-miss", input(
                newYork, today: at(newYork, 10, 18, 19), records: daily(7, newYork, october([12, 13, 15, 17])),
                purchases: [at(newYork, 10, 11, 12)])),
            ("freeze-bought-on-the-missed-day-cannot-repair-it", input(
                newYork, today: at(newYork, 10, 16, 12), records: daily(8, newYork, october([12, 13])),
                purchases: [at(newYork, 10, 15, 12)])),
            ("freezes-bought-today-reach-the-holding-limit", input(
                newYork, today: at(newYork, 10, 14, 18), records: daily(9, newYork, october([13])),
                purchases: [at(newYork, 10, 14, 9), at(newYork, 10, 14, 10)])),
            ("used-extra-freeze-makes-room-for-another", input(
                newYork, today: at(newYork, 10, 15, 18), records: daily(10, newYork, october([12, 15])),
                purchases: [at(newYork, 10, 12, 12), at(newYork, 10, 12, 12, 30)])),
            ("weekend-missed-with-monday-weeks", input(newYork, today: at(newYork, 10, 12, 20), records: weekendOff)),
            ("weekend-missed-with-sunday-weeks", input(newYorkSunday, today: at(newYorkSunday, 10, 12, 20),
                                                       records: weekendOff)),
            ("no-freeze-spent-without-a-streak", input(newYork, today: at(newYork, 10, 13, 20),
                                                       records: daily(12, newYork, october([1, 12, 13])))),
            ("mixed-records-new-york", input(newYork, today: at(newYork, 10, 11, 20), records: mixedWeek(newYork))),
            ("fall-back-week-new-york", input(newYork, today: at(newYork, 11, 3, 23), records: fallBack(newYork),
                                              heatmapWeeks: 3)),
            ("spring-forward-before-ready-new-york", input(newYork, today: at(newYork, 3, 8, 17, 59),
                                                           records: springForward(newYork))),
            ("spring-forward-at-ready-hour-london", input(london, today: at(london, 3, 29, 18),
                                                          records: springForwardLondon(london))),
            ("autumn-change-sydney", input(sydney, today: at(sydney, 4, 5, 20), records: autumnSydney(sydney))),
            ("half-hour-zone-kolkata", input(kolkata, today: at(kolkata, 10, 2, 12), records: [
                focus(id(19, 1), end: at(utc, 10, 1, 18, 29, second: 59), minutes: 25),
                focus(id(19, 2), end: at(utc, 10, 1, 18, 30), minutes: 25),
            ])),
            ("cheers-over-six-weeks", input(utc, today: at(utc, 10, 25, 19), records: cheerWeeks(utc), heatmapWeeks: 8,
                                            recapWeeks: 6)),
            ("thirty-day-milestone", input(utc, today: at(utc, 10, 15, 21), records: thirtyDays(utc), heatmapWeeks: 6,
                                           recapWeeks: 1)),
        ]
    }

    /// Monday 5 to Sunday 11 October in New York, with every kind of record
    /// the recap reads and some it ignores.
    private static func mixedWeek(_ calendar: Calendar) -> [Record] {
        let group = 14
        return [
            // The Sunday before the week, late evening.
            focus(id(group, 1), end: at(calendar, 10, 4, 23, 30), minutes: 45),
            // Monday: a finished and a skipped focus, and a break.
            focus(id(group, 2), end: at(calendar, 10, 5, 10), minutes: 25),
            focus(id(group, 3), end: at(calendar, 10, 5, 11), minutes: 25, outcome: "skipped"),
            rest(id(group, 4), end: at(calendar, 10, 5, 11, 5), minutes: 5),
            // Tuesday: four minutes is not a study day; cards keep only the recap's streak going.
            focus(id(group, 5), end: at(calendar, 10, 6, 9), minutes: 4),
            cards(id(group, 6), end: at(calendar, 10, 6, 20), count: 40),
            // Wednesday: two three-minute stretches add up to a study day but earn no points;
            // a focus record in another unit is ignored.
            focus(id(group, 7), end: at(calendar, 10, 7, 9), minutes: 3),
            focus(id(group, 8), end: at(calendar, 10, 7, 15), minutes: 3),
            focus(id(group, 9), end: at(calendar, 10, 7, 16), minutes: 30, unit: "cards"),
            // Thursday: a focus from 23:40 to 00:10 counts toward Thursday; 24.6 minutes
            // round into the day's minutes but earn points for 24 and no bonus.
            focus(id(group, 10), end: at(calendar, 10, 8, 0, 10), minutes: 30),
            focus(id(group, 11), end: at(calendar, 10, 8, 14), minutes: 24.6),
            // Friday: a task checked twice, one without a subject, and two Party stays.
            task(id(group, 12), at: at(calendar, 10, 9, 9), subject: "task-a"),
            task(id(group, 13), at: at(calendar, 10, 9, 10), subject: "task-a"),
            task(id(group, 14), at: at(calendar, 10, 9, 11), subject: nil),
            focus(id(group, 15), end: at(calendar, 10, 9, 16), minutes: 50, source: "party", friends: 2),
            focus(id(group, 16), end: at(calendar, 10, 9, 18), minutes: 30, source: "party", outcome: "skipped",
                  friends: 3),
            focus(id(group, 17), end: at(calendar, 10, 9, 20), minutes: 25, source: "party", outcome: nil, friends: 5),
            // Sunday: a stopped Flowtime focus counts as finished; its duplicate is ignored;
            // fractional cards are cut to whole ones.
            focus(id(group, 18), end: at(calendar, 10, 11, 15), minutes: 50, outcome: "stopped"),
            focus(id(group, 18), end: at(calendar, 10, 11, 15), minutes: 50, outcome: "stopped"),
            cards(id(group, 19), end: at(calendar, 10, 11, 16), count: 7.9),
            focus(id(group, 20), end: at(calendar, 10, 11, 17), minutes: 10, outcome: "abandoned"),
            // After today: ignored by the streak and the chart, still in the minutes per day.
            focus(id(group, 21), end: at(calendar, 10, 12, 1), minutes: 25),
        ]
    }

    /// 29 October to 3 November in New York; clocks fall back early on
    /// Sunday 1 November, and 01:30 happens twice.
    private static func fallBack(_ calendar: Calendar) -> [Record] {
        let utc = zoneCalendar("UTC", firstWeekday: 2)
        let group = 15
        return daily(group, calendar, [(10, 29), (10, 30), (10, 31), (11, 2), (11, 3)]) + [
            focus(id(group, 1), end: at(utc, 11, 1, 5, 30), minutes: 15),
            focus(id(group, 2), end: at(utc, 11, 1, 6, 30), minutes: 15),
            cards(id(group, 3), end: at(utc, 11, 2, 4, 59, second: 59), count: 20),
        ]
    }

    /// 2 to 8 March in New York; clocks spring forward early on Sunday 8 March.
    private static func springForward(_ calendar: Calendar) -> [Record] {
        let utc = zoneCalendar("UTC", firstWeekday: 2)
        let group = 16
        return daily(group, calendar, (2...7).map { (3, $0) }, minutes: 60) + [
            focus(id(group, 1), end: at(utc, 3, 8, 7, 30), minutes: 40),
            focus(id(group, 2), end: at(calendar, 2, 27, 21), minutes: 90),
        ]
    }

    /// 23 to 29 March in London; clocks spring forward at 01:00 GMT on Sunday 29 March.
    private static func springForwardLondon(_ calendar: Calendar) -> [Record] {
        let utc = zoneCalendar("UTC", firstWeekday: 2)
        let group = 17
        return daily(group, calendar, (23...28).map { (3, $0) }, minutes: 45) + [
            focus(id(group, 1), end: at(utc, 3, 29, 0, 30), minutes: 20),
            focus(id(group, 2), end: at(utc, 3, 29, 1, 30), minutes: 20),
            focus(id(group, 3), end: at(calendar, 3, 29, 23, 30), minutes: 20),
        ]
    }

    /// 30 March to 5 April in Sydney; clocks fall back at 03:00 on Sunday 5 April.
    private static func autumnSydney(_ calendar: Calendar) -> [Record] {
        let utc = zoneCalendar("UTC", firstWeekday: 2)
        let group = 18
        return daily(group, calendar, [(3, 30), (3, 31), (4, 1), (4, 3)], minutes: 30) + [
            // Midnight AEDT starting Sunday 5 April, and 02:30 that night both before and after the change.
            focus(id(group, 1), end: at(utc, 4, 4, 13), minutes: 30),
            focus(id(group, 2), end: at(utc, 4, 4, 15, 30), minutes: 10),
            focus(id(group, 3), end: at(utc, 4, 4, 16, 30), minutes: 10),
            // 23:59 AEDT on Saturday 4 April.
            cards(id(group, 4), end: at(utc, 4, 4, 12, 59), count: 15),
        ]
    }

    /// Six Monday weeks in UTC from 14 September 2026, shaped so every
    /// cheer appears: nothing, a first week, a light one, a best one, a
    /// steady one and one up on the week before.
    private static func cheerWeeks(_ calendar: Calendar) -> [Record] {
        let group = 20
        var records: [Record] = []
        var number = 0
        func add(_ month: Int, _ day: Int, minutes: Double) {
            number += 1
            records.append(focus(id(group, number), end: at(calendar, month, day, 16), minutes: minutes))
        }
        // Week of 21 September: 120 minutes.
        add(9, 22, minutes: 60)
        add(9, 24, minutes: 60)
        // Week of 28 September: 30 minutes and some cards.
        add(9, 30, minutes: 30)
        records.append(cards(id(group, 900), end: at(calendar, 10, 1, 9), count: 25))
        // Week of 5 October: 200 minutes over four days in a row.
        add(10, 5, minutes: 50)
        add(10, 6, minutes: 50)
        add(10, 7, minutes: 50)
        add(10, 8, minutes: 50)
        // Week of 12 October: 150 minutes.
        add(10, 13, minutes: 90)
        add(10, 16, minutes: 60)
        // Week of 19 October: 180 minutes, two days tied as the best, and many cards.
        add(10, 20, minutes: 90)
        add(10, 22, minutes: 90)
        records.append(cards(id(group, 901), end: at(calendar, 10, 25, 9), count: 1_320))
        return records
    }

    /// 15 September to 15 October 2026 in UTC with 30 September missed (and
    /// frozen), so today's study makes the streak 30.
    private static func thirtyDays(_ calendar: Calendar) -> [Record] {
        let days = (15...29).map { (9, $0) } + (1...15).map { (10, $0) }
        var records = daily(21, calendar, days, minutes: 30)
        // Two days tied for the most: the chart's best day is the later one.
        records.append(focus(id(21, 1), end: at(calendar, 10, 3, 20), minutes: 60))
        records.append(focus(id(21, 2), end: at(calendar, 10, 9, 20), minutes: 60))
        return records
    }
}
