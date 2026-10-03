import XCTest
import TabbiKitCore

final class PartyRosterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_123)

    private func presence(_ status: PartyStatus, endsIn seconds: TimeInterval? = nil) -> PartyPresence {
        PartyPresence(status: status, method: status == .idle ? nil : "pomodoro",
                      phaseEndsAt: seconds.map { now.addingTimeInterval($0) },
                      todayMinutes: 40, day: "2026-09-21", lastSeen: now)
    }

    private func friend(_ name: String, code: String, _ presence: PartyPresence?, online: Bool) -> PartyFriend {
        PartyFriend(profile: PartyProfile(code: code, name: name, petName: "Pip", species: "cat", breed: "tabby"),
                    since: now, presence: presence, online: online, party: nil)
    }

    func testStatusIsOfflineWhenNotOnlineOrNeverSeen() {
        XCTAssertEqual(PartyRoster.status(presence(.studying), online: false), .offline)
        XCTAssertEqual(PartyRoster.status(nil, online: true), .offline)
        XCTAssertEqual(PartyRoster.status(presence(.onBreak), online: true), .onBreak)
    }

    func testStatusLineCountsDownLocally() {
        XCTAssertEqual(PartyRoster.statusLine(presence(.studying, endsIn: 17 * 60 + 5), online: true, at: now),
                       "Studying · 18 min left")
        XCTAssertEqual(PartyRoster.statusLine(presence(.onBreak, endsIn: 30), online: true, at: now),
                       "On a break · 1 min left")
        XCTAssertEqual(PartyRoster.statusLine(presence(.studying, endsIn: -10), online: true, at: now),
                       "Studying · ending")
        XCTAssertEqual(PartyRoster.statusLine(presence(.studying), online: true, at: now), "Studying")
        XCTAssertEqual(PartyRoster.statusLine(presence(.idle), online: true, at: now), "Online")
        XCTAssertEqual(PartyRoster.statusLine(presence(.studying, endsIn: 600), online: false, at: now), "Offline")
    }

    func testCompactStatusLineFitsANarrowRow() {
        XCTAssertEqual(PartyRoster.compactStatusLine(presence(.studying, endsIn: 40 * 60 + 1), online: true, at: now),
                       "Studying · 41m")
        XCTAssertEqual(PartyRoster.compactStatusLine(presence(.onBreak, endsIn: 200), online: true, at: now), "Break · 4m")
        XCTAssertEqual(PartyRoster.compactStatusLine(presence(.studying, endsIn: -5), online: true, at: now), "Studying")
        XCTAssertEqual(PartyRoster.compactStatusLine(presence(.onBreak), online: true, at: now), "Break")
        XCTAssertEqual(PartyRoster.compactStatusLine(presence(.idle), online: true, at: now), "Online")
        XCTAssertEqual(PartyRoster.compactStatusLine(nil, online: true, at: now), "Offline")
    }

    func testTimeLeftOnlyForRunningPhases() {
        XCTAssertEqual(PartyRoster.timeLeft(presence(.studying, endsIn: 90), online: true, at: now), 90)
        XCTAssertNil(PartyRoster.timeLeft(presence(.idle, endsIn: 90), online: true, at: now))
        XCTAssertNil(PartyRoster.timeLeft(presence(.studying, endsIn: 90), online: false, at: now))
    }

    func testDuration() {
        XCTAssertEqual(PartyRoster.duration(minutes: 0), "0m")
        XCTAssertEqual(PartyRoster.duration(minutes: 45), "45m")
        XCTAssertEqual(PartyRoster.duration(minutes: 60), "1h")
        XCTAssertEqual(PartyRoster.duration(minutes: 80), "1h 20m")
    }

    func testFriendsSortActiveFirstThenByName() {
        let friends = [
            friend("zoe", code: "AAAAAAA1", nil, online: false),
            friend("Mia", code: "AAAAAAA2", presence(.idle), online: true),
            friend("ben", code: "AAAAAAA3", presence(.onBreak), online: true),
            friend("Ava", code: "AAAAAAA4", presence(.studying), online: true),
            friend("Cal", code: "AAAAAAA5", presence(.studying), online: true),
            friend("Ann", code: "AAAAAAA6", presence(.studying), online: false),
        ]
        XCTAssertEqual(PartyRoster.sorted(friends).map(\.profile.name), ["Ava", "Cal", "ben", "Mia", "Ann", "zoe"])
    }

    func testMembersSortHostFirst() {
        func member(_ name: String, host: Bool) -> PartyMember {
            PartyMember(profile: PartyProfile(code: name.uppercased(), name: name, petName: "Pip", species: "dog", breed: "corgi"),
                        joinedAt: now, host: host, presence: nil, online: true)
        }
        let members = [member("bo", host: false), member("Zed", host: true), member("al", host: false)]
        XCTAssertEqual(PartyRoster.sorted(members).map(\.profile.name), ["Zed", "al", "bo"])
    }
}
