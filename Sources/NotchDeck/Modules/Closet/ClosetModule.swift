import SwiftUI
import NotchKitCore

/// Closet: preview the study pet, rename and recolor it, and dress it in
/// items unlocked with study points. The pet itself lives in `ClosetStore`,
/// which `AppServices` owns so the notch and the coach show the same pet.
@MainActor
final class ClosetModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .closet)
    private let store: ClosetStore

    init(store: ClosetStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(ClosetPanel(store: store))
    }
}
