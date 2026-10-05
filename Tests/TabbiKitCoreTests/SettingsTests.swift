import XCTest
import TabbiKitCore

final class ModuleLayoutTests: XCTestCase {
    private let classic: [ModuleID] = [.spotify, .system, .claudeUsage, .planner, .claudeAsk]
    /// Built-in modules that start switched off: Focus and the study tabs.
    private let optIn: [ModuleID] = [.focus, .study, .anki, .party, .closet]

    func testDefaultShowsTheOriginalTabsAndParksTheRest() {
        XCTAssertEqual(ModuleLayout.default.enabled, classic)
        XCTAssertEqual(ModuleLayout.default.order, ModuleCatalog.builtIn.ids)
        XCTAssertFalse(optIn.contains(where: ModuleLayout.default.isEnabled))
    }

    func testMissingModulesAreAppendedSwitchedOffAndUnknownOnesDropped() {
        let layout = ModuleLayout(
            orderRawValues: ["planner", "futureThing", "spotify", "system", "planner"],
            disabledRawValues: ["spotify", "alsoUnknown"]
        )
        XCTAssertEqual(layout.order, [.planner, .spotify, .system, .claudeUsage, .claudeAsk] + optIn)
        XCTAssertEqual(layout.enabled, [.planner, .system])
    }

    func testAllDisabledDataReenablesFirstModule() {
        let layout = ModuleLayout(order: [.system, .spotify], disabled: Set(ModuleCatalog.builtIn.ids))
        XCTAssertEqual(layout.enabled, [.system])
    }

    func testCannotDisableLastEnabledModule() {
        var layout = ModuleLayout.default
        for module in classic.dropLast() {
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
        XCTAssertEqual(layout.order, [.system, .claudeUsage, .spotify, .planner, .claudeAsk] + optIn)
        layout.move(fromOffsets: [4], toOffset: 0)
        XCTAssertEqual(layout.order, [.claudeAsk, .system, .claudeUsage, .spotify, .planner] + optIn)
        layout.move(fromOffsets: [1, 3], toOffset: 5)
        XCTAssertEqual(layout.order, [.claudeAsk, .claudeUsage, .planner, .system, .spotify] + optIn)
    }

    func testCyclingSkipsDisabledModulesAndWraps() {
        var layout = ModuleLayout.default
        layout.setEnabled(.system, false)
        XCTAssertEqual(layout.module(after: .spotify), .claudeUsage)
        XCTAssertEqual(layout.module(after: .claudeAsk), .spotify)
        XCTAssertEqual(layout.module(before: .claudeUsage), .spotify)
        XCTAssertEqual(layout.module(before: .spotify), .claudeAsk)
    }

    func testNumberShortcutsFollowEnabledTabs() {
        var layout = ModuleLayout.default
        layout.setEnabled(.system, false)
        XCTAssertEqual(layout.module(forShortcut: 1), .spotify)
        XCTAssertEqual(layout.module(forShortcut: 2), .claudeUsage)
        XCTAssertEqual(layout.module(forShortcut: 4), .claudeAsk)
        XCTAssertNil(layout.module(forShortcut: 5))
        XCTAssertNil(layout.module(forShortcut: 0))
        XCTAssertEqual(layout.shortcut(for: .claudeUsage), 2)
        XCTAssertNil(layout.shortcut(for: .system))
        XCTAssertNil(layout.shortcut(for: .study))
    }

    func testNumberShortcutsStopAtNine() {
        let ten: [ModuleID] = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
        let catalog = ModuleCatalog(ten.map {
            ModuleDescriptor(id: $0, title: $0.rawValue, symbol: "circle", category: .productivity,
                             accent: ModuleAccent(red: 1, green: 1, blue: 1))
        })
        let layout = ModuleLayout(order: ten, disabled: [], catalog: catalog)
        XCTAssertEqual(layout.enabled.count, 10)
        XCTAssertEqual(layout.module(forShortcut: 9), "i")
        XCTAssertNil(layout.module(forShortcut: 10))
        XCTAssertEqual(layout.shortcut(for: "i"), 9)
        XCTAssertNil(layout.shortcut(for: "j"), "the tenth tab is reachable by arrows and swipes only")
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
        suiteName = "TabbiTests.\(UUID().uuidString)"
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
            kitID: "student",
            hasChosenKit: true,
            kitAnswers: ["level": ["college"], "flashcards": ["anki", "no"]],
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

    func testModulesMissingFromSavedOrderStartSwitchedOff() {
        defaults.set(["claudeAsk", "system", "spotify", "claudeUsage"], forKey: "settings.modules.order")
        defaults.set(["system"], forKey: "settings.modules.disabled")
        let layout = SettingsRepository(defaults: defaults).load().modules
        XCTAssertEqual(layout.enabled, [.claudeAsk, .spotify, .claudeUsage])
        XCTAssertEqual(layout.order.suffix(6), [.planner, .focus, .study, .anki, .party, .closet])
    }

    func testFirstRunUsesTheDefaultKitsLayout() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        let settings = SettingsRepository(defaults: defaults, defaultKitID: "medicine").load()
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.modules, medicine.layout())
        XCTAssertEqual(settings.modules.enabled.first, .study)
    }

    func testSavedLayoutWinsOverTheKitsLayout() {
        let repository = SettingsRepository(defaults: defaults, defaultKitID: "medicine")
        var settings = repository.load()
        settings.modules.setEnabled(.system, true)
        repository.save(settings)
        let reloaded = repository.load()
        XCTAssertEqual(reloaded.kitID, "medicine")
        XCTAssertTrue(reloaded.modules.isEnabled(.system))
    }

    func testFirstRunHasNotChosenAKitUntilOneIsApplied() throws {
        let repository = SettingsRepository(defaults: defaults, defaultKitID: "medicine")
        var settings = repository.load()
        XCTAssertFalse(settings.hasChosenKit)
        // Saving unrelated preferences doesn't count as choosing.
        settings.openOnHover = true
        repository.save(settings)
        XCTAssertFalse(repository.load().hasChosenKit)

        settings.apply(try XCTUnwrap(KitLibrary.bundled["student"]))
        repository.save(settings)
        let reloaded = repository.load()
        XCTAssertTrue(reloaded.hasChosenKit)
        XCTAssertEqual(reloaded.kitID, "student")
    }

    func testLayoutsSavedBeforeKitsExistedCountAsChosen() {
        // A pre-kits install: a tab layout but no kit and no flag.
        defaults.set(["spotify", "system", "claudeUsage", "planner", "claudeAsk"], forKey: "settings.modules.order")
        XCTAssertTrue(SettingsRepository(defaults: defaults).load().hasChosenKit)
    }

    func testUnknownSavedKitFallsBackToTheDefaultKit() {
        defaults.set("removed-import", forKey: "settings.kit")
        let settings = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(settings.kitID, KitLibrary.defaultKitID)
        XCTAssertEqual(settings.modules, .default)
    }

    func testApplyingAKitReplacesTheLayoutAndKeepsOtherPreferences() throws {
        let student = try XCTUnwrap(KitLibrary.bundled["student"])
        var settings = AppSettings(openOnHover: true)
        settings.modules.setEnabled(.spotify, false)
        settings.apply(student, answers: ["flashcards": ["anki"]])
        XCTAssertEqual(settings.kitID, "student")
        XCTAssertEqual(settings.modules, student.layout(answers: ["flashcards": ["anki"]]))
        XCTAssertTrue(settings.modules.isEnabled(.anki))
        XCTAssertTrue(settings.openOnHover)
        XCTAssertTrue(settings.hasChosenKit)
    }

    func testResetCheckUsesTheSavedOnboardingAnswers() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        var settings = AppSettings()
        settings.apply(medicine, answers: ["anki": ["no"]])
        XCTAssertEqual(settings.kitAnswers, ["anki": ["no"]])
        XCTAssertFalse(settings.modules.isEnabled(.anki))
        XCTAssertTrue(settings.usesDefaults(of: medicine), "the answers' tabs are this user's kit defaults")

        settings.modules.setEnabled(.anki, true)
        XCTAssertFalse(settings.usesDefaults(of: medicine))
    }

    func testApplyingAKitWithoutAnswersClearsTheOldOnes() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        let student = try XCTUnwrap(KitLibrary.bundled["student"])
        var settings = AppSettings()
        settings.apply(medicine, answers: ["anki": ["no"]])
        settings.apply(student)
        XCTAssertEqual(settings.kitAnswers, [:])
    }

    func testApplyingAKitWithTickerDefaultsReplacesThePreviews() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        var settings = AppSettings()
        settings.notchPreview.setEnabled(.focus, false)
        settings.notchPreview.interval = .long
        settings.apply(medicine)
        XCTAssertEqual(settings.notchPreview.disabledKinds, [.claudeUsage])
        XCTAssertEqual(settings.notchPreview.interval, .long)
        XCTAssertTrue(settings.usesDefaults(of: medicine))

        settings.notchPreview.setEnabled(.claudeUsage, true)
        XCTAssertFalse(settings.usesDefaults(of: medicine), "a changed preview means reset has work to do")
    }

    func testApplyingAKitWithoutTickerDefaultsKeepsThePreviews() throws {
        let productivity = try XCTUnwrap(KitLibrary.bundled["productivity"])
        var settings = AppSettings()
        settings.notchPreview.setEnabled(.meeting, false)
        settings.apply(productivity)
        XCTAssertEqual(settings.notchPreview.disabledKinds, [.meeting])
        XCTAssertTrue(settings.usesDefaults(of: productivity))
    }

    func testMalformedPreviewValuesFallBack() {
        defaults.set(7, forKey: "settings.preview.interval")
        defaults.set(["focus", "hologram"], forKey: "settings.preview.disabledKinds")
        defaults.set("on", forKey: "settings.preview.enabled")
        let preview = SettingsRepository(defaults: defaults).load().notchPreview
        XCTAssertEqual(preview.interval, .medium)
        // An unknown kind may be a module's highlights this build lacks, so
        // the choice is kept for when it comes back.
        XCTAssertEqual(preview.disabledKinds, [.focus, TickerKind(rawValue: "hologram")])
        XCTAssertTrue(preview.isEnabled)
    }
}

final class NotchPreviewSettingsTests: XCTestCase {
    func testTogglingAKindOnlyAffectsThatKind() {
        var preview = NotchPreviewSettings.default
        preview.setEnabled(.nowPlaying, false)
        XCTAssertFalse(preview.isEnabled(.nowPlaying))
        XCTAssertEqual(preview.enabledKinds, [.meeting, .focus, .tasks, .progress, .claudeUsage, .party, .pet])
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
        // Progress has no module of its own: only enabled modules publish it.
        XCTAssertEqual(settings.previewKinds, [.meeting, .focus, .progress])
        // Neither has the focus clock: Study or Focus can run it with Today off.
        _ = settings.modules.setEnabled(.planner, false)
        XCTAssertEqual(settings.previewKinds, [.focus, .progress])
        settings.notchPreview.isEnabled = false
        _ = settings.modules.setEnabled(.planner, true)
        XCTAssertTrue(settings.previewKinds.isEmpty)
    }

    func testIntervalsMatchTheOfferedChoices() {
        XCTAssertEqual(TickerInterval.allCases.map(\.seconds), [5, 8, 12])
        XCTAssertEqual(TickerInterval.medium.title, "8 seconds")
    }
}
