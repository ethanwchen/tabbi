import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Settings "Add More" library, wired into the app as at launch: a fresh
/// install starts on the default kit's tabs, and adding or removing a module
/// there starts or stops it and moves it in the notch's tab order right away.
@MainActor
final class ModuleLibraryWiringTests: XCTestCase {
    private var services: AppServices!

    override func setUp() async throws {
        services = AppServices(settings: .ephemeral(catalog: ModuleList.catalog),
                               environment: ["TABBI_DEMO": "1"], arguments: [])
    }

    override func tearDown() async throws {
        services = nil
    }

    func testAFreshInstallRunsOnlyTheFourEssentialsTabsAndThePet() {
        XCTAssertEqual(services.settings.settings.kitID, "essentials")
        XCTAssertEqual(services.settings.settings.modules.tabs, [.study, .planner, .spotify, .claudeAsk].inThisBuild)
        XCTAssertEqual(Set(services.modules.running), Set([.study, .planner, .spotify, .claudeAsk, .closet].inThisBuild))
    }

    func testAddingFromTheLibraryStartsTheModuleAsTheLastTab() {
        XCTAssertTrue(services.settings.settings.modules.available.contains(.system))
        services.settings.settings.modules.add(.system)
        XCTAssertEqual(services.settings.settings.modules.tabs, [.study, .planner, .spotify, .claudeAsk, .system].inThisBuild)
        XCTAssertTrue(services.modules.running.contains(.system))
        XCTAssertFalse(services.settings.settings.modules.available.contains(.system))
    }

    func testRemovingATabStopsItAndReturnsItToTheLibrary() {
        services.settings.settings.modules.add(.system)
        services.settings.settings.modules.remove(.spotify)
        XCTAssertEqual(services.settings.settings.modules.tabs, [.study, .planner, .claudeAsk, .system].inThisBuild)
        XCTAssertFalse(services.modules.running.contains(.spotify))
        XCTAssertTrue(services.settings.settings.modules.available.contains(.spotify))
    }

    func testTheLastTabCannotBeRemoved() throws {
        let enabled = services.settings.settings.modules.enabled
        let last = try XCTUnwrap(enabled.last)
        for id in enabled.dropLast() { XCTAssertTrue(services.settings.settings.modules.remove(id), "\(id)") }
        XCTAssertFalse(services.settings.settings.modules.remove(last))
        XCTAssertEqual(services.settings.settings.modules.enabled, [last])
        XCTAssertEqual(services.modules.running, [last])
    }
}
