import XCTest
import TabbiKitCore
@testable import Tabbi

/// The module list is the one place a module is registered: everything that
/// shows or resolves modules (layouts, kits, the tab bar) reads its catalog.
@MainActor
final class ModuleListTests: XCTestCase {
    func testIdsAreUniqueAndEveryModuleIsDescribed() {
        let catalog = ModuleList.catalog
        XCTAssertEqual(catalog.duplicateIDs, [], "two listed modules share an id")
        XCTAssertEqual(catalog.descriptors.count, ModuleList.all.count)
        for descriptor in catalog.descriptors {
            XCTAssertFalse(descriptor.title.isEmpty, "\(descriptor.id)")
            XCTAssertFalse(descriptor.symbol.isEmpty, "\(descriptor.id)")
            // The Add More library shows it on one line beside the module.
            let summary = descriptor.summary ?? ""
            XCTAssertFalse(summary.isEmpty, "\(descriptor.id) needs a one-line summary for the library")
            XCTAssertLessThanOrEqual(summary.count, 56, "\(descriptor.id)'s summary would truncate")
        }
    }

    func testKeepsTheShippedTabOrder() {
        // Modules a kit doesn't list are appended in this order, so it is
        // user-visible in Settings. New modules go at the end.
        XCTAssertEqual(ModuleList.catalog.ids, [.spotify, .system, .claudeUsage, .planner, .claudeAsk,
                                                .focus, .study, .anki, .party, .closet, .schedule])
    }

    func testClaudeModulesDeclareTheCLIRequirement() {
        XCTAssertTrue(AskClaudeModule.descriptor.permissions.contains(.claudeCLI))
        XCTAssertTrue(ClaudeUsageModule.descriptor.permissions.contains(.claudeCLI))
        XCTAssertEqual(SystemModule.descriptor.permissions, [])
    }

    func testModulesThatUseTheNetworkDeclareTheirHosts() {
        let declared = Dictionary(uniqueKeysWithValues: ModuleList.catalog.descriptors.map {
            ($0.id, Set($0.network.map(\.host)))
        })
        XCTAssertEqual(declared[.spotify], ["i.scdn.co"])
        XCTAssertEqual(declared[.anki], [URLSessionAnkiConnectTransport.defaultEndpoint.host()!])
        XCTAssertEqual(declared[.party], [PartyServer.productionURL.host()!])
        for id in ModuleList.catalog.ids where ![.spotify, .anki, .party].contains(id) {
            XCTAssertEqual(declared[id], [], "\(id) declares a host but makes no network calls")
        }
        for descriptor in ModuleList.catalog.descriptors {
            for access in descriptor.network {
                XCTAssertFalse(access.host.isEmpty, "\(descriptor.id)")
                XCTAssertFalse(access.purpose.isEmpty, "\(descriptor.id)")
            }
        }
    }

    func testModulesDeclareTheOnboardingStepsTheyNeed() {
        let steps = Dictionary(uniqueKeysWithValues: ModuleList.catalog.descriptors.map { ($0.id, $0.setup) })
        XCTAssertEqual(steps[.closet], [.pet])
        XCTAssertEqual(steps[.anki], [.anki])
        XCTAssertEqual(steps[.planner], [.calendar])
        XCTAssertEqual(steps[.study], [.studyMethod])
        XCTAssertEqual(steps[.party], [.party])
        for id in [ModuleID.spotify, .system, .claudeUsage, .claudeAsk, .focus] {
            XCTAssertEqual(steps[id], [], "\(id)")
        }
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

    /// Both bundled kits show the pet's paw at the far right of the header,
    /// and the Closet takes no tab: Essentials keeps four tabs, Med School five.
    func testBundledKitsShowThePawBesideTheirTabs() throws {
        let essentials = try XCTUnwrap(KitLibrary.bundled.kit("essentials")).layout(catalog: ModuleList.catalog)
        XCTAssertEqual(essentials.tabs, [.study, .planner, .spotify, .claudeAsk])
        XCTAssertEqual(essentials.headerShortcuts, [.closet])
        let medicine = try XCTUnwrap(KitLibrary.bundled.kit("medicine")).layout(catalog: ModuleList.catalog)
        XCTAssertEqual(medicine.tabs, [.study, .planner, .anki, .spotify, .claudeAsk])
        XCTAssertEqual(medicine.headerShortcuts, [.closet])
    }

    func testSettingsStoreResolvesLayoutsAgainstTheCatalogItIsGiven() {
        let store = SettingsStore.ephemeral(catalog: ModuleList.catalog, kitID: "medicine")
        XCTAssertEqual(Set(store.settings.modules.order), Set(ModuleList.catalog.ids))
        XCTAssertEqual(store.settings.modules.enabled, KitLibrary.bundled.kit("medicine")?
            .layout(catalog: ModuleList.catalog).enabled)
    }

    /// The App Store edition runs without its excluded modules: they get no
    /// tab, no Settings row and no instance, so none of their code runs.
    func testAppStoreEditionNeitherShowsNorCreatesExcludedModules() throws {
        let edition = try XCTUnwrap(Edition.named("appstore"))
        let catalog = ModuleList.catalog(for: edition)
        XCTAssertEqual(catalog.unavailableIDs, Set(edition.excludedModules))
        for kit in KitLibrary.bundled.kits {
            let store = SettingsStore.ephemeral(catalog: catalog, kitID: kit.id)
            let services = AppServices(settings: store, edition: edition,
                                       environment: ["TABBI_DEMO": "1"], arguments: ["--snapshot", "out"])
            XCTAssertEqual(services.modules.catalog.ids, catalog.ids, kit.id)
            XCTAssertEqual(Set(store.settings.modules.order), Set(catalog.ids), kit.id)
            for id in edition.excludedModules {
                XCTAssertNil(services.modules[id], "\(kit.id) created \(id)")
            }
        }
    }
}
