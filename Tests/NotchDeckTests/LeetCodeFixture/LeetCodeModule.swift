import Combine
import SwiftUI
import NotchKitCore
import NotchKit
@testable import NotchDeck

// The acceptance-test vertical: a minimal "LeetCode daily" module written the
// way a new module is added to the app (see "Adding a module" in AGENTS.md).
// Everything it needs lives in this folder; `LeetCodeAcceptanceTests` adds
// its one line to the module list and checks that Today, Plan my day, the
// ticker, Settings, kits and the tab bar all pick it up with no shared code.

/// Today's problem, as the module's store keeps it.
struct LeetCodeDaily: Equatable {
    var title: String
    var difficulty: String
    var estimatedMinutes: Int
    var isSolved: Bool
    var streak: Int

    /// Sample data for demo mode and tests; a real module would fetch this.
    static let sample = LeetCodeDaily(title: "Two Sum", difficulty: "Easy", estimatedMinutes: 20,
                                      isSolved: false, streak: 6)
}

/// Owns the daily problem and turns it into what the module shares.
@MainActor
final class LeetCodeStore: ObservableObject {
    @Published var daily: LeetCodeDaily
    private(set) var isRunning = false
    private let activity: ActivityLog?

    init(daily: LeetCodeDaily = .sample, activity: ActivityLog? = nil) {
        self.daily = daily
        self.activity = activity
    }

    func start() { isRunning = true }
    func stop() { isRunning = false }

    /// Reads the module's section of a kit's `moduleSettings`, such as
    /// `{"minutesPerProblem": 45}`. Like every module it reads leniently:
    /// a value outside the schema's range keeps the current estimate.
    func use(kitSettings section: KitValue?) {
        guard let minutes = section?["minutesPerProblem"]?.numberValue,
              LeetCodeModule.minutesPerProblem.contains(minutes) else { return }
        daily.estimatedMinutes = Int(minutes)
    }

    /// Marks today's problem solved and logs it in the shared activity log
    /// under a kind of the module's own.
    func markSolved() {
        daily.isSolved = true
        daily.streak += 1
        activity?.record(ActivityRecord(source: LeetCodeModule.descriptor.id, kind: "problem.solved", start: Date(),
                                        quantity: 1, subject: daily.title))
    }

    /// A task for Today and Plan my day, a progress goal, and a ticker line
    /// while the problem is unsolved.
    func provision(source: ModuleID) -> AnyPublisher<ModuleProvision, Never> {
        $daily
            .map { daily in
                ModuleProvision(
                    tasks: [ProvidedTask(id: "daily", source: source, title: "LeetCode: \(daily.title)",
                                         isDone: daily.isSolved, estimatedMinutes: daily.estimatedMinutes)],
                    progress: [ProgressItem(id: "daily", source: source, title: "LeetCode daily",
                                            completed: daily.isSolved ? 1 : 0, target: 1, unit: "problem")],
                    highlights: daily.isSolved ? [] : [
                        TickerHighlight(id: "daily", source: source, text: "1 problem left",
                                        summary: "Today's LeetCode: \(daily.title) (\(daily.difficulty))",
                                        priority: 10),
                    ]
                )
            }
            .eraseToAnyPublisher()
    }
}

/// The module itself: descriptor, store, panel and provision.
@MainActor
final class LeetCodeModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "leetcode", title: "LeetCode", symbol: "chevron.left.forwardslash.chevron.right",
        category: .productivity, accent: ModuleAccent(red: 1.00, green: 0.63, blue: 0.16),
        highlightTitle: "LeetCode daily",
        kitSettings: KitSettingsSchema(["minutesPerProblem": .number(minutesPerProblem)])
    )
    /// The estimate a kit may set for one problem.
    nonisolated static let minutesPerProblem: ClosedRange<Double> = 5...180
    let store: LeetCodeStore
    /// The shared activity log, which the store writes to.
    let activityLog: ActivityLog
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        activityLog = context.activityLog
        store = LeetCodeStore(activity: activityLog)
        store.use(kitSettings: context.activeKit?.defaults.settings(for: context.id))
        context.kitApplied
            .sink { [store, id = context.id] in store.use(kitSettings: $0.kit.defaults.settings(for: id)) }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView { AnyView(LeetCodePanel(store: store)) }
    func start() { store.start() }
    func stop() { store.stop() }

    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.provision(source: descriptor.id)
    }
}

/// Today's problem on a card, with its streak.
private struct LeetCodePanel: View {
    @ObservedObject var store: LeetCodeStore

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(store.daily.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("\(store.daily.difficulty), \(store.daily.streak) day streak")
                    .font(Theme.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
