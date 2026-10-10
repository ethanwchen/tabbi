import XCTest
import TabbiKitCore

/// `PartyState.nextClockChange(after:)` lets the Party panel redraw only
/// when a countdown on it changes, instead of every second.
final class PartyClockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func profile(_ code: String) -> PartyProfile {
        PartyProfile(code: code, name: code, petName: "Mochi", species: "cat", breed: "tabby")
    }

    private func presence(_ status: PartyStatus, endsIn seconds: TimeInterval? = nil) -> PartyPresence {
        PartyPresence(status: status, phaseEndsAt: seconds.map(now.addingTimeInterval), day: "2026-09-21", lastSeen: now)
    }

    private func friend(_ code: String, _ presence: PartyPresence, online: Bool = true) -> PartyFriend {
        PartyFriend(profile: profile(code), since: now, presence: presence, online: online, party: nil)
    }

    private func state(friends: [PartyFriend] = [], members: [PartyMember] = [],
                       sessionEndsIn seconds: TimeInterval? = nil) -> PartyState {
        let session = seconds.map { PartySession(method: "pomodoro", phaseEndsAt: now.addingTimeInterval($0),
                                                 startedAt: now.addingTimeInterval(-60)) }
        let party = Party(code: "Q4RT8M", host: "ME", createdAt: now, lastActive: now,
                          expiresAt: now.addingTimeInterval(3600), maxMembers: 8, session: session,
                          members: [PartyMember(profile: profile("ME"), joinedAt: now, host: true, presence: nil, online: true)] + members)
        return PartyState(profile: profile("ME"), friends: friends, party: party)
    }

    func testNothingCountingDownNeedsNoClock() {
        let quiet = state(friends: [friend("A", presence(.idle)), friend("B", presence(.studying, endsIn: 600), online: false),
                                    friend("C", presence(.studying, endsIn: -5))])
        XCTAssertNil(quiet.nextClockChange(after: now), "idle, offline and finished phases show no countdown")
    }

    func testAFriendsCountdownWakesTheClockOnlyWhenItsMinutesChange() {
        let presence = presence(.studying, endsIn: 150)
        let state = state(friends: [friend("A", presence)])
        func label(at date: Date) -> String {
            PartyRoster.compactStatusLine(presence, online: true, at: date)
        }

        var changes: [TimeInterval] = []
        var date = now
        while let next = state.nextClockChange(after: date) {
            XCTAssertGreaterThan(next, date)
            XCTAssertEqual(label(at: next.addingTimeInterval(-0.01)), label(at: date), "nothing changes before the wakeup")
            XCTAssertNotEqual(label(at: next), label(at: date), "the wakeup lands on a change")
            changes.append(next.timeIntervalSince(now))
            date = next
        }
        XCTAssertEqual(changes, [30, 90, 150], "3m, 2m, 1m and then the end, not once a second")
    }

    func testASharedSessionTicksEverySecondAndWinsOverMinutes() {
        let member = PartyMember(profile: profile("B"), joinedAt: now, host: false,
                                 presence: presence(.studying, endsIn: 600), online: true)
        let state = state(members: [member], sessionEndsIn: 90.4)
        XCTAssertEqual(state.nextClockChange(after: now)?.timeIntervalSince(now) ?? 0, 0.4, accuracy: 0.001)
        let later = now.addingTimeInterval(0.4)
        XCTAssertEqual(state.nextClockChange(after: later)?.timeIntervalSince(later) ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(state.nextClockChange(after: now.addingTimeInterval(91))?.timeIntervalSince(now) ?? 0, 120,
                       accuracy: 0.001, "after the session only the member's minute countdown is left (down to 8 min at 2:00)")
    }
}
