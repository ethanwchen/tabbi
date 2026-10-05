import XCTest
@testable import TabbiKitCore

final class ModuleLifecycleTests: XCTestCase {
    func testFirstUpdateStartsEveryEnabledModuleInTabOrder() {
        var lifecycle = ModuleLifecycle()
        let changes = lifecycle.update(enabled: [.planner, .spotify, .system])
        XCTAssertEqual(changes, .init(start: [.planner, .spotify, .system]))
        XCTAssertEqual(lifecycle.running, [.planner, .spotify, .system])
    }

    func testSameSetIsANoOp() {
        var lifecycle = ModuleLifecycle()
        _ = lifecycle.update(enabled: [.planner, .spotify])
        XCTAssertTrue(lifecycle.update(enabled: [.planner, .spotify]).isEmpty)
    }

    func testReorderingDoesNotRestartModules() {
        var lifecycle = ModuleLifecycle()
        _ = lifecycle.update(enabled: [.planner, .spotify, .system])
        XCTAssertTrue(lifecycle.update(enabled: [.system, .planner, .spotify]).isEmpty)
    }

    func testDisablingStopsAndEnablingStarts() {
        var lifecycle = ModuleLifecycle()
        _ = lifecycle.update(enabled: [.planner, .spotify, .system])
        let changes = lifecycle.update(enabled: [.planner, .anki])
        XCTAssertEqual(changes.stop, [.spotify, .system])
        XCTAssertEqual(changes.start, [.anki])
        XCTAssertEqual(lifecycle.running, [.planner, .anki])
    }

    func testDuplicateIdsStartOnce() {
        var lifecycle = ModuleLifecycle()
        XCTAssertEqual(lifecycle.update(enabled: [.study, .study, .anki]).start, [.study, .anki])
        XCTAssertEqual(lifecycle.running, [.study, .anki])
    }

    func testSwitchingKitsSwapsTheRunningSet() {
        var lifecycle = ModuleLifecycle()
        let productivity = KitLibrary.bundled.kit("productivity")!.layout(catalog: .builtIn)
        let medicine = KitLibrary.bundled.kit("medicine")!.layout(catalog: .builtIn)
        _ = lifecycle.update(enabled: productivity.enabled)
        let changes = lifecycle.update(enabled: medicine.enabled)
        XCTAssertTrue(changes.start.contains(.study))
        XCTAssertTrue(changes.stop.contains(.system))
        XCTAssertFalse(changes.start.contains(.planner), "modules in both kits keep running")
        XCTAssertEqual(Set(lifecycle.running), Set(medicine.enabled))
    }

    func testStopAllStopsInStartOrderAndClears() {
        var lifecycle = ModuleLifecycle()
        _ = lifecycle.update(enabled: [.planner, .spotify])
        XCTAssertEqual(lifecycle.stopAll(), .init(stop: [.planner, .spotify]))
        XCTAssertTrue(lifecycle.running.isEmpty)
        XCTAssertTrue(lifecycle.stopAll().isEmpty)
    }
}
