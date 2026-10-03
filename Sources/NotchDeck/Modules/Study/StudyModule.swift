import Combine
import SwiftUI
import NotchKitCore

/// Study: a study timer with research-backed methods. It runs the
/// `StudyStore` that `AppServices` owns, so a block keeps going while the
/// notch is closed.
@MainActor
final class StudyModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .study)
    private let store: StudyStore

    init(store: StudyStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(StudyPanel(store: store))
    }

    /// Today's study minutes against the kit's daily goal, so Today lists
    /// study time and Plan my day can schedule what is left, and the block
    /// under way as the shared focus timer, so the closed notch counts it
    /// down and a click there opens Study. The deep focus switch rides
    /// along, so the pet coach can nudge only during deep focus blocks.
    /// Today's tally (minutes, stretches, points) feeds Wrap Up.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.goalProgress
            .combineLatest(store.sharedFocus, store.$deepFocus.removeDuplicates(), store.dayTally)
            .map { ModuleProvision(progress: [$0], focus: $1, focusIsDeep: $2, study: $3) }
            .eraseToAnyPublisher()
    }

    func start() {
        store.setEnabled(true)
    }

    func stop() {
        store.setEnabled(false)
    }
}
