import Foundation
import TabbiKitCore
import XCTest

final class StudyStreakTests: XCTestCase {
    /// New York, weeks starting on Monday. October 2026: Monday the 5th,
    /// Monday the 12th and Monday the 19th start weeks.
    private func calendar(_ zone: String = "America/New_York", firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func key(_ day: Int, month: Int = 10) -> PlannerDayKey {
        PlannerDayKey(rawValue: String(format: "2026-%02d-%02d", month, day))!
    }

    private func date(_ day: Int, month: Int = 10, hour: Int = 12, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func streak(studied days: [Int], today: Int, bought: [Int] = [],
                        calendar: Calendar? = nil) -> StudyStreak {
        let calendar = calendar ?? self.calendar()
        return StudyStreak(studyDays: days.map { key($0) },
                           freezePurchases: bought.map { date($0, in: calendar) },
                           today: date(today, in: calendar), calendar: calendar)
    }

    // MARK: Plain streaks

    func testNoStudyHasNoStreakAndAFreeFreezeReady() {
        let result = streak(studied: [], today: 14)
        XCTAssertEqual(result.length, 0)
        XCTAssertFalse(result.isActive)
        XCTAssertFalse(result.needsStudyToday)
        XCTAssertTrue(result.freeFreezeAvailable)
        XCTAssertEqual(result.freezesReady, 1)
    }

    func testConsecutiveDaysThroughTodayCountEachDay() {
        let result = streak(studied: [12, 13, 14], today: 14)
        XCTAssertEqual(result.length, 3)
        XCTAssertTrue(result.studiedToday)
        XCTAssertFalse(result.needsStudyToday)
        XCTAssertTrue(result.frozenDays.isEmpty)
    }

    func testTodayWithoutStudyKeepsTheStreakAndAsksForStudy() {
        let result = streak(studied: [12, 13], today: 14)
        XCTAssertEqual(result.length, 2)
        XCTAssertFalse(result.studiedToday)
        XCTAssertTrue(result.needsStudyToday)
        XCTAssertTrue(result.frozenDays.isEmpty, "today still has time, so it is never frozen")
        XCTAssertTrue(result.freeFreezeAvailable)
    }

    func testStudyDaysAfterTodayAreIgnored() {
        let result = streak(studied: [13, 15, 16], today: 14)
        XCTAssertEqual(result.length, 1)
        XCTAssertFalse(result.studiedToday)
    }

    // MARK: The free weekly freeze

    func testOneMissedDayIsFrozenAndNotCounted() {
        let result = streak(studied: [12, 14, 15], today: 15)
        XCTAssertEqual(result.length, 3, "the frozen day keeps the run but adds nothing")
        XCTAssertEqual(result.frozenDays, [key(13)])
        XCTAssertFalse(result.freeFreezeAvailable, "this week's free freeze is spent")
        XCTAssertEqual(result.freezesReady, 0)
    }

    func testAMissedYesterdayIsFrozenSoTheStreakStillShowsToday() {
        let result = streak(studied: [12, 13], today: 15)
        XCTAssertEqual(result.length, 2)
        XCTAssertEqual(result.frozenDays, [key(14)])
        XCTAssertTrue(result.needsStudyToday)
    }

    func testASecondMissInTheSameWeekEndsTheStreak() {
        let result = streak(studied: [12, 14, 16, 17], today: 17)
        XCTAssertEqual(result.frozenDays, [key(13)])
        XCTAssertEqual(result.length, 2, "the 15th broke the run, so it restarts on the 16th")
    }

    func testTwoMissedDaysInARowEndTheStreakWithOnlyTheFreeFreeze() {
        let result = streak(studied: [12, 13], today: 16)
        XCTAssertEqual(result.frozenDays, [key(14)])
        XCTAssertEqual(result.length, 0)
        XCTAssertFalse(result.isActive)
        XCTAssertFalse(result.needsStudyToday)
    }

    func testMissesInDifferentWeeksEachUseThatWeeksFreeze() {
        // Sunday the 11th ends one week and Monday the 12th starts the next.
        let result = streak(studied: [8, 9, 10, 13, 14], today: 14)
        XCTAssertEqual(result.frozenDays, [key(11), key(12)])
        XCTAssertEqual(result.length, 5)
        XCTAssertFalse(result.freeFreezeAvailable)
    }

    func testTheFreeFreezeResetsEachWeek() {
        let result = streak(studied: [6, 8, 9, 10, 11, 12], today: 12)
        XCTAssertEqual(result.frozenDays, [key(7)])
        XCTAssertTrue(result.freeFreezeAvailable, "last week's freeze does not spend this week's")
    }

    func testTheFirstDayOfTheWeekFollowsTheCalendar() {
        // With Sunday-first weeks the 11th and 12th fall in the same week,
        // so the second miss ends the streak.
        let sundayFirst = calendar(firstWeekday: 1)
        let result = streak(studied: [8, 9, 10, 13, 14], today: 14, calendar: sundayFirst)
        XCTAssertEqual(result.frozenDays, [key(11)])
        XCTAssertEqual(result.length, 2)
    }

    func testNoFreezeIsSpentWhileThereIsNoStreak() {
        let result = streak(studied: [5, 15], today: 16, bought: [4])
        XCTAssertEqual(result.frozenDays, [key(6), key(7)], "the free freeze, then the extra one")
        XCTAssertEqual(result.extraFreezes, 0)
        XCTAssertEqual(result.length, 1, "the run ended on the 8th, and the empty days after it spent nothing")
        let idle = streak(studied: [15], today: 16, bought: [4])
        XCTAssertEqual(idle.extraFreezes, 1, "days before the first study day spend nothing")
        XCTAssertTrue(idle.freeFreezeAvailable)
    }

    // MARK: Extra freezes

    func testAnExtraFreezeCoversASecondMissInAWeek() {
        let result = streak(studied: [12, 14, 16, 17], today: 17, bought: [12])
        XCTAssertEqual(result.frozenDays, [key(13), key(15)])
        XCTAssertEqual(result.length, 4)
        XCTAssertEqual(result.extraFreezes, 0)
    }

    func testTheFreeFreezeIsUsedBeforeAnExtraOne() {
        let result = streak(studied: [12, 14], today: 14, bought: [12])
        XCTAssertEqual(result.frozenDays, [key(13)])
        XCTAssertEqual(result.extraFreezes, 1)
        XCTAssertEqual(result.freezesReady, 1)
    }

    func testSeveralMissedDaysUseEveryFreezeInOrder() {
        let result = streak(studied: [12, 16], today: 16, bought: [10, 11])
        XCTAssertEqual(result.frozenDays, [key(13), key(14), key(15)])
        XCTAssertEqual(result.length, 2)
        XCTAssertEqual(result.extraFreezes, 0)
        XCTAssertEqual(result.freezesReady, 0)
    }

    func testAFreezeBoughtAfterAMissCannotRepairIt() {
        let result = streak(studied: [12, 13, 15], today: 16, bought: [14, 15])
        XCTAssertEqual(result.frozenDays, [key(14)], "the free freeze covered the 14th")
        let late = streak(studied: [12, 15], today: 15, bought: [14])
        XCTAssertEqual(late.frozenDays, [key(13)])
        XCTAssertEqual(late.length, 1, "the freeze bought on the 14th did not protect the 14th")
        XCTAssertEqual(late.extraFreezes, 1, "it waits for the next miss")
    }

    func testAFreezeBoughtTodayIsHeldAndTheHoldingLimitApplies() {
        let one = streak(studied: [14], today: 14, bought: [14])
        XCTAssertEqual(one.extraFreezes, 1)
        XCTAssertTrue(one.canBuyFreeze)
        let two = streak(studied: [14], today: 14, bought: [13, 14])
        XCTAssertEqual(two.extraFreezes, StreakFreezeRules.maxHeld)
        XCTAssertFalse(two.canBuyFreeze)
        XCTAssertEqual(two.freezesReady, 3)
    }

    func testAnExtraFreezeCostsOneTypicalStudyDay() {
        XCTAssertEqual(StreakFreezeRules.price, PetEconomy.pointsPerTypicalDay)
        XCTAssertEqual(StreakFreezeRules.price, 105)
        XCTAssertEqual(StreakFreezeRules.freePerWeek, 1)
    }

    // MARK: Time zones

    func testStudyDaysFollowTheLocalDayOfTheRecords() {
        let newYork = calendar()
        // 11:30 pm on Monday the 12th and 12:30 am on Wednesday the 14th,
        // both New York time: Tuesday the 13th was missed.
        let late = newYork.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 23, minute: 30))!
        let early = newYork.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 0, minute: 30))!
        let records = [late, early].map {
            ActivityRecord(source: "focus", kind: .focusCompleted, start: $0.addingTimeInterval(-20 * 60), end: $0,
                           quantity: 20, unit: .minutes)
        }
        let progress = PetMilestoneProgress(records: records, calendar: newYork)
        let result = StudyStreak(studyDays: progress.studyDays, today: early, calendar: newYork)
        XCTAssertEqual(result.frozenDays, [key(13)])
        XCTAssertEqual(result.length, 2)

        // The same moments in Tokyo fall on the 13th and the 14th: no miss.
        let tokyo = calendar("Asia/Tokyo")
        let tokyoProgress = PetMilestoneProgress(records: records, calendar: tokyo)
        let tokyoResult = StudyStreak(studyDays: tokyoProgress.studyDays, today: early, calendar: tokyo)
        XCTAssertTrue(tokyoResult.frozenDays.isEmpty)
        XCTAssertEqual(tokyoResult.length, 2)
    }

    func testAStreakCrossesADaylightSavingChange() {
        // US clocks fall back on Sunday, November 1, 2026.
        let newYork = calendar()
        let days = [key(30), key(31), key(1, month: 11), key(2, month: 11), key(3, month: 11)]
        let result = StudyStreak(studyDays: days, today: date(3, month: 11, hour: 23, in: newYork), calendar: newYork)
        XCTAssertEqual(result.length, 5)
        XCTAssertTrue(result.frozenDays.isEmpty)
    }
}
