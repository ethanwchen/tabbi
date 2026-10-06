import Foundation

/// When an Ask Claude answer opens in the large chat view.
public enum ClaudeAskLargeView: String, Codable, CaseIterable, Sendable {
    /// The answer stays in the notch; Expand or Command-Return grows it.
    case askEachTime
    /// Every question grows the notch into the large view.
    case always
    /// The chat always stays in the notch, and Expand is hidden.
    case never

    /// The choice as Settings lists it.
    public var title: String {
        switch self {
        case .askEachTime: "Ask each time"
        case .always: "Always"
        case .never: "Never"
        }
    }

    /// Whether sending a question grows the notch; `commandReturn` is true
    /// when the user sent it with Command-Return (send and expand).
    public func opensLarge(commandReturn: Bool) -> Bool {
        switch self {
        case .askEachTime: commandReturn
        case .always: true
        case .never: false
        }
    }

    /// Whether the chat offers an Expand button. With `never` there is
    /// nothing to expand into.
    public var offersExpand: Bool { self != .never }
}

/// Ask Claude's own preferences.
public struct ClaudeAskPreferences: Codable, Equatable, Sendable {
    public var largeView: ClaudeAskLargeView

    public init(largeView: ClaudeAskLargeView = .askEachTime) {
        self.largeView = largeView
    }

    /// Lenient: a value this build doesn't know (say, from a newer build)
    /// keeps the default instead of losing every preference.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        largeView = (try? container.decodeIfPresent(ClaudeAskLargeView.self, forKey: .largeView)) ?? .askEachTime
    }
}

/// Where Ask Claude's preferences live in `UserDefaults`, and their
/// versioned JSON format.
public struct ClaudeAskPreferencesStorage {
    public static let key = "claudeAsk.preferences"
    /// Version 1 is the first format.
    public static let schema = VersionedJSON(current: 1)

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved preferences, or the defaults when none are saved or they
    /// can't be read.
    public func load() -> ClaudeAskPreferences {
        defaults.data(forKey: Self.key)
            .flatMap { try? Self.schema.decode(ClaudeAskPreferences.self, from: $0) } ?? ClaudeAskPreferences()
    }

    public func save(_ preferences: ClaudeAskPreferences) {
        if let data = try? Self.schema.encode(preferences) { defaults.set(data, forKey: Self.key) }
    }
}
