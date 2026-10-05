import Foundation

/// The status light on a Connections row. Four plain answers to "does this
/// work yet?", plus a short-lived `checking` while a probe runs.
public enum ConnectionLight: String, CaseIterable, Hashable, Sendable {
    /// A check is running. Shown briefly, never as a final answer.
    case checking
    /// Everything works.
    case connected
    /// Almost there: one thing left to do (open an app, flip a switch).
    case needsStep
    /// The app is there but was never connected to Tabbi.
    case notSetUp
    /// The app this needs isn't on the Mac.
    case notInstalled

    /// The words beside the light.
    public var title: String {
        switch self {
        case .checking: "Checking"
        case .connected: "Connected"
        case .needsStep: "Needs one step"
        case .notSetUp: "Not set up"
        case .notInstalled: "Not installed"
        }
    }
}

/// An app that a connection opens or asks the user to get.
public struct ConnectionApp: Hashable, Sendable {
    /// The app's name as the user knows it.
    public var name: String
    /// Bundle ids to look for, preferred first. Anki changed its id, so it
    /// has two.
    public var bundleIDs: [String]
    /// The official download page, for "Get <name>".
    public var downloadPage: URL?

    public init(name: String, bundleIDs: [String], downloadPage: URL?) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.downloadPage = downloadPage
    }

    public static let anki = ConnectionApp(
        name: "Anki", bundleIDs: ["net.ankiweb.dtop", "net.ankiweb.anki"],
        downloadPage: URL(string: "https://apps.ankiweb.net")
    )
    public static let spotify = ConnectionApp(
        name: "Spotify", bundleIDs: ["com.spotify.client"],
        downloadPage: URL(string: "https://www.spotify.com/download/mac/")
    )
    public static let music = ConnectionApp(name: "Music", bundleIDs: ["com.apple.Music"], downloadPage: nil)
}

/// A System Settings page a connection sends the user to. Each URL opens
/// the exact pane, so the user never has to hunt for it.
public enum SystemSettingsLink: String, CaseIterable, Hashable, Sendable {
    case calendarPrivacy
    case automationPrivacy
    case notifications
    case internetAccounts

    public var url: URL {
        let string = switch self {
        case .calendarPrivacy: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .automationPrivacy: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .notifications: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .internetAccounts: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
        }
        // Constant strings, checked by tests.
        return URL(string: string)!
    }
}

/// A short walkthrough the app shows for a step it can't do by itself.
public enum ConnectionGuide: String, CaseIterable, Hashable, Sendable {
    /// Install the AnkiConnect add-on from inside Anki.
    case ankiAddOn
    /// Update an old AnkiConnect add-on.
    case ankiAddOnUpdate
    /// Let Tabbi in when AnkiConnect asks, or remove a key that blocks it.
    case ankiAccess
    /// Add a Google account in System Settings so its calendars show up.
    case googleCalendar
    /// Install the Claude app that Plan my day and Ask Claude use.
    case claudeInstall
    /// Sign in to Claude once.
    case claudeSignIn
    /// Make the two shortcuts that turn Do Not Disturb on and off.
    case focusShortcuts
}

/// What a macOS permission prompt is about. The app shows a short priming
/// screen first, then lets macOS ask.
public enum ConnectionPermission: Hashable, Sendable {
    case calendar
    case notifications
    /// Letting Tabbi control a music app (play, pause, skip).
    case automation(ConnectionApp)
}

/// The one button a Connections row shows for its current state.
public enum ConnectionAction: Hashable, Sendable {
    /// Open the app's download page.
    case download(ConnectionApp)
    /// Open (or bring forward) an installed app.
    case openApp(ConnectionApp)
    /// Show a walkthrough.
    case showGuide(ConnectionGuide)
    /// Show the priming screen, then the macOS permission prompt.
    case askPermission(ConnectionPermission)
    /// Open a System Settings page.
    case openSettings(SystemSettingsLink)
    /// Run the checks again.
    case checkAgain
    /// Start a connection that needs a little info from the user (Party:
    /// a name and a pet).
    case setUp

    /// The button's label.
    public var title: String {
        switch self {
        case .download(let app): "Get \(app.name)"
        case .openApp(let app): "Open \(app.name)"
        case .showGuide(.googleCalendar): "Add Google Calendar"
        case .showGuide: "Show me how"
        case .askPermission: "Connect"
        case .openSettings: "Open Settings"
        case .checkAgain: "Check again"
        case .setUp: "Set up"
        }
    }
}

/// Where one integration stands, in words a first-time Mac user follows:
/// a light, a headline, one sentence, and at most one button.
public struct ConnectionStatus: Hashable, Sendable {
    public var light: ConnectionLight
    /// A few words, such as "Anki is closed".
    public var headline: String
    /// One plain sentence: what's going on or what to do.
    public var detail: String
    /// The button that fixes the current state; nil when nothing needs doing.
    public var action: ConnectionAction?
    /// A quieter, optional extra (such as adding Google Calendar when the
    /// calendar already works). Never a fix for a problem.
    public var suggestion: ConnectionAction?

    public init(light: ConnectionLight, headline: String, detail: String,
                action: ConnectionAction? = nil, suggestion: ConnectionAction? = nil) {
        self.light = light
        self.headline = headline
        self.detail = detail
        self.action = action
        self.suggestion = suggestion
    }

    /// Whether the row is in its final good state.
    public var isConnected: Bool { light == .connected }
}
