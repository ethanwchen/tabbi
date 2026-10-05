import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

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

    /// At launch the pet sees the idle Pomodoro before the welcome window's
    /// kit pick. Taking that baseline must not save the starter, or the
    /// picked kit's pet would never apply.
    func testSeeingAnIdleTimerDoesNotSaveTheStarter() throws {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        let focus = PassthroughSubject<ProvidedFocus?, Never>()
        store.follow(focus: focus.eraseToAnyPublisher())
        focus.send(pomodoro(completed: 3))
        XCTAssertFalse(FileManager.default.fileExists(atPath: saveURL.path), "a baseline alone isn't a save")

        store.useStarter(corgi)
        XCTAssertEqual(store.profile.breed, .corgi, "the kit picked after launch decides the first pet")

        focus.send(pomodoro(completed: 4))
        let save = try XCTUnwrap(PetSave.load(from: saveURL), "the first points save the pet")
        XCTAssertEqual(save.profile.breed, .corgi)
        XCTAssertEqual(save.creditedFocusCount, 4, "the baseline survived the kit switch, so the session was paid")
        XCTAssertGreaterThan(save.ledger.balance, 0)
    }

    /// A session that ends while Tabbi is closed is caught up at the next
    /// launch, so the baseline taken when it started has to be on disk.
    func testStartingAClockSavesTheBaseline() throws {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        let focus = PassthroughSubject<ProvidedFocus?, Never>()
        store.follow(focus: focus.eraseToAnyPublisher())
        focus.send(pomodoro(completed: 0))
        focus.send(pomodoro(completed: 0, clock: .countdown(endsAt: .now.addingTimeInterval(1500))))
        XCTAssertEqual(try XCTUnwrap(PetSave.load(from: saveURL)).creditedFocusCount, 0)

        let relaunched = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        let caughtUp = PassthroughSubject<ProvidedFocus?, Never>()
        relaunched.follow(focus: caughtUp.eraseToAnyPublisher())
        caughtUp.send(pomodoro(completed: 1))
        XCTAssertGreaterThan(try XCTUnwrap(PetSave.load(from: saveURL)).ledger.balance, 0,
                             "the session that ended while Tabbi was closed is paid")
    }

    private func pomodoro(completed: Int, clock: ProvidedFocus.Clock = .idle) -> ProvidedFocus {
        ProvidedFocus(
            source: ModuleID("focus"), phase: .focus, clock: clock,
            phaseLength: 1500, focusLength: 1500, completedFocusCount: completed
        )
    }

    func testDemoKeepsItsSamplePet() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .demo, starter: corgi)
        let demo = store.profile
        store.useStarter(.starter(.cat))
        XCTAssertEqual(store.profile, demo)
    }
}
