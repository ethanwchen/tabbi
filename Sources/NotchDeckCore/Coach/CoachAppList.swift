import Foundation

/// How the coach treats the app in front.
///
/// The coach only ever sees bundle ids: never window titles, URLs, or
/// keystrokes. Those would need Screen Recording or Accessibility access,
/// and the coach doesn't need them.
public enum CoachAppCategory: String, Codable, CaseIterable, Hashable, Sendable {
    /// On the user's "focus apps" list (Anki, a Qbank). Never a distraction.
    case focus
    /// On the user's "distracting apps" list.
    case distracting
    /// Anything else, including an unknown frontmost app.
    case neutral
}

/// A suggested distracting app, shown as an opt-in chip in settings.
public struct CoachAppSuggestion: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The user's focus and distracting app lists, matched by bundle id.
///
/// The distracting list starts empty on purpose: the user picks it, and
/// `suggestedDistracting` only offers common choices. Matching ignores case
/// because bundle ids are case-insensitive on macOS. When an app is on both
/// lists, focus wins, so the coach errs toward staying quiet.
public struct CoachAppList: Codable, Hashable, Sendable {
    public private(set) var focus: Set<String>
    public private(set) var distracting: Set<String>

    /// Anki's bundle ids (current launcher build and the historical one) are
    /// focus apps out of the box.
    public static let defaultFocus: Set<String> = ["net.ankiweb.anki", "net.ankiweb.dtop"]

    /// Common distractions offered in settings. Not pre-selected. Websites
    /// such as YouTube can't be detected (that would need window titles),
    /// so the settings copy should say so.
    public static let suggestedDistracting: [CoachAppSuggestion] = [
        CoachAppSuggestion(bundleID: "com.apple.MobileSMS", name: "Messages"),
        CoachAppSuggestion(bundleID: "com.hnc.Discord", name: "Discord"),
        CoachAppSuggestion(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        CoachAppSuggestion(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
        CoachAppSuggestion(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
        CoachAppSuggestion(bundleID: "com.valvesoftware.steam", name: "Steam"),
        CoachAppSuggestion(bundleID: "com.apple.TV", name: "TV"),
    ]

    public init(focus: Set<String> = CoachAppList.defaultFocus, distracting: Set<String> = []) {
        self.focus = Set(focus.map(Self.normalized))
        self.distracting = Set(distracting.map(Self.normalized))
    }

    public func category(of bundleID: String?) -> CoachAppCategory {
        guard let bundleID, !bundleID.isEmpty else { return .neutral }
        let id = Self.normalized(bundleID)
        if focus.contains(id) { return .focus }
        if distracting.contains(id) { return .distracting }
        return .neutral
    }

    /// Marks an app distracting, taking it off the focus list.
    public mutating func markDistracting(_ bundleID: String) {
        let id = Self.normalized(bundleID)
        focus.remove(id)
        distracting.insert(id)
    }

    /// Marks an app as a focus app, taking it off the distracting list.
    public mutating func markFocus(_ bundleID: String) {
        let id = Self.normalized(bundleID)
        distracting.remove(id)
        focus.insert(id)
    }

    /// Takes an app off both lists.
    public mutating func forget(_ bundleID: String) {
        let id = Self.normalized(bundleID)
        focus.remove(id)
        distracting.remove(id)
    }

    private static func normalized(_ bundleID: String) -> String {
        bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
