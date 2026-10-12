import Foundation

/// How fast to retry Anki after a problem (`AnkiConnectionState.problem`).
///
/// Most problems end by themselves within seconds: Anki finishes a sync,
/// the user closes a dialog, a profile finishes loading. So the first
/// minute retries every few seconds, the next few minutes less often, and
/// after that only once a minute, while someone is looking. Shared by the
/// Anki tab and the Connections row so both recover at the same pace.
public enum AnkiRecovery {
    /// The retry interval during the first `fastWindow` of a problem.
    public static let fastInterval: TimeInterval = 4
    /// How long a problem gets fast retries, also the only time a problem
    /// is retried with nothing on screen.
    public static let fastWindow: TimeInterval = 60
    /// The retry interval after the fast window, up to `slowWindow`.
    public static let slowInterval: TimeInterval = 15
    public static let slowWindow: TimeInterval = 5 * 60
    /// The retry interval for a problem that lasts longer.
    public static let idleInterval: TimeInterval = 60

    /// Seconds until the next retry of a problem that started `problemAge`
    /// seconds ago.
    public static func interval(problemAge: TimeInterval) -> TimeInterval {
        if problemAge < fastWindow { return fastInterval }
        if problemAge < slowWindow { return slowInterval }
        return idleInterval
    }

    /// Whether to retry with nothing on screen: only in the fast window.
    public static func pollsWhileHidden(problemAge: TimeInterval) -> Bool {
        problemAge < fastWindow
    }
}
