import XCTest
import TabbiKitCore

/// "Refine with Claude" on the local plan: what Claude is told, how its
/// answer is checked, and what it does to the proposal.
final class PlanRefinementTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour, minute: minute))!
    }

    private lazy var report = PlannerItem(title: "Write report", createdAt: at(8))
    private lazy var standup = UpcomingEvent(id: "standup", title: "Standup", start: at(10), end: at(10, 30))

    private func context() -> DayPlanContext {
        DayPlanContext(now: at(9), events: [standup], tasks: [report], calendar: calendar)
    }

    private func localPlan() -> [PlanBlock] {
        [PlanBlock(start: at(9), end: at(9, 30), title: "Anki reviews", kind: .reviews),
         PlanBlock(start: at(10, 45), end: at(11, 45), title: "Write report", linkedTaskID: report.id)]
    }

    // MARK: - Prompt

    func testThePromptHandsClaudeTheLocalPlanWithTaskIDs() {
        let prompt = DayPlanner.refinePrompt(for: context(), plan: localPlan())
        XCTAssertTrue(prompt.contains("- 09:00-09:30 Anki reviews\n"))
        XCTAssertTrue(prompt.contains("- 10:45-11:45 Write report (task t1)"))
        XCTAssertTrue(prompt.contains("- 10:00-10:30 Standup"), "the calendar is still there")
        XCTAssertTrue(prompt.contains("unchanged if it is already good"))
    }

    func testThePromptAllowsEveryLocalBlockPastTheUsualCap() {
        let many = (0..<7).map { index in
            PlanBlock(start: at(11 + index), end: at(11 + index, 30), title: "Block \(index)")
        }
        XCTAssertTrue(DayPlanner.refinePrompt(for: context(), plan: many).contains("at most 7 focused"))
        XCTAssertTrue(DayPlanner.refinePrompt(for: context(), plan: localPlan())
            .contains("at most \(DayPlanner.maximumBlocks) focused"))
    }

    // MARK: - Answer

    func testTheAnswerKeepsKindsAndLinksAndStaysOffTheCalendar() throws {
        let answer = """
        {"blocks":[{"start":"09:00","end":"09:40","title":"Anki reviews"},
        {"start":"10:15","end":"11:30","title":"Report draft","task":"t1"}]}
        """
        let blocks = try DayPlanner.refinement(from: answer, context: context(), plan: localPlan())

        XCTAssertEqual(blocks.map(\.kind), [.reviews, .focus])
        XCTAssertEqual(blocks[1].linkedTaskID, report.id)
        XCTAssertEqual(blocks[1].start, at(10, 30), "trimmed off the standup")
        XCTAssertEqual(blocks[0].end, at(9, 40))
    }

    func testAnAnswerWithoutJSONThrows() {
        XCTAssertThrowsError(try DayPlanner.refinement(from: "Looks good to me.", context: context(),
                                                       plan: localPlan()))
    }

    // MARK: - Proposal

    func testRefiningReplacesTheBlocksOnOfferAndDropsStrandedBreaks() {
        var proposal = DayPlanProposal(blocks: localPlan(),
                                       breaks: [DateInterval(start: at(9, 30), end: at(9, 35))])
        let refined = [PlanBlock(start: at(9), end: at(9, 45), title: "Anki reviews", kind: .reviews)]
        proposal.refine(with: refined)

        XCTAssertEqual(proposal.refinement, .changed)
        XCTAssertEqual(proposal.pending, refined)
        XCTAssertEqual(proposal.breaks, [])
    }

    func testTheSamePlanIsRecordedAsUnchanged() {
        let local = localPlan()
        var proposal = DayPlanProposal(blocks: local)
        let echoed = local.reversed().map {
            PlanBlock(start: $0.start, end: $0.end, title: $0.title, linkedTaskID: $0.linkedTaskID, kind: $0.kind)
        }
        proposal.refine(with: echoed)

        XCTAssertEqual(proposal.refinement, .unchanged)
        XCTAssertEqual(proposal.pending.map(\.id), local.map(\.id), "the local blocks stay")
    }

    func testAnEmptyAnswerChangesNothing() {
        var proposal = DayPlanProposal(blocks: localPlan())
        proposal.refine(with: [])
        XCTAssertNil(proposal.refinement)
        XCTAssertEqual(proposal.pending.count, 2)
    }
}
