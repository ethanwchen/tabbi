import Foundation

/// Everything the Party tab shows, and how each server reply or failure
/// changes it. The app's store does the networking and feeds results in
/// here, so which screen appears (bad server, connecting, unreachable,
/// empty friends, in a party) is decided by tested, pure code.
///
/// A refresh that fails after data has loaded keeps that data on screen and
/// only records `staleError`, so a flaky network shows a quiet "offline"
/// hint instead of wiping the friends list.
public struct PartyState: Equatable, Sendable {
    public enum Connection: Equatable, Sendable {
        /// The server field in Settings can't be used; the message says why.
        case invalidServer(String)
        /// Registering or syncing the profile for the first time this run.
        case connecting
        /// The first connection failed; nothing has loaded yet.
        case unreachable(PartyError)
        /// The profile is synced and friend code known.
        case connected
    }

    public private(set) var connection: Connection
    /// My profile as the server last returned it.
    public private(set) var profile: PartyProfile?
    /// Friends in display order (`PartyRoster.sorted`).
    public private(set) var friends: [PartyFriend] = []
    /// Whether the friends list has loaded at least once, so "no friends
    /// yet" is never shown while it's still loading.
    public private(set) var friendsLoaded = false
    /// The party I'm in, members in display order; nil when in none.
    public private(set) var party: Party?
    /// The last refresh failed; what's on screen may be out of date.
    public private(set) var staleError: PartyError?

    public init(settings: PartySettings) {
        connection = settings.serverIssue.map(Connection.invalidServer) ?? .connecting
    }

    /// A state with data already loaded, for demo mode and previews.
    public init(profile: PartyProfile, friends: [PartyFriend], party: Party?) {
        connection = .connected
        self.profile = profile
        self.friends = PartyRoster.sorted(friends)
        friendsLoaded = true
        self.party = party.map(Self.ordered)
    }

    // MARK: Derived

    public var friendCode: String? { profile?.code }
    public var inParty: Bool { party != nil }

    /// Whether I host the current party and so control its session.
    public var isHost: Bool {
        guard let party, let code = profile?.code else { return false }
        return party.isHost(code)
    }

    /// The other members of my party, for the pets beside mine in the
    /// closed notch; empty when I'm not in a party.
    public var companions: [PartyMember] {
        party?.members.filter { $0.profile.code != profile?.code } ?? []
    }

    // MARK: Transitions

    /// Starts over after the server setting changed: drops everything that
    /// belonged to the old server.
    public mutating func reset(settings: PartySettings) {
        self = PartyState(settings: settings)
    }

    /// The profile synced (or registered).
    public mutating func didConnect(_ profile: PartyProfile) {
        self.profile = profile
        connection = .connected
        staleError = nil
    }

    /// Registering or syncing the profile failed. Once connected, the old
    /// data stays and the failure only marks it stale.
    public mutating func didFailToConnect(_ error: PartyError) {
        if connection == .connected {
            staleError = error
        } else if case .invalidServer = connection {
            return
        } else {
            connection = .unreachable(error)
        }
    }

    /// Retrying after `unreachable`.
    public mutating func willReconnect() {
        if case .unreachable = connection { connection = .connecting }
    }

    public mutating func didFetchFriends(_ result: Result<[PartyFriend], PartyError>) {
        switch result {
        case .success(let friends):
            self.friends = PartyRoster.sorted(friends)
            friendsLoaded = true
            staleError = nil
        case .failure(let error):
            staleError = error
        }
    }

    /// A party fetch, or the reply to create, join, leave or a session
    /// change. `notInParty` and `partyNotFound` mean the party is gone.
    public mutating func didFetchParty(_ result: Result<Party?, PartyError>) {
        switch result {
        case .success(let party):
            self.party = party.map(Self.ordered)
            staleError = nil
        case .failure(.notInParty), .failure(.partyNotFound):
            party = nil
        case .failure(let error):
            staleError = error
        }
    }

    /// A friend was added: shown right away, before the next list refresh
    /// brings their presence.
    public mutating func didAddFriend(_ profile: PartyProfile, at now: Date) {
        guard !friends.contains(where: { $0.profile.code == profile.code }) else { return }
        friends = PartyRoster.sorted(friends + [PartyFriend(profile: profile, since: now, presence: nil, online: false, party: nil)])
        friendsLoaded = true
    }

    public mutating func didRemoveFriend(code: String) {
        friends.removeAll { $0.profile.code == code }
    }

    private static func ordered(_ party: Party) -> Party {
        var party = party
        party.members = PartyRoster.sorted(party.members)
        return party
    }
}
