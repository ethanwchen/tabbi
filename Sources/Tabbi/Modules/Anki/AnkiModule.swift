import Combine
import SwiftUI
import TabbiKitCore

/// Anki: due cards, streak and review history via AnkiConnect.
@MainActor
final class AnkiModule: NotchModule {
    /// AnkiConnect is a localhost HTTP add-on, so no macOS permission is involved.
    nonisolated static let descriptor = ModuleDescriptor(
        id: .anki, title: "Anki", symbol: "rectangle.stack.fill", category: .study,
        accent: ModuleAccent(red: 0.36, green: 0.62, blue: 1.00),
        network: [ModuleNetworkAccess(host: URLSessionAnkiConnectTransport.defaultEndpoint.host() ?? "",
                                      purpose: "your decks through AnkiConnect")],
        setup: [.anki]
    )
    let store: AnkiStore

    init(context: ModuleContext) {
        store = AnkiStore(activity: context.activityLog, runMode: context.runMode)
    }

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
