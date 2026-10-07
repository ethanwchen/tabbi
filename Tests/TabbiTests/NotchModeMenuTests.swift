import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// The notch's right-click menu switches the notch mode through the app's
/// settings, so the choice is saved and Settings > General shows it.
@MainActor
final class NotchModeMenuTests: XCTestCase {
    func testTheMenuSavesTheNotchModeInSettings() throws {
        let types: [any NotchModule.Type] = [TodayModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        let setNotchMode = try XCTUnwrap(ModuleViews.notchContent(services: services).setNotchMode)

        setNotchMode(.hidden)
        XCTAssertEqual(settings.settings.notchMode, .hidden)
        setNotchMode(.showOnHover)
        XCTAssertEqual(settings.settings.notchMode, .showOnHover)
        setNotchMode(.alwaysVisible)
        XCTAssertEqual(settings.settings.notchMode, .alwaysVisible)
    }
}
