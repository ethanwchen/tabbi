import Combine
import SwiftUI
import NotchKitCore
import NotchKit

/// The app's composition root, created once at launch: the settings, the
/// modules (each built from a `ModuleContext` and owning its own store),
/// the provider hub that merges what they share, and the closed-notch
/// ticker. Adding a module never touches this file; list it in `ModuleList`.
@MainActor
final class AppServices {
    /// Passed in (not created here) so the saved settings, e.g. the `claude`
    /// path override, are applied before any module store starts up.
    let settings: SettingsStore
    /// Every tab this build can show, created from `ModuleList`.
    let modules: ModuleRegistry
    /// What the enabled modules share (tasks, events, progress, focus).
    let providers: ProviderHub
    /// The rotating live preview beside the closed notch.
    let ticker: TickerStore

    private var cancellables: Set<AnyCancellable> = []
    /// Created on first use so launching never builds a window nobody opens.
    private var settingsWindow: SettingsWindowController?

    init(settings: SettingsStore, edition: Edition = .current,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         arguments: [String] = CommandLine.arguments) {
        self.settings = settings
        let providers = ProviderHub()
        let shared = SharedServices()
        let isDemo = environment["NOTCHDECK_DEMO"] == "1"
        let isSnapshot = arguments.contains("--snapshot")
        modules = ModuleRegistry(ModuleList.all.map { type in
            type.init(context: ModuleContext(id: type.descriptor.id, edition: edition, settings: settings,
                                             providers: providers, shared: shared,
                                             isDemo: isDemo, isSnapshot: isSnapshot))
        })
        providers.attach(modules)
        self.providers = providers
        ticker = TickerStore(settings: settings, providers: providers, preview: shared.closedNotchPreview)
        // `$settings` emits before the new value is stored, so read the
        // layout from the emission.
        settings.$settings
            .map(\.modules.enabled)
            .removeDuplicates()
            .sink { [modules, providers] enabled in
                modules.update(enabled: enabled)
                providers.update(enabled: enabled)
            }
            .store(in: &cancellables)
    }

    /// Shows the Settings window (from the notch's gear button or context menu).
    func openSettings() {
        let controller = settingsWindow ?? SettingsWindowController(settings: settings, modules: modules)
        settingsWindow = controller
        controller.present()
    }
}
