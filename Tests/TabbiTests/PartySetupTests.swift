import XCTest
import TabbiKitCore
@testable import Tabbi

/// Onboarding's party step is drawn by the Party module, the one
/// that declares it, and only while the Party tab is on.
@MainActor
final class PartySetupTests: XCTestCase {
    func testPartyDrawsOnboardingsPartyStep() throws {
        let types: [any NotchModule.Type] = [PartyModule.self, ClosetModule.self]
        let services = AppServices(settings: SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types)),
                                   moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        XCTAssertNotNil(services.modules.setupView(for: .party, modules: [.closet, .party]) {})
        XCTAssertNil(services.modules.setupView(for: .party, modules: [.closet]) {}, "the Party tab is off")
        XCTAssertNil(try XCTUnwrap(services.modules.module(PartyModule.self)).makeSetupView(for: .pet) {})
    }
}
