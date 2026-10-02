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
}
