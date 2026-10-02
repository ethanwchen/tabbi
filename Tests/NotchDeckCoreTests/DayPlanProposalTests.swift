import XCTest
import NotchDeckCore

final class DayPlanProposalTests: XCTestCase {
    /// Records what it was asked to write, or fails like a denied calendar.
    private final class RecordingWriter: PlanCalendarWriting {
        struct Denied: Error {}
        var written: [[PlannedCalendarEvent]] = []
        var fails = false

        func write(_ events: [PlannedCalendarEvent]) throws {
            if fails { throw Denied() }
            written.append(events)
        }
    }

    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

    private lazy var first = PlanBlock(start: at(60), end: at(120), title: "Ship planner beta")
    private lazy var second = PlanBlock(start: at(0), end: at(45), title: "Write release notes")
    private lazy var third = PlanBlock(start: at(150), end: at(180), title: "Inbox")

    func testPendingBlocksAreInTimeOrder() {
        let proposal = DayPlanProposal(blocks: [first, second, third])
        XCTAssertEqual(proposal.pending.map(\.title), ["Write release notes", "Ship planner beta", "Inbox"])
        XCTAssertFalse(proposal.isSettled)
    }

    func testAddingOneBlockWritesItWithTheNoteAndRemovesIt() throws {
        var proposal = DayPlanProposal(blocks: [first, second])
        let writer = RecordingWriter()
        try proposal.add([first.id], now: at(-10), events: [], writer: writer)

        XCTAssertEqual(writer.written, [[
            PlannedCalendarEvent(title: "Ship planner beta", start: at(60), end: at(120), notes: "Planned with NotchDeck"),
        ]])
        XCTAssertEqual(proposal.pending.map(\.id), [second.id])
        XCTAssertEqual(proposal.addedCount, 1)
    }

    func testAddAllWritesEveryPendingBlockInOneBatch() throws {
        var proposal = DayPlanProposal(blocks: [first, second, third])
        proposal.dismiss(third.id)
        let writer = RecordingWriter()
        try proposal.add(now: at(-10), events: [], writer: writer)

        XCTAssertEqual(writer.written.count, 1)
        XCTAssertEqual(writer.written.first?.map(\.title), ["Write release notes", "Ship planner beta"])
        XCTAssertTrue(proposal.isSettled)
        XCTAssertEqual(proposal.addedCount, 2)
    }

    func testBlocksThatSlippedIntoThePastAreTrimmedOrDropped() throws {
        var proposal = DayPlanProposal(blocks: [first, second, third])
        let writer = RecordingWriter()
        // 70 minutes in: the earliest block is over and the next has started.
        let written = try proposal.add(now: at(70), events: [], writer: writer)

        XCTAssertEqual(written.map(\.title), ["Ship planner beta", "Inbox"])
        XCTAssertEqual(written.first?.start, at(70))
        XCTAssertEqual(written.first?.end, at(120))
        XCTAssertTrue(proposal.isSettled, "a dropped block is no longer pending either")
        XCTAssertEqual(proposal.addedCount, 2)
        XCTAssertEqual(proposal.skippedCount, 1)
    }

    func testBlocksAreRecheckedAgainstMeetingsAddedSinceTheProposal() throws {
        var proposal = DayPlanProposal(blocks: [first, second, third])
        let writer = RecordingWriter()
        let events = [
            // Takes the first 20 minutes of "Ship planner beta"; the rest stays.
            UpcomingEvent(id: "sync", title: "Sync", start: at(50), end: at(80)),
            // Swallows "Inbox" whole.
            UpcomingEvent(id: "call", title: "Call", start: at(140), end: at(190)),
            // All-day events never block time.
            UpcomingEvent(id: "holiday", title: "Holiday", start: at(-600), end: at(800), isAllDay: true),
        ]
        let written = try proposal.add(now: at(-10), events: events, writer: writer)

        XCTAssertEqual(written.map(\.title), ["Write release notes", "Ship planner beta"])
        XCTAssertEqual(written.last?.start, at(80))
        XCTAssertEqual(written.last?.end, at(120))
        XCTAssertEqual(proposal.addedCount, 2)
        XCTAssertEqual(proposal.skippedCount, 1)
        XCTAssertTrue(proposal.isSettled)
    }

    func testMeetingInTheMiddleKeepsTheLongestFreePiece() throws {
        var proposal = DayPlanProposal(blocks: [first])
        let events = [UpcomingEvent(id: "chat", title: "Chat", start: at(75), end: at(85))]
        let written = try proposal.add(now: at(-10), events: events, writer: RecordingWriter())
        XCTAssertEqual(written.first?.start, at(85))
        XCTAssertEqual(written.first?.end, at(120))
    }

    func testFailedWriteLeavesTheProposalUntouched() {
        var proposal = DayPlanProposal(blocks: [first, second])
        let writer = RecordingWriter()
        writer.fails = true
        XCTAssertThrowsError(try proposal.add(now: at(-10), events: [], writer: writer))
        XCTAssertEqual(proposal.pending.count, 2)
        XCTAssertEqual(proposal.addedCount, 0)
    }

    func testNothingLeftToWriteSkipsTheWriter() throws {
        var proposal = DayPlanProposal(blocks: [second])
        let writer = RecordingWriter()
        writer.fails = true
        XCTAssertEqual(try proposal.add(now: at(40), events: [], writer: writer), [])
        XCTAssertTrue(proposal.isSettled)
        XCTAssertEqual(proposal.skippedCount, 1)
    }

    func testSampleProposalAvoidsTheSampleEventsAndIsInTheFuture() {
        let now = Date()
        let blocks = DayPlanner.sampleProposal(now: now)
        let events = UpcomingEvent.samples(now: now)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertLessThanOrEqual(blocks.count, DayPlanner.maximumBlocks)
        for block in blocks {
            XCTAssertGreaterThan(block.start, now)
            XCTAssertFalse(events.contains { $0.start < block.end && block.start < $0.end }, block.title)
        }
    }
}
