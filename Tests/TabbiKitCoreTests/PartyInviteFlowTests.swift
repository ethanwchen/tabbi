import XCTest
import TabbiKitCore

final class PartyInviteFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let me = "K7QW2MZD"
    private let maya = "M4YA8PET"

    private func profile(_ code: String, _ name: String, pet: String = "Mochi") -> PartyProfile {
        PartyProfile(code: code, name: name, petName: pet, species: "cat", breed: "tabby")
    }

    private func party(_ code: String, members: Int) -> Party {
        let people = (0..<members).map { index in
            PartyMember(profile: profile(index == 0 ? me : "F\(index)AAAAAA", "Friend \(index)"),
                        joinedAt: now, host: index == 0, presence: nil, online: true)
        }
        return Party(code: code, host: me, createdAt: now, lastActive: now, expiresAt: now.addingTimeInterval(3600),
                     maxMembers: 8, session: nil, members: people)
    }

    /// A connected state with the friends list loaded.
    private func connected(friends: [PartyProfile] = [], party: Party? = nil) -> PartyState {
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile(me, "Sam"))
        state.didFetchFriends(.success(friends.map {
            PartyFriend(profile: $0, since: now, presence: nil, online: true, party: nil)
        }))
        if let party { state.didFetchParty(.success(party)) }
        return state
    }

    func testAddingAFriendAsksFirstThenNamesThemAndTheirPet() {
        var flow = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        XCTAssertEqual(flow.stage, .connecting)
        XCTAssertNil(flow.primaryTitle, "nothing to click while connecting")

        flow.update(with: connected(), blocked: [])
        XCTAssertEqual(flow.stage, .confirming)
        XCTAssertEqual(flow.title, "Add a friend?")
        XCTAssertTrue(flow.message.contains("M4YA-8PET"))
        XCTAssertEqual(flow.primaryTitle, "Add Friend")
        XCTAssertEqual(flow.dismissTitle, "Not Now")

        XCTAssertTrue(flow.begin())
        XCTAssertFalse(flow.begin(), "a second click sends nothing")
        flow.didAddFriend(profile(maya, "Maya", pet: "Biscuit"), added: true)

        XCTAssertEqual(flow.title, "Maya is now your friend")
        XCTAssertTrue(flow.message.contains("Biscuit"))
        XCTAssertEqual(flow.person?.name, "Maya")
        XCTAssertTrue(flow.isDone)
        XCTAssertNil(flow.primaryTitle)
        XCTAssertEqual(flow.dismissTitle, "Done")
    }

    func testOffersToTurnPartyOnFirst() {
        var flow = PartyInviteFlow(invite: .joinParty(code: "Q4RT8M"), partyIsOn: false)
        XCTAssertEqual(flow.stage, .needsParty)
        XCTAssertEqual(flow.primaryTitle, "Turn On Party")
        XCTAssertFalse(flow.begin(), "nothing is sent before Party is on")

        flow.update(with: connected(), blocked: nil)
        XCTAssertEqual(flow.stage, .needsParty, "state updates wait for the switch")

        flow.partyTurnedOn()
        XCTAssertEqual(flow.stage, .connecting)
        flow.update(with: connected(), blocked: nil)
        XCTAssertEqual(flow.title, "Join this party?")
        XCTAssertEqual(flow.primaryTitle, "Join Party")
    }

    func testWaitsForTheFriendsListBeforeAsking() {
        var flow = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        var state = PartyState(settings: .oldEnough)
        state.didConnect(profile(me, "Sam"))
        flow.update(with: state, blocked: nil)
        XCTAssertEqual(flow.stage, .connecting, "can't tell an existing friend apart yet")
    }

    func testAnswersLocallyForMyOwnCodeFriendsAndBlocks() {
        var own = PartyInviteFlow(invite: .addFriend(code: me), partyIsOn: true)
        own.update(with: connected(), blocked: nil)
        XCTAssertEqual(own.stage, .refused(.ownCode))
        XCTAssertTrue(own.isDone)

        var friend = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        friend.update(with: connected(friends: [profile(maya, "Maya")]), blocked: nil)
        XCTAssertEqual(friend.title, "Maya is already your friend")
        XCTAssertFalse(friend.begin())

        var blocked = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        blocked.update(with: connected(), blocked: [PartyBlockedUser(code: maya, name: "Maya", petName: "Biscuit")])
        XCTAssertEqual(blocked.stage, .refused(.blocked(name: "Maya")))
        XCTAssertTrue(blocked.message.contains("Unblock"))
        XCTAssertFalse(blocked.begin(), "a block is respected")
    }

    func testJoiningSaysItLeavesTheCurrentPartyAndSkipsTheSameOne() {
        var other = PartyInviteFlow(invite: .joinParty(code: "Q4RT8M"), partyIsOn: true)
        other.update(with: connected(party: party("ZZ3XYW", members: 1)), blocked: nil)
        XCTAssertTrue(other.message.contains("leave your current party"))

        XCTAssertTrue(other.begin())
        other.didJoin(party("Q4RT8M", members: 3))
        XCTAssertEqual(other.title, "You joined the party")
        XCTAssertEqual(other.message, "2 friends are here with you.")

        var same = PartyInviteFlow(invite: .joinParty(code: "Q4RT8M"), partyIsOn: true)
        same.update(with: connected(party: party("Q4RT8M", members: 2)), blocked: nil)
        XCTAssertEqual(same.stage, .finished(.alreadyInParty))
    }

    func testExpiredCodesAndModerationEndWithAFriendlySentence() {
        var expired = PartyInviteFlow(invite: .joinParty(code: "Q4RT8M"), partyIsOn: true)
        expired.update(with: connected(), blocked: nil)
        _ = expired.begin()
        expired.didFail(.partyNotFound)
        XCTAssertEqual(expired.title, "Couldn't join this party")
        XCTAssertEqual(expired.message, "That party has ended. Ask for a new link.")
        XCTAssertTrue(expired.isDone)
        XCTAssertNil(expired.primaryTitle)

        var unknown = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        unknown.update(with: connected(), blocked: nil)
        _ = unknown.begin()
        unknown.didFail(.unknownCode)
        XCTAssertTrue(unknown.message.contains("new one"))

        var banned = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        banned.update(with: connected(), blocked: nil)
        _ = banned.begin()
        banned.didFail(.banned)
        XCTAssertEqual(banned.message, PartyError.banned.message)
        XCTAssertFalse(banned.begin())
    }

    func testRateLimitsAndNetworkFailuresCanBeRetried() {
        var flow = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        flow.update(with: connected(), blocked: nil)
        _ = flow.begin()
        flow.didFail(.rateLimited(retryAfter: 30))
        XCTAssertTrue(flow.message.contains("Wait a minute"))
        XCTAssertEqual(flow.primaryTitle, "Try Again")
        XCTAssertFalse(flow.isDone)

        XCTAssertTrue(flow.begin())
        flow.didAddFriend(profile(maya, "Maya"), added: false)
        XCTAssertEqual(flow.stage, .finished(.alreadyFriends(profile(maya, "Maya"))))
    }

    func testConnectionProblemsShowAndRetryConnecting() {
        var flow = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        var state = PartyState(settings: .oldEnough)
        state.didFailToConnect(.unreachable)
        flow.update(with: state, blocked: nil)
        XCTAssertEqual(flow.stage, .unavailable(.unreachable))
        XCTAssertEqual(flow.primaryTitle, "Try Again")

        flow.retryConnecting()
        XCTAssertEqual(flow.stage, .connecting)
        flow.update(with: connected(), blocked: nil)
        XCTAssertEqual(flow.stage, .confirming)

        var badServer = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        badServer.update(with: PartyState(settings: PartySettings(serverText: "http://example.com")), blocked: nil)
        XCTAssertNil(badServer.primaryTitle)
        XCTAssertTrue(badServer.message.contains("Party options"))
    }

    func testIgnoresRepliesThatDoNotFitTheStep() {
        var flow = PartyInviteFlow(invite: .addFriend(code: maya), partyIsOn: true)
        flow.didAddFriend(profile(maya, "Maya"), added: true)
        XCTAssertEqual(flow.stage, .connecting, "no reply before a request")
        flow.update(with: connected(), blocked: nil)
        _ = flow.begin()
        flow.didJoin(party("Q4RT8M", members: 2))
        XCTAssertEqual(flow.stage, .working, "a join reply doesn't finish a friend link")
    }
}
