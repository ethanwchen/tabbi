import Foundation
import TabbiKitCore
import XCTest

/// Pins Plan my day, from what Today hands it (the checklist, the calendar
/// and what other modules share) to the proposal it offers and the events
/// it writes, to the golden fixture `shared/fixtures/plan-my-day/plan-my-day.json`.
///
/// Each day is planned all three ways (on device, as a study day, and from
/// recorded Claude answers), so the Windows port can check its planners
/// against the same blocks, breaks, reasons and prompts. Run with
/// `TABBI_RECORD_FIXTURES=1` to rewrite it after an intended change.
final class PlanMyDayGoldenTests: XCTestCase {
    func testPlanMyDayMatchesGoldenFixture() throws {
        let url = PlanMyDayGoldenFixture.url
        let current = PlanMyDayGoldenFixture.current()
        if ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1" {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PetGoldenFixtures.encode(current).write(to: url)
            return
        }
        let stored = try JSONDecoder().decode(PlanMyDayGoldenFixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.constants, current.constants, "Plan my day constants changed")
        XCTAssertEqual(stored.days.map(\.name), current.days.map(\.name))
        for (old, new) in zip(stored.days, current.days) {
            XCTAssertEqual(old.input, new.input, old.name)
            XCTAssertEqual(old.output, new.output, "Day \(old.name)")
        }
        XCTAssertEqual(stored.proposals.map(\.name), current.proposals.map(\.name))
        for (old, new) in zip(stored.proposals, current.proposals) {
            XCTAssertEqual(old, new, "Proposal \(old.name)")
        }
        XCTAssertEqual(stored, current, "Plan my day no longer matches \(url.lastPathComponent)")
    }

    /// The fixture's own inputs, replayed: a port that reads only the inputs
    /// from the file gets the recorded outputs.
    func testStoredInputsReplayToStoredOutputs() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["TABBI_RECORD_FIXTURES"] == "1", "Recording")
        let stored = try JSONDecoder().decode(PlanMyDayGoldenFixture.self,
                                              from: Data(contentsOf: PlanMyDayGoldenFixture.url))
        for day in stored.days {
            XCTAssertEqual(PlanMyDayGoldenFixture.plan(day.input), day.output, day.name)
        }
        for proposal in stored.proposals {
            let steps = proposal.steps.map(\.input)
            XCTAssertEqual(PlanMyDayGoldenFixture.run(proposal.blocks, breaks: proposal.breaks, steps: steps),
                           proposal.steps, proposal.name)
        }
    }
}

/// Days planned every way Plan my day can, and proposal sequences.
struct PlanMyDayGoldenFixture: Codable, Equatable {
    static let schemaName = "tabbi.plan-my-day.golden"

    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/fixtures/plan-my-day/plan-my-day.json")
    }

    /// Reasons carry clock times ("Due by 3:00"), written for this locale.
    static let locale = Locale(identifier: "en_US")

    struct Constants: Codable, Equatable {
        var minimumBlockMinutes: Int
        var maximumBlocks: Int
        var maximumTitleLength: Int
        var defaultDayEndHour: Int
        var latestDayEndHour: Int
        var workdayStartMinute: Int
        var defaultSecondsPerCard: Double
        var maximumReviewMinutes: Int
        var eventNote: String
        var claudeArguments: [String]
    }

    // MARK: Input

    struct Event: Codable, Equatable {
        var id: String
        var title: String
        var start: Double
        var end: Double
        var isAllDay: Bool = false
    }

    /// A Today checklist item; `id` is its UUID.
    struct Task: Codable, Equatable {
        var id: String
        var title: String
        var isDone: Bool = false
    }

    struct SharedTask: Codable, Equatable {
        var id: String
        var title: String
        var isDone: Bool = false
        var estimatedMinutes: Int?
    }

    struct Goal: Codable, Equatable {
        var id: String
        var title: String
        var completed: Int
        var target: Int
        var unit: String
        var waitsForStart: Bool = false
    }

    /// What one other module shares, in tab order.
    struct Provided: Codable, Equatable {
        var module: String
        var tasks: [SharedTask] = []
        var progress: [Goal] = []
    }

    /// The kit's `moduleSettings.planner` section, as `TodayPlanSettings`
    /// reads it, plus the kit's study method.
    struct Settings: Codable, Equatable {
        var planMode: String = "local"
        var studyMethod: String?
        var reviewsFirst: Bool = true
        var eventBufferMinutes: Int = 10
        var studyBlockTitle: String = "Study block"
        var secondsPerCard: Double = 10
        var dayEndHour: Int = 18
    }

    struct DayInput: Codable, Equatable {
        var timeZone: String
        var now: Double
        var events: [Event] = []
        var tasks: [Task] = []
        var provided: [Provided] = []
        var settings = Settings()
        /// Result texts Claude might answer the plan prompt with.
        var answers: [String] = []
        /// Result texts Claude might answer the refine prompt with.
        var refineAnswers: [String] = []
    }

    // MARK: Output

    struct Interval: Codable, Equatable {
        var start: Double
        var end: Double
    }

    /// A plan block; `task` is the linked checklist item's UUID. `id` is
    /// only set where the input named the block.
    struct Block: Codable, Equatable {
        var id: String?
        var start: Double
        var end: Double
        var title: String
        var task: String?
        var kind: String
    }

    struct Scheduled: Codable, Equatable {
        var start: Double
        var end: Double
        var title: String
        var task: String?
        var kind: String
        var workID: String
        var reason: String
        var part: Int
        var parts: Int
    }

    struct Unplaced: Codable, Equatable {
        var workID: String
        var title: String
        var kind: String
        var minutes: Int
        var reason: String
    }

    struct SchedulePrefs: Codable, Equatable {
        var workdayStartMinute: Int
        var workdayEndMinute: Int
        var defaultTaskMinutes: Int
        var maximumBlockMinutes: Int
        var breakMinutes: Int
        var longBreakMinutes: Int
        var longBreakEvery: Int?
        var maximumFocusMinutes: Int
        var eventBufferMinutes: Int
        var reviewsFirst: Bool
    }

    struct LocalPlan: Codable, Equatable {
        var preferences: SchedulePrefs
        var work: [String]
        var day: Double
        var blocks: [Scheduled]
        var breaks: [Interval]
        var unplaced: [Unplaced]
        var focusMinutes: Int
    }

    struct StudyPrefs: Codable, Equatable {
        var studyMinutes: Int
        var breakMinutes: Int
        var longBreakMinutes: Int?
        var longBreakEvery: Int?
        var reviewsFirst: Bool
        var eventBufferMinutes: Int
        var studyTitle: String
    }

    struct StudyReview: Codable, Equatable {
        var title: String
        var minutes: Int
    }

    struct StudyPlan: Codable, Equatable {
        var preferences: StudyPrefs
        var reviews: [StudyReview]
        var blocks: [Block]
        var breaks: [Interval]
    }

    /// One Claude answer: what the parser read (nil when it found no JSON),
    /// and what the validator kept.
    struct ClaudeRead: Codable, Equatable {
        var answer: String
        var parsed: [Block]?
        var proposal: [Block]?
    }

    /// One refine answer, validated against the local plan, and the
    /// proposal after `refine(with:)`.
    struct RefineRead: Codable, Equatable {
        var answer: String
        var blocks: [Block]?
        var pending: [Block]
        var breaks: [Interval]
        var refinement: String?
    }

    /// What the panel shows for the day's `planMode`: `proposal` (with its
    /// blocks and breaks), `noFreeTime`, or `failed` when Claude's answer
    /// had no JSON (Claude mode asks once, with the first answer).
    struct Outcome: Codable, Equatable {
        var kind: String
        var blocks: [Block]?
        var breaks: [Interval]?
    }

    struct DayOutput: Codable, Equatable {
        var sharedWork: [String]
        var dayEnd: Double
        var gaps: [Interval]
        var taskKeys: [String]
        var local: LocalPlan
        var study: StudyPlan
        var prompt: String
        var claude: [ClaudeRead]
        var refinePrompt: String
        var refinements: [RefineRead]
        var outcome: Outcome
    }

    struct Day: Codable, Equatable {
        var name: String
        var input: DayInput
        var output: DayOutput
    }

    // MARK: Proposals

    struct Written: Codable, Equatable {
        var title: String
        var start: Double
        var end: Double
        var notes: String
    }

    /// One action on a proposal: `dismiss` the block `id`, `refine` with
    /// `blocks`, or `add` the blocks `ids` (all when absent) at `at` with
    /// the calendar `events` as it is then, through a writer that throws
    /// when `writerFails`.
    struct StepInput: Codable, Equatable {
        var action: String
        var id: String?
        var ids: [String]?
        var blocks: [Block]?
        var at: Double?
        var events: [Event]?
        var writerFails: Bool?
    }

    struct Step: Codable, Equatable {
        var input: StepInput
        var written: [Written]?
        var threw: Bool?
        var pending: [Block]
        /// `breakAfter` for each pending block, in order.
        var breaksAfter: [Interval?]
        var breaks: [Interval]
        var addedCount: Int
        var skippedCount: Int
        var refinement: String?
        var isSettled: Bool
    }

    struct Proposal: Codable, Equatable {
        var name: String
        var blocks: [Block]
        var breaks: [Interval]
        var steps: [Step]
    }

    var schema = Self.schemaName
    var version = 1
    var constants: Constants
    var days: [Day]
    var proposals: [Proposal]

    static func current() -> PlanMyDayGoldenFixture {
        PlanMyDayGoldenFixture(
            constants: Constants(
                minimumBlockMinutes: DayPlanner.minimumBlockMinutes, maximumBlocks: DayPlanner.maximumBlocks,
                maximumTitleLength: DayPlanner.maximumTitleLength, defaultDayEndHour: DayPlanner.defaultDayEndHour,
                latestDayEndHour: DayPlanner.latestDayEndHour, workdayStartMinute: TodayPlanSettings.workdayStartMinute,
                defaultSecondsPerCard: StudyDayPreferences.defaultSecondsPerCard,
                maximumReviewMinutes: StudyDayPreferences.maximumReviewMinutes, eventNote: DayPlanner.eventNote,
                claudeArguments: DayPlanner.extraArguments()
            ),
            days: sampleDays().map { Day(name: $0.name, input: $0.input, output: plan($0.input)) },
            proposals: sampleProposals.map { name, blocks, breaks, steps in
                Proposal(name: name, blocks: blocks, breaks: breaks, steps: run(blocks, breaks: breaks, steps: steps))
            }
        )
    }

    // MARK: Running

    static func plan(_ input: DayInput) -> DayOutput {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: input.timeZone)!
        let now = date(input.now)
        let events = input.events.map(upcoming)
        let tasks = input.tasks.map {
            PlannerItem(id: UUID(uuidString: $0.id)!, title: $0.title, isDone: $0.isDone, createdAt: now)
        }
        let snapshot = ProviderSnapshot(input.provided.map { provided in
            (ModuleID(provided.module), ModuleProvision(
                tasks: provided.tasks.map {
                    ProvidedTask(id: $0.id, source: ModuleID(provided.module), title: $0.title, isDone: $0.isDone,
                                 estimatedMinutes: $0.estimatedMinutes)
                },
                progress: provided.progress.map {
                    ProgressItem(id: $0.id, source: ModuleID(provided.module), title: $0.title, completed: $0.completed,
                                 target: $0.target, unit: $0.unit, waitsForStart: $0.waitsForStart)
                }
            ))
        })
        // What Today passes on: other modules' work, phrased and as tasks and goals.
        let sharedWork = snapshot.plannableWork(excluding: .planner)
        let sharedTasks = snapshot.openTasks.filter { $0.source != .planner }
        let progress = snapshot.progress.filter { $0.source != .planner }
        let settings = TodayPlanSettings(
            planMode: TodayPlanSettings.PlanMode(rawValue: input.settings.planMode)!,
            studyMethod: input.settings.studyMethod.map { StudyMethod.preset(StudyMethodKind(rawValue: $0)!) },
            reviewsFirst: input.settings.reviewsFirst, eventBufferMinutes: input.settings.eventBufferMinutes,
            studyBlockTitle: input.settings.studyBlockTitle, secondsPerCard: input.settings.secondsPerCard,
            dayEndHour: input.settings.dayEndHour
        )
        let context = DayPlanContext(now: now, events: events, tasks: tasks, sharedWork: sharedWork,
                                     calendar: calendar, dayEndHour: settings.dayEndHour)

        let preferences = settings.schedulePreferences(now: now, calendar: calendar)
        let localPlan = settings.localPlan(now: now, events: events, tasks: tasks, sharedTasks: sharedTasks,
                                           progress: progress, calendar: calendar, locale: locale)
        let local = LocalPlan(
            preferences: schedulePrefs(preferences),
            work: settings.localWork(tasks: tasks, sharedTasks: sharedTasks, progress: progress).map(\.id),
            day: localPlan.day.timeIntervalSince1970,
            blocks: localPlan.blocks.map(scheduled),
            breaks: localPlan.breaks.map(interval),
            unplaced: localPlan.unplaced.map {
                Unplaced(workID: $0.work.id, title: $0.work.title, kind: $0.work.kind.rawValue, minutes: $0.minutes,
                         reason: $0.reason)
            },
            focusMinutes: localPlan.focusMinutes
        )

        let studyPlan = settings.studyPlan(context: context, progress: progress)
        let reviews = progress.compactMap { $0.reviewWork(secondsPerUnit: settings.secondsPerCard) }
        let study = StudyPlan(preferences: studyPrefs(settings.preferences),
                              reviews: reviews.map { StudyReview(title: $0.title, minutes: $0.minutes) },
                              blocks: studyPlan.blocks.map { block($0) }, breaks: studyPlan.breaks.map(interval))

        let claude = input.answers.map { answer in
            let parsed = try? DayPlanner.parse(answer, context: context)
            return ClaudeRead(answer: answer, parsed: parsed?.map { block($0) },
                              proposal: parsed.map { DayPlanner.validate($0, context: context).map { block($0) } })
        }

        let localBlocks = localPlan.blocks.map(\.block)
        let refinements = input.refineAnswers.map { answer in
            let refined = try? DayPlanner.refinement(from: answer, context: context, plan: localBlocks)
            var proposal = localPlan.proposal
            if let refined { proposal.refine(with: refined) }
            return RefineRead(answer: answer, blocks: refined?.map { block($0) }, pending: proposal.pending.map { block($0) },
                              breaks: proposal.breaks.map(interval), refinement: proposal.refinement.map(refinementName))
        }

        // DayPlanStore.run: no free time ends planning before any planner runs.
        let outcome: Outcome
        if !context.hasFreeTime {
            outcome = Outcome(kind: "noFreeTime")
        } else {
            switch settings.planMode {
            case .local: outcome = Self.outcome(localPlan.proposal)
            case .study: outcome = Self.outcome(DayPlanProposal(studyPlan))
            case .claude:
                if let answer = input.answers.first, let blocks = try? DayPlanner.proposal(from: answer, context: context) {
                    outcome = blocks.isEmpty ? Outcome(kind: "noFreeTime") : Self.outcome(DayPlanProposal(blocks: blocks))
                } else {
                    outcome = Outcome(kind: "failed")
                }
            }
        }

        return DayOutput(
            sharedWork: sharedWork, dayEnd: context.dayEnd.timeIntervalSince1970, gaps: context.gaps.map(interval),
            taskKeys: context.taskKeys.map { "\($0.key)=\($0.task.id.uuidString)" }
                + context.sharedWorkKeys.map { "\($0.key)=\($0.work)" },
            local: local, study: study, prompt: DayPlanner.prompt(for: context), claude: claude,
            refinePrompt: DayPlanner.refinePrompt(for: context, plan: localBlocks), refinements: refinements,
            outcome: outcome
        )
    }

    private static func outcome(_ proposal: DayPlanProposal) -> Outcome {
        proposal.isSettled
            ? Outcome(kind: "noFreeTime")
            : Outcome(kind: "proposal", blocks: proposal.pending.map { block($0) }, breaks: proposal.breaks.map(interval))
    }

    private struct Writer: PlanCalendarWriting {
        struct Failure: Error {}
        var fails: Bool
        func write(_ events: [PlannedCalendarEvent]) throws {
            if fails { throw Failure() }
        }
    }

    static func run(_ blocks: [Block], breaks: [Interval], steps: [StepInput]) -> [Step] {
        var proposal = DayPlanProposal(blocks: blocks.map(planBlock), breaks: breaks.map(dateInterval))
        return steps.map { input in
            var written: [Written]?
            var threw: Bool?
            switch input.action {
            case "dismiss":
                proposal.dismiss(UUID(uuidString: input.id!)!)
            case "refine":
                proposal.refine(with: (input.blocks ?? []).map(planBlock))
            default:
                do {
                    written = try proposal.add(input.ids.map { Set($0.map { UUID(uuidString: $0)! }) },
                                               now: date(input.at!), events: (input.events ?? []).map(upcoming),
                                               writer: Writer(fails: input.writerFails ?? false))
                        .map { Written(title: $0.title, start: $0.start.timeIntervalSince1970,
                                       end: $0.end.timeIntervalSince1970, notes: $0.notes) }
                    threw = false
                } catch {
                    threw = true
                }
            }
            return Step(
                input: input, written: written, threw: threw, pending: proposal.pending.map { block($0, id: true) },
                breaksAfter: proposal.pending.map { proposal.breakAfter($0).map(interval) },
                breaks: proposal.breaks.map(interval), addedCount: proposal.addedCount,
                skippedCount: proposal.skippedCount, refinement: proposal.refinement.map(refinementName),
                isSettled: proposal.isSettled
            )
        }
    }

    // MARK: Conversions

    private static func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }

    private static func upcoming(_ event: Event) -> UpcomingEvent {
        UpcomingEvent(id: event.id, title: event.title, start: date(event.start), end: date(event.end),
                      isAllDay: event.isAllDay)
    }

    private static func interval(_ interval: DateInterval) -> Interval {
        Interval(start: interval.start.timeIntervalSince1970, end: interval.end.timeIntervalSince1970)
    }

    private static func dateInterval(_ interval: Interval) -> DateInterval {
        DateInterval(start: date(interval.start), end: date(interval.end))
    }

    private static func block(_ block: PlanBlock, id: Bool = false) -> Block {
        Block(id: id ? block.id.uuidString : nil, start: block.start.timeIntervalSince1970,
              end: block.end.timeIntervalSince1970, title: block.title, task: block.linkedTaskID?.uuidString,
              kind: block.kind.rawValue)
    }

    private static func planBlock(_ block: Block) -> PlanBlock {
        PlanBlock(id: block.id.flatMap(UUID.init(uuidString:)) ?? UUID(), start: date(block.start), end: date(block.end),
                  title: block.title, linkedTaskID: block.task.flatMap(UUID.init(uuidString:)),
                  kind: PlanBlockKind(rawValue: block.kind)!)
    }

    private static func scheduled(_ scheduled: ScheduledBlock) -> Scheduled {
        let block = block(scheduled.block)
        return Scheduled(start: block.start, end: block.end, title: block.title, task: block.task, kind: block.kind,
                         workID: scheduled.workID, reason: scheduled.reason, part: scheduled.part, parts: scheduled.parts)
    }

    private static func refinementName(_ refinement: PlanRefinement) -> String {
        switch refinement {
        case .changed: "changed"
        case .unchanged: "unchanged"
        }
    }

    private static func schedulePrefs(_ prefs: SchedulePreferences) -> SchedulePrefs {
        SchedulePrefs(workdayStartMinute: prefs.workdayStartMinute, workdayEndMinute: prefs.workdayEndMinute,
                      defaultTaskMinutes: prefs.defaultTaskMinutes, maximumBlockMinutes: prefs.maximumBlockMinutes,
                      breakMinutes: prefs.breakMinutes, longBreakMinutes: prefs.longBreakMinutes,
                      longBreakEvery: prefs.longBreakEvery, maximumFocusMinutes: prefs.maximumFocusMinutes,
                      eventBufferMinutes: prefs.eventBufferMinutes, reviewsFirst: prefs.reviewsFirst)
    }

    private static func studyPrefs(_ prefs: StudyDayPreferences) -> StudyPrefs {
        StudyPrefs(studyMinutes: prefs.studyMinutes, breakMinutes: prefs.breakMinutes,
                   longBreakMinutes: prefs.longBreakMinutes, longBreakEvery: prefs.longBreakEvery,
                   reviewsFirst: prefs.reviewsFirst, eventBufferMinutes: prefs.eventBufferMinutes,
                   studyTitle: prefs.studyTitle)
    }
}
