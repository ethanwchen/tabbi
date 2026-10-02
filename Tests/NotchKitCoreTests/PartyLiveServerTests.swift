import XCTest
import NotchKitCore

/// End-to-end run of `PartyClient` against a real worker. Skipped unless
/// `PARTY_TEST_SERVER` is set, e.g.:
///
///     (cd backend && npm run dev) &
///     PARTY_TEST_SERVER=http://localhost:8787 swift test --filter PartyLiveServerTests
///
/// It only creates throwaway users and deletes them at the end, so it is
/// also safe against production.
final class PartyLiveServerTests: XCTestCase {
    func testFriendsPartyAndSessionRoundTrip() async throws {
        guard let text = ProcessInfo.processInfo.environment["PARTY_TEST_SERVER"],
              let server = PartyServer.parse(text)
        else { throw XCTSkip("Set PARTY_TEST_SERVER to run against a worker") }

        let anonymous = PartyClient(baseURL: server)
        let healthy = try await anonymous.health()
        XCTAssertTrue(healthy)

        let ana = try await anonymous.register(PartyProfileUpdate(name: "Test Ana", petName: "Mochi", species: "cat", breed: "tabby"))
        let ben = try await anonymous.register(PartyProfileUpdate(name: "Test Ben", petName: "Biscuit", species: "dog", breed: "corgi"))
        let anaClient = PartyClient(baseURL: server, token: ana.token)
        let benClient = PartyClient(baseURL: server, token: ben.token)
        do {
            let profile = try await anaClient.updateProfile(PartyProfileUpdate(costume: "scrubs", accessories: ["glasses"]))
            XCTAssertEqual(profile.costume, "scrubs")

            let added = try await anaClient.addFriend(code: ben.code.lowercased())
            XCTAssertTrue(added.added)
            XCTAssertEqual(added.friend.name, "Test Ben")

            let phaseEnd = Date().addingTimeInterval(25 * 60)
            let beat = try await benClient.heartbeat(PartyHeartbeat(status: .studying, method: "pomodoro", phaseEndsAt: phaseEnd, todayMinutes: 30, day: Self.today()))
            XCTAssertEqual(beat.presence.status, .studying)
            XCTAssertNotNil(beat.nextHeartbeat)

            let party = try await benClient.createParty()
            let friends = try await anaClient.friends()
            XCTAssertEqual(friends.map(\.profile.code), [ben.code])
            XCTAssertEqual(friends.first?.presence?.status, .studying)
            XCTAssertEqual(friends.first?.party?.code, party.code)
            XCTAssertEqual(friends.first?.canJoin, true)

            let joined = try await anaClient.joinParty(friend: ben.code)
            XCTAssertEqual(joined.members.map(\.profile.code), [ben.code, ana.code])

            do {
                _ = try await anaClient.startSession(method: "pomodoro", phaseEndsAt: phaseEnd)
                XCTFail("only the host may start a session")
            } catch let error as PartyError {
                XCTAssertEqual(error, .notHost)
            }
            let withSession = try await benClient.startSession(method: "pomodoro", phaseEndsAt: phaseEnd)
            XCTAssertEqual(withSession.session?.phaseEndsAt.timeIntervalSince1970, phaseEnd.timeIntervalSince1970.rounded())
            let ended = try await benClient.endSession()
            XCTAssertNil(ended.session)

            let board = try await anaClient.leaderboard()
            XCTAssertEqual(Set(board.entries.map(\.profile.code)), [ana.code, ben.code])
            XCTAssertEqual(board.entries.first { $0.profile.code == ben.code }?.minutes, 30)

            let left = try await anaClient.leaveParty()
            XCTAssertTrue(left)
            let none = try await anaClient.party()
            XCTAssertNil(none)

            let offline = try await benClient.heartbeat(.offline)
            XCTAssertNil(offline.nextHeartbeat)
            let removed = try await anaClient.removeFriend(code: ben.code)
            XCTAssertTrue(removed)
        } catch {
            try? await anaClient.deleteMe()
            try? await benClient.deleteMe()
            throw error
        }
        try await anaClient.deleteMe()
        try await benClient.deleteMe()
        do {
            _ = try await anaClient.me()
            XCTFail("a deleted user's token stops working")
        } catch let error as PartyError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
