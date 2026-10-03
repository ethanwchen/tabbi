import Foundation
import XCTest
import NotchKitCore
@testable import NotchDeck

/// A kit's `closet.pet` decides the first pet: the pet follows kit switches
/// (such as the one picked on first run) until it is saved, and a saved pet
/// never changes.
@MainActor
final class ClosetStarterPetTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("closet-\(UUID().uuidString)")
    private let corgi = PetProfile.starter(kit: KitDefaults(moduleSettings: ["closet": ["pet": ["breed": "corgi"]]]))

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var saveURL: URL { ClosetStore.saveURL(in: EditionStorage(root: folder)) }

    func testAnUnsavedPetFollowsTheKitAndIsNotWrittenUntilChanged() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        XCTAssertEqual(store.profile, .starter(.cat))
        store.useStarter(corgi)
        XCTAssertEqual(store.profile.breed, .corgi)
        XCTAssertEqual(store.presence.profile.breed, .corgi, "the closed notch shows the same pet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path), "a starter pet isn't saved by itself")
    }

    func testASavedPetKeepsItsLookOnKitSwitches() throws {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: corgi)
        store.rename("Waffles")
        store.useStarter(.starter(.cat))
        XCTAssertEqual(store.profile.breed, .corgi)
        XCTAssertEqual(store.profile.name, "Waffles")

        let relaunched = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        relaunched.useStarter(.starter(.cat))
        XCTAssertEqual(relaunched.profile.name, "Waffles", "the save wins over any kit's starter")
    }

    func testDemoKeepsItsSamplePet() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .demo, starter: corgi)
        let demo = store.profile
        store.useStarter(.starter(.cat))
        XCTAssertEqual(store.profile, demo)
    }
}
