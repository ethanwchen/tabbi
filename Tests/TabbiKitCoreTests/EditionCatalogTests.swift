import XCTest
@testable import TabbiKitCore

/// An edition that leaves modules out (the App Store edition) must still
/// apply every kit cleanly: the left-out tabs are skipped without a warning,
/// and nothing offers them.
final class EditionCatalogTests: XCTestCase {
    private var appStore: Edition {
        get throws { try XCTUnwrap(Edition.named("appstore")) }
    }

    func testExcludingDropsModulesAndRemembersThemAsUnavailable() {
        let catalog = ModuleCatalog.builtIn.excluding([.claudeAsk, "chess"])
        XCTAssertFalse(catalog.contains(.claudeAsk))
        XCTAssertEqual(catalog.ids, ModuleCatalog.builtIn.ids.filter { $0 != .claudeAsk })
        XCTAssertTrue(catalog.isUnavailable(.claudeAsk))
        XCTAssertTrue(catalog.isUnavailable("chess"))
        XCTAssertFalse(catalog.isUnavailable(.planner))
        XCTAssertFalse(ModuleCatalog.builtIn.isUnavailable(.claudeAsk))
        XCTAssertEqual(catalog.excluding([.party]).unavailableIDs, [.claudeAsk, "chess", .party])
        XCTAssertNotEqual(catalog, ModuleCatalog(catalog.descriptors), "unavailable ids are part of the catalog")
    }

    func testAModuleTheCatalogHasIsNeverUnavailable() {
        let catalog = ModuleCatalog(ModuleCatalog.builtIn.descriptors, unavailable: [.planner, "chess"])
        XCTAssertTrue(catalog.contains(.planner))
        XCTAssertEqual(catalog.unavailableIDs, ["chess"])
    }

    func testEveryBundledKitAppliesCleanlyInTheAppStoreEdition() throws {
        let edition = try appStore
        let catalog = edition.catalog(from: .builtIn)
        XCTAssertFalse(KitLibrary.bundled.kits.isEmpty)
        for kit in KitLibrary.bundled.kits {
            XCTAssertEqual(kit.issues(catalog: catalog), [], kit.id)
            XCTAssertEqual(kit.missingRequirements(catalog: catalog), [], kit.id)
            let layout = kit.layout(catalog: catalog)
            XCTAssertEqual(Set(layout.order), Set(catalog.ids), kit.id)
            XCTAssertTrue(Set(layout.order).isDisjoint(with: edition.excludedModules), kit.id)
            XCTAssertFalse(layout.tabs.isEmpty, kit.id)
            let ticker = try XCTUnwrap(kit.defaults.resolvedTicker(catalog: catalog), kit.id)
            XCTAssertFalse(ticker.contains(.party), kit.id)
            XCTAssertTrue(ticker.allSatisfy { kind in kind.module.map(catalog.contains) ?? true }, kit.id)
        }
    }

    func testEssentialsKeepsAskAIInTheAppStoreEdition() throws {
        // Ask answers through API keys or Ollama there, so no tab is lost.
        let essentials = try XCTUnwrap(KitLibrary.bundled["essentials"])
        let full = essentials.layout(catalog: .builtIn)
        let appStore = essentials.layout(catalog: try appStore.catalog(from: .builtIn))
        XCTAssertTrue(full.tabs.contains(.claudeAsk))
        XCTAssertEqual(appStore.tabs, full.tabs)
        XCTAssertEqual(appStore.headerShortcuts, full.headerShortcuts)
    }

    func testOnboardingAnswersThatEnableAnExcludedModuleAreIgnored() throws {
        let kit = try KitManifest.decode(from: Data(#"""
        {"formatVersion": 1, "id": "ai", "name": "AI", "modules": ["planner"],
         "defaults": {"ticker": ["claudeUsage", "party", "tasks"], "moduleSettings": {"claudeUsage": {"plan": "x"}}},
         "onboarding": [{"id": "q", "prompt": "Q", "options": [{"id": "a", "label": "A", "enables": ["claudeUsage"]}]}]}
        """#.utf8))
        let catalog = try appStore.catalog(from: .builtIn)
        XCTAssertEqual(kit.issues(catalog: catalog), [])
        let layout = kit.layout(catalog: catalog, answers: ["q": ["a"]])
        XCTAssertEqual(layout.enabled, [.planner])
        XCTAssertEqual(kit.defaults.resolvedTicker(catalog: catalog), [.tasks])
    }

    func testTyposAreStillReportedInTheAppStoreEdition() throws {
        let kit = try KitManifest.decode(from: Data(#"""
        {"formatVersion": 1, "id": "typo", "name": "Typo", "modules": ["planner", "claudeAks"],
         "defaults": {"ticker": ["partty"]}}
        """#.utf8))
        XCTAssertEqual(kit.issues(catalog: try appStore.catalog(from: .builtIn)),
                       [.unknownModule("claudeAks"), .unknownTickerKind("partty")])
    }

    func testAKitThatRequiresAnExcludedModuleIsRefused() throws {
        let kit = try KitManifest.decode(from: Data(#"""
        {"formatVersion": 1, "id": "usage", "name": "Usage", "modules": ["claudeUsage"],
         "requires": {"modules": ["claudeUsage"]}}
        """#.utf8))
        XCTAssertEqual(kit.missingRequirements(catalog: try appStore.catalog(from: .builtIn)), [.claudeUsage])
    }

    func testSettingsOfferNoPreviewForAnExcludedModule() throws {
        let catalog = try appStore.catalog(from: .builtIn)
        let kinds = TickerKind.all(in: catalog)
        XCTAssertFalse(kinds.contains(.party))
        XCTAssertFalse(kinds.contains(.highlights(from: .claudeUsage)))
        XCTAssertTrue(kinds.contains(.pet))
        XCTAssertTrue(TickerKind.all(in: .builtIn).contains(.party))
    }
}
