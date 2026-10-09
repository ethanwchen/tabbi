import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

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
    /// First-run setup inside the notch, also re-run from Settings.
    let onboarding: OnboardingStore
    /// Celebrations of real events, played over the open panel.
    let celebrations: CelebrationCenter
    /// The optional Sign in with Apple account that syncs the pet.
    let accountSync: SyncStore

    private var cancellables: Set<AnyCancellable> = []
    /// Created on first use so launching never builds a window nobody opens.
    private var settingsWindow: SettingsWindowController?

    /// - Parameter moduleTypes: the modules to create, `ModuleList.all` in
    ///   the app; `settings` must resolve layouts against their catalog.
    ///   Types missing from `settings.catalog` (the edition leaves them out)
    ///   are never created, so they run no code at all.
    init(settings: SettingsStore, moduleTypes: [any NotchModule.Type] = ModuleList.all, edition: Edition = .current,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         arguments: [String] = CommandLine.arguments) {
        self.settings = settings
        let providers = ProviderHub()
        let shared = SharedServices()
        let runMode = RunMode(environment: environment, arguments: arguments)
        let available = moduleTypes.filter { settings.catalog.contains($0.descriptor.id) }
        modules = ModuleRegistry(available.map { type in
            type.init(context: ModuleContext(id: type.descriptor.id, edition: edition, settings: settings,
                                             providers: providers, shared: shared, runMode: runMode))
        })
        providers.attach(modules)
        self.providers = providers
        ticker = TickerStore(settings: settings, providers: providers, preview: shared.closedNotchPreview)
        onboarding = OnboardingStore(settings: settings)
        celebrations = shared.celebrations(settings: settings, runMode: runMode)
        accountSync = ModuleContext(id: "account", edition: edition, settings: settings, providers: providers,
                                    shared: shared, runMode: runMode).accountSync
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
        ConnectionsStore.shared.hubPresenter = { [weak self] in
            self?.openSettings(pane: AppSettingsPane.connections.rawValue)
        }
    }

    /// Shows the Settings window (from the notch's gear button or context
    /// menu), at `pane` when given.
    func openSettings(pane: String? = nil) {
        let controller = settingsWindow ?? SettingsWindowController(settings: settings, modules: modules,
                                                                    onboarding: onboarding, account: accountSync)
        settingsWindow = controller
        if let pane { controller.select(pane) }
        controller.present()
    }
}
