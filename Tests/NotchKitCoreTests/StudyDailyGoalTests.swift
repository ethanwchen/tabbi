import XCTest
@testable import NotchKitCore

final class StudyDailyGoalTests: XCTestCase {
    private func kit(_ study: KitValue) -> KitDefaults {
        KitDefaults(moduleSettings: ["study": study])
    }

    func testGoalsAreClampedAndSnappedToQuarterHours() {
        XCTAssertEqual(StudyDailyGoal(minutes: 0).minutes, 15)
        XCTAssertEqual(StudyDailyGoal(minutes: -90).minutes, 15)
        XCTAssertEqual(StudyDailyGoal(minutes: 10_000).minutes, 720)
        XCTAssertEqual(StudyDailyGoal(minutes: 100).minutes, 105)
        XCTAssertEqual(StudyDailyGoal(minutes: 97).minutes, 90)
        XCTAssertEqual(StudyDailyGoal(minutes: 240).minutes, 240)
    }

    func testKitSetsTheGoal() {
        XCTAssertEqual(StudyDailyGoal(kit: kit(.object(["dailyGoalMinutes": .number(360)]))).minutes, 360)
        XCTAssertEqual(StudyDailyGoal(kit: kit(.object(["dailyGoalMinutes": .number(1e300)]))).minutes, 720)
    }

    func testMissingOrInvalidKitGoalFallsBackToStandard() {
        XCTAssertEqual(StudyDailyGoal(kit: nil), .standard)
        XCTAssertEqual(StudyDailyGoal(kit: KitDefaults()), .standard)
        XCTAssertEqual(StudyDailyGoal(kit: kit(.object(["dailyGoalMinutes": .string("lots")]))), .standard)
        XCTAssertEqual(StudyDailyGoal(kit: kit(.object(["dailyGoalMinutes": .number(.nan)]))), .standard)
        XCTAssertEqual(StudyDailyGoal(kit: kit(.string("oops"))), .standard)
        XCTAssertEqual(StudyDailyGoal.standard.minutes, 120)
    }

    func testKitGoalDecodesFromManifestJSON() throws {
        let json = #"{"moduleSettings": {"study": {"dailyGoalMinutes": 300}}}"#
        let defaults = try JSONDecoder().decode(KitDefaults.self, from: Data(json.utf8))
        XCTAssertEqual(StudyDailyGoal(kit: defaults).minutes, 300)
    }

    func testDecodingRepairsCorruptGoals() throws {
        func decode(_ json: String) throws -> StudyDailyGoal {
            try JSONDecoder().decode(StudyDailyGoal.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"minutes": 0}"#).minutes, 15)
        XCTAssertEqual(try decode(#"{"minutes": 99999}"#).minutes, 720)
        XCTAssertEqual(try decode("{}"), .standard)
        let goal = StudyDailyGoal(minutes: 180)
        XCTAssertEqual(try JSONDecoder().decode(StudyDailyGoal.self, from: JSONEncoder().encode(goal)), goal)
    }

    func testSteppingStaysInRange() {
        XCTAssertEqual(StudyDailyGoal(minutes: 120).stepped(by: 1).minutes, 135)
        XCTAssertEqual(StudyDailyGoal(minutes: 120).stepped(by: -2).minutes, 90)
        XCTAssertEqual(StudyDailyGoal(minutes: 15).stepped(by: -1).minutes, 15)
        XCTAssertEqual(StudyDailyGoal(minutes: 720).stepped(by: 1).minutes, 720)
    }

    func testProgressReachesTodayAndPlanMyDay() {
        let goal = StudyDailyGoal(minutes: 120)
        let item = goal.progressItem(for: StudyDaySummary(minutes: 45, completedSessions: 2, points: 50))
        XCTAssertEqual(item.completed, 45)
        XCTAssertEqual(item.target, 120)
        XCTAssertEqual(item.remaining, 75)

        let snapshot = ProviderSnapshot([(.study, ModuleProvision(progress: [item]))])
        let row = snapshot.sharedTodayItems(excluding: .planner).first
        XCTAssertEqual(row?.source, .study)
        XCTAssertEqual(row?.detail, "45/120 min")
        XCTAssertEqual(row?.isDone, false)
        XCTAssertEqual(snapshot.plannableWork(excluding: .planner), ["Study time (75 min left)"])
        XCTAssertNil(snapshot.cardsReviewedToday(excluding: .anki), "study minutes are not cards")
    }

    func testMetGoalIsDoneAndLeavesPlanMyDay() {
        let item = StudyDailyGoal(minutes: 60).progressItem(for: StudyDaySummary(minutes: 75))
        XCTAssertTrue(item.isComplete)
        let snapshot = ProviderSnapshot([(.study, ModuleProvision(progress: [item]))])
        XCTAssertEqual(snapshot.sharedTodayItems(excluding: .planner).first?.isDone, true)
        XCTAssertEqual(snapshot.plannableWork(excluding: .planner), [])
    }
}
