import Foundation

/// The confirmation an invite link opens in the Party tab, from "Turn on
/// Party?" through "Add a friend?" to "Maya is now your friend". The app
/// feeds it the Party state and the server's answers; which step shows,
/// and what it says, is decided here so it can be tested.
///
/// Nothing happens without a click: a link only asks. Checks that need no
/// server (my own code, someone already a friend, someone I blocked, the
/// party I'm already in) answer before anything is sent, and the server's
/// refusals (unknown or expired codes, limits, moderation) end in a
/// friendly sentence rather than a raw error.
public struct PartyInviteFlow: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        /// The Party tab is off; the link asks to turn it on first.
        case needsParty
        /// Waiting for Party to connect and load the friends list.
        case connecting
        /// Party can't connect; "Try Again" shows when the problem may pass.
        case unavailable(PartyError)
        /// Party waits for its age check (`PartyAgeCheck`), which the Party
        /// tab asks; `tooYoungUntil` is set when it said under 13.
        case ageCheck(tooYoungUntil: Date?)
        /// Asking "Add a friend?" or "Join this party?".
        case confirming
        /// The request is on its way.
        case working
        /// Done: the friend was added or the party joined.
        case finished(Outcome)
        /// Not done, and why.
        case refused(Refusal)
    }

    public enum Outcome: Equatable, Sendable {
        case added(PartyProfile)
        case alreadyFriends(PartyProfile)
        case joined(Party)
        case alreadyInParty
    }

    public enum Refusal: Equatable, Sendable {
        /// The link carries my own friend code.
        case ownCode
        /// I blocked the person behind the link.
        case blocked(name: String)
        /// The server said no.
        case failed(PartyError)
    }

    public let invite: PartyInvite
    public private(set) var stage: Stage
    /// The party I was in when asked, so the question can say joining leaves it.
    public private(set) var currentParty: String?

    public init(invite: PartyInvite, partyIsOn: Bool) {
        self.invite = invite
        stage = partyIsOn ? .connecting : .needsParty
    }

    // MARK: Steps

    /// The user turned Party on from the first question.
    public mutating func partyTurnedOn() {
        guard stage == .needsParty else { return }
        stage = .connecting
    }

    /// The user asked to try connecting again after `.unavailable`.
    public mutating func retryConnecting() {
        guard case .unavailable = stage else { return }
        stage = .connecting
    }

    /// Follows the Party state while connecting: moves on once it is
    /// connected (and, for a friend link, the friends list has loaded so
    /// "already friends" can be told apart), or stops on a connection
    /// failure. `blocked` is the Blocked list when it has loaded.
    public mutating func update(with state: PartyState, blocked: [PartyBlockedUser]?) {
        guard stage == .connecting else { return }
        switch state.connection {
        case .invalidServer:
            stage = .unavailable(.invalidRequest("server"))
            return
        case .unreachable(let error):
            stage = .unavailable(error)
            return
        case .ageCheck(let until):
            stage = .ageCheck(tooYoungUntil: until)
            return
        case .connecting:
            return
        case .connected:
            break
        }
        switch invite {
        case .addFriend(let code):
            guard state.friendsLoaded else { return }
            if code == state.friendCode {
                stage = .refused(.ownCode)
            } else if let friend = state.friends.first(where: { $0.profile.code == code }) {
                stage = .finished(.alreadyFriends(friend.profile))
            } else if let user = blocked?.first(where: { $0.code == code }) {
                stage = .refused(.blocked(name: user.name))
            } else {
                stage = .confirming
            }
        case .joinParty(let code):
            if state.party?.code == code {
                stage = .finished(.alreadyInParty)
            } else {
                currentParty = state.party?.code
                stage = .confirming
            }
        }
    }

    /// The user confirmed, or asked to try a failed request again. Returns
    /// whether the app should now send the request.
    public mutating func begin() -> Bool {
        switch stage {
        case .confirming:
            break
        case .refused(.failed(let error)) where error.isTransient:
            break
        default:
            return false
        }
        stage = .working
        return true
    }

    /// The server added the friend (`added` false: they already were).
    public mutating func didAddFriend(_ profile: PartyProfile, added: Bool) {
        guard stage == .working, case .addFriend = invite else { return }
        stage = .finished(added ? .added(profile) : .alreadyFriends(profile))
    }

    public mutating func didJoin(_ party: Party) {
        guard stage == .working, case .joinParty = invite else { return }
        stage = .finished(.joined(party))
    }

    public mutating func didFail(_ error: PartyError) {
        guard stage == .working else { return }
        stage = .refused(.failed(error))
    }

    // MARK: Copy

    /// Whether the flow is over and only needs closing.
    public var isDone: Bool {
        switch stage {
        case .finished: true
        case .refused(.failed(let error)): !error.isTransient
        case .refused: true
        case .ageCheck(let until): until != nil
        default: false
        }
    }

    /// The person behind the link, once known.
    public var person: PartyProfile? {
        switch stage {
        case .finished(.added(let profile)), .finished(.alreadyFriends(let profile)): profile
        default: nil
        }
    }

    public var title: String {
        switch stage {
        case .needsParty: "Turn on Party?"
        case .connecting: "Connecting to Party"
        case .unavailable, .ageCheck(tooYoungUntil: .some): "Party isn't available"
        case .ageCheck: "One question first"
        case .confirming, .working:
            switch invite {
            case .addFriend: "Add a friend?"
            case .joinParty: "Join this party?"
            }
        case .finished(.added(let profile)): "\(profile.name) is now your friend"
        case .finished(.alreadyFriends(let profile)): "\(profile.name) is already your friend"
        case .finished(.joined): "You joined the party"
        case .finished(.alreadyInParty): "You're already in this party"
        case .refused(.ownCode): "That's your own link"
        case .refused(.blocked(let name)): "You blocked \(name)"
        case .refused(.failed): failedTitle
        }
    }

    public var message: String {
        switch stage {
        case .needsParty:
            switch invite {
            case .addFriend: return "Party lets you study beside friends. Turn it on to add this friend."
            case .joinParty: return "Party lets you study beside friends. Turn it on to join this party."
            }
        case .connecting:
            return "One moment."
        case .ageCheck(.some):
            return "Party is for people \(PartyAgeCheck.minimumAge) and older."
        case .ageCheck:
            return "The Party tab asks when you were born before you join. Then open the link again."
        case .unavailable(let error):
            if case .invalidRequest = error { return "Check the server in Party options." }
            return error.message
        case .confirming, .working:
            switch invite {
            case .addFriend(let code):
                return "Friend code \(Self.display(code)). You'll see each other's pets and study time."
            case .joinParty(let code):
                let leaving = currentParty == nil ? "" : " You'll leave your current party."
                return "Party code \(code). Study together with everyone in it.\(leaving)"
            }
        case .finished(.added(let profile)), .finished(.alreadyFriends(let profile)):
            return "You'll see \(profile.petName) in your Party tab."
        case .finished(.joined(let party)):
            let others = party.members.count - 1
            switch others {
            case ..<1: return "You're the only one here for now."
            case 1: return "1 friend is here with you."
            default: return "\(others) friends are here with you."
            }
        case .finished(.alreadyInParty):
            return "Nothing to do."
        case .refused(.ownCode):
            return "Share it with a friend so they can add you."
        case .refused(.blocked):
            return "Unblock them in Party options to add them again."
        case .refused(.failed(let error)):
            return failedMessage(error)
        }
    }

    /// The main button, or `nil` when there is nothing to do but close.
    public var primaryTitle: String? {
        switch stage {
        case .needsParty: return "Turn On Party"
        case .unavailable(let error): return error.isTransient ? "Try Again" : nil
        case .ageCheck(nil): return "Open Party"
        case .confirming, .working:
            switch invite {
            case .addFriend: return "Add Friend"
            case .joinParty: return "Join Party"
            }
        case .refused(.failed(let error)): return error.isTransient ? "Try Again" : nil
        default: return nil
        }
    }

    /// The other button: "Not Now" while asking, "Done" once over.
    public var dismissTitle: String { isDone ? "Done" : "Not Now" }

    private var failedTitle: String {
        switch invite {
        case .addFriend: "Couldn't add this friend"
        case .joinParty: "Couldn't join this party"
        }
    }

    /// Server refusals in the words of an invite: a code from a link is
    /// rarely mistyped, so it most likely expired or was changed.
    private func failedMessage(_ error: PartyError) -> String {
        switch error {
        case .unknownCode: "This link doesn't match anyone now. Ask your friend for a new one."
        case .partyNotFound: "That party has ended. Ask for a new link."
        case .rateLimited: "Too many tries for now. Wait a minute, then try again."
        case .selfFriend: "That's your own link."
        default: error.message
        }
    }

    /// "K7QW-2MZD": friend codes read more easily in two groups of four.
    private static func display(_ code: String) -> String {
        guard code.count > 6 else { return code }
        let split = code.index(code.startIndex, offsetBy: code.count / 2)
        return code[..<split] + "-" + code[split...]
    }
}
