import Foundation
import TabbiKitCore

/// Drives Plan My Day: gathers today's events, open tasks and review goals,
/// plans them on device with `SchedulePlanner` (or, when the kit's
/// `TodayPlanSettings` say so, asks the local `claude` CLI, or plans study
/// blocks with `StudyDayPlanner`), and writes the blocks the user accepts
/// to the calendar.
/// The proposal replaces the checklist inline.
///
/// With `TABBI_DEMO=1` it plans around `UpcomingEvent.samples(now:)` and
/// never runs the CLI or touches EventKit.
@MainActor
final class DayPlanStore: ObservableObject {
    enum Phase: Equatable {
        /// The checklist shows; nothing is being planned.
        case idle
        /// Working out the plan (only noticeable while waiting for Claude).
        case planning
        case proposal(DayPlanProposal)
        /// Nothing fits in today's free time (or the day is over).
        case noFreeTime
        case failed(Failure)
    }

    /// Why planning stopped, phrased for the panel.
    enum Failure: Equatable {
        case claudeNotFound
        case calendarOff
        /// This build can't ask for calendar access (an unbundled `swift run`).
        case calendarUnavailable
        case claudeFailed

        var title: String {
            switch self {
            case .claudeNotFound: "Claude isn't set up yet"
            case .calendarOff: "Calendar access is off"
            case .calendarUnavailable: "Connect your calendar"
            case .claudeFailed: "Couldn't plan your day"
            }
        }

        var detail: String {
            switch self {
            case .claudeNotFound: "Plan my day needs Claude, an AI helper, on this Mac."
            case .calendarOff: "Allow \(Edition.current.name) in Privacy & Security to plan around meetings."
            case .calendarUnavailable: "Plan my day fits your plan around your calendar."
            case .claudeFailed: "Claude didn't send back a usable plan. Try again in a moment."
            }
        }

        /// Asking Claude again only helps when Claude was the problem;
        /// calendar access is fixed in System Settings instead.
        var canRetry: Bool { self == .claudeFailed }

        /// The missing app or calendar is set up in Connections, which
        /// walks through every step.
        var opensConnections: Bool { self == .claudeNotFound || self == .calendarUnavailable }
    }

    @Published private(set) var phase: Phase = .idle
    /// True when the last Add didn't reach the calendar; the proposal stays.
    @Published private(set) var writeFailed = false
    /// True when the on-device plan can get a second look from Claude
    /// ("Refine with Claude"): the plan is local and the CLI is installed.
    @Published private(set) var canRefine = false
    /// Waiting for Claude's refinement; the local plan stays on screen.
    @Published private(set) var isRefining = false
    /// Claude's refinement didn't come back usable; the local plan stays.
    @Published private(set) var refineFailed = false

    var isActive: Bool { phase != .idle }
    /// The day being planned: today, or tomorrow when planning ahead.
    @Published private(set) var target: PlannerViewedDay = .today

    private let upNext: UpNextStore
    private let isDemo: Bool
    /// False in a build that can't run the `claude` CLI: Refine never shows.
    private let usesClaude: Bool
    private var task: Task<Void, Never>?
    private var lastTasks: [PlannerItem] = []
    private var lastSharedWork: [String] = []
    private var lastSharedTasks: [ProvidedTask] = []
    private var lastProgress: [ProgressItem] = []
    /// The active kit's planning settings; `PlannerStore` keeps them current.
    var settings: TodayPlanSettings
    /// Bumped on every run and cancel so a superseded run can't publish.
    private var generation = 0

    /// Longest wait for Claude before showing the Retry message.
    private static let timeout: Duration = .seconds(60)

    init(upNext: UpNextStore, settings: TodayPlanSettings, usesClaude: Bool = true, runMode: RunMode) {
        self.upNext = upNext
        self.settings = settings
        self.usesClaude = usesClaude
        let environment = ProcessInfo.processInfo.environment
        isDemo = runMode.isDemo
        // Lets demo snapshots render each state: `TABBI_PLANNER_PREVIEW=plan`.
        // Demo only, so a preview proposal can never reach the real calendar.
        guard isDemo else { return }
        canRefine = usesClaude && settings.planMode == .local
        switch environment["TABBI_PLANNER_PREVIEW"] {
        case "plan", "plan-refining":
            phase = .proposal(sampleProposal(
                tasks: PlannerDay.sample(on: PlannerDayKey(date: Date()), kind: settings.sampleDay).items,
                sharedTasks: [], progress: [AnkiSummary.demo().progressItem()]))
            isRefining = canRefine && environment["TABBI_PLANNER_PREVIEW"] == "plan-refining"
        case "planning": phase = .planning
        case "plan-failed": phase = .failed(.claudeFailed)
        case "plan-calendar-off": phase = .failed(.calendarOff)
        default: break
        }
    }

    /// Starts planning the rest of today (or all of tomorrow, from the start
    /// of the working day) around `tasks` (unfinished ones count) and what
    /// other modules share: `sharedWork` phrased for Claude
    /// (`ProviderSnapshot.plannableWork`), `sharedTasks` with their estimates
    /// for the local planner, and `progress` as goals that become review blocks.
    func plan(_ day: PlannerViewedDay = .today, tasks: [PlannerItem], sharedWork: [String] = [],
              sharedTasks: [ProvidedTask] = [], progress: [ProgressItem] = []) {
        guard day.planStart(now: Date()) != nil else { return }
        target = day
        lastTasks = tasks
        lastSharedWork = sharedWork
        lastSharedTasks = sharedTasks
        lastProgress = progress
        invalidateRun()
        writeFailed = false
        phase = .planning
        let generation = generation
        if !isDemo { checkRefineAvailable() }

        if isDemo {
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                guard let self else { return }
                let proposal = self.sampleProposal(tasks: tasks, sharedTasks: sharedTasks, progress: progress)
                self.publish(generation, proposal.isSettled ? .noFreeTime : .proposal(proposal))
            }
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.run()
            self.publish(generation, outcome)
        }
    }

    /// Demo only: shows the sample proposal for `day` at once, so a
    /// snapshot can render a plan without waiting for the demo's delay.
    func showSampleProposal(_ day: PlannerViewedDay, tasks: [PlannerItem]) {
        guard isDemo, day.planStart(now: Date()) != nil else { return }
        invalidateRun()
        target = day
        lastTasks = tasks
        phase = .proposal(sampleProposal(tasks: tasks, sharedTasks: [], progress: []))
    }

    func retry() {
        plan(target, tasks: lastTasks, sharedWork: lastSharedWork, sharedTasks: lastSharedTasks,
             progress: lastProgress)
    }

    func openPrivacySettings() { upNext.openPrivacySettings() }

    /// Asks Claude for suggestions on the local plan's blocks still on offer.
    /// Optional by design: whatever happens, the local plan stays usable,
    /// and Claude's answer is validated like any plan before it replaces it.
    func refine() {
        guard canRefine, !isRefining, case .proposal(let proposal) = phase, proposal.refinement == nil else { return }
        invalidateRun()
        isRefining = true
        refineFailed = false
        let generation = generation
        let blocks = proposal.pending

        task = Task { [weak self] in
            guard let self else { return }
            let refined: [PlanBlock]?
            if self.isDemo {
                // Demo mode never runs the CLI: Claude agrees with the sample plan.
                try? await Task.sleep(for: .seconds(1.2))
                refined = blocks
            } else {
                refined = await self.refinedBlocks(blocks)
            }
            guard generation == self.generation, case .proposal(var current) = self.phase else { return }
            self.isRefining = false
            if let refined, !refined.isEmpty {
                current.refine(with: refined)
                self.phase = .proposal(current)
            } else if !Task.isCancelled {
                self.refineFailed = true
            }
        }
    }

    /// Discards the proposal (or stops waiting) and shows the checklist again.
    func cancel() {
        invalidateRun()
        writeFailed = false
        phase = .idle
    }

    func dismiss(_ id: PlanBlock.ID) {
        guard !isRefining, case .proposal(var proposal) = phase else { return }
        proposal.dismiss(id)
        settle(proposal)
    }

    /// Adds one block, or every remaining block when `id` is nil.
    func add(_ id: PlanBlock.ID? = nil) {
        guard !isRefining, case .proposal(var proposal) = phase else { return }
        do {
            // Re-read the calendar: meetings may have arrived since the plan was made.
            try proposal.add(id.map { [$0] }, now: Date(), events: upNext.planEvents(on: target),
                             writer: upNext.makePlanWriter())
            writeFailed = false
            settle(proposal)
        } catch {
            writeFailed = true
        }
    }

    // MARK: - Private

    /// Demo mode's proposal over the demo calendar: the kit's on-device
    /// planner, or Claude's canned sample.
    private func sampleProposal(tasks: [PlannerItem], sharedTasks: [ProvidedTask],
                                progress: [ProgressItem]) -> DayPlanProposal {
        let now = Date()
        if target != .today, let context = context(tasks: tasks, sharedWork: [], now: now) {
            // Tomorrow's samples sit at fixed hours, so it plans as it is.
            return settings.planMode == .study
                ? DayPlanProposal(settings.studyPlan(context: context, progress: progress))
                : settings.localPlan(now: context.now, events: context.events, tasks: tasks,
                                     sharedTasks: sharedTasks, progress: progress).proposal
        }
        switch settings.planMode {
        case .local:
            return settings.sampleLocalPlan(now: now, events: upNext.todayEvents(), tasks: tasks,
                                            sharedTasks: sharedTasks, progress: progress).proposal
        case .claude:
            return DayPlanProposal(blocks: DayPlanner.sampleProposal(now: now))
        case .study:
            let context = DayPlanContext(now: now, events: upNext.todayEvents(), tasks: tasks,
                                         dayEndHour: settings.dayEndHour)
            return DayPlanProposal(settings.studyPlan(context: context, progress: progress))
        }
    }

    private func settle(_ proposal: DayPlanProposal) {
        phase = proposal.isSettled ? .idle : .proposal(proposal)
    }

    private func invalidateRun() {
        generation += 1
        task?.cancel()
        task = nil
        isRefining = false
        refineFailed = false
    }

    /// Looks for the `claude` CLI off the main thread while a local plan is
    /// worked out, so "Refine with Claude" only shows when it can work.
    private func checkRefineAvailable() {
        guard usesClaude, settings.planMode == .local else {
            canRefine = false
            return
        }
        Task { [weak self] in
            let found = await Task.detached(priority: .utility, operation: { ClaudeCLI.locate() }).value != nil
            self?.canRefine = found
        }
    }

    /// Claude's refinement of `blocks` on today's calendar as it is now, or
    /// nil when Claude is missing or its answer isn't usable.
    private func refinedBlocks(_ blocks: [PlanBlock]) async -> [PlanBlock]? {
        guard let context = context(tasks: lastTasks, sharedWork: lastSharedWork, now: Date()),
              let executable = await Task.detached(priority: .userInitiated, operation: { ClaudeCLI.locate() }).value,
              let text = await DayPlanner.answer(executable: executable,
                                                prompt: DayPlanner.refinePrompt(for: context, plan: blocks),
                                                timeout: Self.timeout)
        else { return nil }
        return try? DayPlanner.refinement(from: text, context: context, plan: blocks)
    }

    /// What planning `target` knows at `now`: its calendar, and where
    /// planning starts (now today, the working day's start tomorrow).
    private func context(tasks: [PlannerItem], sharedWork: [String], now: Date) -> DayPlanContext? {
        guard let start = target.planStart(now: now) else { return nil }
        return DayPlanContext(now: start, events: upNext.planEvents(on: target), tasks: tasks,
                              sharedWork: sharedWork, dayEndHour: settings.dayEndHour,
                              isPlanningAhead: target == .tomorrow)
    }

    private func publish(_ generation: Int, _ phase: Phase) {
        guard generation == self.generation else { return }
        self.phase = phase
    }

    private func run() async -> Phase {
        switch await upNext.ensureAccess() {
        case .granted: break
        case .denied, .notDetermined: return .failed(.calendarOff)
        // `swift run` builds can't ask, so blocks couldn't be written either.
        // Dry runs plan without meetings, which is enough to try the flow.
        case .unavailable: guard upNext.isPlanDryRun else { return .failed(.calendarUnavailable) }
        }
        guard let context = context(tasks: lastTasks, sharedWork: lastSharedWork, now: Date()),
              context.hasFreeTime else { return .noFreeTime }

        switch settings.planMode {
        case .local:
            let proposal = settings.localPlan(now: context.now, events: context.events, tasks: lastTasks,
                                              sharedTasks: lastSharedTasks, progress: lastProgress).proposal
            return proposal.isSettled ? .noFreeTime : .proposal(proposal)
        case .study:
            let proposal = DayPlanProposal(settings.studyPlan(context: context, progress: lastProgress))
            return proposal.isSettled ? .noFreeTime : .proposal(proposal)
        case .claude:
            break
        }

        guard usesClaude, let executable = await Task.detached(priority: .userInitiated, operation: { ClaudeCLI.locate() }).value else {
            return .failed(.claudeNotFound)
        }
        guard let text = await DayPlanner.answer(executable: executable, prompt: DayPlanner.prompt(for: context),
                                                   timeout: Self.timeout),
              let blocks = try? DayPlanner.proposal(from: text, context: context)
        else { return Task.isCancelled ? .idle : .failed(.claudeFailed) }
        return blocks.isEmpty ? .noFreeTime : .proposal(DayPlanProposal(blocks: blocks))
    }
}
