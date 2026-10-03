import Combine
import SwiftUI
import NotchKitCore

/// Study: a study timer with research-backed methods. The module owns its
/// `StudyStore` for the app's lifetime, so a block keeps going while the
/// notch is closed.
@MainActor
final class StudyModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .study, title: "Study", symbol: "timer", category: .study,
        accent: ModuleAccent(red: 1.00, green: 0.62, blue: 0.26), ownsFocusClock: true
    )
    private let store: StudyStore
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        let kit = context.activeKit?.defaults
        store = StudyStore(menu: StudyMethodMenu(kit: kit), goal: StudyDailyGoal(kit: kit), storage: context.storage,
                           activity: context.activityLog)
        store.followCards(from: context.providers.$snapshot)
        context.kitApplied
            .sink { [store] application in
                let kit = application.kit.defaults
                store.use(StudyMethodMenu(kit: kit), goal: StudyDailyGoal(kit: kit), kitApplied: true)
            }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(StudyPanel(store: store))
    }

    /// Today's study minutes against the kit's daily goal, so Today lists
    /// study time and Plan my day can schedule what is left, and the block
    /// under way as the shared focus clock, so the closed notch counts it
    /// and a click there opens Study. The deep focus switch rides along, so
    /// the pet coach holds its idle nudges longer in deep focus blocks.
    /// Today's tally (minutes, stretches, points) feeds Wrap Up.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.goalProgress
            .combineLatest(store.sharedFocus(by: descriptor.id), store.dayTally)
            .map { ModuleProvision(progress: [$0], focus: $1, study: $2) }
            .eraseToAnyPublisher()
    }

    func start() {
        store.setEnabled(true)
    }

    func stop() {
        store.setEnabled(false)
    }
}
