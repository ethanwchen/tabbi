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
    private let providers: ProviderHub
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        store = context.focusTimer
        providers = context.providers
        // A kit's focus sounds and mode defaults, also while this tab is off,
        // since Today and Study run focus mode too.
        context.kitApplied
            .sink { application in
                let focus = FocusController.shared
                focus.settings = focus.settings.applying(application.kit.defaults)
            }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(FocusPanel(store: store, providers: providers))
    }

    func makeSettingsPane() -> SettingsPane? { .focus }

    /// The focus timer, for the ticker and other modules.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        store.$timer
            .map { ModuleProvision(focus: $0) }
            .eraseToAnyPublisher()
    }
}

extension ModuleContext {
    /// The one Pomodoro timer. Today embeds it, Focus shows it as a tab, and
    /// the pet coach pauses it, so all of them share this instance; it keeps
    /// running while the notch is closed or either tab is off.
    var focusTimer: FocusStore { shared.resolve { FocusStore() } }
}
