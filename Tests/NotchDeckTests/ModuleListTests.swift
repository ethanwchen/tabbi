import XCTest
import NotchKitCore
@testable import NotchDeck

/// The module list is the one place a module is registered: everything that
/// shows or resolves modules (layouts, kits, the tab bar) reads its catalog.
@MainActor
final class ModuleListTests: XCTestCase {
    func testIdsAreUniqueAndEveryModuleIsDescribed() {
        let catalog = ModuleList.catalog
        XCTAssertEqual(catalog.descriptors.count, ModuleList.all.count, "two listed modules share an id")
        for descriptor in catalog.descriptors {
            XCTAssertFalse(descriptor.title.isEmpty, "\(descriptor.id)")
            XCTAssertFalse(descriptor.symbol.isEmpty, "\(descriptor.id)")
        }
    }

    func testKeepsTheShippedTabOrder() {
        // Modules a kit doesn't list are appended in this order, so it is
        // user-visible in Settings. New modules go at the end.
        XCTAssertEqual(ModuleList.catalog.ids, [.spotify, .system, .claudeUsage, .planner, .claudeAsk,
                                                .focus, .study, .anki, .party, .closet])
    }

    func testClaudeModulesDeclareTheCLIRequirement() {
        XCTAssertTrue(AskClaudeModule.descriptor.permissions.contains(.claudeCLI))
        XCTAssertTrue(ClaudeUsageModule.descriptor.permissions.contains(.claudeCLI))
        XCTAssertEqual(SystemModule.descriptor.permissions, [])
    }

    func testEveryBundledKitResolvesAgainstTheModuleList() {
        XCTAssertEqual(KitLibrary.bundled.kits.count, KitLibrary.bundledIDs.count)
        for kit in KitLibrary.bundled.kits {
            XCTAssertEqual(kit.issues(catalog: ModuleList.catalog), [], kit.id)
            let layout = kit.layout(catalog: ModuleList.catalog)
            XCTAssertEqual(Set(layout.order), Set(ModuleList.catalog.ids), kit.id)
            XCTAssertFalse(layout.enabled.isEmpty, kit.id)
        }
    }

    func testSettingsStoreResolvesLayoutsAgainstTheCatalogItIsGiven() {
        let store = SettingsStore.ephemeral(catalog: ModuleList.catalog, kitID: "medicine")
        XCTAssertEqual(Set(store.settings.modules.order), Set(ModuleList.catalog.ids))
        XCTAssertEqual(store.settings.modules.enabled, KitLibrary.bundled.kit("medicine")?
            .layout(catalog: ModuleList.catalog).enabled)
    }
}
