import Combine
import SwiftUI
import NotchKitCore

/// Anki: due cards via AnkiConnect (preview panel until the feature lands).
@MainActor
final class AnkiModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .anki)

    func makePanel() -> AnyView {
        AnyView(AnkiPanel())
    }

    /// Today's reviews as a progress goal for Today. Only the demo sample for
    /// now; the live AnkiConnect summary replaces it when the deck view lands.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        guard ProcessInfo.processInfo.environment["NOTCHDECK_DEMO"] == "1" else { return nil }
        return Just(ModuleProvision(progress: [AnkiSummary.demo().progressItem(source: descriptor.id)]))
            .eraseToAnyPublisher()
    }
}
