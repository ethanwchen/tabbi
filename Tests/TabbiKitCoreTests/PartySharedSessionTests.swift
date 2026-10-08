import XCTest
import TabbiKitCore

/// The host's shared session as each member sees it: in the Timer tab
/// (`ProvidedParty.session`) and as the shared focus clock.
final class PartySharedSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func member(_ code: String, _ name: String, host: Bool = false, online: Bool = true) -> PartyMember {
        PartyMember(profile: PartyProfile(code: code, name: name, petName: name, species: "cat", breed: "tabby"),
                    joinedAt: now, host: host,
                    presence: PartyPresence(status: online ? .studying : .offline, day: "2026-09-21", lastSeen: now),
                    online: online)
    }

    /// I am `ME0000`; Zoe hosts unless `iHost`, and Bo is offline.
    private func state(iHost: Bool = false, session: PartySession?) -> PartyState {
        let members = [
            member("HOST00", "Zoe", host: !iHost),
            member("ME0000", "Ana", host: iHost),
            member("FRND00", "Kai"),
            member("AWAY00", "Bo", online: false),
        ]
        let party = Party(code: "Q4RT8M", host: iHost ? "ME0000" : "HOST00", createdAt: now, lastActive: now,
                          expiresAt: now.addingTimeInterval(3600), maxMembers: 8, session: session, members: members)
        return PartyState(profile: members[1].profile, friends: [], party: party)
    }

    private var running: PartySession {
        PartySession(method: "pomodoro", phaseEndsAt: now.addingTimeInterval(20 * 60),
                     startedAt: now.addingTimeInterval(-5 * 60))
    }

    func testAMemberSeesTheHostsSessionWithTheFriendsOnline() throws {
        let session = try XCTUnwrap(state(session: running).session(at: now))
        XCTAssertEqual(session.methodName, "Pomodoro")
        XCTAssertEqual(session.remaining(at: now), 20 * 60)
        XCTAssertEqual(session.length, 25 * 60)
        XCTAssertEqual(session.friendCount, 2, "Zoe and Kai count; Bo is offline")
        XCTAssertEqual(session.companyLine, "with 2 friends")
        XCTAssertEqual(session.hostName, "Zoe")
        XCTAssertFalse(session.isHost)
    }

    func testTheHostSeesTheirOwnSession() throws {
        let session = try XCTUnwrap(state(iHost: true, session: running).session(at: now))
        XCTAssertTrue(session.isHost)
        XCTAssertNil(session.hostName)
    }

    func testNoSessionWhenNoneRunsOrItRanOut() {
        XCTAssertNil(state(session: nil).session(at: now))
        XCTAssertNil(state(session: running).session(at: now.addingTimeInterval(20 * 60)))
        XCTAssertNil(PartyState(settings: PartySettings()).session(at: now))
    }

    func testSteppingOutOnlyDropsTheSessionForMe() {
        var state = state(session: running)
        state.leaveSession()
        XCTAssertNil(state.session(at: now))
        XCTAssertTrue(state.hasLeftSession(at: now))
        XCTAssertEqual(state.party?.session, running, "the session goes on for the others")
        XCTAssertNotNil(state.provided(at: now), "still in the party")
        XCTAssertNil(state.provided(at: now)?.session)

        state.rejoinSession()
        XCTAssertNotNil(state.session(at: now))
    }

    func testANewSessionIncludesAMemberWhoSteppedOutOfTheLastOne() {
        var state = state(session: running)
        state.leaveSession()
        let next = PartySession(method: "pomodoro", phaseEndsAt: now.addingTimeInterval(50 * 60), startedAt: now)
        state.didFetchParty(.success(state.party.map { party in
            var party = party
            party.session = next
            return party
        }))
        XCTAssertNotNil(state.session(at: now))
        XCTAssertFalse(state.hasLeftSession(at: now))
    }

    func testTheSessionIsTheSharedFocusClock() throws {
        let session = try XCTUnwrap(state(session: running).session(at: now))
        let focus = session.focus(by: .party)
        XCTAssertEqual(focus.label, ProvidedPartySession.label)
        XCTAssertEqual(focus.phase, .focus)
        XCTAssertEqual(focus.endsAt, running.phaseEndsAt)
        XCTAssertEqual(focus.remaining(at: now), 20 * 60)
        XCTAssertEqual(focus.completedFocusCount, 0, "Party pays a finished session itself")

        // The closed notch counts it down like any other focus clock.
        let snapshot = ProviderSnapshot([(.party, ModuleProvision(focus: focus, party: state(session: running).provided(at: now)))])
        XCTAssertEqual(snapshot.focus?.source, .party)
        XCTAssertEqual(snapshot.party?.session?.friendCount, 2)
        XCTAssertEqual(TickerSources(focus: snapshot.focus).items(at: now),
                       [.focus(TickerFocus(focus, at: now))])
    }

    func testCompanyLineAndUnknownMethods() {
        func session(friends: Int, method: String = "pomodoro") -> ProvidedPartySession {
            ProvidedPartySession(method: method, startedAt: now, endsAt: now.addingTimeInterval(60), friendCount: friends)
        }
        XCTAssertEqual(session(friends: 0).companyLine, "on your own")
        XCTAssertEqual(session(friends: 1).companyLine, "with 1 friend")
        XCTAssertEqual(session(friends: 7).companyLine, "with 7 friends")
        XCTAssertEqual(session(friends: 1, method: "fiftyTwoSeventeen").methodName, "52 / 17")
        XCTAssertEqual(session(friends: 1, method: "something-new").methodName, "Focus")
    }
}
