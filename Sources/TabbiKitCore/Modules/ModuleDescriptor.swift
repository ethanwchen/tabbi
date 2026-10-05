/// Where a module is grouped in Settings and kit pickers.
/// The shelf a module sits on in Settings and the module browser.
///
/// An open string type like `ModuleID`, so a new vertical (an LSAT or a
/// coding module) can bring a category of its own without editing this
/// file: declare `static let law = ModuleCategory("law", title: "Law")`
/// beside the module. Two categories are equal when their ids are, and only
/// the id is stored, so a title can change without touching saved data.
public struct ModuleCategory: RawRepresentable, Hashable, Codable, Sendable, Identifiable,
                              ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    /// The name shown to people, such as "Productivity".
    public let title: String

    /// A category whose title is its id with the first letter capitalized.
    public init(rawValue: String) {
        self.init(rawValue, title: rawValue.prefix(1).uppercased() + rawValue.dropFirst())
    }

    public init(_ rawValue: String, title: String) {
        self.rawValue = rawValue
        self.title = title
    }

    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self.builtIn.first { $0.rawValue == raw } ?? ModuleCategory(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(rawValue) }

    public var id: String { rawValue }
    public var description: String { rawValue }
}

public extension ModuleCategory {
    static let media = ModuleCategory("media", title: "Media")
    static let system = ModuleCategory("system", title: "System")
    static let productivity = ModuleCategory("productivity", title: "Productivity")
    static let study = ModuleCategory("study", title: "Study")
    static let ai = ModuleCategory("ai", title: "AI")
    static let fun = ModuleCategory("fun", title: "Fun")

    /// The categories the built-in modules use, so decoding a stored id
    /// gets back the proper title ("AI", not "Ai").
    static let builtIn: [ModuleCategory] = [.media, .system, .productivity, .study, .ai, .fun]
}

/// A macOS permission a module asks for, so Settings and onboarding can say
/// up front what turning a module on will prompt for.
public enum ModulePermission: String, CaseIterable, Codable, Sendable {
    /// Apple Events to control another app (Spotify, Music).
    case automation
    case calendars
    case reminders
    case notifications
    /// The local `claude` CLI must be installed.
    case claudeCLI

    public var title: String {
        switch self {
        case .automation: "Automation"
        case .calendars: "Calendars"
        case .reminders: "Reminders"
        case .notifications: "Notifications"
        case .claudeCLI: "Claude Code CLI"
        }
    }
}

/// A host a module talks to over the network, declared on its descriptor so
/// Settings and the kit import sheet can say up front where data goes.
/// Tabbi has no telemetry; this lists only what a module inherently needs.
public struct ModuleNetworkAccess: Hashable, Codable, Sendable {
    /// The host name, such as `i.scdn.co`, or the default one when the user
    /// can pick another (Party's server).
    public var host: String
    /// What the module fetches or sends there, finishing "connects to the
    /// host for ...", e.g. "album artwork".
    public var purpose: String

    public init(host: String, purpose: String) {
        self.host = host
        self.purpose = purpose
    }

    /// True for a service on this Mac (AnkiConnect), which sends nothing
    /// off the machine.
    public var isLocal: Bool {
        ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
    }
}

/// An sRGB color in 0...1 components, so module accents can live in pure
/// code and later come from kit or theme files.
public struct ModuleAccent: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Everything about a module that is known without running it: what the tab
/// bar, Settings, and kit manifests need.
public struct ModuleDescriptor: Hashable, Sendable, Identifiable {
    public var id: ModuleID
    public var title: String
    /// SF Symbol shown in the tab bar and Settings.
    public var symbol: String
    /// One plain sentence on what the module does, shown beside it in the
    /// Settings "Add more" library. Nil falls back to the category's name.
    public var summary: String?
    public var category: ModuleCategory
    public var accent: ModuleAccent
    public var permissions: Set<ModulePermission>
    /// The hosts the module connects to; empty for a module that never
    /// touches the network. Declare every host a module's own code calls.
    public var network: [ModuleNetworkAccess]
    /// Label for the Settings toggle of this module's closed-notch
    /// highlights, e.g. "Claude usage above 80%"; nil when the module never
    /// publishes `TickerHighlight`s.
    public var highlightTitle: String?
    /// The module runs a focus clock of its own (Study's session), not the
    /// shared Pomodoro. A layout with such a module enabled has one timer:
    /// Today shows that module's clock instead of its Pomodoro card.
    public var ownsFocusClock: Bool
    /// The keys this module reads from its section of a kit's
    /// `moduleSettings`, so kit validation can warn about typos and bad
    /// values there. Nil leaves the section unchecked.
    public var kitSettings: KitSettingsSchema?
    /// What first-run onboarding asks once this module is turned on (the
    /// pet's name, calendar access), in no particular order: onboarding
    /// sorts every enabled module's steps by rank and asks each one once.
    public var setup: [OnboardingSetupStep]

    public init(
        id: ModuleID,
        title: String,
        symbol: String,
        summary: String? = nil,
        category: ModuleCategory,
        accent: ModuleAccent,
        permissions: Set<ModulePermission> = [],
        network: [ModuleNetworkAccess] = [],
        highlightTitle: String? = nil,
        ownsFocusClock: Bool = false,
        kitSettings: KitSettingsSchema? = nil,
        setup: [OnboardingSetupStep] = []
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.category = category
        self.accent = accent
        self.permissions = permissions
        self.network = network
        self.highlightTitle = highlightTitle
        self.ownsFocusClock = ownsFocusClock
        self.kitSettings = kitSettings
        self.setup = setup
    }

    /// Stand-in for an id no catalog knows (say, from a newer kit file), so
    /// the UI degrades to a neutral tab instead of crashing.
    public static func unknown(_ id: ModuleID) -> ModuleDescriptor {
        ModuleDescriptor(id: id, title: id.rawValue, symbol: "square.dashed",
                         category: .productivity, accent: ModuleAccent(red: 0.6, green: 0.6, blue: 0.6))
    }
}
