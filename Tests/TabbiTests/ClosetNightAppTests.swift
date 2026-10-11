import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The closed-notch pet dozes late at night in real and demo runs, opening
/// the notch wakes it, and a snapshot run renders the same pet at any hour.
@MainActor
final class ClosetNightAppTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLiveAndDemoPetsKeepTheNightButSnapshotsDoNot() {
        XCTAssertEqual(ClosetStore(storage: EditionStorage(root: root), runMode: .live).presence.night, .standard)
        XCTAssertEqual(ClosetStore(storage: EditionStorage(root: root), runMode: .demo).presence.night, .standard)
        XCTAssertNil(ClosetStore(storage: EditionStorage(root: root), runMode: RunMode(isDemo: false, isSnapshot: true)).presence.night)
    }

    func testOpeningOrClosingTheNotchWakesThePet() throws {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let toggled = PassthroughSubject<Void, Never>()
        store.follow(notchToggled: toggled.eraseToAnyPublisher())
        XCTAssertNil(store.presence.lastWoken)
        let opened = Date()
        toggled.send()
        let wokenOnOpen = try XCTUnwrap(store.presence.lastWoken)
        XCTAssertGreaterThanOrEqual(wokenOnOpen, opened)
        Thread.sleep(forTimeInterval: 0.01)
        toggled.send()
        XCTAssertGreaterThan(try XCTUnwrap(store.presence.lastWoken), wokenOnOpen)
    }

    func testOpeningAndClosingTheNotchInTheAppWakeThePet() throws {
        let types: [any NotchModule.Type] = [ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        let store = try XCTUnwrap(services.modules.module(ClosetModule.self)).store
        // The ticker starting at launch counts as the notch closing.
        let launched = store.presence.lastWoken ?? .distantPast
        Thread.sleep(forTimeInterval: 0.01)
        services.ticker.setActive(false)
        let wokenOnOpen = try XCTUnwrap(store.presence.lastWoken)
        XCTAssertGreaterThan(wokenOnOpen, launched, "the notch opened")
        // A long look at the open notch must not use up the wake spell: it
        // starts again when the notch closes, where the pet shows.
        Thread.sleep(forTimeInterval: 0.01)
        services.ticker.setActive(true)
        XCTAssertGreaterThan(try XCTUnwrap(store.presence.lastWoken), wokenOnOpen, "the notch closed")
    }
}
