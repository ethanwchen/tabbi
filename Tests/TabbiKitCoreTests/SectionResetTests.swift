import XCTest
import TabbiKitCore

/// Settings' per-section "Reset to Defaults": General and Look each put back
/// only their own preferences.
final class SectionResetTests: XCTestCase {
    private let catalog = ModuleCatalog.builtIn
    private var medicine: KitManifest { KitLibrary.bundled["medicine"]! }
    private var essentials: KitManifest { KitLibrary.bundled["essentials"]! }

    private func customized() -> AppSettings {
        var settings = AppSettings(modules: .default)
        settings.apply(medicine, catalog: catalog)
        settings.openOnHover = true
        settings.hapticsEnabled = false
        settings.celebrationSoundEnabled = false
        settings.launchAtLogin = true
        settings.hotkey = Hotkey(keyCode: 0, modifiers: [.command, .option])
        settings.preferredDisplay = .main
        settings.showOnExternalDisplays = false
        settings.hideInFullscreen = false
        settings.hideFromScreenCapture = true
        settings.hideInMissionControl = true
        settings.notchMode = .hidden
        settings.panelSize = .compact
        settings.motionPace = .fast
        settings.notchPreview.isEnabled = false
        settings.notchPreview.interval = .long
        settings.notchPreview.setEnabled(.focus, false)
        settings.claudePathOverride = "/opt/claude"
        settings.themeID = ThemeID.neon
        return settings
    }

    func testGeneralResetRestoresGeneralAndKeepsTheRest() {
        var settings = customized()
        XCTAssertFalse(settings.usesGeneralDefaults(of: medicine, catalog: catalog))

        settings.resetGeneral(to: medicine, catalog: catalog)

        let fresh = AppSettings(modules: settings.modules)
        XCTAssertEqual(settings.openOnHover, fresh.openOnHover)
        XCTAssertEqual(settings.hapticsEnabled, fresh.hapticsEnabled)
        XCTAssertEqual(settings.celebrationSoundEnabled, fresh.celebrationSoundEnabled)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.preferredDisplay, .builtIn)
        XCTAssertEqual(settings.showOnExternalDisplays, fresh.showOnExternalDisplays)
        XCTAssertEqual(settings.hideInFullscreen, fresh.hideInFullscreen)
        XCTAssertFalse(settings.hideFromScreenCapture)
        XCTAssertFalse(settings.hideInMissionControl)
        XCTAssertEqual(settings.notchMode, .alwaysVisible)
        XCTAssertEqual(settings.panelSize, .regular)
        XCTAssertEqual(settings.motionPace, .smooth)
        XCTAssertTrue(settings.notchPreview.isEnabled)
        XCTAssertEqual(settings.notchPreview.interval, NotchPreviewSettings.default.interval)
        XCTAssertTrue(settings.usesGeneralDefaults(of: medicine, catalog: catalog))

        XCTAssertTrue(settings.launchAtLogin, "a login item is the user's deliberate system choice")
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.modules, customized().modules)
        XCTAssertEqual(settings.claudePathOverride, "/opt/claude")
        XCTAssertEqual(settings.themeID, ThemeID.neon)
    }

    func testGeneralResetShowsTheKitsLiveActivityItems() throws {
        var settings = customized()
        settings.resetGeneral(to: medicine, catalog: catalog)
        let kinds = try XCTUnwrap(medicine.defaults.resolvedTicker(catalog: catalog))
        let shown = TickerKind.all(in: catalog).filter { settings.notchPreview.isEnabled($0) }
        XCTAssertEqual(Set(shown), kinds)

        settings.resetGeneral(to: nil, catalog: catalog)
        XCTAssertTrue(settings.notchPreview.disabledKinds.isEmpty, "without a kit every item shows")
    }

    func testAFreshInstallAlreadyUsesGeneralDefaults() {
        var settings = AppSettings(modules: .default)
        settings.apply(essentials, catalog: catalog)
        XCTAssertTrue(settings.usesGeneralDefaults(of: essentials, catalog: catalog))
        settings.launchAtLogin = true
        XCTAssertTrue(settings.usesGeneralDefaults(of: essentials, catalog: catalog),
                      "launch at login is not part of the reset")
        settings.openOnHover.toggle()
        XCTAssertFalse(settings.usesGeneralDefaults(of: essentials, catalog: catalog))
    }

    func testGeneralResetKeepsTheUsersName() {
        var settings = customized()
        settings.displayName = "Ada"
        XCTAssertTrue(AppSettings(displayName: "Ada", modules: .default).usesGeneralDefaults(of: nil, catalog: catalog),
                      "a name alone is nothing to reset")
        settings.resetGeneral(to: medicine, catalog: catalog)
        XCTAssertEqual(settings.displayName, "Ada")
    }

    func testLookDefaultIsTheKitsThemeOrTheAppDefault() {
        XCTAssertEqual(AppSettings.defaultTheme(for: medicine), ThemeID.cozy)
        XCTAssertEqual(AppSettings.defaultTheme(for: essentials), ThemeID.midnight)
        XCTAssertEqual(AppSettings.defaultTheme(for: nil), ThemeCatalog.defaultID)
    }
}
