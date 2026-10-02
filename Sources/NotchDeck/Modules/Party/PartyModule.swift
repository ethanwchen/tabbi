import SwiftUI
import NotchKitCore

/// Party: study with friends (preview panel until the feature lands).
@MainActor
final class PartyModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .party)

    func makePanel() -> AnyView {
        AnyView(PartyPanel())
    }
}
