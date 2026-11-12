import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Closet's Radiant upgrade flow: the sheet previews the effect on the
/// big pet, the upgrade is saved, its setting and the pinned goal stick.
@MainActor
final class ClosetRadiantAppTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private let wizard = PetItem.accessory(.wizardHat)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func savedSave() throws -> PetSave? {
        try PetSave.load(from: ClosetStore.saveURL(in: EditionStorage(root: root)))
    }

    func testUpgradingFromTheSheetSavesItAndShowsTheEffect() throws {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        store.receiveGift(points: 8_000)
        store.tap(wizard)
        store.tap(wizard)
        XCTAssertEqual(store.closet.radiantState(of: wizard), .affordable)

        store.showRadiant(wizard)
        XCTAssertEqual(store.radiantSheet, wizard)
        XCTAssertEqual(store.preview.profile.radiantLook, PetRadiantLook([wizard: .bold]), "the big pet previews it worn")
        store.previewRadiance(.subtle)
        XCTAssertEqual(store.preview.profile.radiantLook, PetRadiantLook([wizard: .subtle]))
        XCTAssertFalse(store.closet.profile.isWearing(wizard), "a preview changes nothing saved")

        XCTAssertTrue(store.upgradeToRadiant(wizard))
        XCTAssertEqual(store.closet.radiantState(of: wizard), .radiant(.bold))
        XCTAssertTrue(store.closet.profile.isWearing(wizard))
        XCTAssertEqual(store.closet.balance, 8_000 - 1_150 - 5_750)
        XCTAssertFalse(store.upgradeToRadiant(wizard), "once only")

        store.setRadiance(.subtle, for: wizard)
        let saved = try XCTUnwrap(savedSave())
        XCTAssertTrue(saved.ledger.isRadiant(wizard))
        XCTAssertEqual(saved.profile.radiance(of: wizard), .subtle)

        store.showRadiant(nil)
        XCTAssertEqual(store.preview.profile.radiantLook, PetRadiantLook([wizard: .subtle]))
    }

    func testAPinnedGoalIsSavedAndEndsWithTheUpgrade() throws {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        store.receiveGift(points: 3_000)
        store.tap(wizard)
        store.pinRadiantGoal(wizard)
        XCTAssertEqual(store.closet.radiantGoalProgress?.have, 1_850)
        XCTAssertEqual(try savedSave()?.radiantGoal, wizard)
        store.receiveGift(points: 4_000)
        XCTAssertEqual(store.closet.radiantGoalProgress?.isReady, true)
        XCTAssertTrue(store.upgradeToRadiant(wizard))
        XCTAssertNil(store.closet.radiantGoalProgress)
        XCTAssertNil(try savedSave()?.radiantGoal)
    }
}
