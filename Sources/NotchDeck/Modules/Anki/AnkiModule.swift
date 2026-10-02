import SwiftUI
import NotchKitCore

/// Anki: due cards via AnkiConnect (preview panel until the feature lands).
@MainActor
final class AnkiModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .anki)

    func makePanel() -> AnyView {
        AnyView(AnkiPanel())
    }
}
