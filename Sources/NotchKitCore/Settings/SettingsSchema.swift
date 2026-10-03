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
