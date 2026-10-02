import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// Focus: the Pomodoro timer and focus mode (sound, playlist, Do Not
/// Disturb) as a tab of its own, for people who want a timer without
/// Today's checklist. It runs the same `FocusStore` that Today embeds, so
/// both tabs always agree.
@MainActor
final class FocusModule: NotchModule {
    let descriptor = ModuleCatalog.builtIn.descriptor(for: .focus)
    private let store: FocusStore

    init(store: FocusStore) {
        self.store = store
    }

    func makePanel() -> AnyView {
        AnyView(FocusPanel(store: store))
    }

    func makeSettingsPane() -> SettingsPane? { .focus }

    /// The focus timer, for the ticker and other modules.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.$timer
            .map { ModuleProvision(focus: $0) }
            .eraseToAnyPublisher()
    }
}
