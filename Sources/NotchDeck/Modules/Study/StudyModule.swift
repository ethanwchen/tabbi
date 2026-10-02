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
    /// study time and Plan my day can schedule what is left.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.goalProgress
            .map { ModuleProvision(progress: [$0]) }
            .eraseToAnyPublisher()
    }

    func start() {
        store.setEnabled(true)
    }

    func stop() {
        store.setEnabled(false)
    }
}
