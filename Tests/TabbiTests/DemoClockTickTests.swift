import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A demo's running timers count down while their panel shows, so the demo
/// never looks frozen; snapshot runs keep the clock still.
@MainActor
final class DemoClockTickTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("demo-clock-\(UUID().uuidString)")
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() async throws {
        cancellables = []
        try? FileManager.default.removeItem(at: folder)
    }

    func testTheDemoFocusTimerTicksWhileVisible() {
        let store = FocusStore(runMode: .demo, defaults: InMemoryDefaults())
        XCTAssertTrue(store.timer.isRunning)
        store.setVisible(true, viewer: .focus)
        defer { store.setVisible(false, viewer: .focus) }
        let start = store.remaining
        expectTick(on: store.$now.dropFirst())
        XCTAssertLessThan(store.remaining, start)
    }

    func testTheDemoStudySessionTicksWhileVisible() {
        let store = StudyStore(storage: EditionStorage(root: folder), runMode: .demo)
        XCTAssertTrue(store.session.isRunning)
        store.setVisible(true)
        defer { store.setVisible(false) }
        let start = store.now
        expectTick(on: store.$now.dropFirst())
        XCTAssertGreaterThan(store.now, start)
    }

    func testASnapshotFocusTimerStaysStill() {
        let store = FocusStore(runMode: RunMode(isDemo: true, isSnapshot: true), defaults: InMemoryDefaults())
        store.setVisible(true, viewer: .focus)
        defer { store.setVisible(false, viewer: .focus) }
        let ticked = expectation(description: "no tick")
        ticked.isInverted = true
        store.$now.dropFirst().sink { _ in ticked.fulfill() }.store(in: &cancellables)
        wait(for: [ticked], timeout: 1.5)
    }

    /// Waits for the once-a-second ticker's next beat.
    private func expectTick(on now: some Publisher<Date, Never>) {
        let ticked = expectation(description: "tick")
        ticked.assertForOverFulfill = false
        now.sink { _ in ticked.fulfill() }.store(in: &cancellables)
        wait(for: [ticked], timeout: 3)
    }
}
