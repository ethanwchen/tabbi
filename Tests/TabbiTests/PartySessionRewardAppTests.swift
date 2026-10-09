import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A finished shared session reaches the pet's save and the activity log.
@MainActor
final class PartySessionRewardAppTests: XCTestCase {
    func testAFinishedSharedSessionPaysThePetAndIsLogged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = EditionStorage(root: root)
        let pet = ClosetStore(storage: storage, runMode: .live)
        let log = ActivityLog(repository: nil)
        var logged: [ActivityRecord] = []
        let subscription = log.recorded.sink { logged.append($0) }
        defer { subscription.cancel() }

        let end = Date()
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: end.addingTimeInterval(-25 * 60),
                                                endedAt: end, friendCount: 2, hostName: "Maya")
        let award = try XCTUnwrap(PartyModule.finish(completion, pet: pet, log: log))

        XCTAssertEqual(award.points, PetPointsRules.sharedPoints(forMinutes: 25, friends: 2))
        XCTAssertEqual(pet.closet.balance, award.points)
        XCTAssertEqual(try PetSave.load(from: ClosetStore.saveURL(in: storage))?.ledger.balance, award.points,
                       "The points are saved")
        XCTAssertEqual(logged.map(\.kind), [.focusCompleted])
        XCTAssertEqual(logged.first?.source, PartyModule.descriptor.id)
    }

    func testAFinishedSharedSessionCelebratesInTheParty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pet = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let party = PartyStore(runMode: .demo, environment: [:])
        let end = Date()
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: end.addingTimeInterval(-25 * 60),
                                                endedAt: end, friendCount: 2, hostName: "Maya")
        let award = try XCTUnwrap(PartyModule.finish(completion, pet: pet, log: ActivityLog(repository: nil),
                                                     party: party, at: end))

        let celebration = try XCTUnwrap(party.celebration)
        XCTAssertEqual(celebration.title, "Great job, team!")
        XCTAssertEqual(celebration.points, award.points)
        XCTAssertTrue(celebration.detail.hasPrefix("+\(award.points) points for \(pet.profile.name)"))

        party.clearCelebration()
        XCTAssertNil(party.celebration)
    }

    func testAFinishedSharedSessionHandsTheMessageToTheNotification() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pet = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let end = Date()
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: end.addingTimeInterval(-25 * 60),
                                                endedAt: end, friendCount: 1, hostName: nil)
        var notified: [PartyTeamCelebration] = []
        let award = try XCTUnwrap(PartyModule.finish(completion, pet: pet, log: ActivityLog(repository: nil),
                                                     notify: { notified.append($0) }, at: end))

        XCTAssertEqual(notified.count, 1)
        XCTAssertEqual(notified.first?.title, "Great job, team!")
        XCTAssertEqual(notified.first?.points, award.points)
        XCTAssertTrue(notified.first?.detail.hasSuffix("25 min with 1 friend") ?? false)
    }

    func testAStayCutShortPaysAndLogsQuietly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let pet = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let log = ActivityLog(repository: nil)
        var logged: [ActivityRecord] = []
        let subscription = log.recorded.sink { logged.append($0) }
        defer { subscription.cancel() }
        pet.follow(activity: log.recorded)
        let party = PartyStore(runMode: .demo, environment: [:])
        let end = Date()
        let completion = PartySessionCompletion(method: "pomodoro", joinedAt: end.addingTimeInterval(-15 * 60),
                                                endedAt: end, friendCount: 2, hostName: "Maya", finished: false)
        var notified: [PartyTeamCelebration] = []
        let award = try XCTUnwrap(PartyModule.finish(completion, pet: pet, log: log, party: party,
                                                     notify: { notified.append($0) }, at: end))

        XCTAssertEqual(award.points, 15)
        XCTAssertEqual(pet.closet.balance, 15, "Paid once, not again from the log record")
        XCTAssertEqual(logged.map(\.kind), [.focusCompleted])
        XCTAssertEqual(logged.first?.quantity, 15)
        XCTAssertNil(party.celebration, "No team celebration for a stay cut short")
        XCTAssertTrue(notified.isEmpty)
    }

    func testDemoAndSnapshotRunsPostNoNotifications() {
        XCTAssertNil(PartyNotifications.make(runMode: .demo))
        XCTAssertNil(PartyNotifications.make(runMode: RunMode(isDemo: false, isSnapshot: true)))
    }
}
