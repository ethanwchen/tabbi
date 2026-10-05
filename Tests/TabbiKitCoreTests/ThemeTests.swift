import XCTest
@testable import TabbiKitCore

final class ThemeCatalogTests: XCTestCase {
    func testShipsEveryThemeOnceInPickerOrder() {
        XCTAssertEqual(ThemeCatalog.all.map(\.id),
                       [.midnight, .graphite, .liquidGlass, .neon, .monochrome, .cozy, .sakura, .forest])
        XCTAssertEqual(Set(ThemeCatalog.all.map(\.name)).count, ThemeCatalog.all.count)
        XCTAssertEqual(ThemeCatalog.all.filter { $0.family == .cozy }.map(\.id), [.cozy, .sakura, .forest])
    }

    func testEveryPanelBodyIsOpaqueBlackSoTheOpenNotchMeetsTheHardware() {
        for theme in ThemeCatalog.all {
            XCTAssertEqual(theme.palette.background, ThemeColor(white: 0), theme.name)
            if let glow = theme.palette.glow {
                // A hint of color, never a repainted panel.
                XCTAssertLessThanOrEqual(glow.opacity, 0.3, theme.name)
            }
        }
    }

    func testTextKeepsReadableContrastOnEveryCard() {
        for theme in ThemeCatalog.all {
            let palette = theme.palette
            // Worst case: text on a card lit by the full glow.
            let body = (palette.glow ?? palette.background).composited(over: palette.background)
            let card = palette.surfaceHover.composited(over: body)
            func contrast(_ text: ThemeColor) -> Double { text.composited(over: card).contrast(with: card) }
            XCTAssertGreaterThanOrEqual(contrast(palette.primaryText), 7, "\(theme.name) primary")
            XCTAssertGreaterThanOrEqual(contrast(palette.secondaryText), 4.5, "\(theme.name) secondary")
            XCTAssertGreaterThanOrEqual(contrast(palette.tertiaryText), 2.5, "\(theme.name) tertiary")
        }
    }

    func testCozyThemesMoveGentlyAndOnlyLiquidGlassUsesGlass() {
        for theme in ThemeCatalog.all {
            XCTAssertEqual(theme.motion == .gentle, theme.family == .cozy, theme.name)
            XCTAssertEqual(theme.controls == .glass, theme.id == .liquidGlass, theme.name)
        }
    }

    func testUnknownIDsResolveToTheDefault() {
        XCTAssertNil(ThemeCatalog.theme("aurora"))
        XCTAssertEqual(ThemeCatalog.resolve("aurora").id, ThemeCatalog.defaultID)
        XCTAssertEqual(ThemeCatalog.resolve(.forest).name, "Forest")
    }

    func testKitValuesAcceptTheOldNotchName() {
        XCTAssertEqual(ThemeCatalog.id(forKitValue: "notch"), .midnight)
        XCTAssertEqual(ThemeCatalog.id(forKitValue: "cozy"), .cozy)
        XCTAssertNil(ThemeCatalog.id(forKitValue: "aurora"))
    }
}

final class ThemeColorTests: XCTestCase {
    func testContrastMatchesWCAG() {
        XCTAssertEqual(ThemeColor(white: 1).contrast(with: ThemeColor(white: 0)), 21, accuracy: 0.01)
        XCTAssertEqual(ThemeColor(white: 0.5).contrast(with: ThemeColor(white: 0.5)), 1, accuracy: 0.001)
    }

    func testCompositingAndMixing() {
        let half = ThemeColor(white: 1, opacity: 0.5).composited(over: ThemeColor(white: 0))
        XCTAssertEqual(half, ThemeColor(white: 0.5))
        let mixed = ThemeColor(red: 1, green: 0, blue: 0).mixed(with: ThemeColor(red: 0, green: 0, blue: 1), by: 0.25)
        XCTAssertEqual(mixed, ThemeColor(red: 0.75, green: 0, blue: 0.25))
    }
}

final class AccentTreatmentTests: XCTestCase {
    private let teal = ModuleAccent(red: 0.2, green: 0.6, blue: 0.5)

    func testOriginalKeepsTheModuleAccent() {
        XCTAssertEqual(AccentTreatment.original.apply(to: teal), ThemeColor(teal))
    }

    func testMonochromeIsALightGray() {
        let gray = AccentTreatment.monochrome.apply(to: teal)
        XCTAssertEqual(gray.red, gray.green)
        XCTAssertEqual(gray.green, gray.blue)
        XCTAssertGreaterThan(gray.red, 0.55)
        XCTAssertLessThanOrEqual(gray.red, 0.95)
    }

    func testVividKeepsTheHueAtFullSaturation() {
        let vivid = AccentTreatment.vivid.apply(to: teal)
        XCTAssertEqual(vivid.red, 0, accuracy: 0.0001)
        XCTAssertEqual(vivid.green, 1, accuracy: 0.0001)
        XCTAssertEqual(vivid.blue, 0.75, accuracy: 0.0001)
        // A gray accent has no hue to saturate.
        XCTAssertEqual(AccentTreatment.vivid.apply(to: ModuleAccent(red: 0.4, green: 0.4, blue: 0.4)),
                       ThemeColor(white: 1))
    }

    func testPastelIsLighterAndWarmer() {
        let pastel = AccentTreatment.pastel.apply(to: teal)
        XCTAssertGreaterThan(pastel.luminance, ThemeColor(teal).luminance)
        XCTAssertGreaterThan(pastel.red, teal.red)
    }
}

final class ControlMaterialTests: XCTestCase {
    func testGlassOnlyWhereTheSystemHasItAndTransparencyIsAllowed() {
        XCTAssertEqual(ControlMaterial.resolve(.glass, glassAvailable: true, reduceTransparency: false), .glass)
        XCTAssertEqual(ControlMaterial.resolve(.glass, glassAvailable: false, reduceTransparency: false), .material)
        XCTAssertEqual(ControlMaterial.resolve(.glass, glassAvailable: true, reduceTransparency: true), .opaque)
        XCTAssertEqual(ControlMaterial.resolve(.glass, glassAvailable: false, reduceTransparency: true), .opaque)
    }

    func testSolidThemesAlwaysUseTheirOpaqueSurface() {
        XCTAssertEqual(ControlMaterial.resolve(.solid, glassAvailable: true, reduceTransparency: false), .opaque)
    }
}

final class ThemeSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "ThemeSettingsTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func kit(theme: String?) throws -> KitManifest {
        var kit = try XCTUnwrap(KitLibrary.bundled["essentials"])
        kit.defaults.theme = theme
        return kit
    }

    func testFreshInstallUsesTheDefault() {
        XCTAssertEqual(SettingsRepository(defaults: defaults).load().themeID, ThemeCatalog.defaultID)
    }

    func testApplyingAKitSwitchesToItsThemeAndUndoPutsItBack() throws {
        var settings = AppSettings(themeID: .neon)
        let before = settings.kitState
        settings.apply(try kit(theme: "forest"))
        XCTAssertEqual(settings.themeID, .forest)
        settings.kitState = before
        XCTAssertEqual(settings.themeID, .neon)
    }

    func testAKitWithoutAKnownThemeKeepsTheUsersTheme() throws {
        var settings = AppSettings(themeID: .graphite)
        settings.apply(try kit(theme: nil))
        XCTAssertEqual(settings.themeID, .graphite)
        settings.apply(try kit(theme: "aurora"))
        XCTAssertEqual(settings.themeID, .graphite)
    }

    func testPickingAnotherThemeMeansTheKitDefaultsChanged() throws {
        let kit = try kit(theme: "cozy")
        var settings = AppSettings()
        settings.apply(kit)
        XCTAssertTrue(settings.usesDefaults(of: kit))
        settings.themeID = .midnight
        XCTAssertFalse(settings.usesDefaults(of: kit))
    }

    func testThemeIDsFromANewerBuildSurviveASave() {
        defaults.set("aurora", forKey: "settings.theme")
        let repository = SettingsRepository(defaults: defaults)
        let settings = repository.load()
        XCTAssertEqual(settings.themeID, "aurora")
        repository.save(settings)
        XCTAssertEqual(defaults.string(forKey: "settings.theme"), "aurora")
    }

    func testKitValidationWarnsAboutAnUnknownTheme() throws {
        XCTAssertTrue(try kit(theme: "aurora").issues().contains(.unknownTheme("aurora")))
        XCTAssertFalse(try kit(theme: "notch").issues().contains { if case .unknownTheme = $0 { true } else { false } })
    }

    func testMedSchoolStartsCozyAndEssentialsMidnight() {
        func theme(_ kit: String) -> ThemeID? {
            KitLibrary.bundled[kit]?.defaults.theme.flatMap(ThemeCatalog.id(forKitValue:))
        }
        XCTAssertEqual(theme("medicine"), .cozy)
        XCTAssertEqual(theme("essentials"), .midnight)
    }
}
