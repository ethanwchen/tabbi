import Combine
import SwiftUI
import NotchKitCore

/// Anki: due cards, streak and review history via AnkiConnect.
@MainActor
final class AnkiModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .anki)
    let store = AnkiStore()

    func makePanel() -> AnyView {
        AnyView(AnkiPanel(store: store))
    }

    func start() { store.start() }
    func stop() { store.stop() }

    /// Today's reviews as a progress goal for Today and the ticker.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.provision(source: descriptor.id)
    }
}
