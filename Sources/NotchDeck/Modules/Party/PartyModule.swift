import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Party: study with friends on the Tabbi friends server. The store
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

    /// The party I'm in, so the closed notch can show members' pets by mine.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.$state
            .map { ModuleProvision(party: $0.provided) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func start() {
        store.start()
    }

    func stop() {
        store.stop()
    }
}
