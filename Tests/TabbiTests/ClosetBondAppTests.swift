import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Closet's pet card shows the bond from the activity log the store
/// already follows: past focus counts on launch, new focus grows it, and
/// demo mode shows a well grown bond.
@MainActor
final class ClosetBondAppTests: XCTestCase {
    /// A fresh folder per test: XCTest makes a new instance for each one.
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func focus(minutes: Double, daysAgo: Int = 0) -> ActivityRecord {
        let end = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        return ActivityRecord(source: "focus", kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                              end: end, quantity: minutes, unit: .minutes)
    }

    func testANewPetHasJustMet() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        XCTAssertEqual(store.bond.level, 1)
        XCTAssertEqual(store.bond.tierName, "Just met")
        XCTAssertEqual(store.bond.progressInLevel, 0)
    }

    func testPastAndNewFocusGrowTheBond() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let log = ActivityLog(repository: nil)
        // Three study days of 30 minutes: 90 minutes plus 3 day bonuses.
        store.follow(activity: log.recorded, history: (1...3).map { focus(minutes: 30, daysAgo: $0) })
        XCTAssertEqual(store.bond, PetBond(points: 90 + 3 * PetBond.pointsPerStudyDay))
        XCTAssertEqual(store.bond.level, 2)

        log.record(focus(minutes: 200))
        XCTAssertEqual(store.bond, PetBond(points: 290 + 4 * PetBond.pointsPerStudyDay))
        XCTAssertEqual(store.bond.level, 3)
    }

    func testDemoShowsAGrownBond() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .demo)
        XCTAssertGreaterThanOrEqual(store.bond.level, 4, "demo shows the collar and happy idle unlocked")
        XCTAssertLessThan(store.bond.level, PetBond.maxLevel, "and a ring still filling")
    }
}
