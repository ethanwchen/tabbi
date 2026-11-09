import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Goals section through the Closet's store: history replayed at launch
/// counts quietly, new records unlock badge tiers and mastery outfits, and
/// `Pet/progression.json` keeps it all.
@MainActor
final class ClosetGoalsAppTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var storage: EditionStorage { EditionStorage(root: root) }

    private func focus(minutes: Double, hoursAgo: Double) -> ActivityRecord {
        let end = Date().addingTimeInterval(-hoursAgo * 3600)
        return ActivityRecord(source: "focus", kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes,
                              metadata: [ActivityMetadata.outcome: StudyPhaseOutcome.completed.rawValue])
    }

    private func savedProgression() throws -> ProgressionSave? {
        try ProgressionSave.load(from: ClosetStore.progressionURL(in: storage))
    }

    func testHistoryCountsQuietlyAndUnlocksTheOutfitItEarned() throws {
        let store = ClosetStore(storage: storage, runMode: .live)
        // 50 finished sessions over the last few days: Sessions Silver.
        let history = (0..<50).map { focus(minutes: 25, hoursAgo: Double($0)) }
        store.follow(activity: ActivityLog(repository: nil).recorded, history: history)

        XCTAssertTrue(store.progression.isReached(ProgressBadge(.sessions, .silver)))
        XCTAssertTrue(store.closet.save.ledger.owns(.outfit(.apprenticeRobe)))
        XCTAssertEqual(store.closet.balance, 0, "history counts toward goals, not points")
        XCTAssertTrue(store.hasUnseenGoals, "what the log already earned waits with a dot")
        XCTAssertEqual(try savedProgression()?.reached.keys.contains(ProgressBadge(.sessions, .silver)), true)
        XCTAssertEqual(try PetSave.load(from: ClosetStore.saveURL(in: storage))?.ledger.owns(.outfit(.apprenticeRobe)), true)

        store.markGoalsSeen()
        XCTAssertFalse(store.hasUnseenGoals)
        XCTAssertEqual(try savedProgression()?.seen, try savedProgression().map { Set($0.reached.keys) })
    }

    func testANewRecordReachesATierAndSavesIt() throws {
        let store = ClosetStore(storage: storage, runMode: .live)
        let log = ActivityLog(repository: nil)
        store.follow(activity: log.recorded, history: (0..<9).map { focus(minutes: 25, hoursAgo: Double($0 + 1)) })
        XCTAssertNil(store.progression.tier(of: .sessions))

        log.record(focus(minutes: 25, hoursAgo: 0))
        XCTAssertEqual(store.progression.tier(of: .sessions), .bronze)
        XCTAssertEqual(try savedProgression()?.best[.sessions], 10)
    }

    func testProgressSurvivesALostLog() throws {
        let first = ClosetStore(storage: storage, runMode: .live)
        first.follow(activity: ActivityLog(repository: nil).recorded,
                     history: (0..<12).map { focus(minutes: 30, hoursAgo: Double($0)) })
        XCTAssertEqual(first.progression.value(of: .sessions), 12)

        let relaunched = ClosetStore(storage: storage, runMode: .live)
        relaunched.follow(activity: ActivityLog(repository: nil).recorded, history: [])
        XCTAssertEqual(relaunched.progression.value(of: .sessions), 12)
        XCTAssertEqual(relaunched.progression.tier(of: .sessions), .bronze)
    }

    func testAnUnreadableFileIsNeverOverwritten() throws {
        let url = ClosetStore.progressionURL(in: storage)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: url)
        let store = ClosetStore(storage: storage, runMode: .live)
        store.follow(activity: ActivityLog(repository: nil).recorded,
                     history: (0..<12).map { focus(minutes: 30, hoursAgo: Double($0)) })
        XCTAssertEqual(store.progression.tier(of: .sessions), .bronze, "it still counts in memory")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ broken")
    }

    func testDemoAndSnapshotRunsSaveNothing() throws {
        let demo = ClosetStore(storage: storage, runMode: .demo)
        demo.follow(activity: ActivityLog(repository: nil).recorded)
        XCTAssertTrue(demo.closet.save.ledger.owns(.accessory(.littleSprout)), "the demo shelf has outfits earned")
        XCTAssertGreaterThan(demo.progression.reachedCount, 0)
        let snapshot = ClosetStore(storage: storage, runMode: RunMode(isSnapshot: true))
        snapshot.follow(activity: ActivityLog(repository: nil).recorded,
                        history: (0..<12).map { focus(minutes: 30, hoursAgo: Double($0)) })
        XCTAssertFalse(FileManager.default.fileExists(atPath: ClosetStore.progressionURL(in: storage).path))
    }
}
