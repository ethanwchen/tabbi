import XCTest
import TabbiKitCore
@testable import TabbiKit
@testable import Tabbi

/// Unlocking a Closet item is a real event, so it sparkles over the open
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
}
