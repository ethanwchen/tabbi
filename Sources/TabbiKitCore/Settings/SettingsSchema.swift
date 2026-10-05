import Foundation

/// The version of the settings stored in `UserDefaults`, and the ordered
/// steps that bring older settings up to it.
///
/// `SettingsRepository.load` runs every step newer than the stored
/// `settings.schemaVersion` once, then records `current`. To change how a
/// preference is stored, bump `current` and append a step that rewrites the
/// old keys; never edit a step that has shipped. Settings written by a newer
/// build (a stored version above `current`, after a downgrade) are left
/// untouched, and the per-key loading already ignores what it can't read.
public enum SettingsSchema {
    /// One step: upgrades settings stored at `version - 1` to `version`.
    public struct Migration: Sendable {
        public let version: Int
        public let migrate: @Sendable (UserDefaults) -> Void

        public init(version: Int, migrate: @escaping @Sendable (UserDefaults) -> Void) {
            self.version = version
            self.migrate = migrate
        }
    }

    public static let versionKey = "settings.schemaVersion"

    /// Every step, in order. Settings with no version key are version 0.
    public static let migrations: [Migration] = [
        // 0 -> 1: installs from before kits saved a tab layout but no "kit
        // chosen" flag. Those users already set Tabbi up, so record that they
        // chose, instead of greeting them with the kit picker again.
        Migration(version: 1) { defaults in
            if defaults.object(forKey: SettingsRepository.Key.hasChosenKit) == nil,
               defaults.object(forKey: SettingsRepository.Key.moduleOrder) != nil {
                defaults.set(true, forKey: SettingsRepository.Key.hasChosenKit)
            }
        },
        // 1 -> 2: the shared focus timer and its session log move from the
        // `planner.*` keys Today used to own to `focus.*` keys.
        Migration(version: 2) { defaults in
            FocusTimerStorage.moveLegacyKeys(in: defaults)
        },
        // 2 -> 3: imported kits go by `KitLibrary.importedID`, so a kit a
        // later Tabbi ships can't shadow one the user imported. An active kit
        // id that isn't a bundled kit was an import; give it the new id.
        // (A kit bundled then and retired since is still a bundled id here,
        // so step 4 can move it to its replacement.)
        Migration(version: 3) { defaults in
            let key = SettingsRepository.Key.kitID
            if let id = defaults.string(forKey: key), !KitLibrary.isBundled(id),
               KitLibrary.retiredKitIDs[id] == nil {
                defaults.set(KitLibrary.importedID(id), forKey: key)
            }
        },
        // 3 -> 4: Productivity and Student fold into Essentials. Someone on
        // either moves to Essentials and keeps the tabs they had (the saved
        // layout is left alone). Their onboarding answers belonged to the old
        // kit's questions, so they go.
        Migration(version: 4) { defaults in
            let key = SettingsRepository.Key.kitID
            if let id = defaults.string(forKey: key), let replacement = KitLibrary.retiredKitIDs[id] {
                defaults.set(replacement, forKey: key)
                defaults.removeObject(forKey: SettingsRepository.Key.kitAnswers)
            }
        },
    ]

    /// The version this build writes.
    public static var current: Int { migrations.last?.version ?? 0 }

    /// The version of the settings in `defaults` (0 when none is recorded).
    public static func storedVersion(in defaults: UserDefaults) -> Int {
        defaults.object(forKey: versionKey) as? Int ?? 0
    }

    /// Runs the steps `defaults` hasn't had yet and records `current`.
    /// A fresh install (nothing stored) just records `current`.
    public static func migrate(_ defaults: UserDefaults, steps: [Migration] = migrations) {
        let stored = storedVersion(in: defaults)
        let target = steps.last?.version ?? 0
        guard stored < target else { return }
        for step in steps where step.version > stored {
            step.migrate(defaults)
        }
        defaults.set(target, forKey: versionKey)
    }

    /// The tab order to store: `live` (the modules this build knows, in the
    /// user's order) with every id from `stored` that this build doesn't know
    /// put back right after the id it followed before.
    ///
    /// So running an older build, or one without a module, doesn't lose that
    /// module's place in the tab bar for when it comes back.
    public static func storedOrder(_ live: [String], keepingUnknownFrom stored: [String],
                                   isKnown: (String) -> Bool) -> [String] {
        var result = live
        var previous: String?
        for id in stored {
            defer { previous = id }
            guard !isKnown(id), !result.contains(id) else { continue }
            let index = previous.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(id, at: index)
        }
        return result
    }
}
