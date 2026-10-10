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

    func testLibraryOffersEveryModuleThatIsNotATab() {
        XCTAssertEqual(ModuleLayout.default.available, optIn)
    }

    func testAddingFromTheLibraryAppendsTheLastTab() {
        var layout = ModuleLayout(order: [.spotify, .party, .planner, .system], disabled: [.party, .system])
        layout.add(.system)
        XCTAssertEqual(layout.enabled, [.spotify, .planner, .system])
        layout.add(.party)
        XCTAssertEqual(layout.enabled, [.spotify, .planner, .system, .party])
        XCTAssertFalse(layout.available.contains(.party))
        // Adding a tab again leaves the order alone.
        layout.add(.spotify)
        XCTAssertEqual(layout.enabled, [.spotify, .planner, .system, .party])
    }

    func testRemovingPutsTheModuleBackInTheLibraryButKeepsOneTab() {
        var layout = ModuleLayout(order: [.spotify, .planner], disabled: Set(optIn + [.system, .claudeUsage, .claudeAsk]))
        XCTAssertTrue(layout.remove(.spotify))
        XCTAssertEqual(layout.enabled, [.planner])
        XCTAssertTrue(layout.available.contains(.spotify))
        XCTAssertFalse(layout.remove(.planner))
        XCTAssertEqual(layout.enabled, [.planner])
        // Removed and added again, a module comes back at the end.
        layout.add(.spotify)
        XCTAssertEqual(layout.enabled, [.planner, .spotify])
    }

    func testMovingTabsUsesTabOffsetsAndLeavesLibrarySlots() {
        var layout = ModuleLayout(order: [.spotify, .party, .planner, .system, .claudeAsk], disabled: [.party, .system])
        layout.moveTabs(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(layout.enabled, [.claudeAsk, .spotify, .planner])
        XCTAssertEqual(Array(layout.order.prefix(5)), [.claudeAsk, .party, .spotify, .system, .planner])
        layout.moveTabs(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(layout.enabled, [.spotify, .planner, .claudeAsk])
        layout.moveTabs(fromOffsets: [7], toOffset: 0)
        XCTAssertEqual(layout.enabled, [.spotify, .planner, .claudeAsk])
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

    /// A layout whose "pet" module opens from the header (key P), not a tab.
    private func layoutWithPet(order: [ModuleID], disabled: Set<ModuleID> = []) -> ModuleLayout {
        let catalog = ModuleCatalog(["a", "b", "pet", "c"].map { (id: ModuleID) in
            ModuleDescriptor(id: id, title: id.rawValue, symbol: "circle", category: .productivity,
                             accent: ModuleAccent(red: 1, green: 1, blue: 1),
                             headerShortcut: id == "pet" ? ModuleHeaderShortcut(label: "Your pet", key: "P") : nil)
        })
        return ModuleLayout(order: order, disabled: disabled, catalog: catalog)
    }

    func testHeaderModulesLeaveTheTabBarAndTakeNoNumber() {
        let layout = layoutWithPet(order: ["a", "pet", "b", "c"])
        XCTAssertEqual(layout.enabled, ["a", "pet", "b", "c"])
        XCTAssertEqual(layout.tabs, ["a", "b", "c"])
        XCTAssertEqual(layout.headerShortcuts, ["pet"])
        XCTAssertEqual(layout.module(forShortcut: 2), "b", "numbers count the visible tabs only")
        XCTAssertNil(layout.shortcut(for: "pet"))
        XCTAssertEqual(layout.headerKey(for: "pet"), "p")
        XCTAssertNil(layout.headerKey(for: "a"))
    }

    func testMovingTabsSkipsTheHeaderModule() {
        var layout = layoutWithPet(order: ["a", "pet", "b", "c"])
        layout.moveTabs(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(layout.tabs, ["c", "a", "b"], "offsets count the tab bar only")
        XCTAssertEqual(layout.order, ["c", "pet", "a", "b"], "the paw keeps its slot")
        XCTAssertEqual(layout.headerShortcuts, ["pet"])
    }

    func testHeaderKeyOpensOnlyAnEnabledHeaderModule() {
        XCTAssertEqual(layoutWithPet(order: ["a", "b", "pet"]).module(forHeaderKey: "P"), "pet")
        XCTAssertEqual(layoutWithPet(order: ["a", "b", "pet"]).module(forHeaderKey: "p"), "pet")
        XCTAssertNil(layoutWithPet(order: ["a", "b", "pet"]).module(forHeaderKey: "a"))
        let petOff = layoutWithPet(order: ["a", "b", "pet"], disabled: ["pet"])
        XCTAssertTrue(petOff.headerShortcuts.isEmpty, "no pet module on, no paw")
        XCTAssertNil(petOff.module(forHeaderKey: "p"))
        XCTAssertNil(petOff.headerKey(for: "pet"))
    }

    func testArrowsCycleTabsAndLeaveTheHeaderModuleTowardTheTabs() {
        let layout = layoutWithPet(order: ["a", "pet", "b"], disabled: ["c"])
        XCTAssertEqual(layout.module(after: "a"), "b", "arrows skip the paw")
        XCTAssertEqual(layout.module(after: "b"), "a")
        XCTAssertEqual(layout.module(after: "pet"), "a")
        XCTAssertEqual(layout.module(before: "pet"), "b")
    }

    func testOnlyTheHeaderModuleOnKeepsItSelected() {
        let layout = layoutWithPet(order: ["pet", "a", "b", "c"], disabled: ["a", "b", "c"])
        XCTAssertTrue(layout.tabs.isEmpty)
        XCTAssertEqual(layout.resolvedSelection("a"), "pet")
        XCTAssertEqual(layout.module(after: "pet"), "pet")
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
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = InMemoryDefaults()
    }

    func testEmptyStoreYieldsDefaults() throws {
        let settings = SettingsRepository(defaults: defaults).load()
        var expected = AppSettings.default
        expected.modules = try XCTUnwrap(KitLibrary.bundled[KitLibrary.defaultKitID]).layout()
        XCTAssertEqual(settings, expected, "a fresh install starts on the default kit's tabs")
        XCTAssertEqual(settings.modules.enabled, [.study, .planner, .spotify, .claudeAsk, .closet])
        XCTAssertFalse(settings.openOnHover)
        XCTAssertTrue(settings.hapticsEnabled)
        XCTAssertTrue(settings.celebrationSoundEnabled)
        XCTAssertTrue(settings.weeklyRecapEnabled, "the weekly recap starts on")
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.preferredDisplay, .builtIn)
        XCTAssertTrue(settings.showOnExternalDisplays)
        XCTAssertTrue(settings.hideInFullscreen)
        XCTAssertEqual(settings.notchMode, .alwaysVisible)
        XCTAssertEqual(settings.panelSize, .regular)
        XCTAssertTrue(settings.notchPreview.isEnabled)
        XCTAssertEqual(settings.notchPreview.enabledKinds, Set(TickerKind.allCases))
        XCTAssertEqual(settings.notchPreview.interval, .medium)
        XCTAssertEqual(settings.displayName, "")
        XCTAssertNil(settings.cleanedDisplayName, "no name until the user gives one")
    }

    func testDisplayNameIsKeptAsTypedAndCleanedForUse() {
        var settings = AppSettings(modules: .default)
        settings.displayName = "  Ada\u{200B} King, Countess of Lovelace "
        XCTAssertEqual(settings.displayName, "  Ada\u{200B} King, Countess of Lovelace ")
        XCTAssertEqual(settings.cleanedDisplayName, "Ada King, Countess of Lo")
        settings.displayName = " \n "
        XCTAssertNil(settings.cleanedDisplayName)
    }

    func testGreetingFollowsTheHourAndNeedsAName() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func at(_ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour, minute: 30))!
        }
        XCTAssertEqual(DisplayName.greeting(for: " Ana ", at: at(4), calendar: calendar), "Good morning, Ana")
        XCTAssertEqual(DisplayName.greeting(for: "Ana", at: at(11), calendar: calendar), "Good morning, Ana")
        XCTAssertEqual(DisplayName.greeting(for: "Ana", at: at(12), calendar: calendar), "Good afternoon, Ana")
        XCTAssertEqual(DisplayName.greeting(for: "Ana", at: at(17), calendar: calendar), "Good evening, Ana")
        XCTAssertEqual(DisplayName.greeting(for: "Ana", at: at(2), calendar: calendar), "Good evening, Ana",
                       "late at night is still evening, not morning")
        XCTAssertNil(DisplayName.greeting(for: nil, at: at(9), calendar: calendar))
        XCTAssertNil(DisplayName.greeting(for: " \u{200B} ", at: at(9), calendar: calendar), "no greeting for a blank name")
    }

    func testRoundTripsEveryField() {
        var modules = ModuleLayout(order: [.claudeAsk, .planner], disabled: [])
        modules.setEnabled(.spotify, false)
        let settings = AppSettings(
            displayName: "  Ada ",
            kitID: "medicine",
            hasChosenKit: true,
            kitAnswers: ["stage": ["clinical"], "anki": ["yes", "no"]],
            modules: modules,
            openOnHover: true,
            hapticsEnabled: false,
            celebrationSoundEnabled: false,
            weeklyRecapEnabled: false,
            launchAtLogin: true,
            hotkey: Hotkey(keyCode: 40, modifiers: [.command, .shift]),
            claudePathOverride: "/opt/claude",
            preferredDisplay: .specific(5),
            showOnExternalDisplays: false,
            hideInFullscreen: false,
            notchMode: .showOnHover,
            panelSize: .large,
            notchPreview: NotchPreviewSettings(isEnabled: false, disabledKinds: [.tasks, .claudeUsage], interval: .long),
            themeID: .sakura
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
        defaults.set("loud", forKey: "settings.celebrationSoundEnabled")
        defaults.set("Sundays", forKey: "settings.weeklyRecapEnabled")
        defaults.set("sometimes", forKey: "settings.notchMode")
        defaults.set("huge", forKey: "settings.panelSize")
        let settings = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(settings.panelSize, .regular)
        XCTAssertEqual(settings.notchMode, .alwaysVisible)
        XCTAssertFalse(settings.openOnHover)
        XCTAssertEqual(settings.hotkey, .default)
        XCTAssertEqual(settings.preferredDisplay, .builtIn)
        XCTAssertFalse(settings.hapticsEnabled)
        XCTAssertTrue(settings.celebrationSoundEnabled)
        XCTAssertTrue(settings.weeklyRecapEnabled)
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

    func testFreshInstallOfTabbiShowsTheFourEssentialsTabs() {
        let settings = SettingsRepository(defaults: defaults, defaultKitID: Edition.tabbi.defaultKitID).load()
        XCTAssertEqual(settings.kitID, "essentials")
        XCTAssertEqual(settings.modules.enabled, [.study, .planner, .spotify, .claudeAsk, .closet])
        XCTAssertEqual(Set(settings.modules.available),
                       Set(ModuleCatalog.builtIn.ids).subtracting(settings.modules.enabled),
                       "everything else waits in the Add More library")
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

        settings.apply(try XCTUnwrap(KitLibrary.bundled["essentials"]))
        repository.save(settings)
        let reloaded = repository.load()
        XCTAssertTrue(reloaded.hasChosenKit)
        XCTAssertEqual(reloaded.kitID, "essentials")
    }

    func testLayoutsSavedBeforeKitsExistedCountAsChosen() {
        // A pre-kits install: a tab layout but no kit and no flag.
        defaults.set(["spotify", "system", "claudeUsage", "planner", "claudeAsk"], forKey: "settings.modules.order")
        XCTAssertTrue(SettingsRepository(defaults: defaults).load().hasChosenKit)
    }

    func testUnknownSavedKitFallsBackToTheDefaultKit() throws {
        defaults.set("removed-import", forKey: "settings.kit")
        let settings = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(settings.kitID, KitLibrary.defaultKitID)
        XCTAssertEqual(settings.modules, try XCTUnwrap(KitLibrary.bundled[KitLibrary.defaultKitID]).layout())
    }

    func testApplyingAKitReplacesTheLayoutAndKeepsOtherPreferences() throws {
        let medicine = try XCTUnwrap(KitLibrary.bundled["medicine"])
        var settings = AppSettings(openOnHover: true)
        settings.modules.setEnabled(.spotify, false)
        settings.apply(medicine, answers: ["anki": ["yes"]])
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.modules, medicine.layout(answers: ["anki": ["yes"]]))
        XCTAssertTrue(settings.modules.isEnabled(.anki))
        XCTAssertTrue(settings.modules.isEnabled(.spotify))
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
        let essentials = try XCTUnwrap(KitLibrary.bundled["essentials"])
        var settings = AppSettings()
        settings.apply(medicine, answers: ["anki": ["no"]])
        settings.apply(essentials)
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
        let plain = KitManifest(id: "plain", name: "Plain", summary: "", symbol: "circle",
                                modules: [KitModuleEntry(.planner), KitModuleEntry(.spotify)])
        var settings = AppSettings()
        settings.notchPreview.setEnabled(.meeting, false)
        settings.apply(plain)
        XCTAssertEqual(settings.notchPreview.disabledKinds, [.meeting])
        XCTAssertTrue(settings.usesDefaults(of: plain))
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
