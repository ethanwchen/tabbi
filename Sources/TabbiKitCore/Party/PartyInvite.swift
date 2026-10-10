import Foundation

/// A Party invite link: a friend code to add or a party code to join.
/// People share the web form (`https://tabbinotch.com/add/K7QW2MZD`), whose
/// page hands off to the app form (`tabbi://add/K7QW2MZD`) when Tabbi is
/// installed. Both come from outside the app, so parsing is strict: only
/// these two hosts, these two actions and a code that passes `PartyCode`;
/// anything else is not an invite.
public enum PartyInvite: Hashable, Sendable {
    case addFriend(code: String)
    case joinParty(code: String)

    /// The app's URL scheme, registered in Info.plist.
    public static let scheme = "tabbi"
    /// The website that serves the invite pages.
    public static let webHost = "tabbinotch.com"

    /// The path word for each action: `add` and `join`.
    public enum Action {
        public static let addFriend = "add"
        public static let joinParty = "join"
    }

    /// The invite in `url`, or `nil` unless it is a well-formed invite with
    /// a valid code. Codes are normalized (upper-cased, dashes dropped), so
    /// a hand-typed `tabbi://add/k7qw-2mzd` works. Query and fragment are
    /// ignored.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        let host = components.host?.lowercased() ?? ""
        let path = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let action: String
        let rawCode: String
        switch scheme {
        case Self.scheme:
            // tabbi://add/CODE: the action is the host.
            guard path.count == 1 else { return nil }
            action = host
            rawCode = path[0]
        case "https":
            guard host == Self.webHost || host == "www." + Self.webHost,
                  components.port == nil, path.count == 2 else { return nil }
            action = path[0].lowercased()
            rawCode = path[1]
        default:
            return nil
        }
        // A percent-encoded code is not one we hand out; reject rather than decode.
        guard !rawCode.contains("%") else { return nil }
        switch action {
        case Action.addFriend:
            guard let code = PartyCode.friendCode(rawCode) else { return nil }
            self = .addFriend(code: code)
        case Action.joinParty:
            guard let code = PartyCode.partyCode(rawCode) else { return nil }
            self = .joinParty(code: code)
        default:
            return nil
        }
    }

    /// The normalized friend or party code.
    public var code: String {
        switch self {
        case .addFriend(let code), .joinParty(let code): code
        }
    }

    private var action: String {
        switch self {
        case .addFriend: Action.addFriend
        case .joinParty: Action.joinParty
        }
    }

    /// The link to share, which works whether or not the friend has Tabbi.
    public var webURL: URL {
        URL(string: "https://\(Self.webHost)/\(action)/\(code)")!
    }

    /// The link that opens Tabbi directly.
    public var appURL: URL {
        URL(string: "\(Self.scheme)://\(action)/\(code)")!
    }
}
