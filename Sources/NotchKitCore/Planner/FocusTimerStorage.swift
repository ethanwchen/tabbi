import Foundation

/// Where the shared Pomodoro timer lives in `UserDefaults`, and its
/// versioned JSON format, plus the session log older builds kept there.
///
/// Builds before settings had a schema version stored them under
/// `planner.*` keys; `SettingsSchema` step 2 moves them here.
public struct FocusTimerStorage {
    public static let timerKey = "focus.timer"
    public static let sessionLogKey = "focus.sessionLog"
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

    /// The session log an older build saved, removed from `UserDefaults` so
    /// it is handed out once, for moving into the activity log. Nil when
    /// there is none or it can't be read.
    public func takeSessionLog() -> FocusSessionLog? {
        guard let data = defaults.data(forKey: Self.sessionLogKey) else { return nil }
        defaults.removeObject(forKey: Self.sessionLogKey)
        return try? Self.sessionLogSchema.decode(FocusSessionLog.self, from: data)
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
