import XCTest
import TabbiKitCore

final class DayPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// 2026-10-01 at `hour:minute` Los Angeles time.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> UpcomingEvent {
        UpcomingEvent(id: id, title: id, start: start, end: end, isAllDay: allDay)
    }

    private let taskA = PlannerItem(title: "Ship planner beta", createdAt: Date(timeIntervalSince1970: 0))
    private let taskB = PlannerItem(title: "Write release notes", createdAt: Date(timeIntervalSince1970: 0))
    private let doneTask = PlannerItem(title: "Done already", isDone: true, createdAt: Date(timeIntervalSince1970: 0))

    private func context(now: Date, events: [UpcomingEvent] = []) -> DayPlanContext {
        DayPlanContext(now: now, events: events, tasks: [taskA, doneTask, taskB], calendar: calendar)
    }

    // MARK: - Day end

    func testDayEndIsSixPMOrTwoHoursOutCappedAtTenPM() {
        XCTAssertEqual(DayPlanner.dayEnd(now: at(9), calendar: calendar), at(18))
        XCTAssertEqual(DayPlanner.dayEnd(now: at(17), calendar: calendar), at(19))
        XCTAssertEqual(DayPlanner.dayEnd(now: at(21), calendar: calendar), at(22))
        XCTAssertEqual(DayPlanner.dayEnd(now: at(23), calendar: calendar), at(22))
    }

    func testDayEndFollowsTheKitsEndHour() {
        XCTAssertEqual(DayPlanner.dayEnd(now: at(9), calendar: calendar, endHour: 21), at(21))
        XCTAssertEqual(DayPlanner.dayEnd(now: at(20), calendar: calendar, endHour: 21), at(22))
        XCTAssertEqual(DayPlanner.dayEnd(now: at(9), calendar: calendar, endHour: 23), at(22))
        let evening = DayPlanContext(now: at(17), events: [], tasks: [], calendar: calendar, dayEndHour: 21)
        XCTAssertEqual(evening.gaps, [DateInterval(start: at(17), end: at(21))])
    }

    // MARK: - Gaps

    func testFreeGapsSkipEventsAllDayEventsAndSlivers() {
        let events = [
            event("standup", at(9, 50), at(10, 15)),
            event("holiday", at(0), at(23, 59), allDay: true),
            event("lunch", at(12), at(13)),
            event("overlapping", at(12, 30), at(13, 30)),
            event("sliver-maker", at(13, 40), at(14)),
        ]
        let gaps = DayPlanner.freeGaps(events: events, from: at(9, 2), until: at(18))
        XCTAssertEqual(gaps, [
            DateInterval(start: at(9, 5), end: at(9, 50)),
            DateInterval(start: at(10, 15), end: at(12)),
            DateInterval(start: at(14), end: at(18)),
        ])
    }

    func testFreeGapsHandleEventInProgressAndPastEnd() {
        let events = [event("now", at(14), at(15)), event("evening", at(17, 30), at(19))]
        XCTAssertEqual(
            DayPlanner.freeGaps(events: events, from: at(14, 30), until: at(18)),
            [DateInterval(start: at(15), end: at(17, 30))]
        )
        XCTAssertEqual(DayPlanner.freeGaps(events: [], from: at(19), until: at(18)), [])
    }

    func testContextDropsFinishedTasksAndKeysTheRest() {
        let context = context(now: at(9))
        XCTAssertEqual(context.taskKeys.map(\.key), ["t1", "t2"])
        XCTAssertEqual(context.taskKeys.map(\.task.id), [taskA.id, taskB.id])
        XCTAssertTrue(context.hasFreeTime)
        XCTAssertFalse(self.context(now: at(22, 30)).hasFreeTime)
    }

    // MARK: - Prompt and flags

    func testPromptListsLocalTimesEventsGapsAndTasks() {
        let prompt = DayPlanner.prompt(for: context(now: at(13, 2), events: [event("Design review", at(15), at(15, 30))]))
        XCTAssertTrue(prompt.contains("It is now 13:02"))
        XCTAssertTrue(prompt.contains("end by 18:00"))
        XCTAssertTrue(prompt.contains("- 15:00-15:30 Design review"))
        XCTAssertTrue(prompt.contains("- 13:05-15:00"))
        XCTAssertTrue(prompt.contains("- 15:30-18:00"))
        XCTAssertTrue(prompt.contains("- t1: Ship planner beta"))
        XCTAssertTrue(prompt.contains("- t2: Write release notes"))
        XCTAssertFalse(prompt.contains("Done already"))
    }

    func testSharedWorkIsKeyedAfterChecklistAndNeverLinksABlock() throws {
        let context = DayPlanContext(now: at(9), events: [], tasks: [taskA, doneTask, taskB],
                                     sharedWork: ["Anki reviews (320 cards left)", "  "], calendar: calendar)
        XCTAssertEqual(context.sharedWorkKeys.map(\.key), ["t3"])
        let prompt = DayPlanner.prompt(for: context)
        XCTAssertTrue(prompt.contains("- t2: Write release notes\n- t3: Anki reviews (320 cards left)"))
        let text = #"{"blocks":[{"start":"10:00","end":"11:00","title":"Anki reviews","task":"t3"}]}"#
        let blocks = try DayPlanner.parse(text, context: context)
        XCTAssertEqual(blocks.map(\.title), ["Anki reviews"])
        XCTAssertNil(blocks[0].linkedTaskID)
    }

    func testPlanningTomorrowAheadStartsAtTheWorkingDayAndLandsOnThatDay() throws {
        // 9 pm on Oct 1, planning Oct 2.
        let start = try XCTUnwrap(PlannerViewedDay.tomorrow.planStart(now: at(21), calendar: calendar))
        let nine = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 9))!
        XCTAssertEqual(start, nine)
        let meeting = event("Standup", nine.addingTimeInterval(3600), nine.addingTimeInterval(5400))
        let context = DayPlanContext(now: start, events: [meeting], tasks: [taskA], calendar: calendar,
                                     isPlanningAhead: true)
        XCTAssertEqual(context.dayEnd, nine.addingTimeInterval(9 * 3600), "a full day, ending at 6 pm")
        XCTAssertEqual(context.gaps.first, DateInterval(start: nine, end: meeting.start))

        let prompt = DayPlanner.prompt(for: context)
        XCTAssertTrue(prompt.contains("day tomorrow, ahead of time. The day starts at 09:00"))
        XCTAssertFalse(prompt.contains("It is now"))
        XCTAssertTrue(prompt.contains("- 10:00-10:30 Standup"))

        let blocks = try DayPlanner.proposal(from: #"[{"start":"09:00","end":"09:45","title":"Ship","task":"t1"}]"#,
                                             context: context)
        XCTAssertEqual(blocks.first?.start, nine, "HH:mm resolves on the planned day, not tonight")
        XCTAssertEqual(blocks.first?.linkedTaskID, taskA.id)
    }

    func testPromptSaysNoneForEmptySections() {
        let prompt = DayPlanner.prompt(for: DayPlanContext(now: at(23), events: [], tasks: [], calendar: calendar))
        XCTAssertEqual(prompt.components(separatedBy: "- none").count - 1, 3)
    }

    func testExtraArgumentsUseFastModelNoToolsAndValidSchema() throws {
        let arguments = DayPlanner.extraArguments()
        XCTAssertEqual(arguments.first, "--model")
        XCTAssertEqual(arguments[1], DayPlanner.model)
        let toolsIndex = try XCTUnwrap(arguments.firstIndex(of: "--tools"))
        XCTAssertEqual(arguments[toolsIndex + 1], "")
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        let schemaIndex = try XCTUnwrap(arguments.firstIndex(of: "--json-schema"))
        let schema = try JSONSerialization.jsonObject(with: Data(arguments[schemaIndex + 1].utf8)) as? [String: Any]
        XCTAssertEqual(schema?["required"] as? [String], ["blocks"])
    }

    // MARK: - Parsing

    func testParsesFencedJSONWithProseAndLinksTasks() throws {
        let text = """
        Here's your plan:
        ```json
        {"blocks": [
          {"start": "13:30", "end": "14:30", "title": "Ship planner beta", "task": "t1"},
          {"start": "9:05", "end": "9:45", "title": "  Inbox   zero ", "task": "t9"},
          {"start": "15:00", "end": "15:30", "title": "Notes", "task": "\(taskB.id.uuidString)"}
        ]}
        ```
        """
        let blocks = try DayPlanner.parse(text, context: context(now: at(9)))
        XCTAssertEqual(blocks.map(\.start), [at(13, 30), at(9, 5), at(15)])
        XCTAssertEqual(blocks.map(\.end), [at(14, 30), at(9, 45), at(15, 30)])
        XCTAssertEqual(blocks.map(\.title), ["Ship planner beta", "Inbox zero", "Notes"])
        XCTAssertEqual(blocks.map(\.linkedTaskID), [taskA.id, nil, taskB.id])
    }

    func testParseAcceptsBareArrayAndSkipsMalformedEntries() throws {
        let text = """
        [{"start":"10:00","end":"11:00","title":"Good"},
         {"start":"11:00","end":"10:00","title":"Backwards"},
         {"start":"25:00","end":"26:00","title":"Bad hour"},
         {"start":"10:0","end":"11:00","title":"Bad minutes"},
         {"start":"12:00","end":"13:00","title":"   "},
         {"start":"12:00","end":"13:00"},
         "nonsense"]
        """
        XCTAssertEqual(try DayPlanner.parse(text, context: context(now: at(9))).map(\.title), ["Good"])
    }

    func testParseOfObjectWithoutBlocksIsEmptyAndNoJSONThrows() throws {
        XCTAssertEqual(try DayPlanner.parse(#"{"plan": []}"#, context: context(now: at(9))), [])
        XCTAssertThrowsError(try DayPlanner.parse("Sorry, I can't help with that.", context: context(now: at(9)))) {
            XCTAssertEqual($0 as? DayPlanner.ParseError, .noJSON)
        }
        XCTAssertThrowsError(try DayPlanner.parse("{not json}", context: context(now: at(9))))
    }

    // MARK: - Validation

    func testValidateTrimsBlocksOverlappingEventsAndThePast() {
        let context = context(now: at(10, 7), events: [event("lunch", at(12), at(13))])
        let blocks = [
            PlanBlock(start: at(9), end: at(10, 45), title: "Starts in the past"),
            PlanBlock(start: at(11, 30), end: at(12, 30), title: "Runs into lunch"),
            PlanBlock(start: at(12, 10), end: at(12, 50), title: "Inside lunch"),
            PlanBlock(start: at(17, 30), end: at(19), title: "Past day end"),
        ]
        let valid = DayPlanner.validate(blocks, context: context)
        XCTAssertEqual(valid.map(\.title), ["Starts in the past", "Runs into lunch", "Past day end"])
        XCTAssertEqual(valid.map(\.start), [at(10, 10), at(11, 30), at(17, 30)])
        XCTAssertEqual(valid.map(\.end), [at(10, 45), at(12), at(18)])
    }

    func testValidateKeepsLongestPieceOfBlockSpanningAnEvent() {
        let context = context(now: at(9), events: [event("call", at(10), at(10, 30))])
        let valid = DayPlanner.validate([PlanBlock(start: at(9, 45), end: at(11, 30), title: "Deep work")], context: context)
        XCTAssertEqual(valid.map(\.interval), [DateInterval(start: at(10, 30), end: at(11, 30))])
    }

    func testValidateResolvesOverlapsBetweenBlocksAndDropsShortOnes() {
        let context = context(now: at(9))
        let blocks = [
            PlanBlock(start: at(11), end: at(12), title: "Second"),
            PlanBlock(start: at(10), end: at(11, 30), title: "First"),
            PlanBlock(start: at(11, 50), end: at(12, 10), title: "Squeezed"),
            PlanBlock(start: at(14), end: at(14, 10), title: "Too short"),
        ]
        let valid = DayPlanner.validate(blocks, context: context)
        XCTAssertEqual(valid.map(\.title), ["First", "Second"])
        XCTAssertEqual(valid.map(\.interval), [
            DateInterval(start: at(10), end: at(11, 30)),
            DateInterval(start: at(11, 30), end: at(12)),
        ])
    }

    func testValidateCapsBlockCount() {
        let blocks = (0..<10).map { PlanBlock(start: at(9 + $0 / 2, ($0 % 2) * 30), end: at(9 + $0 / 2, ($0 % 2) * 30 + 25), title: "\($0)") }
        XCTAssertEqual(DayPlanner.validate(blocks, context: context(now: at(9))).count, DayPlanner.maximumBlocks)
    }

    func testProposalParsesThenValidates() throws {
        let context = context(now: at(16), events: [event("gym", at(17), at(18))])
        let text = #"{"blocks":[{"start":"16:00","end":"17:30","title":"Release notes","task":"t2"},{"start":"17:00","end":"17:45","title":"Gym clash"}]}"#
        let proposal = try DayPlanner.proposal(from: text, context: context)
        XCTAssertEqual(proposal.map(\.title), ["Release notes"])
        XCTAssertEqual(proposal.first?.interval, DateInterval(start: at(16), end: at(17)))
        XCTAssertEqual(proposal.first?.linkedTaskID, taskB.id)
    }
}
