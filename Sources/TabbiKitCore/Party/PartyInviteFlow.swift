import Foundation

/// The confirmation an invite link opens in the Party tab, from "Turn on
/// Party?" through "Add a friend?" to "Request sent to Maya" (or "Maya is
/// now your friend" when Maya had asked first). The app
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
        /// Done: the friend was asked or added, or the party joined.
        case finished(Outcome)
        /// Not done, and why.
        case refused(Refusal)
    }

    public enum Outcome: Equatable, Sendable {
        case added(PartyProfile)
        case alreadyFriends(PartyProfile)
        /// My friend request waits for them to accept.
        case requested(PartyProfile)
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
    /// The person behind a friend link when they already asked me to be
    /// friends, so confirming accepts their request.
    public private(set) var asker: PartyProfile?

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
            } else if let sent = state.outgoingRequests.first(where: { $0.profile.code == code }) {
                stage = .finished(.requested(sent.profile))
            } else if let user = blocked?.first(where: { $0.code == code }) {
                stage = .refused(.blocked(name: user.name))
            } else {
                asker = state.incomingRequests.first { $0.profile.code == code }?.profile
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

    /// The server's answer to asking the person behind the link.
    public mutating func didAsk(_ addition: PartyFriendAddition) {
        guard stage == .working, case .addFriend = invite else { return }
        switch addition {
        case .friends(let profile): stage = .finished(.added(profile))
        case .alreadyFriends(let profile): stage = .finished(.alreadyFriends(profile))
        case .requested(let profile): stage = .finished(.requested(profile))
        }
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
        case .finished(.added(let profile)), .finished(.alreadyFriends(let profile)), .finished(.requested(let profile)): profile
        default: nil
        }
    }

    public var title: String {
        switch stage {
        case .needsParty: String(localized: "Turn on Party?", bundle: .tabbi)
        case .connecting: String(localized: "Connecting to Party", bundle: .tabbi)
        case .unavailable, .ageCheck(tooYoungUntil: .some): String(localized: "Party isn't available", bundle: .tabbi)
        case .ageCheck: String(localized: "One question first", bundle: .tabbi)
        case .confirming, .working:
            switch invite {
            case .addFriend:
                if let asker {
                    String(localized: "\(asker.name) wants to be friends", bundle: .tabbi)
                } else {
                    String(localized: "Add a friend?", bundle: .tabbi)
                }
            case .joinParty: String(localized: "Join this party?", bundle: .tabbi)
            }
        case .finished(.requested(let profile)): String(localized: "Request sent to \(profile.name)", bundle: .tabbi)
        case .finished(.added(let profile)): String(localized: "\(profile.name) is now your friend", bundle: .tabbi)
        case .finished(.alreadyFriends(let profile)): String(localized: "\(profile.name) is already your friend", bundle: .tabbi)
        case .finished(.joined): String(localized: "You joined the party", bundle: .tabbi)
        case .finished(.alreadyInParty): String(localized: "You're already in this party", bundle: .tabbi)
        case .refused(.ownCode): String(localized: "That's your own link", bundle: .tabbi)
        case .refused(.blocked(let name)): String(localized: "You blocked \(name)", bundle: .tabbi)
        case .refused(.failed): failedTitle
        }
    }

    public var message: String {
        switch stage {
        case .needsParty:
            switch invite {
            case .addFriend: return String(localized: "Party lets you study beside friends. Turn it on to add this friend.", bundle: .tabbi)
            case .joinParty: return String(localized: "Party lets you study beside friends. Turn it on to join this party.", bundle: .tabbi)
            }
        case .connecting:
            return String(localized: "One moment.", bundle: .tabbi)
        case .ageCheck(.some):
            return String(localized: "Party is for people \(PartyAgeCheck.minimumAge) and older.", bundle: .tabbi)
        case .ageCheck:
            return String(localized: "The Party tab asks when you were born before you join. Then open the link again.", bundle: .tabbi)
        case .unavailable(let error):
            if case .invalidRequest = error { return String(localized: "Check the server in Party options.", bundle: .tabbi) }
            return error.message
        case .confirming, .working:
            switch invite {
            case .addFriend(let code):
                if asker != nil {
                    return String(localized: "Friend code \(Self.display(code)). Accept to see each other's pets and study time.", bundle: .tabbi)
                }
                return String(localized: "Friend code \(Self.display(code)). Once they accept, you'll see each other's pets and study time.", bundle: .tabbi)
            case .joinParty(let code):
                if currentParty == nil {
                    return String(localized: "Party code \(code). Study together with everyone in it.", bundle: .tabbi)
                }
                return String(localized: "Party code \(code). Study together with everyone in it. You'll leave your current party.", bundle: .tabbi)
            }
        case .finished(.added(let profile)), .finished(.alreadyFriends(let profile)):
            return String(localized: "You'll see \(profile.petName) in your Party tab.", bundle: .tabbi)
        case .finished(.requested):
            return String(localized: "You'll be friends once they accept.", bundle: .tabbi)
        case .finished(.joined(let party)):
            let others = party.members.count - 1
            if others < 1 { return String(localized: "You're the only one here for now.", bundle: .tabbi) }
            return String(localized: "\(others) friends are here with you.", bundle: .tabbi)
        case .finished(.alreadyInParty):
            return String(localized: "Nothing to do.", bundle: .tabbi)
        case .refused(.ownCode):
            return String(localized: "Share it with a friend so they can add you.", bundle: .tabbi)
        case .refused(.blocked):
            return String(localized: "Unblock them in Party options to add them again.", bundle: .tabbi)
        case .refused(.failed(let error)):
            return failedMessage(error)
        }
    }

    /// The main button, or `nil` when there is nothing to do but close.
    public var primaryTitle: String? {
        switch stage {
        case .needsParty: return String(localized: "Turn On Party", bundle: .tabbi)
        case .unavailable(let error): return error.isTransient ? String(localized: "Try Again", bundle: .tabbi) : nil
        case .ageCheck(nil): return String(localized: "Open Party", bundle: .tabbi)
        case .confirming, .working:
            switch invite {
            case .addFriend:
                return asker == nil ? String(localized: "Add Friend", bundle: .tabbi) : String(localized: "Accept", bundle: .tabbi)
            case .joinParty: return String(localized: "Join Party", bundle: .tabbi)
            }
        case .refused(.failed(let error)): return error.isTransient ? String(localized: "Try Again", bundle: .tabbi) : nil
        default: return nil
        }
    }

    /// The other button: "Not Now" while asking, "Done" once over.
    public var dismissTitle: String { isDone ? String(localized: "Done", bundle: .tabbi) : String(localized: "Not Now", bundle: .tabbi) }

    private var failedTitle: String {
        switch invite {
        case .addFriend: String(localized: "Couldn't add this friend", bundle: .tabbi)
        case .joinParty: String(localized: "Couldn't join this party", bundle: .tabbi)
        }
    }

    /// Server refusals in the words of an invite: a code from a link is
    /// rarely mistyped, so it most likely expired or was changed.
    private func failedMessage(_ error: PartyError) -> String {
        switch error {
        case .unknownCode: String(localized: "This link doesn't match anyone now. Ask your friend for a new one.", bundle: .tabbi)
        case .partyNotFound: String(localized: "That party has ended. Ask for a new link.", bundle: .tabbi)
        case .rateLimited: String(localized: "Too many tries for now. Wait a minute, then try again.", bundle: .tabbi)
        case .selfFriend: String(localized: "That's your own link.", bundle: .tabbi)
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
