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
    /// Label for the Settings toggle of this module's closed-notch
    /// highlights, e.g. "Claude usage above 80%"; nil when the module never
    /// publishes `TickerHighlight`s.
    public var highlightTitle: String?
    /// The module runs a focus clock of its own (Study's session), not the
    /// shared Pomodoro. A layout with such a module enabled has one timer:
    /// Today shows that module's clock instead of its Pomodoro card.
    public var ownsFocusClock: Bool

    public init(
        id: ModuleID,
        title: String,
        symbol: String,
        category: ModuleCategory,
        accent: ModuleAccent,
        permissions: Set<ModulePermission> = [],
        highlightTitle: String? = nil,
        ownsFocusClock: Bool = false
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.category = category
        self.accent = accent
        self.permissions = permissions
        self.highlightTitle = highlightTitle
        self.ownsFocusClock = ownsFocusClock
    }

    /// Stand-in for an id no catalog knows (say, from a newer kit file), so
    /// the UI degrades to a neutral tab instead of crashing.
    public static func unknown(_ id: ModuleID) -> ModuleDescriptor {
        ModuleDescriptor(id: id, title: id.rawValue, symbol: "square.dashed",
                         category: .productivity, accent: ModuleAccent(red: 0.6, green: 0.6, blue: 0.6))
    }
}
