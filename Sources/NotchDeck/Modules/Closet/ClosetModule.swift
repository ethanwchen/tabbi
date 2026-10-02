import SwiftUI
import NotchKitCore

/// Closet: the study pet and its costumes (preview panel until the feature lands).
@MainActor
final class ClosetModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .closet)

    func makePanel() -> AnyView {
        AnyView(ClosetPanel())
    }
}
