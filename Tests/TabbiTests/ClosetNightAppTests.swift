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

    func testOpeningTheNotchWakesThePet() {
        let store = ClosetStore(storage: EditionStorage(root: root), runMode: .live)
        let opened = PassthroughSubject<Void, Never>()
        store.follow(notchOpened: opened.eraseToAnyPublisher())
        XCTAssertNil(store.presence.lastWoken)
        let before = Date()
        opened.send()
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(store.presence.lastWoken), before)
    }

    func testOpeningTheNotchInTheAppWakesThePet() throws {
        let types: [any NotchModule.Type] = [ClosetModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        let store = try XCTUnwrap(services.modules.module(ClosetModule.self)).store
        XCTAssertNil(store.presence.lastWoken, "the notch starts closed")
        services.ticker.setActive(false)
        XCTAssertNotNil(store.presence.lastWoken, "the notch opened")
    }
}
