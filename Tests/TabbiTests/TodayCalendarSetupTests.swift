import XCTest
import TabbiKitCore
@testable import Tabbi

/// Onboarding's calendar step is drawn by Today, the module that declares
/// it, and only while Today is on.
@MainActor
final class TodayCalendarSetupTests: XCTestCase {
    func testTodayDrawsOnboardingsCalendarStep() throws {
        let types: [any NotchModule.Type] = [TodayModule.self, ClosetModule.self]
        let services = AppServices(settings: SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types)),
                                   moduleTypes: types, environment: ["TABBI_DEMO": "1"], arguments: [])
        XCTAssertNotNil(services.modules.setupView(for: .calendar, modules: [.closet, .planner]) {})
        XCTAssertNil(services.modules.setupView(for: .calendar, modules: [.closet]) {}, "the Today tab is off")
        XCTAssertNil(try XCTUnwrap(services.modules.module(TodayModule.self)).makeSetupView(for: .pet) {})
    }
}
