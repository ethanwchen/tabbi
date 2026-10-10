import Foundation
import XCTest
import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// The pet greets each seasonal event run once beside the closed notch,
/// and remembers it across launches.
@MainActor
final class SeasonalEventGreeterAppTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func quietCenter() -> CelebrationCenter {
        CelebrationCenter(hapticsEnabled: { false }, playSound: { _ in }, performHaptic: { _ in })
    }

    func testTheFirstLaunchDuringAnEventCheersOnceAndALaterLaunchDoesNot() throws {
        // Partway into the current or next event, whatever today is.
        let moment = try XCTUnwrap(SeasonalEventDemo(today: .now)).moment
        let center = quietCenter()
        let first = SeasonalEventGreeter(storage: EditionStorage(root: root), runMode: .live,
                                         celebrations: center, now: { moment })
        first.check()
        XCTAssertEqual(center.cheer?.kind, .dance)
        first.check()
        XCTAssertEqual(center.cheer?.id, 1)

        let relaunched = SeasonalEventGreeter(storage: EditionStorage(root: root), runMode: .live,
                                              celebrations: center, now: { moment })
        relaunched.check()
        XCTAssertEqual(center.cheer?.id, 1)
        first.stop()
        relaunched.stop()
    }

    func testNothingCheersBetweenEventsAndADemoSavesNothing() throws {
        let center = quietCenter()
        // Between summer (to Aug 31) and Halloween (from Oct 17) in any year.
        let between = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12)))
        let greeter = SeasonalEventGreeter(storage: EditionStorage(root: root), runMode: .live,
                                           celebrations: center, now: { between })
        greeter.check()
        XCTAssertNil(center.cheer)
        greeter.stop()

        let demoMoment = try XCTUnwrap(SeasonalEventDemo(today: .now)).moment
        let demo = SeasonalEventGreeter(storage: EditionStorage(root: root), runMode: .demo,
                                        celebrations: center, now: { demoMoment })
        demo.check()
        XCTAssertNotNil(center.cheer)
        XCTAssertFalse(FileManager.default.fileExists(atPath: SeasonalEventGreeter.saveURL(in: EditionStorage(root: root)).path))
    }
}
