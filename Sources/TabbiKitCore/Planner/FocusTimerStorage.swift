import Foundation

/// Where the shared Pomodoro timer lives in `UserDefaults`, and its
/// versioned JSON format, plus the session log older builds kept there.
///
/// Builds before settings had a schema version stored them under
/// `planner.*` keys; `SettingsSchema` step 2 moves them here.
public struct FocusTimerStorage {
    public static let timerKey = "focus.timer"
    public static let sessionLogKey = "focus.sessionLog"
    public static let lastAliveKey = "focus.lastAlive"
    static let legacyTimerKey = "planner.focusTimer"
    static let legacySessionLogKey = "planner.focusSessions"

    /// The timer format. Version 1 added the `schemaVersion` key.
    public static let timerSchema = VersionedJSON(current: 1)
    /// The legacy session log format. Version 1 added the `schemaVersion` key.
    public static let sessionLogSchema = VersionedJSON(current: 1)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved timer, or a fresh one when none is saved or it can't be read.
    public func loadTimer() -> FocusTimer {
        defaults.data(forKey: Self.timerKey)
            .flatMap { try? Self.timerSchema.decode(FocusTimer.self, from: $0) } ?? FocusTimer()
    }

    public func save(_ timer: FocusTimer) {
        if let data = try? Self.timerSchema.encode(timer) { defaults.set(data, forKey: Self.timerKey) }
    }

    /// The last moment Tabbi was known to be alive with a session under way,
    /// so a launch after a crash can end that session there. Nil from builds
    /// that never saved one.
    public var lastAlive: Date? {
        defaults.object(forKey: Self.lastAliveKey) as? Date
    }

    public func saveLastAlive(_ date: Date) {
        defaults.set(date, forKey: Self.lastAliveKey)
    }

    /// Hands the session log an older build saved to `move`, and removes it
    /// from `UserDefaults` once `move` reports that it is safely stored
    /// elsewhere (the activity log), so a failed move is retried on the next
    /// launch instead of losing the history. A log that can't be read is
    /// removed without calling `move`, since nothing can be recovered from it.
    public func moveSessionLog(_ move: (FocusSessionLog) -> Bool) {
        guard let data = defaults.data(forKey: Self.sessionLogKey) else { return }
        if let log = try? Self.sessionLogSchema.decode(FocusSessionLog.self, from: data), !move(log) { return }
        defaults.removeObject(forKey: Self.sessionLogKey)
    }

    /// Moves values from the `planner.*` keys to the `focus.*` keys, unless
    /// the new key already has one.
    static func moveLegacyKeys(in defaults: UserDefaults) {
        for (old, new) in [(legacyTimerKey, timerKey), (legacySessionLogKey, sessionLogKey)] {
            guard let value = defaults.object(forKey: old) else { continue }
            if defaults.object(forKey: new) == nil { defaults.set(value, forKey: new) }
            defaults.removeObject(forKey: old)
        }
    }
}
