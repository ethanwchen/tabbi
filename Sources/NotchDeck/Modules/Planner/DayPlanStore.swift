import Foundation
import NotchKitCore

/// Drives Plan My Day: gathers today's events and open tasks, asks the local
/// `claude` CLI for time blocks, validates them, and writes the ones the
/// user accepts to the calendar. The proposal replaces the checklist inline.
///
/// With `NOTCHDECK_DEMO=1` it shows `DayPlanner.sampleProposal` and never
/// runs the CLI or touches EventKit.
@MainActor
final class DayPlanStore: ObservableObject {
    enum Phase: Equatable {
        /// The checklist shows; nothing is being planned.
        case idle
        /// Waiting for Claude.
        case planning
        case proposal(DayPlanProposal)
        /// Claude found nothing worth planning (or the day is over).
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
            case .claudeNotFound: "Claude isn't installed"
            case .calendarOff: "Calendar access is off"
            case .calendarUnavailable: "Calendar isn't available"
            case .claudeFailed: "Couldn't plan your day"
            }
        }

        var detail: String {
            switch self {
            case .claudeNotFound: "Install the claude CLI, or set its path in Settings."
            case .calendarOff: "Allow \(Edition.current.name) in Privacy & Security to plan around meetings."
            case .calendarUnavailable: "Open the \(Edition.current.name) app to plan around your calendar."
            case .claudeFailed: "Claude didn't send back a usable plan. Try again in a moment."
            }
        }

        /// Asking Claude again only helps when Claude was the problem;
        /// calendar access is fixed in System Settings instead.
        var canRetry: Bool { self == .claudeFailed }
    }

    @Published private(set) var phase: Phase = .idle
    /// True when the last Add didn't reach the calendar; the proposal stays.
    @Published private(set) var writeFailed = false

    var isActive: Bool { phase != .idle }

    private let upNext: UpNextStore
    private let isDemo: Bool
    private var task: Task<Void, Never>?
    private var lastTasks: [PlannerItem] = []
    /// Bumped on every run and cancel so a superseded run can't publish.
    private var generation = 0

    /// Longest wait for Claude before showing the Retry message.
    private static let timeout: Duration = .seconds(60)

    init(upNext: UpNextStore) {
        self.upNext = upNext
        let environment = ProcessInfo.processInfo.environment
        isDemo = environment["NOTCHDECK_DEMO"] == "1"
        // Lets demo snapshots render each state: `NOTCHDECK_PLANNER_PREVIEW=plan`.
        // Demo only, so a preview proposal can never reach the real calendar.
        guard isDemo else { return }
        switch environment["NOTCHDECK_PLANNER_PREVIEW"] {
        case "plan": phase = .proposal(DayPlanProposal(blocks: DayPlanner.sampleProposal(now: Date())))
        case "planning": phase = .planning
        case "plan-failed": phase = .failed(.claudeFailed)
        case "plan-calendar-off": phase = .failed(.calendarOff)
        default: break
        }
    }

    /// Starts planning the rest of today around `tasks` (unfinished ones count).
    func plan(tasks: [PlannerItem]) {
        lastTasks = tasks
        invalidateRun()
        writeFailed = false
        phase = .planning
        let generation = generation

        if isDemo {
            task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.publish(generation, .proposal(DayPlanProposal(blocks: DayPlanner.sampleProposal(now: Date()))))
            }
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.run()
            self.publish(generation, outcome)
        }
    }

    func retry() { plan(tasks: lastTasks) }

    func openPrivacySettings() { upNext.openPrivacySettings() }

    /// Discards the proposal (or stops waiting) and shows the checklist again.
    func cancel() {
        invalidateRun()
        writeFailed = false
        phase = .idle
    }

    func dismiss(_ id: PlanBlock.ID) {
        guard case .proposal(var proposal) = phase else { return }
        proposal.dismiss(id)
        settle(proposal)
    }

    /// Adds one block, or every remaining block when `id` is nil.
    func add(_ id: PlanBlock.ID? = nil) {
        guard case .proposal(var proposal) = phase else { return }
        do {
            // Re-read the calendar: meetings may have arrived since Claude answered.
            try proposal.add(id.map { [$0] }, now: Date(), events: upNext.todayEvents(),
                             writer: upNext.makePlanWriter())
            writeFailed = false
            settle(proposal)
        } catch {
            writeFailed = true
        }
    }

    // MARK: - Private

    private func settle(_ proposal: DayPlanProposal) {
        phase = proposal.isSettled ? .idle : .proposal(proposal)
    }

    private func invalidateRun() {
        generation += 1
        task?.cancel()
        task = nil
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
        let context = DayPlanContext(now: Date(), events: upNext.todayEvents(), tasks: lastTasks)
        guard context.hasFreeTime else { return .noFreeTime }

        guard let executable = await Task.detached(priority: .userInitiated, operation: { ClaudeCLI.locate() }).value else {
            return .failed(.claudeNotFound)
        }
        guard let text = await Self.answer(executable: executable, prompt: DayPlanner.prompt(for: context)),
              let blocks = try? DayPlanner.proposal(from: text, context: context)
        else { return Task.isCancelled ? .idle : .failed(.claudeFailed) }
        return blocks.isEmpty ? .noFreeTime : .proposal(DayPlanProposal(blocks: blocks))
    }

    /// The final result text of one `claude -p` run, or nil on error or timeout.
    private static func answer(executable: URL, prompt: String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var text: String?
                do {
                    let events = ClaudeCLI.stream(executable: executable, prompt: prompt,
                                                  extraArguments: DayPlanner.extraArguments())
                    for try await event in events {
                        if case .result(let result) = event, !result.isError { text = result.text }
                    }
                } catch {
                    // A successful result followed by a non-zero exit still counts.
                }
                return text
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
