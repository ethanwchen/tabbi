import XCTest
import TabbiKitCore

final class PartyStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func profile(_ code: String, _ name: String) -> PartyProfile {
        PartyProfile(code: code, name: name, petName: "Mochi", species: "cat", breed: "tabby")
    }

    private func friend(_ code: String, _ name: String, online: Bool = true, status: PartyStatus = .idle) -> PartyFriend {
        PartyFriend(profile: profile(code, name), since: now,
                    presence: PartyPresence(status: status, day: "2026-09-21", lastSeen: now),
                    online: online, party: nil)
    }

    private func party(host: String, members: [(String, String)]) -> Party {
        Party(code: "Q4RT8M", host: host, createdAt: now, lastActive: now, expiresAt: now.addingTimeInterval(3600),
              maxMembers: 8, session: nil,
              members: members.map { PartyMember(profile: profile($0.0, $0.1), joinedAt: now, host: $0.0 == host, presence: nil, online: true) })
    }

    func testStartsConnectingOrReportsABadServer() {
        XCTAssertEqual(PartyState(settings: .oldEnough).connection, .connecting)
        let bad = PartyState(settings: PartySettings(serverText: "http://example.com"))
        guard case .invalidServer(let message) = bad.connection else { return XCTFail("expected invalidServer") }
        XCTAssertFalse(message.isEmpty)

        var state = bad
        state.didFailToConnect(.unreachable)
        XCTAssertEqual(state.connection, bad.connection, "a bad server isn't masked by network errors")
    }

    func testFirstFailureIsUnreachableAndRetryGoesBackToConnecting() {
        var state = PartyState(settings: .oldEnough)
        state.didFailToConnect(.timedOut)
        XCTAssertEqual(state.connection, .unreachable(.timedOut))

        state.willReconnect()
        XCTAssertEqual(state.connection, .connecting)

        state.didConnect(profile("K7QW2MZD", "Sam"))
        XCTAssertEqual(state.connection, .connected)
        XCTAssertEqual(state.friendCode, "K7QW2MZD")
    }

    func testFailuresAfterLoadingKeepTheDataAndMarkItStale() {
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile("K7QW2MZD", "Sam"))
        XCTAssertFalse(state.friendsLoaded, "no empty state before the first list arrives")
        state.didFetchFriends(.success([friend("B", "Ben")]))

        state.didFetchFriends(.failure(.unreachable))
        state.didFailToConnect(.serverUnavailable)

        XCTAssertEqual(state.connection, .connected)
        XCTAssertEqual(state.friends.map(\.profile.name), ["Ben"])
        XCTAssertEqual(state.staleError, .serverUnavailable)

        state.didFetchFriends(.success([]))
        XCTAssertNil(state.staleError)
        XCTAssertTrue(state.friendsLoaded)
        XCTAssertTrue(state.friends.isEmpty)
    }

    func testFriendsAreSortedAndEditedLocally() {
        var state = PartyState(settings: .oldEnough)
        state.didFetchFriends(.success([
            friend("O", "Olive", online: false),
            friend("S", "Sky", status: .studying),
            friend("A", "Ash"),
        ]))
        XCTAssertEqual(state.friends.map(\.profile.name), ["Sky", "Ash", "Olive"])

        state.didAddFriend(profile("B", "Bea"), at: now)
        state.didAddFriend(profile("B", "Bea"), at: now)
        XCTAssertEqual(state.friends.map(\.profile.name), ["Sky", "Ash", "Bea", "Olive"],
                       "a new friend shows once, offline until the next refresh")

        state.didRemoveFriend(code: "S")
        XCTAssertEqual(state.friends.map(\.profile.name), ["Ash", "Bea", "Olive"])
    }

    func testBlockingHidesThemFromFriendsAndTheParty() {
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile("ME", "Sam"))
        state.didFetchFriends(.success([friend("A", "Ash"), friend("Z", "Zoe")]))
        state.didFetchParty(.success(party(host: "ME", members: [("Z", "Zoe"), ("ME", "Sam"), ("A", "Ash")])))

        state.didBlock(code: "Z")

        XCTAssertEqual(state.friends.map(\.profile.name), ["Ash"])
        XCTAssertEqual(state.party?.members.map(\.profile.name), ["Sam", "Ash"])
        XCTAssertTrue(state.isHost)
    }

    func testPartyMembershipHostAndCompanions() {
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile("ME", "Sam"))
        state.didFetchParty(.success(party(host: "ME", members: [("Z", "Zoe"), ("ME", "Sam"), ("A", "Ash")])))

        XCTAssertTrue(state.inParty)
        XCTAssertTrue(state.isHost)
        XCTAssertEqual(state.party?.members.map(\.profile.name), ["Sam", "Ash", "Zoe"], "host first, then by name")
        XCTAssertEqual(state.companions.map(\.profile.name), ["Ash", "Zoe"])

        state.didFetchParty(.success(party(host: "Z", members: [("Z", "Zoe"), ("ME", "Sam")])))
        XCTAssertFalse(state.isHost)

        state.didFetchParty(.failure(.unreachable))
        XCTAssertTrue(state.inParty, "a network blip keeps the party")

        state.didFetchParty(.failure(.notInParty))
        XCTAssertFalse(state.inParty)
        XCTAssertTrue(state.companions.isEmpty)
    }

    func testResetDropsTheOldServersData() {
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile("ME", "Sam"))
        state.didFetchFriends(.success([friend("B", "Ben")]))

        state.reset(settings: PartySettings(serverText: "http://localhost:8787", ageEligibleFrom: .distantPast))

        XCTAssertEqual(state.connection, .connecting)
        XCTAssertNil(state.friendCode)
        XCTAssertTrue(state.friends.isEmpty)
    }

    func testDemoCoversEveryStatusAndAJoinableParty() {
        let state = PartyState.demo(now: now)

        XCTAssertEqual(state.connection, .connected)
        XCTAssertTrue(state.isHost)
        XCTAssertEqual(state.companions.count, 2)
        XCTAssertNotNil(state.party?.session)
        let statuses = Set(state.friends.map { PartyRoster.status($0.presence, online: $0.online) })
        XCTAssertEqual(statuses, [.studying, .onBreak, .offline])
        XCTAssertTrue(state.friends.contains { $0.canJoin && $0.party?.code != state.party?.code },
                      "one friend is in another party, to show Join")
        for member in state.party?.members ?? [] {
            XCTAssertEqual(PartyPetAppearance.pet(for: member.profile).name, member.profile.petName,
                           "demo pets come from real appearance data")
        }
    }

    func testDemoScenariosCoverEveryScreen() {
        func demo(_ scenario: PartyDemoScenario) -> PartyState { PartyState.demo(scenario, now: now) }

        XCTAssertEqual(demo(.hosting), PartyState.demo(now: now))
        let guest = demo(.guest)
        XCTAssertFalse(guest.isHost)
        XCTAssertNil(guest.party?.session)
        XCTAssertEqual(guest.party?.members.first?.host, true, "the host stands first")
        XCTAssertEqual(guest.party?.members.filter(\.host).count, 1)
        let member = demo(.member)
        XCTAssertFalse(member.isHost)
        XCTAssertEqual(member.session(at: now)?.hostName, "Maya")
        XCTAssertEqual(member.session(at: now)?.friendCount, 2)
        let crowded = demo(.crowded)
        XCTAssertTrue(crowded.isHost)
        XCTAssertEqual(crowded.party?.isFull, true)
        XCTAssertEqual(Set(crowded.party?.members.map(\.id) ?? []).count, 8)
        XCTAssertFalse(demo(.lobby).inParty)
        XCTAssertFalse(demo(.lobby).friends.isEmpty)
        let noFriends = demo(.noFriends)
        XCTAssertTrue(noFriends.friendsLoaded)
        XCTAssertTrue(noFriends.friends.isEmpty)
        XCTAssertNotNil(noFriends.friendCode)
        XCTAssertEqual(demo(.hosting).incomingRequests.map(\.profile.name), ["Noor"], "the demo shows one incoming request")
        XCTAssertEqual(demo(.hosting).waitingRequestCount, 1)
        XCTAssertTrue(demo(.requests).friends.isEmpty)
        XCTAssertEqual(demo(.requests).outgoingRequests.count, 1)
        XCTAssertTrue(demo(.requests).hasPeople)
        XCTAssertFalse(demo(.noFriends).hasPeople)
        XCTAssertEqual(demo(.connecting).connection, .connecting)
        XCTAssertEqual(demo(.unreachable).connection, .unreachable(.unreachable))
        guard case .invalidServer = demo(.invalidServer).connection else {
            return XCTFail("expected an invalid server")
        }
    }

    private func request(_ code: String, _ name: String) -> PartyFriendRequest {
        PartyFriendRequest(profile: profile(code, name), since: now)
    }

    func testFriendRequestsLoadAndSettle() {
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile("K7QW2MZD", "Sam"))
        state.didFetchFriendList(.success(PartyFriendList(friends: [friend("B", "Ben")],
                                                          incoming: [request("N", "Noor"), request("O", "Omar")],
                                                          outgoing: [request("K", "Kai")])))
        XCTAssertEqual(state.incomingRequests.map(\.id), ["N", "O"])
        XCTAssertEqual(state.waitingRequestCount, 2)

        state.didAddFriend(profile("N", "Noor"), at: now)
        XCTAssertEqual(state.incomingRequests.map(\.id), ["O"], "accepting settles the request")
        XCTAssertEqual(state.waitingRequestCount, 1)
        XCTAssertEqual(state.friends.map(\.profile.name), ["Ben", "Noor"])

        state.didRemoveFriend(code: "O")
        XCTAssertEqual(state.incomingRequests, [], "declining drops it")
        XCTAssertEqual(state.waitingRequestCount, 0)
        state.didRemoveFriend(code: "K")
        XCTAssertEqual(state.outgoingRequests, [], "cancelling drops mine")
        XCTAssertEqual(state.friends.count, 2)
    }

    func testAskingShowsTheRequestOrTheFriendAtOnce() {
        var state = PartyState(profile: profile("K7QW2MZD", "Sam"), friends: [], party: nil)
        state.didAsk(.requested(profile("K", "Kai")), at: now)
        state.didAsk(.requested(profile("K", "Kai")), at: now)
        XCTAssertEqual(state.outgoingRequests.map(\.id), ["K"], "asking twice keeps one row")
        XCTAssertTrue(state.hasPeople)

        state.didAsk(.friends(profile("K", "Kai")), at: now)
        XCTAssertEqual(state.outgoingRequests, [])
        XCTAssertEqual(state.friends.map(\.id), ["K"])
    }

    func testAHeartbeatCountsWaitingRequestsForTheBadge() {
        var state = PartyState(profile: profile("K7QW2MZD", "Sam"), friends: [], party: nil)
        XCTAssertEqual(state.waitingRequestCount, 0)
        state.didCountWaitingRequests(3)
        XCTAssertEqual(state.waitingRequestCount, 3, "the badge follows heartbeats while the list is not loaded")
        state.didFetchFriendList(.success(PartyFriendList(friends: [], incoming: [request("N", "Noor")])))
        XCTAssertEqual(state.waitingRequestCount, 1, "the list, once loaded, is the truth")
        state.didFetchFriends(.success([]))
        XCTAssertEqual(state.waitingRequestCount, 0, "a server without requests has none")
    }

    func testBlockingDropsTheirRequest() {
        var state = PartyState(profile: profile("K7QW2MZD", "Sam"), friends: [], party: nil, incoming: [request("N", "Noor")])
        state.didBlock(code: "N")
        XCTAssertEqual(state.incomingRequests, [])
        XCTAssertEqual(state.waitingRequestCount, 0)
    }
}
