/// Where a module is grouped in Settings and kit pickers.
public enum ModuleCategory: String, CaseIterable, Codable, Sendable {
    case media
    case system
    case productivity
    case study
    case ai
    case fun

    public var title: String {
        switch self {
        case .media: "Media"
        case .system: "System"
        case .productivity: "Productivity"
        case .study: "Study"
        case .ai: "AI"
        case .fun: "Fun"
        }
    }
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

    public init(
        id: ModuleID,
        title: String,
        symbol: String,
        category: ModuleCategory,
        accent: ModuleAccent,
        permissions: Set<ModulePermission> = [],
        network: [ModuleNetworkAccess] = [],
        highlightTitle: String? = nil,
        ownsFocusClock: Bool = false,
        kitSettings: KitSettingsSchema? = nil
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.category = category
        self.accent = accent
        self.permissions = permissions
        self.network = network
        self.highlightTitle = highlightTitle
        self.ownsFocusClock = ownsFocusClock
        self.kitSettings = kitSettings
    }

    /// Stand-in for an id no catalog knows (say, from a newer kit file), so
    /// the UI degrades to a neutral tab instead of crashing.
    public static func unknown(_ id: ModuleID) -> ModuleDescriptor {
        ModuleDescriptor(id: id, title: id.rawValue, symbol: "square.dashed",
                         category: .productivity, accent: ModuleAccent(red: 0.6, green: 0.6, blue: 0.6))
    }
}
