import XCTest
import TabbiKitCore
@testable import Tabbi

/// Onboarding's Anki step is drawn by the Anki module, the one that
/// declares it, and only while the Anki tab is on.
@MainActor
final class AnkiConnectSetupTests: XCTestCase {
    func testAnkiDrawsOnboardingsAnkiStep() throws {
        let types: [any NotchModule.Type] = [AnkiModule.self, ClosetModule.self]
        let services = AppServices(settings: SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types)),
                                   moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        XCTAssertNotNil(services.modules.setupView(for: .anki, modules: [.closet, .anki]) {})
        XCTAssertNil(services.modules.setupView(for: .anki, modules: [.closet]) {}, "the Anki tab is off")
        XCTAssertNil(try XCTUnwrap(services.modules.module(AnkiModule.self)).makeSetupView(for: .calendar) {})
    }
}
