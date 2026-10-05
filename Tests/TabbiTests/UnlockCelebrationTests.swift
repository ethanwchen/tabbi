import Combine
import XCTest
import TabbiKitCore
@testable import TabbiKit
@testable import Tabbi

/// Unlocking a Closet item, by buying it or by earning the points that make
/// it affordable (a level up), is a real event, so it sparkles over the open
/// panel; wearing something already owned is not.
@MainActor
final class UnlockCelebrationTests: XCTestCase {
    private func openCenter() -> CelebrationCenter {
        let center = CelebrationCenter(isEnabled: true, hapticsEnabled: { false })
        center.stageAppeared()
        return center
    }

    func testBuyingAnItemSparkles() throws {
        let center = openCenter()
        let store = ClosetStore(storage: EditionStorage(root: FileManager.default.temporaryDirectory),
                                runMode: .demo, celebrations: center)
        let item = try XCTUnwrap(PetItem.allCases.first { store.closet.state(of: $0) == .affordable })

        XCTAssertEqual(store.tap(item), .boughtAndWore)
        XCTAssertEqual(center.current?.style, .sparkles)
        XCTAssertEqual(center.current?.tier, .milestone)
    }

    func testWearingAnOwnedItemDoesNotCelebrate() throws {
        let center = openCenter()
        let store = ClosetStore(storage: EditionStorage(root: FileManager.default.temporaryDirectory),
                                runMode: .demo, celebrations: center)
        let item = try XCTUnwrap(PetItem.allCases.first { store.closet.state(of: $0) == .owned })

        XCTAssertEqual(store.tap(item), .wore)
        XCTAssertNil(center.current)
    }

    func testALevelUpFromStudyPointsSparkles() throws {
        let center = openCenter()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = EditionStorage(root: root)
        var save = PetSave(profile: .starter(.cat), ledger: PetPointsLedger(earned: 20))
        save.creditedFocusCount = 0
        save.creditedFocusSource = FocusModule.descriptor.id
        try save.write(to: ClosetStore.saveURL(in: storage))
        let store = ClosetStore(storage: storage, runMode: .live, celebrations: center)
        let focus = PassthroughSubject<ProvidedFocus?, Never>()
        store.follow(focus: focus.eraseToAnyPublisher())

        let start = Date()
        var timer = FocusTimer()
        timer.start(at: start)
        focus.send(timer.provided(by: FocusModule.descriptor.id))
        XCTAssertNil(center.current)
        timer.advance(to: start.addingTimeInterval(25 * 60))
        focus.send(timer.provided(by: FocusModule.descriptor.id))

        XCTAssertEqual(center.current?.style, .sparkles)
        XCTAssertEqual(center.current?.tier, .milestone)
    }
}
