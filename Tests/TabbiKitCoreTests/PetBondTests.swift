import XCTest
import TabbiKitCore

final class PetBondTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))!
        return calendar.date(byAdding: .day, value: offset, to: start)!
    }

    private func focus(minutes: Double, on date: Date) -> ActivityRecord {
        ActivityRecord(source: .focus, kind: .focusCompleted, start: date.addingTimeInterval(-minutes * 60), end: date,
                       quantity: minutes, unit: .minutes)
    }

    // MARK: Curve

    func testCurveStartsAtLevelOneAndRisesGently() {
        XCTAssertEqual(PetBond.thresholds.count, PetBond.maxLevel)
        XCTAssertEqual(PetBond.thresholds.first, 0)
        let steps = zip(PetBond.thresholds.dropFirst(), PetBond.thresholds).map { $0 - $1 }
        XCTAssertEqual(steps, steps.sorted(), "each level takes at least as long as the one before")
        XCTAssertTrue(steps.allSatisfy { $0 > 0 })
    }

    func testLevelsAtTheThresholds() {
        XCTAssertEqual(PetBond(points: 0).level, 1)
        XCTAssertEqual(PetBond(points: 99).level, 1)
        XCTAssertEqual(PetBond(points: 100).level, 2)
        XCTAssertEqual(PetBond(points: 600).level, 4)
        XCTAssertEqual(PetBond(points: 6999).level, 9)
        XCTAssertEqual(PetBond(points: 7000).level, 10)
        XCTAssertEqual(PetBond(points: 1_000_000).level, 10)
        XCTAssertEqual(PetBond(points: -50).points, 0)
    }

    func testProgressInLevelAndPointsToNext() {
        let bond = PetBond(points: 450)
        XCTAssertEqual(bond.level, 3)
        XCTAssertEqual(bond.progressInLevel, 0.5, accuracy: 0.0001)
        XCTAssertEqual(bond.pointsToNextLevel, 150)
        let maxed = PetBond(points: 9000)
        XCTAssertTrue(maxed.isMaxed)
        XCTAssertNil(maxed.pointsToNextLevel)
        XCTAssertEqual(maxed.progressInLevel, 1)
    }

    func testFirstLevelsComeWithinTheFirstDaysOfATypicalHabit() {
        // A typical day: three 25 minute blocks.
        let records = (0..<3).flatMap { offset in
            (0..<3).map { block in focus(minutes: 25, on: day(offset).addingTimeInterval(Double(block) * 3600)) }
        }
        let bond = PetBond(records: records, calendar: calendar)
        XCTAssertEqual(bond.points, 3 * 75 + 3 * PetBond.pointsPerStudyDay)
        XCTAssertEqual(bond.level, 3)
    }

    func testConsistencyGrowsTheBondFasterThanOneCram() {
        let steady = (0..<5).map { focus(minutes: 30, on: day($0)) }
        let cram = [focus(minutes: 150, on: day(0))]
        XCTAssertGreaterThan(PetBond(records: steady, calendar: calendar).points,
                             PetBond(records: cram, calendar: calendar).points)
    }

    func testBondNeverShrinksAfterABreak() {
        let records = (0..<10).map { focus(minutes: 60, on: day($0)) }
        let before = PetBond(records: records, calendar: calendar)
        // Thirty days off take nothing away; the next session adds on top.
        let more = PetBond(records: records + [focus(minutes: 10, on: day(40))], calendar: calendar)
        XCTAssertGreaterThan(more.points, before.points)
    }

    func testOnlyFocusMinutesCount() {
        let cards = ActivityRecord(source: .anki, kind: .cardsReviewed, start: day(0), quantity: 300, unit: .cards)
        XCTAssertEqual(PetBond(records: [cards], calendar: calendar).points, 0)
    }

    // MARK: Tier names

    func testEveryLevelHasADistinctWarmName() {
        let names = (1...PetBond.maxLevel).map(PetBond.tierName(forLevel:))
        XCTAssertEqual(Set(names).count, PetBond.maxLevel)
        XCTAssertEqual(names.first, "Just met")
        XCTAssertEqual(PetBond.tierName(forLevel: 4), "Best friends")
        XCTAssertEqual(names.last, "Forever friends")
        XCTAssertEqual(PetBond.tierName(forLevel: 0), "Just met")
        XCTAssertEqual(PetBond.tierName(forLevel: 99), "Forever friends")
        XCTAssertEqual(PetBond(points: 600).tierName, "Best friends")
    }

    // MARK: Unlocks

    func testCollarUpgradesAtItsTiers() {
        let collars = (1...PetBond.maxLevel).map { PetBondLook(level: $0).collar }
        XCTAssertEqual(collars, [.none, .plain, .plain, .bell, .bell, .star, .star, .gold, .gold, .gold])
        XCTAssertEqual(PetCollar.allCases, PetCollar.allCases.sorted())
    }

    func testHappyIdleAndSparkleThresholds() {
        XCTAssertFalse(PetBondLook(level: 2).happyIdle)
        XCTAssertTrue(PetBondLook(level: 3).happyIdle)
        XCTAssertFalse(PetBondLook(level: 8).sparkle)
        XCTAssertTrue(PetBondLook(level: 9).sparkle)
        XCTAssertTrue(PetBondLook(level: 10).sparkle)
        XCTAssertEqual(PetBond(points: 0).look, PetBondLook(level: 1))
    }

    func testUnlockHintNamesWhatEachLevelAdds() {
        XCTAssertEqual(PetBondLook.unlock(atLevel: 2), "Plain collar")
        XCTAssertEqual(PetBondLook.unlock(atLevel: 3), "Happy wiggle")
        XCTAssertEqual(PetBondLook.unlock(atLevel: 4), "Bell collar")
        XCTAssertEqual(PetBondLook.unlock(atLevel: 8), "Gold tag")
        XCTAssertEqual(PetBondLook.unlock(atLevel: 9), "Sparkle")
        XCTAssertNil(PetBondLook.unlock(atLevel: 5))
        XCTAssertNil(PetBondLook.unlock(atLevel: 11))
    }
}
