import XCTest
import NotchKitCore

final class TodayPlanSettingsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute))!
    }

    private func kit(_ planner: [String: KitValue]?, studyMethod: String? = nil) -> KitDefaults {
        KitDefaults(studyMethod: studyMethod, moduleSettings: planner.map { ["planner": .object($0)] } ?? [:])
    }

    // MARK: - Reading the kit

    func testKitsWithoutASectionKeepTheClaudePlanner() {
        XCTAssertEqual(TodayPlanSettings(kit: nil), TodayPlanSettings())
        XCTAssertEqual(TodayPlanSettings(kit: KitDefaults()).planMode, .claude)
    }

    func testReadsEveryKey() {
        let settings = TodayPlanSettings(kit: kit([
            "planMode": .string("study"), "reviewsFirst": .bool(false), "eventBufferMinutes": .number(15),
            "studyBlockTitle": .string("  Shelf prep  "), "secondsPerCard": .number(6),
        ], studyMethod: "fiftyTwoSeventeen"))
        XCTAssertEqual(settings.planMode, .study)
        XCTAssertEqual(settings.studyMethod, .fiftyTwoSeventeen)
        XCTAssertFalse(settings.reviewsFirst)
        XCTAssertEqual(settings.eventBufferMinutes, 15)
        XCTAssertEqual(settings.studyBlockTitle, "Shelf prep")
        XCTAssertEqual(settings.secondsPerCard, 6)
    }

    func testBadValuesFallBackToDefaults() {
        let settings = TodayPlanSettings(kit: kit([
            "planMode": .string("astrology"), "reviewsFirst": .string("yes"), "eventBufferMinutes": .number(-5),
            "studyBlockTitle": .string("   "), "secondsPerCard": .number(0),
        ], studyMethod: "nope"))
        let defaults = TodayPlanSettings()
        XCTAssertEqual(settings.planMode, .claude)
        XCTAssertEqual(settings.studyMethod, defaults.studyMethod)
        XCTAssertTrue(settings.reviewsFirst)
        XCTAssertEqual(settings.eventBufferMinutes, 0)
        XCTAssertEqual(settings.studyBlockTitle, "Study block")
        XCTAssertEqual(settings.secondsPerCard, 1)
    }

    func testMedicineKitPlansStudyDays() throws {
        let medicine = try KitLibrary.loadBundled("medicine")
        let settings = TodayPlanSettings(kit: medicine.defaults)
        XCTAssertEqual(settings.planMode, .study)
        XCTAssertEqual(settings.studyMethod.kind, medicine.defaults.resolvedStudyMethod)
        XCTAssertTrue(settings.reviewsFirst)
    }

    // MARK: - Planning

    func testStudyPlanTurnsUnfinishedGoalsIntoReviewBlocks() {
        let settings = TodayPlanSettings(planMode: .study, studyMethod: .fiftyTwoSeventeen,
                                         studyBlockTitle: "Shelf prep", secondsPerCard: 10)
        let context = DayPlanContext(now: at(8), events: [], tasks: [], calendar: calendar)
        let progress = [
            ProgressItem(id: "reviews", source: .anki, title: "Anki reviews", completed: 50, target: 230, unit: "cards"),
            ProgressItem(id: "done", source: .anki, title: "New cards", completed: 20, target: 20, unit: "cards"),
        ]
        let plan = settings.studyPlan(context: context, progress: progress)

        // 180 cards at 10 s is 30 min, first thing; the finished goal gets no block.
        let reviews = plan.blocks.filter { $0.kind == .reviews }
        XCTAssertEqual(reviews.map(\.title), ["Anki reviews"])
        XCTAssertEqual(reviews.first?.start, at(8))
        XCTAssertEqual(reviews.first?.end, at(8, 30))

        let study = plan.blocks.filter { $0.kind == .study }
        XCTAssertFalse(study.isEmpty)
        XCTAssertTrue(study.allSatisfy { $0.end.timeIntervalSince($0.start) == 52 * 60 })
        XCTAssertTrue(study.allSatisfy { $0.title == "Shelf prep" })
        for (a, b) in zip(plan.blocks, plan.blocks.dropFirst()) {
            XCTAssertLessThanOrEqual(a.end, b.start)
        }
    }

    func testStudyPlanKeepsTheBufferAroundEvents() {
        let settings = TodayPlanSettings(planMode: .study, eventBufferMinutes: 15)
        let lecture = UpcomingEvent(id: "lecture", title: "Lecture", start: at(10), end: at(12))
        let context = DayPlanContext(now: at(8), events: [lecture], tasks: [], calendar: calendar)
        let plan = settings.studyPlan(context: context, progress: [])
        XCTAssertFalse(plan.blocks.isEmpty)
        for block in plan.blocks {
            XCTAssertTrue(block.end <= at(9, 45) || block.start >= at(12, 15), "\(block.start) crowds the lecture")
        }
    }
}
