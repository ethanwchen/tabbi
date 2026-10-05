import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A layout has one timer: with Study on (the Med School kit), Today shows
/// Study's clock instead of offering its own Pomodoro.
@MainActor
final class FocusClockOwnerTests: XCTestCase {
    private let moduleTypes: [any NotchModule.Type] = [TodayModule.self, FocusModule.self, StudyModule.self]

    private var services: AppServices!
    private var today: TodayModule!

    override func setUp() async throws {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: moduleTypes))
        services = AppServices(settings: settings, moduleTypes: moduleTypes,
                               environment: ["TABBI_DEMO": "1"], arguments: [])
        today = try XCTUnwrap(services.modules.module(TodayModule.self))
    }

    override func tearDown() async throws {
        services = nil
        today = nil
    }

    func testStudyOwnsTheTimerWhileItIsOn() {
        services.settings.settings.modules.setEnabled(.study, true)
        XCTAssertEqual(today.store.focusClockOwner, .study)
        services.settings.settings.modules.setEnabled(.study, false)
        XCTAssertNil(today.store.focusClockOwner)
    }

    func testTheFocusTabSharesThePomodoroSoTodayKeepsIt() {
        services.settings.settings.modules.setEnabled(.study, false)
        services.settings.settings.modules.setEnabled(.focus, true)
        XCTAssertNil(today.store.focusClockOwner)
    }

    func testTheMedSchoolKitHasOneTimer() throws {
        services.settings.switchKit(to: "medicine")
        XCTAssertEqual(today.store.focusClockOwner, .study)
        services.settings.switchKit(to: "productivity")
        XCTAssertNil(today.store.focusClockOwner)
    }
}
