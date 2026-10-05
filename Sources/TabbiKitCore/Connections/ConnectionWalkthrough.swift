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
        case .copyAndOpen(_, let app) where app == .anki: "Copy code and open Anki"
        case .copyAndOpen(_, let app): "Copy and open \(app.name)"
        case .openApp(let app): "Open \(app.name)"
        case .openSettings(.internetAccounts): "Open Internet Accounts"
        case .openSettings: "Open System Settings"
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
    public static let waiting = "Tabbi checks by itself and turns green when it works."
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
    /// shortcuts, which default to the suggested ones.
    public func walkthrough(onShortcut: String = FocusSettings.suggestedOnShortcut,
                            offShortcut: String = FocusSettings.suggestedOffShortcut) -> ConnectionWalkthrough {
        let code = AnkiConnectClient.addOnCode
        let reopenAnki = ConnectionWalkthrough.Step(
            symbol: "arrow.clockwise", text: "Quit Anki and open it again. Tabbi notices by itself."
        )
        switch self {
        case .ankiAddOn:
            // A guide, not an automatic install: Anki installs and updates
            // its own add-ons, and Tabbi never writes into Anki's folders.
            return ConnectionWalkthrough(
                title: "Add AnkiConnect to Anki",
                intro: "AnkiConnect is a free add-on that lets Tabbi count your due cards. It takes about a minute.",
                steps: [
                    .init(symbol: "menubar.rectangle", text: "In Anki's menu bar, click Tools, then Add-ons."),
                    .init(symbol: "doc.on.clipboard",
                          text: "Click Get Add-ons, paste this code, then click OK.", copyable: code),
                    reopenAnki,
                ],
                start: .copyAndOpen(text: code, app: .anki),
                learnMore: URL(string: "https://ankiweb.net/shared/info/\(code)")
            )
        case .ankiAddOnUpdate:
            return ConnectionWalkthrough(
                title: "Update AnkiConnect",
                intro: "Your copy of AnkiConnect is too old for Tabbi. Anki can update it in a few clicks.",
                steps: [
                    .init(symbol: "menubar.rectangle", text: "In Anki's menu bar, click Tools, then Add-ons."),
                    .init(symbol: "arrow.triangle.2.circlepath",
                          text: "Click AnkiConnect in the list, then click Check for Updates."),
                    reopenAnki,
                ],
                start: .openApp(.anki)
            )
        case .ankiAccess:
            return ConnectionWalkthrough(
                title: "Let Tabbi into Anki",
                intro: "AnkiConnect's settings keep Tabbi out. Putting them back to normal fixes it and leaves your cards alone.",
                steps: [
                    .init(symbol: "menubar.rectangle",
                          text: "In Anki, click Tools, then Add-ons. Click AnkiConnect, then Config."),
                    .init(symbol: "arrow.uturn.backward", text: "Click Restore Defaults, then OK."),
                    .init(symbol: "checkmark.circle",
                          text: "Quit Anki and open it again. If it asks about Tabbi, click Yes."),
                ],
                start: .openApp(.anki)
            )
        case .googleCalendar:
            return ConnectionWalkthrough(
                title: "Add your Google Calendar",
                intro: "Tabbi shows the calendars your Mac knows about. Add your Google account once and its events show up.",
                steps: [
                    .init(symbol: "plus.circle",
                          text: "In Internet Accounts, click Add Account, then Google, and sign in."),
                    .init(symbol: "calendar", text: "Make sure Calendars is turned on for that account."),
                ],
                start: .openSettings(.internetAccounts)
            )
        case .claudeInstall:
            let command = ClaudeConnectionState.installCommand
            return ConnectionWalkthrough(
                title: "Set up Claude",
                intro: "Claude is an AI helper. Tabbi uses it to plan your day and answer questions. It's optional: everything else works without it.",
                steps: [
                    .init(symbol: "terminal",
                          text: "Click the button below. It copies the setup line and opens Terminal, an app that comes with your Mac."),
                    .init(symbol: "doc.on.clipboard",
                          text: "Click in the Terminal window, press Command-V to paste, then press Return.",
                          copyable: command),
                    .init(symbol: "person.crop.circle.badge.checkmark",
                          text: "When it's done, sign in with your Claude account. Tabbi notices by itself."),
                ],
                start: .copyAndOpen(text: command, app: .terminal),
                learnMore: ClaudeConnectionState.installPage
            )
        case .claudeSignIn:
            let command = ClaudeConnectionState.signInCommand
            return ConnectionWalkthrough(
                title: "Sign in to Claude",
                intro: "Claude is on your Mac. Sign in once and Tabbi can use it.",
                steps: [
                    .init(symbol: "terminal",
                          text: "Click the button below. It copies the sign-in line and opens Terminal."),
                    .init(symbol: "doc.on.clipboard",
                          text: "Click in the Terminal window, press Command-V to paste, then press Return.",
                          copyable: command),
                    .init(symbol: "safari", text: "Sign in on the page that opens. Tabbi notices by itself."),
                ],
                start: .copyAndOpen(text: command, app: .terminal),
                learnMore: ClaudeConnectionState.installPage
            )
        case .focusShortcuts:
            return ConnectionWalkthrough(
                title: "Set up Do Not Disturb",
                intro: "Your Mac lets apps switch Do Not Disturb only through shortcuts you make. Two small ones do it.",
                steps: [
                    .init(symbol: "plus.square",
                          text: "In Shortcuts, click the + button and name the new shortcut:", copyable: onShortcut),
                    .init(symbol: "moon.fill",
                          text: "Search for Set Focus, add it, and pick Do Not Disturb, turned On."),
                    .init(symbol: "moon",
                          text: "Make one more the same way, turned Off, and name it:", copyable: offShortcut),
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
    public let button = "Continue"
}

extension ConnectionPermission {
    public var priming: ConnectionPriming {
        switch self {
        case .calendar:
            ConnectionPriming(
                symbol: "calendar",
                title: "Show your calendar in Tabbi",
                message: "Next, your Mac asks if Tabbi can use your calendar. Click Allow.",
                points: ["Tabbi only reads events to show today's plan.",
                         "Claude only sees your events when you ask it to plan your day."]
            )
        case .notifications:
            ConnectionPriming(
                symbol: "bell.badge.fill",
                title: "Get a heads-up when time's up",
                message: "Next, your Mac asks if Tabbi can send alerts. Click Allow.",
                points: ["Tabbi only alerts you when a focus block or break ends.",
                         "You can turn alerts off any time in System Settings."]
            )
        case .automation(let app):
            ConnectionPriming(
                symbol: "music.note",
                title: "Control \(app.name) from the notch",
                message: "Next, your Mac asks if Tabbi can control \(app.name). Click Allow.",
                points: ["Tabbi only plays, pauses, skips and shows what's playing.",
                         "If \(app.name) isn't open, Tabbi opens it first so your Mac can ask."]
            )
        }
    }
}
