import Foundation

/// Where Party stands. There's no account to make: the user picks a name
/// and a pet once, and Tabbi registers by itself.
public enum PartyConnectionState: Hashable, Sendable {
    /// No name chosen yet.
    case notSetUp
    case connecting
    /// The server couldn't be reached.
    case offline
    case connected(friendCode: String)

    /// The state for the Party tab's connection and whether the user has
    /// picked a name.
    public static func resolve(_ connection: PartyState.Connection, friendCode: String?, hasChosenName: Bool) -> PartyConnectionState {
        guard hasChosenName else { return .notSetUp }
        switch connection {
        case .connecting: return .connecting
        case .invalidServer, .unreachable: return .offline
        case .connected: return friendCode.map { .connected(friendCode: $0) } ?? .connecting
        }
    }

    public var connectionStatus: ConnectionStatus {
        switch self {
        case .notSetUp:
            return ConnectionStatus(light: .notSetUp, headline: "Party isn't set up",
                                    detail: "Pick a name and a pet to start. No account needed.",
                                    action: .setUp)
        case .connecting:
            return ConnectionStatus(light: .checking, headline: "Connecting",
                                    detail: "This takes a second.")
        case .offline:
            return ConnectionStatus(light: .needsStep, headline: "Party can't connect",
                                    detail: "Check that your Wi-Fi is on, then try again.",
                                    action: .checkAgain)
        case .connected(let code):
            return ConnectionStatus(light: .connected, headline: "Party is ready",
                                    detail: "Your friend code is \(code). Share it so friends can add you.",
                                    suggestion: .copyFriendCode(code))
        }
    }
}

/// The one screen Party needs before it starts: the name and pet friends
/// see. Tabbi registers by itself once it's filled in, so there's no
/// account, email or password to make.
public enum PartySetup {
    public static let title = "Join Party"
    public static let intro = "Pick the name and pet your friends will see. No account or password needed."
    public static let nameLabel = "Your name"
    public static let namePlaceholder = "Like Sam or Dr. Sam"
    public static let petLabel = "Your pet"
    public static let petNote = "You can dress your pet up later in the Closet tab."
    public static let start = "Start Party"
    /// The header once Party is ready.
    public static let readyTitle = "You're in Party"
    public static let readyIntro = "Send friends your code so they can add you. They see your name, pet and study timer."

    /// The name to save, or nil while nothing usable is typed, so the
    /// start button stays off until there's a real name.
    public static func name(from text: String) -> String? {
        PartySettings(name: text).cleanedName
    }
}
