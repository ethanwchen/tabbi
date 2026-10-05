/// A module's stable identifier, used in saved settings, kit manifests, and
/// snapshot file names.
///
/// Open rather than a closed enum so modules (and kits that list them) can be
/// added without touching a central switch. Ids are lower camel case and must
/// never change once shipped, since users' layouts are stored by id.
public struct ModuleID: RawRepresentable, Hashable, Codable, Sendable, Identifiable,
                        ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var id: String { rawValue }
    public var description: String { rawValue }
}

public extension ModuleID {
    static let spotify: ModuleID = "spotify"
    static let system: ModuleID = "system"
    static let claudeUsage: ModuleID = "claudeUsage"
    static let planner: ModuleID = "planner"
    static let claudeAsk: ModuleID = "claudeAsk"
    /// The Pomodoro timer and focus mode as a tab of its own.
    static let focus: ModuleID = "focus"
    // Study modules (Med School and Student kits).
    static let study: ModuleID = "study"
    static let anki: ModuleID = "anki"
    static let party: ModuleID = "party"
    static let closet: ModuleID = "closet"
}
