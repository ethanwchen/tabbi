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
            return ConnectionStatus(light: .notSetUp, headline: "Study with friends",
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
                                    detail: "Your friend code is \(code). Share it so friends can add you.")
        }
    }
}
