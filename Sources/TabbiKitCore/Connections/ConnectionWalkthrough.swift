import Foundation

/// A step in a walkthrough that Tabbi can do for the user with one click.
public enum ConnectionStepAction: Hashable, Sendable {
    /// Put some text on the clipboard, then open an app to paste it in
    /// (the AnkiConnect code into Anki, a line into Terminal).
    case copyAndOpen(text: String, app: ConnectionApp)
    /// Open (or bring forward) an app.
    case openApp(ConnectionApp)
    /// Open a System Settings page.
    case openSettings(SystemSettingsLink)

    /// The button's label.
    public var title: String {
        switch self {
        case .copyAndOpen(_, let app) where app == .anki: String(localized: "Copy code and open Anki", bundle: .tabbi)
        case .copyAndOpen(_, let app): String(localized: "Copy and open \(app.displayName)", bundle: .tabbi)
        case .openApp(let app): String(localized: "Open \(app.displayName)", bundle: .tabbi)
        case .openSettings(.internetAccounts): String(localized: "Open Internet Accounts", bundle: .tabbi)
        case .openSettings: String(localized: "Open System Settings", bundle: .tabbi)
        }
    }
}

extension ConnectionApp {
    /// Terminal, which comes with every Mac. Only Claude's setup needs it.
    public static let terminal = ConnectionApp(name: "Terminal", bundleIDs: ["com.apple.Terminal"], downloadPage: nil)
    /// Shortcuts, which comes with every Mac.
    public static let shortcuts = ConnectionApp(name: "Shortcuts", bundleIDs: ["com.apple.shortcuts"], downloadPage: nil)
}

/// A short, numbered walkthrough for a step Tabbi can't do by itself. It
/// has one primary button that starts it, and Tabbi watches for the result,
/// so the user never has to report back.
public struct ConnectionWalkthrough: Hashable, Sendable {
    /// One numbered step: a symbol to recognize it by, one sentence, and
    /// optionally a short value the user needs (a code to paste), shown
    /// with its own Copy button.
    public struct Step: Hashable, Sendable {
        public var symbol: String
        public var text: String
        public var copyable: String?

        public init(symbol: String, text: String, copyable: String? = nil) {
            self.symbol = symbol
            self.text = text
            self.copyable = copyable
        }
    }

    public var title: String
    /// Why this is needed and how long it takes, in one or two sentences.
    public var intro: String
    public var steps: [Step]
    /// The one button that starts the walkthrough.
    public var start: ConnectionStepAction
    /// An official page with more help, shown as a quiet link.
    public var learnMore: URL?

    public init(title: String, intro: String, steps: [Step], start: ConnectionStepAction, learnMore: URL? = nil) {
        self.title = title
        self.intro = intro
        self.steps = steps
        self.start = start
        self.learnMore = learnMore
    }

    /// What the sheet says while Tabbi waits for the steps to work.
    public static let waiting = String(localized: "Tabbi checks by itself and turns green when it works.", bundle: .tabbi)
}

extension ConnectionGuide {
    /// The row this guide fixes.
    public var kind: ConnectionKind {
        switch self {
        case .ankiAddOn, .ankiAddOnUpdate, .ankiAccess: .anki
        case .googleCalendar: .calendar
        case .claudeInstall, .claudeSignIn: .claude
        case .focusShortcuts: .doNotDisturb
        }
    }

    /// The walkthrough for this guide. Do Not Disturb names the user's own
    /// shortcuts, which default to the suggested ones. Claude's sign-in runs
    /// `claudeExecutable`, the `claude` Tabbi found, by its full path.
    public func walkthrough(onShortcut: String = FocusSettings.suggestedOnShortcut,
                            offShortcut: String = FocusSettings.suggestedOffShortcut,
                            claudeExecutable: URL? = nil) -> ConnectionWalkthrough {
        let code = AnkiConnectClient.addOnCode
        let reopenAnki = ConnectionWalkthrough.Step(
            symbol: "arrow.clockwise", text: String(localized: "Quit Anki and open it again. Tabbi notices by itself.", bundle: .tabbi)
        )
        switch self {
        case .ankiAddOn:
            // A guide, not an automatic install: Anki installs and updates
            // its own add-ons, and Tabbi never writes into Anki's folders.
            return ConnectionWalkthrough(
                title: String(localized: "Add AnkiConnect to Anki", bundle: .tabbi),
                intro: String(localized: "AnkiConnect is a free add-on that lets Tabbi count your due cards. It takes about a minute.", bundle: .tabbi),
                steps: [
                    .init(symbol: "menubar.rectangle", text: String(localized: "In Anki's menu bar, click Tools, then Add-ons.", bundle: .tabbi)),
                    .init(symbol: "doc.on.clipboard",
                          text: String(localized: "Click Get Add-ons, paste this code, then click OK.", bundle: .tabbi), copyable: code),
                    reopenAnki,
                ],
                start: .copyAndOpen(text: code, app: .anki),
                learnMore: URL(string: "https://ankiweb.net/shared/info/\(code)")
            )
        case .ankiAddOnUpdate:
            return ConnectionWalkthrough(
                title: String(localized: "Update AnkiConnect", bundle: .tabbi),
                intro: String(localized: "Your copy of AnkiConnect is too old for Tabbi. Anki can update it in a few clicks.", bundle: .tabbi),
                steps: [
                    .init(symbol: "menubar.rectangle", text: String(localized: "In Anki's menu bar, click Tools, then Add-ons.", bundle: .tabbi)),
                    .init(symbol: "arrow.triangle.2.circlepath",
                          text: String(localized: "Click AnkiConnect in the list, then click Check for Updates.", bundle: .tabbi)),
                    reopenAnki,
                ],
                start: .openApp(.anki)
            )
        case .ankiAccess:
            return ConnectionWalkthrough(
                title: String(localized: "Let Tabbi into Anki", bundle: .tabbi),
                intro: String(localized: "AnkiConnect's settings keep Tabbi out. Putting them back to normal fixes it and leaves your cards alone.", bundle: .tabbi),
                steps: [
                    .init(symbol: "menubar.rectangle",
                          text: String(localized: "In Anki, click Tools, then Add-ons. Click AnkiConnect, then Config.", bundle: .tabbi)),
                    .init(symbol: "arrow.uturn.backward", text: String(localized: "Click Restore Defaults, then OK.", bundle: .tabbi)),
                    .init(symbol: "checkmark.circle",
                          text: String(localized: "Quit Anki and open it again. If it asks about Tabbi, click Yes.", bundle: .tabbi)),
                ],
                start: .openApp(.anki)
            )
        case .googleCalendar:
            return ConnectionWalkthrough(
                title: String(localized: "Add your Google Calendar", bundle: .tabbi),
                intro: String(localized: "Tabbi shows the calendars your Mac knows about. Add your Google account once and its events show up.", bundle: .tabbi),
                steps: [
                    .init(symbol: "plus.circle",
                          text: String(localized: "In Internet Accounts, click Add Account, then Google, and sign in.", bundle: .tabbi)),
                    .init(symbol: "calendar", text: String(localized: "Make sure Calendars is turned on for that account.", bundle: .tabbi)),
                ],
                start: .openSettings(.internetAccounts)
            )
        case .claudeInstall:
            let command = ClaudeConnectionState.installCommand
            return ConnectionWalkthrough(
                title: String(localized: "Set up Claude", bundle: .tabbi),
                intro: String(localized: "Claude is an AI helper. Tabbi uses it to plan your day and answer questions. It's optional: everything else works without it.", bundle: .tabbi),
                steps: [
                    .init(symbol: "terminal",
                          text: String(localized: "Click the button below. It copies the setup line and opens Terminal, an app that comes with your Mac.", bundle: .tabbi)),
                    .init(symbol: "doc.on.clipboard",
                          text: String(localized: "Click in the Terminal window, press Command-V to paste, then press Return.", bundle: .tabbi),
                          copyable: command),
                    .init(symbol: "safari",
                          text: String(localized: "It installs Claude, then opens a sign-in page in your browser. Sign in there and Tabbi notices by itself.", bundle: .tabbi)),
                ],
                start: .copyAndOpen(text: command, app: .terminal),
                learnMore: ClaudeConnectionState.installPage
            )
        case .claudeSignIn:
            let command = ClaudeConnectionState.signInCommand(executable: claudeExecutable)
            return ConnectionWalkthrough(
                title: String(localized: "Sign in to Claude", bundle: .tabbi),
                intro: String(localized: "Claude is on your Mac. Sign in once and Tabbi can use it.", bundle: .tabbi),
                steps: [
                    .init(symbol: "terminal",
                          text: String(localized: "Click the button below. It copies the sign-in line and opens Terminal.", bundle: .tabbi)),
                    .init(symbol: "doc.on.clipboard",
                          text: String(localized: "Click in the Terminal window, press Command-V to paste, then press Return.", bundle: .tabbi),
                          copyable: command),
                    .init(symbol: "safari", text: String(localized: "Sign in on the page that opens. Tabbi notices by itself.", bundle: .tabbi)),
                ],
                start: .copyAndOpen(text: command, app: .terminal),
                learnMore: ClaudeConnectionState.installPage
            )
        case .focusShortcuts:
            return ConnectionWalkthrough(
                title: String(localized: "Set up Do Not Disturb", bundle: .tabbi),
                intro: String(localized: "Your Mac lets apps switch Do Not Disturb only through shortcuts you make. Two small ones do it.", bundle: .tabbi),
                steps: [
                    .init(symbol: "plus.square",
                          text: String(localized: "In Shortcuts, click the + button and name the new shortcut:", bundle: .tabbi), copyable: onShortcut),
                    .init(symbol: "moon.fill",
                          text: String(localized: "Search for Set Focus, add it, and pick Do Not Disturb, turned On.", bundle: .tabbi)),
                    .init(symbol: "moon",
                          text: String(localized: "Make one more the same way, turned Off, and name it:", bundle: .tabbi), copyable: offShortcut),
                ],
                start: .openApp(.shortcuts)
            )
        }
    }
}

extension ConnectionStatus {
    /// Whether a walkthrough opened from this row has done its job. A guide
    /// opened to fix a problem is done once the row is connected; one opened
    /// as a connected row's suggestion (Add Google Calendar) is done once the
    /// row stops suggesting it.
    public func finishes(_ guide: ConnectionGuide, openedAsSuggestion: Bool) -> Bool {
        guard isConnected else { return false }
        return !openedAsSuggestion || suggestion != .showGuide(guide)
    }
}

/// The short screen Tabbi shows just before a macOS permission prompt, so
/// the prompt is expected and the user knows which button to click. Per
/// Apple's guidance it has one button that leads straight to the prompt.
public struct ConnectionPriming: Hashable, Sendable {
    public var symbol: String
    public var title: String
    /// What the prompt will ask and which button to click.
    public var message: String
    /// Short reassurances: what Tabbi does and doesn't do with it.
    public var points: [String]
    /// Always "Continue": the button leads to the prompt, it doesn't grant.
    public let button = String(localized: "Continue", bundle: .tabbi)
}

extension ConnectionPermission {
    public var priming: ConnectionPriming {
        switch self {
        case .calendar:
            ConnectionPriming(
                symbol: "calendar",
                title: String(localized: "Show your calendar in Tabbi", bundle: .tabbi),
                message: String(localized: "Next, your Mac asks if Tabbi can use your calendar. Click Allow.", bundle: .tabbi),
                points: [String(localized: "Tabbi only reads events to show today's plan.", bundle: .tabbi),
                         String(localized: "Claude only sees your events when you ask it to plan your day.", bundle: .tabbi)]
            )
        case .notifications:
            ConnectionPriming(
                symbol: "bell.badge.fill",
                title: String(localized: "Get a heads-up when time's up", bundle: .tabbi),
                message: String(localized: "Next, your Mac asks if Tabbi can send alerts. Click Allow.", bundle: .tabbi),
                points: [String(localized: "Tabbi only alerts you when a focus block or break ends.", bundle: .tabbi),
                         String(localized: "You can turn alerts off any time in System Settings.", bundle: .tabbi)]
            )
        case .automation(let app):
            ConnectionPriming(
                symbol: "music.note",
                title: String(localized: "Control \(app.displayName) from the notch", bundle: .tabbi),
                message: String(localized: "Next, your Mac asks if Tabbi can control \(app.displayName). Click Allow.", bundle: .tabbi),
                points: [String(localized: "Tabbi only plays, pauses, skips and shows what's playing.", bundle: .tabbi),
                         String(localized: "If \(app.displayName) isn't open, Tabbi opens it first so your Mac can ask.", bundle: .tabbi)]
            )
        }
    }
}
