import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Limited edition items reach the pet's save: milestones from the activity
/// log (past and new) and event items the server grants.
@MainActor
final class ClosetLimitedEditionAppTests: XCTestCase {
    /// A fresh folder per test: XCTest makes a new instance for each one.
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func focus(minutes: Double, daysAgo: Int = 0, source: ModuleID = "focus",
                       outcome: StudyPhaseOutcome = .completed) -> ActivityRecord {
        let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return ActivityRecord(source: source, kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes,
                              metadata: [ActivityMetadata.outcome: outcome.rawValue])
    }

    private func savedLedger() throws -> PetPointsLedger? {
        try PetSave.load(from: ClosetStore.saveURL(in: EditionStorage(root: root)))?.ledger
    }

    func testAMilestoneReachedInThePastUnlocksOnLaunchWithoutPayingAgain() throws {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let history = (0..<7).map { focus(minutes: 30, daysAgo: $0) }
        store.follow(activity: ActivityLog(repository: nil).recorded, history: history)

        XCTAssertTrue(store.closet.save.ledger.owns(.accessory(.flameHeadband)))
        XCTAssertEqual(store.closet.balance, 0, "history counts toward milestones, not points")
        XCTAssertEqual(store.milestones.currentStreak(today: .now), 7)
        XCTAssertEqual(try savedLedger()?.granted, [.accessory(.flameHeadband)])
    }

    func testANewPartyRecordUnlocksTheTeamMedal() throws {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let log = ActivityLog(repository: nil)
        store.follow(activity: log.recorded)
        XCTAssertFalse(store.closet.save.ledger.owns(.accessory(.teamMedal)))

        let end = Date()
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: end.addingTimeInterval(-25 * 60),
                                                endedAt: end, friendCount: 2, hostName: "Maya")
        PartyModule.finish(completion, pet: store, log: log)

        XCTAssertTrue(store.closet.save.ledger.owns(.accessory(.teamMedal)))
        XCTAssertEqual(store.milestones.finishedPartySessions, 1)
        XCTAssertEqual(store.closet.balance, PetPointsRules.sharedPoints(forMinutes: 25, friends: 2),
                       "the Party record is paid once, by Party")
        XCTAssertEqual(try savedLedger()?.granted, [.accessory(.teamMedal)])
    }

    func testFocusDuringASeasonalEventEarnsItsItemsFromHistoryAndNewRecords() throws {
        let calendar = Calendar.current
        func halloween(_ day: Int, minutes: Double) -> ActivityRecord {
            let end = calendar.date(from: DateComponents(year: 2025, month: 10, day: day, hour: 12))!
            return ActivityRecord(source: "focus", kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                                  end: end, quantity: minutes, unit: .minutes)
        }
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let log = ActivityLog(repository: nil)
        store.follow(activity: log.recorded, history: [halloween(20, minutes: 100)])

        let witchHat = PetLimitedEdition.halloweenWitchHat.item
        let pumpkin = PetLimitedEdition.halloweenPumpkin.item
        XCTAssertTrue(store.closet.save.ledger.owns(witchHat), "a goal reached in the past unlocks on launch")
        XCTAssertFalse(store.closet.save.ledger.owns(pumpkin))
        XCTAssertEqual(store.closet.balance, 0, "history counts toward the event, not points")

        log.record(halloween(28, minutes: 200))
        XCTAssertTrue(store.closet.save.ledger.owns(pumpkin))
        XCTAssertEqual(try savedLedger()?.granted, [witchHat, pumpkin])
    }

    func testServerGrantsUnlockEventItemsOnce() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let cap = PetLimitedEdition.launchWeekCap.item
        XCTAssertEqual(store.applyGrants([cap.id, "accessory.fromANewerBuild", PetItem.accessory(.beanie).id]), [cap])
        XCTAssertEqual(store.applyGrants([cap.id]), [], "a repeated sync grants nothing new")
        XCTAssertTrue(store.closet.save.ledger.owns(cap))
        XCTAssertFalse(store.closet.save.ledger.owns(.accessory(.beanie)), "shop items are never granted")
    }

    func testDemoShowsMilestonesPartWayAndTheLaunchCapGranted() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .demo)
        store.follow(activity: ActivityLog(repository: nil).recorded)
        XCTAssertTrue(store.closet.save.ledger.owns(PetLimitedEdition.launchWeekCap.item))
        for milestone in PetMilestone.allCases {
            XCTAssertLessThan(store.milestones.value(of: milestone, today: .now), milestone.goal,
                              "\(milestone) is still to earn in the demo")
        }
        XCTAssertGreaterThan(store.milestones.value(of: .weekStreak, today: .now), 0)
        XCTAssertGreaterThan(store.milestones.value(of: .fiftyHours, today: .now), 0)
    }
}
