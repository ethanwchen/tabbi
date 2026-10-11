import Foundation

/// Where Party stands. There's no account to make: the user picks a name
/// and a pet once, and Tabbi registers by itself.
public enum PartyConnectionState: Hashable, Sendable {
    /// No name chosen yet.
    case notSetUp
    /// Waiting for the age check, which the Party tab asks
    /// (`PartyAgeCheck`); `tooYoungUntil` is set when it said under 13.
    case ageCheck(tooYoungUntil: Date?)
    case connecting
    /// The server couldn't be reached.
    case offline
    case connected(friendCode: String)

    /// The state for the Party tab's connection and whether the user has
    /// picked a name.
    public static func resolve(_ connection: PartyState.Connection, friendCode: String?, hasChosenName: Bool) -> PartyConnectionState {
        if case .ageCheck(let until) = connection { return .ageCheck(tooYoungUntil: until) }
        guard hasChosenName else { return .notSetUp }
        switch connection {
        case .ageCheck(let until): return .ageCheck(tooYoungUntil: until)
        case .connecting: return .connecting
        case .invalidServer, .unreachable: return .offline
        case .connected: return friendCode.map { .connected(friendCode: $0) } ?? .connecting
        }
    }

    public var connectionStatus: ConnectionStatus {
        switch self {
        case .notSetUp:
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "Party isn't set up", bundle: .tabbi),
                                    detail: String(localized: "Pick a name and a pet to start. No account needed.", bundle: .tabbi),
                                    action: .setUp)
        case .ageCheck(nil):
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "Party isn't set up", bundle: .tabbi),
                                    detail: String(localized: "Pick a name and a pet, and say when you were born.", bundle: .tabbi),
                                    action: .setUp)
        case .ageCheck:
            // Nothing to fix: Party opens once the user is 13, which
            // Check Again (or opening the Party tab) notices.
            return ConnectionStatus(light: .notSetUp, headline: String(localized: "Party isn't available", bundle: .tabbi),
                                    detail: String(localized: "It's for people \(PartyAgeCheck.minimumAge) and older.", bundle: .tabbi),
                                    action: .checkAgain)
        case .connecting:
            return ConnectionStatus(light: .checking, headline: String(localized: "Connecting", bundle: .tabbi),
                                    detail: String(localized: "This takes a second.", bundle: .tabbi))
        case .offline:
            return ConnectionStatus(light: .needsStep, headline: String(localized: "Party can't connect", bundle: .tabbi),
                                    detail: String(localized: "Check that your Wi-Fi is on, then try again.", bundle: .tabbi),
                                    action: .checkAgain)
        case .connected(let code):
            return ConnectionStatus(light: .connected, headline: String(localized: "Party is ready", bundle: .tabbi),
                                    detail: String(localized: "Your friend code is \(code). Share it so friends can add you.", bundle: .tabbi),
                                    suggestion: .copyFriendCode(code))
        }
    }
}

/// The one screen Party needs before it starts: the name and pet friends
/// see. Tabbi registers by itself once it's filled in, so there's no
/// account, email or password to make.
public enum PartySetup {
    public static var title: String { String(localized: "Join Party", bundle: .tabbi) }
    public static var intro: String { String(localized: "Pick the name and pet your friends will see. No account or password needed.", bundle: .tabbi) }
    public static var nameLabel: String { String(localized: "Your name", bundle: .tabbi) }
    public static var namePlaceholder: String { String(localized: "Like Sam or Dr. Sam", bundle: .tabbi) }
    public static var petLabel: String { String(localized: "Your pet", bundle: .tabbi) }
    public static var petNote: String { String(localized: "You can dress your pet up later in the Closet tab.", bundle: .tabbi) }
    public static var start: String { String(localized: "Start Party", bundle: .tabbi) }
    public static var birthLabel: String { String(localized: "When were you born?", bundle: .tabbi) }
    public static var birthNote: String { String(localized: "Asked once. Your answer stays on this Mac.", bundle: .tabbi) }
    /// The agreement under the age check, as Markdown with both links.
    public static var agreement: String {
        String(localized: "By joining you agree to the [Terms of Use](\(SupportContact.termsURL.absoluteString)) and the [Privacy Policy](\(SupportContact.privacyURL.absoluteString)).", bundle: .tabbi)
    }
    /// The header once Party is ready.
    public static var readyTitle: String { String(localized: "You're in Party", bundle: .tabbi) }
    public static var readyIntro: String { String(localized: "Send friends your code so they can add you. They see your name, pet and study timer.", bundle: .tabbi) }

    /// The name to save, or nil while nothing usable is typed, so the
    /// start button stays off until there's a real name.
    public static func name(from text: String) -> String? {
        PartySettings(name: text).cleanedName
    }
}
