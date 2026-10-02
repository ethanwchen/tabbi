import SwiftUI
import NotchKitCore
import NotchKit

/// Party: study with friends on the StudyNotch friends server. The store
/// lives in `AppServices` so presence keeps flowing while the notch is
/// closed; it connects when the module is enabled and goes offline when
/// it's turned off.
@MainActor
final class PartyModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .party)
    private let store: PartyStore

    init(store: PartyStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(PartyPanel(store: store))
    }

    func makeSettingsPane() -> SettingsPane? {
        .party(store: store)
    }

    func start() {
        store.start()
    }

    func stop() {
        store.stop()
    }
}
