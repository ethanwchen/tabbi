import Foundation

/// The AppleScript the sandboxed App Store build sends to Shortcuts Events
/// to run the Do Not Disturb shortcuts, and how its errors read.
///
/// A sandboxed app can't start `/usr/bin/shortcuts`, but Shortcuts Events
/// (the background half of the Shortcuts app) runs shortcuts over Apple
/// Events without opening a window. Its scripting definition puts `run`
/// and reading shortcut names in the `com.apple.shortcuts.run` access group,
/// which the App Store entitlements name under
/// `com.apple.security.scripting-targets`, so no temporary exception is
/// needed. macOS asks the user once (Automation) before the first event.
public enum ShortcutsEventsScript {
    /// Shortcuts Events' bundle id, the Apple Events target.
    public static let bundleIdentifier = "com.apple.shortcuts.events"
    /// The access group the entitlement names for running shortcuts.
    public static let accessGroup = "com.apple.shortcuts.run"
    /// How long one shortcut may take, as the command line runner allows.
    public static let timeoutSeconds = 15

    /// Runs the shortcut called `name` and waits for it.
    public static func run(_ name: String) -> String {
        """
        with timeout of \(timeoutSeconds) seconds
            tell application id "\(bundleIdentifier)" to run shortcut \(quoted(name))
        end timeout
        """
    }

    /// The names of the user's shortcuts, to check the two exist.
    public static var listNames: String {
        "tell application id \"\(bundleIdentifier)\" to get name of every shortcut"
    }

    /// `text` as an AppleScript string literal: quotes and backslashes are
    /// escaped, so a shortcut's name can never end the string early.
    public static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// What a finished run means for the user, from the AppleScript error
    /// number and message (nil when the script succeeded).
    public static func result(errorNumber: Int?, message: String?, name: String) -> FocusShortcutResult {
        guard let errorNumber else { return .succeeded }
        switch errorNumber {
        // errAEEventNotPermitted: the user said no, or hasn't been asked.
        case -1743, -10004: return .notAllowed
        // errAENoSuchObject: there is no shortcut by that name.
        case -1728: return .notFound(name: name)
        // errAETimeout.
        case -1712: return .timedOut
        // procNotFound, connectionInvalid: Shortcuts Events didn't start.
        case -600, -609: return .unavailable
        default:
            let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failed(message: text)
        }
    }
}
