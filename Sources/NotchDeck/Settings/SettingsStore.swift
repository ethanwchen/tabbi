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

    private let repository: SettingsRepository

    init(repository: SettingsRepository = SettingsRepository()) {
        self.repository = repository
        settings = repository.load()
        apply()
    }

    /// A store backed by a throwaway defaults suite, so snapshots always render
    /// the default layout regardless of the user's saved preferences.
    static func ephemeral() -> SettingsStore {
        let suite = "NotchDeck.ephemeral"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(repository: SettingsRepository(defaults: defaults))
    }

    private func apply() {
        ClaudeCLI.userPathOverride = settings.claudePathOverride
    }
}
