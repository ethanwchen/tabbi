import Foundation
import NotchKitCore

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

    /// True while the Settings window records a new shortcut. The global
    /// hotkey is suspended meanwhile, so pressing the current shortcut is
    /// recorded instead of toggling the notch.
    @Published var isRecordingHotkey = false

    /// The `claude` path override currently in effect. Publishes only after
    /// `ClaudeCLI.userPathOverride` is updated, so subscribers that re-locate
    /// the binary in response always see the new value.
    @Published private(set) var appliedClaudePathOverride: String?

    /// The kits Settings offers: bundled ones, then the user's imports.
    @Published private(set) var kits: KitLibrary

    private let repository: SettingsRepository
    /// Where imported kits live; nil for snapshot stores, which only show
    /// the bundled kits.
    private let kitStore: ImportedKitStore?
    /// The edition's kit, used again when the active imported kit is removed.
    private let defaultKitID: String
    /// False for snapshot stores, which must never touch the real login item.
    let integratesWithSystem: Bool

    /// - Parameter defaultKitID: the kit used before the user picks one,
    ///   e.g. a branded edition's kit.
    init(
        defaults: UserDefaults = .standard,
        defaultKitID: String = KitLibrary.defaultKitID,
        kitStore: ImportedKitStore? = .standard,
        integratesWithSystem: Bool = true
    ) {
        let kits = KitLibrary.installed(imported: kitStore?.load() ?? [])
        let repository = SettingsRepository(defaults: defaults, kits: kits, defaultKitID: defaultKitID)
        self.kits = kits
        self.kitStore = kitStore
        self.defaultKitID = defaultKitID
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
    /// the kit's default layout regardless of the user's saved preferences.
    static func ephemeral(kitID: String = KitLibrary.defaultKitID) -> SettingsStore {
        let suite = "NotchDeck.ephemeral"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults, defaultKitID: kitID, kitStore: nil, integratesWithSystem: false)
    }

    // MARK: Kits

    /// The kit the user picked (the default kit if it has gone missing).
    var activeKit: KitManifest? { kits.kit(settings.kitID) }

    /// True when the tabs already match the active kit, so reset is a no-op.
    var usesKitDefaults: Bool {
        activeKit.map { settings.usesDefaults(of: $0) } ?? true
    }

    /// Switches to another kit, replacing the tab layout with its defaults.
    func switchKit(to id: String) {
        guard id != settings.kitID, let kit = kits[id] else { return }
        settings.apply(kit)
    }

    /// Puts the active kit's tabs back the way the kit ships them.
    func resetToKitDefaults() {
        guard let kit = activeKit else { return }
        settings.apply(kit)
    }

    /// Copies a kit file into the user's kits and switches to it. Returns
    /// what the kit uses that this build will skip, so the user can be told.
    func importKit(from url: URL) throws -> (kit: KitManifest, issues: [KitIssue]) {
        guard let kitStore else { throw KitError.malformed("importing is off in this mode") }
        let kit = try kitStore.install(from: url)
        kits = KitLibrary.installed(imported: kitStore.load())
        settings.apply(kit)
        return (kit, kit.issues())
    }

    /// True when the active kit was imported, so it can be removed.
    var canRemoveActiveKit: Bool {
        kitStore != nil && !KitLibrary.isBundled(settings.kitID) && kits[settings.kitID] != nil
    }

    /// Deletes the active imported kit and falls back to the default kit.
    func removeActiveKit() throws {
        guard canRemoveActiveKit, let kitStore else { return }
        try kitStore.remove(id: settings.kitID)
        kits = KitLibrary.installed(imported: kitStore.load())
        if let fallback = kits.kit(defaultKitID) {
            settings.apply(fallback)
        }
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
        if appliedClaudePathOverride != settings.claudePathOverride {
            appliedClaudePathOverride = settings.claudePathOverride
        }
    }
}
