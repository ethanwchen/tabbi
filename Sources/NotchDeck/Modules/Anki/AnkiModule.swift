import Combine
import SwiftUI
import NotchKitCore

/// Anki: due cards, streak and review history via AnkiConnect.
@MainActor
final class AnkiModule: NotchModule {
    /// AnkiConnect is a localhost HTTP add-on, so no macOS permission is involved.
    nonisolated static let descriptor = ModuleDescriptor(
        id: .anki, title: "Anki", symbol: "rectangle.stack.fill", category: .study,
        accent: ModuleAccent(red: 0.36, green: 0.62, blue: 1.00)
    )
    let store = AnkiStore()

    init(context: ModuleContext) {}

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
