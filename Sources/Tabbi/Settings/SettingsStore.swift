import Combine
import Foundation
import TabbiKitCore

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

    /// A kit the user just applied. Defaults that live outside
    /// `AppSettings` (the focus sound, starter tasks) are applied by
    /// whoever owns them.
    struct KitApplication {
        enum Kind {
            /// The user picked or switched to the kit.
            case switched
            /// Reset to Kit Defaults re-applied the active kit.
            case reset
            /// Undo put the kit back that the last switch replaced. Modules
            /// restore what they held before that switch (Focus: the focus
            /// sound) and take back what it added (Today: untouched starter
            /// tasks).
            case undo
        }

        let kit: KitManifest
        /// The onboarding answers it was applied with.
        let answers: KitAnswers
        let kind: Kind

        /// True when the user picked or switched to the kit (not a reset or
        /// an undo), so its starter tasks belong on Today.
        var addsStarterTasks: Bool { kind == .switched }
    }

    /// What the last kit switch replaced, so Settings can offer to undo it.
    struct KitSwitchUndo {
        /// The kit, tabs and previews before the switch. Undo restores only
        /// these, so other settings changed since stay.
        let kitState: AppSettings.KitState
        /// The kit switched to, imported or removed, for the Undo button's help.
        let kitName: String
        /// False for an import that kept the user's tabs (Add Only, Keep My
        /// Tabs), whose undo only takes the kit file back.
        let switchedKit: Bool
        /// Imported kit files the switch wrote or removed: each id with the
        /// bytes saved under it before (nil when there was no file).
        let kitFiles: [String: Data?]
    }

    /// The last kit switch, import or removal, until it is undone or another
    /// one replaces it.
    @Published private(set) var lastKitSwitch: KitSwitchUndo?

    /// Emits after `settings` holds the applied kit.
    let kitApplied = PassthroughSubject<KitApplication, Never>()

    /// The modules this build has (`ModuleList.catalog`), which layouts and
    /// kits resolve against.
    let catalog: ModuleCatalog
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
        catalog: ModuleCatalog,
        defaults: UserDefaults = .standard,
        defaultKitID: String = KitLibrary.defaultKitID,
        kitStore: ImportedKitStore? = .standard(),
        integratesWithSystem: Bool = true
    ) {
        let kits = KitLibrary.installed(imported: kitStore?.load() ?? [])
        let repository = SettingsRepository(defaults: defaults, catalog: catalog, kits: kits, defaultKitID: defaultKitID)
        self.catalog = catalog
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
    static func ephemeral(catalog: ModuleCatalog, kitID: String = KitLibrary.defaultKitID) -> SettingsStore {
        let suite = "NotchDeck.ephemeral"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(catalog: catalog, defaults: defaults, defaultKitID: kitID, kitStore: nil, integratesWithSystem: false)
    }

    // MARK: Kits

    /// The kit the user picked (the default kit if it has gone missing).
    var activeKit: KitManifest? { kits.kit(settings.kitID) }

    /// True when the tabs already match the active kit, so reset is a no-op.
    var usesKitDefaults: Bool {
        activeKit.map { settings.usesDefaults(of: $0, catalog: catalog) } ?? true
    }

    /// Switches to a kit, replacing the tab layout with its defaults for the
    /// user's onboarding `answers` (Settings asks the kit's questions first,
    /// as first-run setup does). Re-applies the active kit too, so a kit
    /// re-imported with changes takes effect. `undoKitSwitch` reverts it.
    func switchKit(to id: String, answers: KitAnswers = [:]) {
        guard let kit = kits[id] else { return }
        switchKit(to: kit, answers: answers, kitFiles: [:])
    }

    /// The first-run pick: applies `id`'s tabs for the user's onboarding
    /// `answers` even when it is already the default kit, and records that
    /// the user has chosen.
    func chooseKit(_ id: String, answers: KitAnswers = [:]) {
        guard let kit = kits[id] ?? activeKit else { return }
        apply(kit, answers: kit.id == id ? answers : [:], kind: .switched)
    }

    /// Puts the active kit's tabs back the way the kit sets them up for the
    /// answers the user gave when picking it.
    func resetToKitDefaults() {
        guard let kit = activeKit else { return }
        apply(kit, answers: settings.kitAnswers, kind: .reset)
    }

    /// What switching to `kit` with `answers` would change, for the sheet
    /// Settings shows before applying an imported kit.
    func preview(of kit: KitManifest, answers: KitAnswers = [:]) -> KitChangePreview {
        KitChangePreview(applying: kit, answers: answers, to: settings, catalog: catalog)
    }

    /// Reads and validates a kit file without saving or switching, so
    /// Settings can show what it changes first; `installKit` keeps it.
    func inspectKit(from url: URL) throws -> KitImportCandidate {
        guard let kitStore else { throw KitError.malformed("importing is off in this mode") }
        return try kitStore.inspect(from: url, catalog: catalog)
    }

    /// Saves an inspected kit into the user's kits, replacing an earlier
    /// import with its id, and switches to it with `answers` unless they are
    /// nil. Undo removes the file again (or puts the replaced one back).
    func installKit(_ candidate: KitImportCandidate, switchingWith answers: KitAnswers?) throws {
        guard let kitStore else { throw KitError.malformed("importing is off in this mode") }
        let id = candidate.kit.id
        let previous: [String: Data?] = [id: kitStore.savedData(for: id)]
        try kitStore.install(candidate)
        kits = KitLibrary.installed(imported: kitStore.load())
        if let answers, let kit = kits[id] {
            switchKit(to: kit, answers: answers, kitFiles: previous)
        } else {
            // Replaces any earlier switch's undo, so Undo never reverts that
            // switch and deletes the file just imported.
            lastKitSwitch = KitSwitchUndo(kitState: settings.kitState, kitName: candidate.kit.name,
                                          switchedKit: false, kitFiles: previous)
        }
    }

    /// What `kit` uses that this build skips, so the user can be told.
    func issues(of kit: KitManifest) -> [KitIssue] {
        kit.issues(catalog: catalog)
    }

    /// True when the active kit was imported, so it can be removed.
    var canRemoveActiveKit: Bool {
        kitStore != nil && !KitLibrary.isBundled(settings.kitID) && kits[settings.kitID] != nil
    }

    /// Deletes the active imported kit and falls back to the default kit.
    /// Undo puts the file and the tabs back.
    func removeActiveKit() throws {
        guard canRemoveActiveKit, let kitStore, let removed = activeKit else { return }
        let previous: [String: Data?] = [removed.id: kitStore.savedData(for: removed.id)]
        try kitStore.remove(id: removed.id)
        kits = KitLibrary.installed(imported: kitStore.load())
        if let fallback = kits.kit(defaultKitID) {
            switchKit(to: fallback, answers: [:], kitFiles: previous, undoName: removed.name)
        }
    }

    /// Reverts the last kit switch, import or removal: the kit files it
    /// wrote or deleted, then the kit, tabs and previews as they were, and
    /// modules hear the previous kit again as an `.undo` so they restore
    /// their own state. An import that kept the tabs only takes its file back.
    func undoKitSwitch() {
        guard let undo = lastKitSwitch else { return }
        lastKitSwitch = nil
        if let kitStore, !undo.kitFiles.isEmpty {
            for (id, data) in undo.kitFiles {
                try? kitStore.restore(data, for: id)
            }
            kits = KitLibrary.installed(imported: kitStore.load())
        }
        guard undo.switchedKit else { return }
        settings.kitState = undo.kitState
        if let kit = activeKit {
            kitApplied.send(KitApplication(kit: kit, answers: settings.kitAnswers, kind: .undo))
        }
    }

    /// - Parameter undoName: the kit Undo names; `kit` unless the switch
    ///   is the fallback after removing a kit.
    private func switchKit(to kit: KitManifest, answers: KitAnswers, kitFiles: [String: Data?], undoName: String? = nil) {
        let before = settings.kitState
        apply(kit, answers: answers, kind: .switched)
        lastKitSwitch = KitSwitchUndo(kitState: before, kitName: undoName ?? kit.name, switchedKit: true, kitFiles: kitFiles)
    }

    private func apply(_ kit: KitManifest, answers: KitAnswers = [:], kind: KitApplication.Kind) {
        settings.apply(kit, answers: answers, catalog: catalog)
        kitApplied.send(KitApplication(kit: kit, answers: answers, kind: kind))
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
