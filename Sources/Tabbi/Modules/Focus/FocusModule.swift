import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// Focus: the Pomodoro timer and focus mode (sound, playlist, Do Not
/// Disturb) as a tab of its own, for people who want a timer without
/// Today's checklist. It runs the same `FocusStore` that Today embeds, so
/// both tabs always agree.
@MainActor
final class FocusModule: NotchModule {
    /// Off in every bundled kit: Today already embeds the same timer.
    nonisolated static let descriptor = ModuleDescriptor(
        id: .focus, title: "Focus", symbol: "hourglass",
        summary: "A Pomodoro timer that switches between focus and breaks.", category: .productivity,
        accent: ModuleAccent(red: 0.30, green: 0.84, blue: 0.76), permissions: [.notifications],
        kitSettings: FocusSettings.kitSettings
    )
    private let store: FocusStore
    /// Internal so app tests can drive focus mode.
    let focusMode: FocusController
    private let providers: ProviderHub
    /// Focus mode as it was before the last kit switch, for undo.
    private var settingsBeforeSwitch: FocusSettings?
    private var cancellables: Set<AnyCancellable> = []

    init(context: ModuleContext) {
        store = context.focusTimer
        focusMode = context.focusMode
        providers = context.providers
        // A kit's focus sounds and mode defaults, also while this tab is off,
        // since Today and Study run focus mode too.
        // Undo puts back the sound the user had before the switch.
        context.kitApplied
            .sink { [weak self, focusMode] application in
                switch application.kind {
                case .switched:
                    self?.settingsBeforeSwitch = focusMode.settings
                    focusMode.settings = focusMode.settings.applying(application.kit.defaults)
                case .reset:
                    focusMode.settings = focusMode.settings.applying(application.kit.defaults)
                case .undo:
                    focusMode.settings = self?.settingsBeforeSwitch ?? focusMode.settings.applying(application.kit.defaults)
                    self?.settingsBeforeSwitch = nil
                }
            }
            .store(in: &cancellables)
    }

    func makePanel() -> AnyView {
        AnyView(FocusPanel(store: store, focusMode: focusMode, providers: providers))
    }

    func makeSettingsPane() -> SettingsPane? { .focus(focusMode) }

    /// The focus sound and mode come from the kit (see `init`), so Reset to
    /// Kit Defaults has work to do once the user changes them.
    func usesKitDefaults(of kit: KitManifest) -> AnyPublisher<Bool, Never>? {
        focusMode.$settings
            .map { $0.usesDefaults(of: kit.defaults) }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// The focus timer, for the ticker and other modules.
    var provision: AnyPublisher<ModuleProvision, Never>? {
        let id = descriptor.id
        return store.$timer
            .map { ModuleProvision(focus: $0.provided(by: id)) }
            .eraseToAnyPublisher()
    }
}

extension ModuleContext {
    /// The one Pomodoro timer. Today embeds it, Focus shows it as a tab, and
    /// the pet coach pauses it, so all of them share this instance; it keeps
    /// running while the notch is closed or either tab is off. Its finished
    /// phases go to the activity log under the Focus module's id.
    var focusTimer: FocusStore {
        shared.resolve {
            FocusStore(activity: activityLog, focusMode: focusMode, celebrations: celebrations, runMode: runMode)
        }
    }

    /// Focus mode (sound, playlist, Do Not Disturb), which follows the
    /// Pomodoro and Study's deep focus blocks alike. One per app, since it
    /// owns the audio engine and the saved focus settings.
    var focusMode: FocusController { shared.resolve { FocusController(runMode: runMode) } }
}
