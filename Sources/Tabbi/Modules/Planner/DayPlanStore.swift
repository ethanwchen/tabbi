import Foundation
import TabbiKitCore

/// Drives Plan My Day: gathers today's events, open tasks and review goals,
/// plans them on device with `SchedulePlanner` (or, when the kit's
/// `TodayPlanSettings` say so, asks the AI the user picked, or plans study
/// blocks with `StudyDayPlanner`), and writes the blocks the user accepts
/// to the calendar.
/// The proposal replaces the checklist inline.
///
/// With `TABBI_DEMO=1` it plans around `UpcomingEvent.samples(now:)` and
/// never asks an AI or touches EventKit.
@MainActor
final class DayPlanStore: ObservableObject {
    enum Phase: Equatable {
        /// The checklist shows; nothing is being planned.
        case idle
        /// Working out the plan (only noticeable while waiting for the AI).
        case planning
        case proposal(DayPlanProposal)
        /// Nothing fits in today's free time (or the day is over).
        case noFreeTime
        case failed(Failure)
    }

    /// Why planning stopped, phrased for the panel.
    enum Failure: Equatable {
        /// No AI can answer yet: none is picked (nil), or the picked one
        /// still needs its key or its command line tool.
        case aiNotSetUp(AIProviderID?)
        case calendarOff
        /// This build can't ask for calendar access (an unbundled `swift run`).
        case calendarUnavailable
        /// The AI, named here ("Gemini"), answered with no usable plan.
        case aiFailed(assistant: String)

        var title: String {
            switch self {
            case .aiNotSetUp(nil): "Choose an AI to plan with"
            case .aiNotSetUp(let id?): "\(id.displayName) isn't set up yet"
            case .calendarOff: "Calendar access is off"
            case .calendarUnavailable: "Connect your calendar"
            case .aiFailed: "Couldn't plan your day"
            }
        }

        var detail: String {
            switch self {
            case .aiNotSetUp(nil): "Plan my day asks the AI you pick in Settings."
            case .aiNotSetUp(let id?):
                id.requiresAPIKey ? "Add your \(id.displayName) key in Settings." : "Install \(id.displayName) to plan with it."
            case .calendarOff: "Allow \(Edition.current.name) in Privacy & Security to plan around meetings."
            case .calendarUnavailable: "Plan my day fits your plan around your calendar."
            case .aiFailed(let assistant): "\(assistant) didn't send back a usable plan. Try again in a moment."
            }
        }

        /// Asking again only helps when the AI was the problem; calendar
        /// access is fixed in System Settings instead.
        var canRetry: Bool {
            if case .aiFailed = self { return true }
            return false
        }

        /// The AI or the calendar is set up in Connections, which walks
        /// through every step.
        var opensConnections: Bool {
            switch self {
            case .aiNotSetUp, .calendarUnavailable: true
            case .calendarOff, .aiFailed: false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    /// True when the last Add didn't reach the calendar; the proposal stays.
    @Published private(set) var writeFailed = false
    /// True when the on-device plan can get a second look from the AI
    /// ("Refine"): the plan is local and the picked AI can answer.
    @Published private(set) var canRefine = false
    /// Waiting for the AI's refinement; the local plan stays on screen.
    @Published private(set) var isRefining = false
    /// The AI's refinement didn't come back usable; the local plan stays.
    @Published private(set) var refineFailed = false

    var isActive: Bool { phase != .idle }
    /// The picked AI's name for the panel's copy ("Refine with Gemini").
    var assistantName: String { ai?.assistantName ?? "AI" }

    private let upNext: UpNextStore
    private let isDemo: Bool
    /// The AI the user picked, which plans in `claude` plan mode and
    /// refines a local plan. Nil turns both off (tests).
    private let ai: AIService?
    private var task: Task<Void, Never>?
    private var lastTasks: [PlannerItem] = []
    private var lastSharedWork: [String] = []
    private var lastSharedTasks: [ProvidedTask] = []
    private var lastProgress: [ProgressItem] = []
    /// The active kit's planning settings; `PlannerStore` keeps them current.
    var settings: TodayPlanSettings
    /// Bumped on every run and cancel so a superseded run can't publish.
    private var generation = 0

    /// Longest wait for the AI before showing the Retry message.
    private static let timeout: Duration = .seconds(60)

    init(upNext: UpNextStore, settings: TodayPlanSettings, ai: AIService? = nil, runMode: RunMode) {
        self.upNext = upNext
        self.settings = settings
        self.ai = ai
        let environment = ProcessInfo.processInfo.environment
        isDemo = runMode.isDemo
        // Lets demo snapshots render each state: `TABBI_PLANNER_PREVIEW=plan`.
        // Demo only, so a preview proposal can never reach the real calendar.
        guard isDemo else { return }
        canRefine = ai != nil && settings.planMode == .local
        switch environment["TABBI_PLANNER_PREVIEW"] {
        case "plan", "plan-refining":
            phase = .proposal(sampleProposal(
                tasks: PlannerDay.sample(on: PlannerDayKey(date: Date()), kind: settings.sampleDay).items,
                sharedTasks: [], progress: [AnkiSummary.demo().progressItem()]))
            isRefining = canRefine && environment["TABBI_PLANNER_PREVIEW"] == "plan-refining"
        case "planning": phase = .planning
        case "plan-failed": phase = .failed(.aiFailed(assistant: assistantName))
        case "plan-calendar-off": phase = .failed(.calendarOff)
        default: break
        }
    }

    /// Starts planning the rest of today around `tasks` (unfinished ones
    /// count) and what other modules share: `sharedWork` phrased for the AI
    /// (`ProviderSnapshot.plannableWork`), `sharedTasks` with their estimates
    /// for the local planner, and `progress` as goals that become review blocks.
    func plan(tasks: [PlannerItem], sharedWork: [String] = [], sharedTasks: [ProvidedTask] = [],
              progress: [ProgressItem] = []) {
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

    func retry() {
        plan(tasks: lastTasks, sharedWork: lastSharedWork, sharedTasks: lastSharedTasks, progress: lastProgress)
    }

    func openPrivacySettings() { upNext.openPrivacySettings() }

    /// Asks the AI for suggestions on the local plan's blocks still on offer.
    /// Optional by design: whatever happens, the local plan stays usable,
    /// and the answer is validated like any plan before it replaces it.
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
                // Demo mode never asks an AI: it agrees with the sample plan.
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
            try proposal.add(id.map { [$0] }, now: Date(), events: upNext.todayEvents(),
                             writer: upNext.makePlanWriter())
            writeFailed = false
            settle(proposal)
        } catch {
            writeFailed = true
        }
    }

    // MARK: - Private

    /// Demo mode's proposal over the demo calendar: the kit's on-device
    /// planner, or the AI's canned sample.
    private func sampleProposal(tasks: [PlannerItem], sharedTasks: [ProvidedTask],
                                progress: [ProgressItem]) -> DayPlanProposal {
        let now = Date()
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

    /// Checks off the main thread whether the picked AI can answer while a
    /// local plan is worked out, so "Refine" only shows when it can work.
    private func checkRefineAvailable() {
        guard let ai, settings.planMode == .local else {
            canRefine = false
            return
        }
        Task { [weak self] in
            let ready = await ai.readyProvider() != nil
            self?.canRefine = ready
        }
    }

    /// The AI's refinement of `blocks` on today's calendar as it is now, or
    /// nil when it can't answer or its answer isn't usable.
    private func refinedBlocks(_ blocks: [PlanBlock]) async -> [PlanBlock]? {
        let context = DayPlanContext(now: Date(), events: upNext.todayEvents(), tasks: lastTasks,
                                     sharedWork: lastSharedWork, dayEndHour: settings.dayEndHour)
        guard let provider = await ai?.readyProvider()?.provider,
              let text = await DayPlanner.answer(from: provider,
                                                prompt: DayPlanner.refinePrompt(for: context, plan: blocks),
                                                timeout: Self.timeout)
        else { return nil }
        return try? DayPlanner.refinement(from: text, context: context, plan: blocks)
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
        let context = DayPlanContext(now: Date(), events: upNext.todayEvents(), tasks: lastTasks,
                                     sharedWork: lastSharedWork, dayEndHour: settings.dayEndHour)
        guard context.hasFreeTime else { return .noFreeTime }

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

        guard let ai else { return .failed(.aiNotSetUp(nil)) }
        guard let provider = await ai.readyProvider()?.provider else {
            return .failed(.aiNotSetUp(ai.setupState.provider))
        }
        guard let text = await DayPlanner.answer(from: provider, prompt: DayPlanner.prompt(for: context),
                                                   timeout: Self.timeout),
              let blocks = try? DayPlanner.proposal(from: text, context: context)
        else { return Task.isCancelled ? .idle : .failed(.aiFailed(assistant: assistantName)) }
        return blocks.isEmpty ? .noFreeTime : .proposal(DayPlanProposal(blocks: blocks))
    }
}
