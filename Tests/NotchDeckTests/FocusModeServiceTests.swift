import Combine
import Foundation
import XCTest
import NotchKitCore
@testable import NotchDeck

/// Focus mode is one context service, `context.focusMode`, that Today, Focus
/// and Study share, and its kit-derived settings tell Settings whether Reset
/// to Kit Defaults has work to do without Settings knowing the Focus module.
@MainActor
final class FocusModeServiceTests: XCTestCase {
    private let moduleTypes: [any NotchModule.Type] = [TodayModule.self, FocusModule.self, StudyModule.self]

    func testEveryModuleSharesOneFocusMode() {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        let shared = SharedServices()
        func context(_ id: ModuleID) -> ModuleContext {
            ModuleContext(id: id, edition: .notchDeck, settings: settings, providers: ProviderHub(), shared: shared,
                          runMode: .demo)
        }
        XCTAssertTrue(context(.focus).focusMode === context(.study).focusMode)
        XCTAssertTrue(context(.planner).focusMode === context(.focus).focusMode)
    }

    func testFocusModeFollowsTheContextsRunMode() {
        XCTAssertFalse(FocusController(runMode: .demo).isLive)
        XCTAssertFalse(FocusController(runMode: RunMode(isDemo: false, isSnapshot: true)).isLive)
    }

    func testResetHasWorkOnlyOnceTheFocusSoundDrifts() throws {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: moduleTypes))
        let services = AppServices(settings: settings, moduleTypes: moduleTypes,
                                   environment: ["NOTCHDECK_DEMO": "1"], arguments: [])
        let focusMode = try XCTUnwrap(services.modules.module(FocusModule.self)).focusMode
        settings.switchKit(to: "student")
        let kit = try XCTUnwrap(settings.activeKit)

        var matches: [Bool] = []
        let subscription = services.modules.usesKitDefaults(of: kit).sink { matches.append($0) }
        defer { subscription.cancel() }
        XCTAssertEqual(matches, [true], "switching applied the kit's focus sound")

        // Volume is the user's; only the kit's focus sound counts.
        focusMode.settings.volume = focusMode.settings.volume == 0.2 ? 0.3 : 0.2
        XCTAssertEqual(matches, [true])
        focusMode.settings.mix = kit.defaults.resolvedFocusMix == .off ? FocusMix([.init(sound: .rain)]) : .off
        XCTAssertEqual(matches, [true, false])

        settings.resetToKitDefaults()
        XCTAssertEqual(matches, [true, false, true])
    }

    func testModulesWithoutKitStateAlwaysMatch() throws {
        let types: [any NotchModule.Type] = [StudyModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types,
                                   environment: ["NOTCHDECK_DEMO": "1"], arguments: [])
        let kit = try XCTUnwrap(settings.kits.kits.first)
        var matches: [Bool] = []
        let subscription = services.modules.usesKitDefaults(of: kit).sink { matches.append($0) }
        defer { subscription.cancel() }
        XCTAssertEqual(matches, [true])
    }
}
