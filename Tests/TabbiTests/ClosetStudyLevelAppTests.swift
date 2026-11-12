import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Study Level through the Closet's store: a long history lands at
/// its level quietly, a level up never pays points, the nameplate pick is
/// kept, a lost log keeps the level, and Party sends it to friends.
@MainActor
final class ClosetStudyLevelAppTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var storage: EditionStorage { EditionStorage(root: root) }

    private func focus(minutes: Double, hoursAgo: Double,
                       outcome: StudyPhaseOutcome = .completed) -> ActivityRecord {
        let end = Date().addingTimeInterval(-hoursAgo * 3600)
        return ActivityRecord(source: "focus", kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes,
                              metadata: [ActivityMetadata.outcome: outcome.rawValue])
    }

    /// 240 hours of focus, six hours a day for 40 days: level 12.
    private var longHistory: [ActivityRecord] {
        (1...40).map { focus(minutes: 360, hoursAgo: Double($0) * 24) }
    }

    private func savedProgression() throws -> ProgressionSave? {
        try ProgressionSave.load(from: ClosetStore.progressionURL(in: storage))
    }

    func testALongHistoryLandsAtItsLevelQuietlyWithADot() throws {
        let store = ClosetStore(storage: storage, runMode: .live)
        store.follow(activity: ActivityLog(repository: nil).recorded, history: longHistory)

        XCTAssertEqual(store.progression.studyLevel, StudyLevel(12))
        XCTAssertEqual(store.closet.balance, 0, "history and levels pay no points")
        XCTAssertTrue(store.hasUnseenGoals, "the level waits with the Goals pill's dot")
        XCTAssertEqual(try savedProgression()?.level, 12)
        XCTAssertEqual(try savedProgression()?.levelSeen, 0)

        store.markGoalsSeen()
        XCTAssertFalse(store.hasUnseenGoals)
        XCTAssertEqual(try savedProgression()?.levelSeen, 12)
    }

    /// The block that crosses a level earns what the same block earns on
    /// a store far from any level: nothing more.
    func testALevelUpNeverChangesThePointsLedger() throws {
        // 3 h 50 min so far: the next 25 minutes reach level 1.
        let crossing = ClosetStore(storage: storage, runMode: .live)
        let crossingLog = ActivityLog(repository: nil)
        crossing.follow(activity: crossingLog.recorded,
                        history: (1...23).map { focus(minutes: 10, hoursAgo: Double($0)) })
        let calm = ClosetStore(storage: EditionStorage(root: root.appendingPathComponent("calm")), runMode: .live)
        let calmLog = ActivityLog(repository: nil)
        calm.follow(activity: calmLog.recorded, history: [])
        XCTAssertEqual(crossing.progression.studyLevel, StudyLevel(0))
        let before = (crossing.closet.save.ledger, calm.closet.save.ledger)

        let block = focus(minutes: 25, hoursAgo: 0, outcome: .skipped)
        crossingLog.record(block)
        calmLog.record(block)

        XCTAssertEqual(crossing.progression.studyLevel, StudyLevel(1), "the block reached level 1")
        XCTAssertEqual(calm.progression.studyLevel, StudyLevel(0))
        let earned = crossing.closet.save.ledger.earned - before.0.earned
        XCTAssertEqual(earned, calm.closet.save.ledger.earned - before.1.earned, "a level adds nothing")
        XCTAssertEqual(earned, PetPointsRules.points(forMinutes: 25, completed: false))
        XCTAssertEqual(crossing.closet.save.ledger.spent, before.0.spent)
        XCTAssertEqual(crossing.closet.save.ledger.granted, before.0.granted)
    }

    func testAPickedNameplateIsKeptAndSharedWithParty() throws {
        let store = ClosetStore(storage: storage, runMode: .live)
        store.follow(activity: ActivityLog(repository: nil).recorded, history: longHistory)
        var shared: [StudyStanding] = []
        let subscription = store.standings.sink { shared.append($0) }
        defer { subscription.cancel() }

        store.pick(.honey)
        XCTAssertEqual(store.progression.nameplate, .plain, "Honey waits for level 15")
        store.pick(.ember)
        XCTAssertEqual(store.progression.nameplate, .ember)
        XCTAssertEqual(try savedProgression()?.nameplate, .ember)
        XCTAssertEqual(shared.last, StudyStanding(level: StudyLevel(12), nameplate: .ember))
        store.markGoalsSeen()

        let relaunched = ClosetStore(storage: storage, runMode: .live)
        relaunched.follow(activity: ActivityLog(repository: nil).recorded, history: [])
        XCTAssertEqual(relaunched.progression.nameplate, .ember)
        XCTAssertEqual(relaunched.progression.studyLevel, StudyLevel(12), "a lost log keeps the level")
        XCTAssertFalse(relaunched.hasUnseenGoals, "nothing new on a plain relaunch")
    }

    func testEveryNewBestIsSavedNotOnlyNewTiers() throws {
        let store = ClosetStore(storage: storage, runMode: .live)
        let log = ActivityLog(repository: nil)
        store.follow(activity: log.recorded, history: [focus(minutes: 30, hoursAgo: 2)])
        log.record(focus(minutes: 30, hoursAgo: 0))
        XCTAssertEqual(try savedProgression()?.best[.focusHours], 60, "kept though no tier or level was reached")
    }
}

/// A friends server that records every profile body it takes.
private final class RecordingFriendsServer: PartyTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []

    var profileBodies: [[String: Any]] { lock.withLock { bodies } }

    func send(_ request: PartyHTTPRequest, timeout: TimeInterval) async throws -> PartyHTTPResponse {
        if let body = request.body, let fields = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           request.path == "/v1/me" || request.path == "/v1/register" {
            lock.withLock { bodies.append(fields) }
        }
        let profile = #"{"code":"CODE0001","name":"Ana","petName":"Mochi","species":"cat","breed":"tabby","colors":[],"costume":"none","accessories":[],"points":0,"level":1}"#
        switch (request.method, request.path) {
        case ("POST", "/v1/register"):
            let token = String(repeating: "1", count: 64)
            return reply(#"{"ok":true,"token":"\#(token)","code":"CODE0001","profile":\#(profile)}"#, 201)
        case ("PATCH", "/v1/me"):
            return reply(#"{"ok":true,"profile":\#(profile)}"#)
        case ("GET", "/v1/grants"):
            return reply(#"{"ok":true,"items":[]}"#)
        default:
            return reply(#"{"ok":false,"error":"not_found","message":"no route"}"#, 404)
        }
    }

    private func reply(_ text: String, _ status: Int = 200) -> PartyHTTPResponse {
        PartyHTTPResponse(statusCode: status, body: Data(text.utf8))
    }
}

@MainActor
final class PartyStudyLevelTests: XCTestCase {
    func testPartySendsTheStudyLevelAndResendsItWhenItGrows() async throws {
        let server = RecordingFriendsServer()
        let party = PartyStore(runMode: RunMode(isSnapshot: true),
                               environment: ["TABBI_PARTY_SERVER": "http://localhost:8787", "TABBI_PARTY_NAME": "Ana"],
                               transport: server)
        party.update(standing: StudyStanding(level: StudyLevel(12), nameplate: .ember))
        party.start()
        defer { party.stop() }
        try await waitUntil { party.state.connection == .connected }
        let first = try XCTUnwrap(server.profileBodies.last)
        XCTAssertEqual(first["studyLevel"] as? Int, 12)
        XCTAssertEqual(first["nameplate"] as? String, "ember")

        party.update(standing: StudyStanding(level: StudyLevel(13), nameplate: .ember))
        try await waitUntil { (server.profileBodies.last?["studyLevel"] as? Int) == 13 }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
