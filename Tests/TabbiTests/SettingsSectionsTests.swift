import XCTest
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// Settings has five sections in plain words whatever tabs are on, and a
/// module's own settings open from its row in Tabs instead of adding a
/// toolbar item.
@MainActor
final class SettingsSectionsTests: XCTestCase {
    func testSettingsHasFiveSectionsWhateverTabsAreOn() {
        let services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog), moduleTypes: ModuleList.all,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        let window = SettingsWindowController(settings: services.settings, modules: services.modules)
        XCTAssertEqual(window.paneIDs, ["general", "tabs", "look", "connections", "about"])

        services.settings.settings.modules.add(.party)
        services.settings.settings.modules.add(.focus)
        XCTAssertEqual(window.paneIDs, ["general", "tabs", "look", "connections", "about"],
                       "turning modules on adds no toolbar items")
    }

    /// A closed Settings window is let go with its panes (about 20 MB of
    /// views once they have all shown) and comes back on the pane it closed on.
    func testClosingSettingsLetsItGoAndReopeningShowsTheSamePane() {
        _ = NSApplication.shared
        let services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog), moduleTypes: ModuleList.all,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        services.openSettings(pane: AppSettingsPane.look.rawValue)
        XCTAssertEqual(services.settingsPaneOnScreen, "look")

        services.closeSettings()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(services.hasSettingsWindow, "the closed window is still held")

        services.openSettings()
        XCTAssertEqual(services.settingsPaneOnScreen, "look", "reopening shows the pane Settings closed on")
        services.openSettings(pane: AppSettingsPane.about.rawValue)
        XCTAssertEqual(services.settingsPaneOnScreen, "about", "a pane asked for wins")
        services.closeSettings()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(services.hasSettingsWindow)
    }

    func testModulesWithSettingsOfferThemFromTheirTabRow() {
        let services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog), moduleTypes: ModuleList.all,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        let options = AppSettingsPane.moduleOptions(settings: services.settings, modules: services.modules,
                                                    onboarding: nil)
        XCTAssertEqual(options(.planner)?.id, "focus", "Today runs the focus timer, so it offers the focus settings")
        XCTAssertEqual(options(.focus)?.id, "focus", "Focus shares the same settings")
        XCTAssertEqual(options(.closet)?.id, "coach")
        XCTAssertEqual(options(.party)?.id, "party")
        #if APPSTORE
        XCTAssertNil(options(.spotify), "the App Store build has no SoundCloud player to opt in to")
        #else
        XCTAssertEqual(options(.spotify)?.id, "nowPlaying", "Now Playing offers the opt-in SoundCloud player")
        #endif
    }
}
