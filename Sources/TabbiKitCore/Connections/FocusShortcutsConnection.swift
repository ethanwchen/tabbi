import Foundation

/// Where Do Not Disturb stands. macOS lets an app switch Focus only through
/// the user's own shortcuts, so this checks that the two Tabbi runs exist.
public struct FocusShortcutsState: Hashable, Sendable {
    /// The shortcut that turns Do Not Disturb on.
    public var onName: String
    /// The shortcut that turns it off.
    public var offName: String
    /// The names of the user's shortcuts, or nil while they're being listed.
    public var installed: Set<String>?

    public init(onName: String, offName: String, installed: Set<String>?) {
        self.onName = onName
        self.offName = offName
        self.installed = installed
    }

    /// Reads `shortcuts list` output: one shortcut name per line.
    public static func parseList(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
    }

    /// The shortcuts still to make, on first.
    public var missing: [String] {
        guard let installed else { return [] }
        return [onName, offName].filter { !installed.contains($0) }
    }

    public var connectionStatus: ConnectionStatus {
        guard installed != nil else {
            return ConnectionStatus(light: .checking, headline: "Looking for your shortcuts",
                                    detail: "This takes a second.")
        }
        switch missing.count {
        case 0:
            return ConnectionStatus(light: .connected, headline: "Do Not Disturb is ready",
                                    detail: "Alerts go quiet while you focus.")
        case 1:
            return ConnectionStatus(light: .needsStep, headline: "One shortcut left",
                                    detail: "Make \u{201C}\(missing[0])\u{201D} so Tabbi can switch Do Not Disturb both ways.",
                                    action: .showGuide(.focusShortcuts))
        default:
            return ConnectionStatus(light: .notSetUp, headline: "Do Not Disturb isn't set up",
                                    detail: "Two quick shortcuts let Tabbi quiet alerts while you focus.",
                                    action: .showGuide(.focusShortcuts))
        }
    }
}
