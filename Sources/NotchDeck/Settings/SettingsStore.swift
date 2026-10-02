import Foundation
import NotchDeckCore

/// The app's live preferences. Views and controllers observe `settings`;
/// every change is persisted immediately and applied to process-wide state
/// (such as the `claude` path override) so it takes effect without a relaunch.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            repository.save(settings)
            apply()
        }
    }

    /// Why the last launch-at-login change failed, for the Settings window.
    @Published private(set) var launchAtLoginError: String?

    /// False when another app already owns `settings.hotkey`; set by whoever
    /// registers the shortcut so the Settings window can explain it.
    @Published var hotkeyIsRegistered = true

    private let repository: SettingsRepository
    /// False for snapshot stores, which must never touch the real login item.
    let integratesWithSystem: Bool

    init(repository: SettingsRepository = SettingsRepository(), integratesWithSystem: Bool = true) {
        self.repository = repository
        self.integratesWithSystem = integratesWithSystem
        var settings = repository.load()
        if integratesWithSystem, LaunchAtLogin.isAvailable {
            // The user may have removed the login item in System Settings.
            settings.launchAtLogin = LaunchAtLogin.isEnabled
            repository.save(settings)
        }
        self.settings = settings
        apply()
    }

    /// A store backed by a throwaway defaults suite, so snapshots always render
    /// the default layout regardless of the user's saved preferences.
    static func ephemeral() -> SettingsStore {
        let suite = "NotchDeck.ephemeral"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(repository: SettingsRepository(defaults: defaults), integratesWithSystem: false)
    }

    /// Registers or removes the login item first and only records the
    /// preference once the system accepted it, so the toggle never lies.
    func setLaunchAtLogin(_ enabled: Bool) {
        guard integratesWithSystem else {
            settings.launchAtLogin = enabled
            return
        }
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        settings.launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func apply() {
        ClaudeCLI.userPathOverride = settings.claudePathOverride
    }
}
