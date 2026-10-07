import XCTest
import TabbiKitCore

final class SettingsSchemaTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "TabbiTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// The catalog of an older build that has no Party module.
    private var catalogWithoutParty: ModuleCatalog {
        ModuleCatalog(ModuleCatalog.builtIn.descriptors.filter { $0.id != .party })
    }

    // MARK: Versions and steps

    func testFreshInstallRecordsTheCurrentVersion() {
        _ = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(SettingsSchema.storedVersion(in: defaults), SettingsSchema.current)
        XCTAssertGreaterThanOrEqual(SettingsSchema.current, 1)
    }

    func testStepsRunOnceInOrderFromTheStoredVersion() {
        // Each step notes that it ran in the defaults it migrates.
        let steps = (1...3).map { version in
            SettingsSchema.Migration(version: version) { defaults in
                defaults.set((defaults.array(forKey: "ran") as? [Int] ?? []) + [version], forKey: "ran")
            }
        }
        defaults.set(1, forKey: SettingsSchema.versionKey)
        SettingsSchema.migrate(defaults, steps: steps)
        SettingsSchema.migrate(defaults, steps: steps)
        XCTAssertEqual(defaults.array(forKey: "ran") as? [Int], [2, 3])
        XCTAssertEqual(SettingsSchema.storedVersion(in: defaults), 3)
    }

    func testSettingsFromANewerBuildAreLeftAlone() {
        defaults.set(SettingsSchema.current + 5, forKey: SettingsSchema.versionKey)
        defaults.set(["spotify", "system"], forKey: "settings.modules.order")
        let repository = SettingsRepository(defaults: defaults)
        let settings = repository.load()
        // Step 1 would have set the flag; a newer build owns these settings.
        XCTAssertNil(defaults.object(forKey: "settings.kit.chosen"))
        XCTAssertFalse(settings.hasChosenKit)
        repository.save(settings)
        XCTAssertEqual(SettingsSchema.storedVersion(in: defaults), SettingsSchema.current + 5)
    }

    func testVersionZeroLayoutWithoutAFlagCountsAsChosenAndIsMigratedOnDisk() {
        defaults.set(["spotify", "system", "claudeUsage", "planner", "claudeAsk"], forKey: "settings.modules.order")
        XCTAssertTrue(SettingsRepository(defaults: defaults).load().hasChosenKit)
        XCTAssertEqual(defaults.object(forKey: "settings.kit.chosen") as? Bool, true)
    }

    func testVersionZeroWithoutALayoutStillAsksForAKit() {
        defaults.set(true, forKey: "settings.openOnHover")
        XCTAssertFalse(SettingsRepository(defaults: defaults).load().hasChosenKit)
    }

    func testVersionTwoActiveImportGetsItsNamespacedID() throws {
        defaults.set(2, forKey: SettingsSchema.versionKey)
        defaults.set("deep-work", forKey: "settings.kit")
        let imported = try KitManifest.decode(from: Data(#"{"formatVersion": 1, "id": "deep-work", "name": "Deep Work", "modules": ["focus"]}"#.utf8))
        var deepWork = imported
        deepWork.id = KitLibrary.importedID(imported.id)
        let settings = SettingsRepository(defaults: defaults, kits: .installed(imported: [deepWork])).load()
        XCTAssertEqual(settings.kitID, "imported.deep-work")
        XCTAssertEqual(defaults.string(forKey: "settings.kit"), "imported.deep-work")
    }

    func testVersionTwoBundledKitIDIsKept() {
        defaults.set(2, forKey: SettingsSchema.versionKey)
        defaults.set("medicine", forKey: "settings.kit")
        XCTAssertEqual(SettingsRepository(defaults: defaults).load().kitID, "medicine")
    }

    func testRetiredKitsMoveToEssentialsAndKeepTheirTabs() {
        for (retired, version) in [("productivity", 3), ("student", 3), ("productivity", 2), ("student", 0)] {
            let suite = "TabbiTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(version, forKey: SettingsSchema.versionKey)
            defaults.set(retired, forKey: "settings.kit")
            defaults.set(true, forKey: "settings.kit.chosen")
            defaults.set(["level": ["college"]], forKey: "settings.kit.answers")
            defaults.set(["spotify", "system", "claudeUsage", "planner", "claudeAsk", "anki"], forKey: "settings.modules.order")
            defaults.set(["anki"], forKey: "settings.modules.disabled")

            let settings = SettingsRepository(defaults: defaults).load()
            XCTAssertEqual(settings.kitID, "essentials", "\(retired) at version \(version)")
            XCTAssertEqual(defaults.string(forKey: "settings.kit"), "essentials")
            XCTAssertTrue(settings.hasChosenKit, "no kit picker again")
            XCTAssertEqual(settings.kitAnswers, [:], "answers to the old kit's questions are dropped")
            XCTAssertEqual(settings.modules.enabled, [.spotify, .system, .claudeUsage, .planner, .claudeAsk],
                           "every tab the user had stays on, in their order")
            XCTAssertFalse(settings.modules.isEnabled(.anki))
        }
    }

    func testVersionFourInstallKeepsTheRegularPanel() {
        defaults.set(4, forKey: SettingsSchema.versionKey)
        defaults.set("essentials", forKey: "settings.kit")
        XCTAssertEqual(SettingsRepository(defaults: defaults).load().panelSize, .regular)
        XCTAssertEqual(defaults.string(forKey: "settings.panelSize"), "regular", "recorded on disk by the step")
    }

    func testPanelSizeStepLeavesAFreshInstallAndASavedSizeAlone() {
        SettingsSchema.migrate(defaults)
        XCTAssertNil(defaults.object(forKey: "settings.panelSize"), "a fresh install takes the default")

        let suite = "TabbiTests.\(UUID().uuidString)"
        let saved = UserDefaults(suiteName: suite)!
        defer { saved.removePersistentDomain(forName: suite) }
        saved.set(4, forKey: SettingsSchema.versionKey)
        saved.set("essentials", forKey: "settings.kit")
        saved.set("compact", forKey: "settings.panelSize")
        XCTAssertEqual(SettingsRepository(defaults: saved).load().panelSize, .compact)
    }

    func testCurrentKitsAreNotMovedByTheRetiredKitStep() {
        defaults.set(3, forKey: SettingsSchema.versionKey)
        defaults.set("medicine", forKey: "settings.kit")
        defaults.set(["anki": ["no"]], forKey: "settings.kit.answers")
        let settings = SettingsRepository(defaults: defaults).load()
        XCTAssertEqual(settings.kitID, "medicine")
        XCTAssertEqual(settings.kitAnswers, ["anki": ["no"]])
    }

    func testRetiredKitIDsAreNotBundledAndPointAtABundledKit() {
        for (retired, replacement) in KitLibrary.retiredKitIDs {
            XCTAssertNil(KitLibrary.bundled[retired], "\(retired) is retired, so it must not ship again")
            XCTAssertNotNil(KitLibrary.bundled[replacement], "\(retired) moves to a kit that ships")
        }
    }

    // MARK: Modules this build doesn't know

    func testStoredOrderPutsUnknownIdsBackAfterTheirPredecessor() {
        let order = SettingsSchema.storedOrder(
            ["b", "a", "c"],
            keepingUnknownFrom: ["x", "a", "y", "z", "b", "c"],
            isKnown: { ["a", "b", "c"].contains($0) }
        )
        XCTAssertEqual(order, ["x", "b", "a", "y", "z", "c"])
    }

    func testAnOlderBuildKeepsAModuleItDoesNotKnow() {
        // A build with Party: Party is the second tab and switched on,
        // Closet is off.
        let newer = SettingsRepository(defaults: defaults)
        var settings = newer.load()
        settings.modules = ModuleLayout(order: [.study, .party, .planner, .closet],
                                        disabled: [.closet])
        settings.modules.setEnabled(.party, true)
        newer.save(settings)

        // An older build without Party loads, rearranges and saves.
        let older = SettingsRepository(defaults: defaults, catalog: catalogWithoutParty)
        var olderSettings = older.load()
        XCTAssertFalse(olderSettings.modules.order.contains(.party))
        olderSettings.modules.setEnabled(.closet, true)
        older.save(olderSettings)

        // Back on the newer build, Party is where it was and still on.
        let reloaded = newer.load().modules
        XCTAssertEqual(Array(reloaded.order.prefix(4)), [.study, .party, .planner, .closet])
        XCTAssertTrue(reloaded.isEnabled(.party))
        XCTAssertTrue(reloaded.isEnabled(.closet))
    }

    func testAnOlderBuildKeepsAnUnknownModuleSwitchedOff() {
        let newer = SettingsRepository(defaults: defaults)
        var settings = newer.load()
        settings.modules = ModuleLayout(order: [.planner, .party], disabled: [.party])
        newer.save(settings)

        let older = SettingsRepository(defaults: defaults, catalog: catalogWithoutParty)
        older.save(older.load())

        XCTAssertFalse(newer.load().modules.isEnabled(.party))
        XCTAssertEqual(Array(newer.load().modules.order.prefix(2)), [.planner, .party])
    }
}
