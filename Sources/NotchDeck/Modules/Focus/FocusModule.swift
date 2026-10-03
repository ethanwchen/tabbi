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
    /// Off in every bundled kit: Today already embeds the same timer.
    nonisolated static let descriptor = ModuleDescriptor(
        id: .focus, title: "Focus", symbol: "hourglass", category: .productivity,
        accent: ModuleAccent(red: 0.30, green: 0.84, blue: 0.76), permissions: [.notifications]
    )
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
