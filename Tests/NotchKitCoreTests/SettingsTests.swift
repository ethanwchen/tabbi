import XCTest
import NotchKitCore

final class ModuleLayoutTests: XCTestCase {
    func testDefaultEnablesEveryModuleInCanonicalOrder() {
        XCTAssertEqual(ModuleLayout.default.enabled, ModuleID.allCases)
    }

    func testMissingModulesAreAppendedEnabledAndUnknownOnesDropped() {
        let layout = ModuleLayout(
            orderRawValues: ["planner", "futureThing", "spotify", "planner"],
            disabledRawValues: ["spotify", "alsoUnknown"]
        )
        XCTAssertEqual(layout.order, [.planner, .spotify, .system, .claudeUsage, .claudeAsk])
        XCTAssertEqual(layout.enabled, [.planner, .system, .claudeUsage, .claudeAsk])
    }

    func testAllDisabledDataReenablesFirstModule() {
        let layout = ModuleLayout(order: [.system, .spotify], disabled: Set(ModuleID.allCases))
        XCTAssertEqual(layout.enabled, [.system])
    }

    func testCannotDisableLastEnabledModule() {
        var layout = ModuleLayout.default
        for module in ModuleID.allCases.dropLast() {
            XCTAssertTrue(layout.setEnabled(module, false))
        }
        XCTAssertFalse(layout.canDisable(.claudeAsk))
        XCTAssertFalse(layout.setEnabled(.claudeAsk, false))
        XCTAssertEqual(layout.enabled, [.claudeAsk])
        XCTAssertTrue(layout.setEnabled(.system, true))
        XCTAssertEqual(layout.enabled, [.system, .claudeAsk])
    }

    func testMoveMatchesOnMoveSemantics() {
        var layout = ModuleLayout.default
        layout.move(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(layout.order, [.system, .claudeUsage, .spotify, .planner, .claudeAsk])
        layout.move(fromOffsets: [4], toOffset: 0)
        XCTAssertEqual(layout.order, [.claudeAsk, .system, .claudeUsage, .spotify, .planner])
        layout.move(fromOffsets: [1, 3], toOffset: 5)
        XCTAssertEqual(layout.order, [.claudeAsk, .claudeUsage, .planner, .system, .spotify])
    }

    func testCyclingSkipsDisabledModulesAndWraps() {
        var layout = ModuleLayout.default
        layout.setEnabled(.system, false)
        XCTAssertEqual(layout.module(after: .spotify), .claudeUsage)
        XCTAssertEqual(layout.module(after: .claudeAsk), .spotify)
        XCTAssertEqual(layout.module(before: .claudeUsage), .spotify)
        XCTAssertEqual(layout.module(before: .spotify), .claudeAsk)
    }

    func testSelectionFallsBackToFirstEnabled() {
        var layout = ModuleLayout(order: [.planner, .spotify, .system, .claudeUsage, .claudeAsk], disabled: [])
        layout.setEnabled(.system, false)
        XCTAssertEqual(layout.resolvedSelection(.system), .planner)
        XCTAssertEqual(layout.resolvedSelection(.spotify), .spotify)
        XCTAssertEqual(layout.module(after: .system), .planner)
    }
}

final class HotkeyTests: XCTestCase {
    func testDefaultIsControlOptionSpace() {
        XCTAssertEqual(Hotkey.default.displayString, "⌃⌥Space")
        XCTAssertTrue(Hotkey.default.isValid)
    }

    func testDisplayUsesAppleModifierOrder() {
        let hotkey = Hotkey(keyCode: 40, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘K")
        XCTAssertEqual(Hotkey.Modifiers([.command, .option]).symbols, "⌥⌘")
        XCTAssertEqual(Hotkey.Modifiers([]).symbols, "")
    }

    func testRequiresANonShiftModifierAndKnownKey() {
        XCTAssertFalse(Hotkey(keyCode: 0, modifiers: [.shift]).isValid)
        XCTAssertFalse(Hotkey(keyCode: 0, modifiers: []).isValid)
        XCTAssertFalse(Hotkey(keyCode: 999, modifiers: [.command]).isValid)
        XCTAssertTrue(Hotkey(keyCode: 0, modifiers: [.command, .shift]).isValid)
    }

    func testRecordingAcceptsSafeCombinations() {
        XCTAssertEqual(Hotkey.record(keyCode: 49, modifiers: [.control, .option]), .recorded(.default))
        XCTAssertEqual(Hotkey.record(keyCode: 40, modifiers: [.option]),
                       .recorded(Hotkey(keyCode: 40, modifiers: [.option])))
        XCTAssertEqual(Hotkey.record(keyCode: 40, modifiers: [.command, .shift]),
                       .recorded(Hotkey(keyCode: 40, modifiers: [.command, .shift])))
    }

    func testRecordingRefusesCombinationsThatWouldHijackTyping() {
        XCTAssertEqual(Hotkey.record(keyCode: 0, modifiers: []), .needsModifier)
        XCTAssertEqual(Hotkey.record(keyCode: 0, modifiers: [.shift]), .needsModifier)
        // ⌘C alone would swallow Copy in every app.
        XCTAssertEqual(Hotkey.record(keyCode: 8, modifiers: [.command]), .needsModifier)
    }

    func testEscapeAloneCancelsButIsRecordableWithModifiers() {
        XCTAssertEqual(Hotkey.record(keyCode: 53, modifiers: []), .cancelled)
        XCTAssertEqual(Hotkey.record(keyCode: 53, modifiers: [.control]),
                       .recorded(Hotkey(keyCode: 53, modifiers: [.control])))
    }

    func testRecordingRejectsUnknownKeys() {
        XCTAssertEqual(Hotkey.record(keyCode: 999, modifiers: [.control]), .unsupportedKey)
    }
}

final class DisplayPreferenceTests: XCTestCase {
    private let builtIn = DisplayPreference.Screen(id: 1, isBuiltIn: true, isMain: false)
    private let external = DisplayPreference.Screen(id: 7, isBuiltIn: false, isMain: true)
    private let side = DisplayPreference.Screen(id: 9, isBuiltIn: false, isMain: false)

    func testResolvesEachPreference() {
        let screens = [external, builtIn, side]
        XCTAssertEqual(DisplayPreference.builtIn.resolve(in: screens), builtIn)
        XCTAssertEqual(DisplayPreference.main.resolve(in: screens), external)
        XCTAssertEqual(DisplayPreference.specific(9).resolve(in: screens), side)
    }

    func testFallsBackWhenPreferredScreenIsGone() {
        XCTAssertEqual(DisplayPreference.specific(42).resolve(in: [external, builtIn]), builtIn)
        XCTAssertEqual(DisplayPreference.builtIn.resolve(in: [side, external]), external)
        XCTAssertEqual(DisplayPreference.main.resolve(in: [side]), side)
        XCTAssertNil(DisplayPreference.main.resolve(in: []))
    }

    func testStorageValueRoundTrips() {
        for preference in [DisplayPreference.builtIn, .main, .specific(69_733_632)] {
            XCTAssertEqual(DisplayPreference(storageValue: preference.storageValue), preference)
        }
        XCTAssertNil(DisplayPreference(storageValue: "screen:abc"))
        XCTAssertNil(DisplayPreference(storageValue: ""))
    }
}

final class SettingsRepositoryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "NotchDeckTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testEmptyStoreYieldsDefaults() {
        let settings = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(settings, .default)
        XCTAssertFalse(settings.openOnHover)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.preferredDisplay, .builtIn)
        XCTAssertTrue(settings.notchPreview.isEnabled)
        XCTAssertEqual(settings.notchPreview.enabledKinds, Set(TickerKind.allCases))
        XCTAssertEqual(settings.notchPreview.interval, .medium)
    }

    func testRoundTripsEveryField() {
        var modules = ModuleLayout(order: [.claudeAsk, .planner], disabled: [])
        modules.setEnabled(.spotify, false)
        let settings = AppSettings(
            modules: modules,
            openOnHover: true,
            hapticsEnabled: false,
            launchAtLogin: true,
            hotkey: Hotkey(keyCode: 40, modifiers: [.command, .shift]),
            claudePathOverride: "/opt/claude",
            preferredDisplay: .specific(5),
            notchPreview: NotchPreviewSettings(isEnabled: false, disabledKinds: [.tasks, .claudeUsage], interval: .long)
        )
        let repository = SettingsRepository(defaults: defaults)
        repository.save(settings)
        XCTAssertEqual(repository.load(), settings)
    }

    func testClearingPathOverrideRemovesIt() {
        let repository = SettingsRepository(defaults: defaults)
        repository.save(AppSettings(claudePathOverride: "/opt/claude"))
        var settings = repository.load()
        settings.claudePathOverride = "   "
        XCTAssertNil(settings.claudePathOverride)
        repository.save(settings)
        XCTAssertNil(repository.load().claudePathOverride)
    }

    func testPathOverrideExpandsTilde() {
        let settings = AppSettings(claudePathOverride: " ~/bin/claude ")
        XCTAssertEqual(settings.claudePathOverride, NSHomeDirectory() + "/bin/claude")
    }

    func testMalformedValuesFallBackIndividually() {
        defaults.set("yes please", forKey: "settings.openOnHover")
        defaults.set(Data("garbage".utf8), forKey: "settings.hotkey")
        defaults.set("screen:nope", forKey: "settings.preferredDisplay")
        defaults.set(false, forKey: "settings.hapticsEnabled")
        let settings = SettingsRepository(defaults: defaults).load()
        XCTAssertFalse(settings.openOnHover)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.preferredDisplay, .builtIn)
        XCTAssertFalse(settings.hapticsEnabled)
    }

    func testFutureModuleIsEnabledAtEndOfSavedOrder() {
        defaults.set(["claudeAsk", "system", "spotify", "claudeUsage"], forKey: "settings.modules.order")
        defaults.set(["system"], forKey: "settings.modules.disabled")
        let layout = SettingsRepository(defaults: defaults).load().modules
        XCTAssertEqual(layout.enabled, [.claudeAsk, .spotify, .claudeUsage, .planner])
    }

    func testMalformedPreviewValuesFallBack() {
        defaults.set(7, forKey: "settings.preview.interval")
        defaults.set(["focus", "hologram"], forKey: "settings.preview.disabledKinds")
        defaults.set("on", forKey: "settings.preview.enabled")
        let preview = SettingsRepository(defaults: defaults).load().notchPreview
        XCTAssertEqual(preview.interval, .medium)
        XCTAssertEqual(preview.disabledKinds, [.focus])
        XCTAssertTrue(preview.isEnabled)
    }
}

final class NotchPreviewSettingsTests: XCTestCase {
    func testTogglingAKindOnlyAffectsThatKind() {
        var preview = NotchPreviewSettings.default
        preview.setEnabled(.nowPlaying, false)
        XCTAssertFalse(preview.isEnabled(.nowPlaying))
        XCTAssertEqual(preview.enabledKinds, [.meeting, .focus, .tasks, .claudeUsage])
        preview.setEnabled(.nowPlaying, true)
        XCTAssertEqual(preview.enabledKinds, Set(TickerKind.allCases))
    }

    func testMasterSwitchHidesEveryKindButKeepsChoices() {
        var preview = NotchPreviewSettings(disabledKinds: [.tasks])
        preview.isEnabled = false
        XCTAssertTrue(preview.enabledKinds.isEmpty)
        XCTAssertFalse(preview.isEnabled(.tasks))
        preview.isEnabled = true
        XCTAssertEqual(preview.enabledKinds, Set(TickerKind.allCases).subtracting([.tasks]))
    }

    func testPreviewSkipsKindsWhoseModuleIsOff() {
        var settings = AppSettings(notchPreview: NotchPreviewSettings(disabledKinds: [.tasks]))
        _ = settings.modules.setEnabled(.claudeUsage, false)
        _ = settings.modules.setEnabled(.spotify, false)
        XCTAssertEqual(settings.previewKinds, [.meeting, .focus])
        _ = settings.modules.setEnabled(.planner, false)
        XCTAssertTrue(settings.previewKinds.isEmpty)
        settings.notchPreview.isEnabled = false
        _ = settings.modules.setEnabled(.planner, true)
        XCTAssertTrue(settings.previewKinds.isEmpty)
    }

    func testIntervalsMatchTheOfferedChoices() {
        XCTAssertEqual(TickerInterval.allCases.map(\.seconds), [5, 8, 12])
        XCTAssertEqual(TickerInterval.medium.title, "8 seconds")
    }
}
