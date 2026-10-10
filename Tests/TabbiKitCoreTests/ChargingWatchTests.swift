import XCTest
import TabbiKitCore

/// When plugging the Mac in makes the pet sip from its mug.
final class ChargingWatchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    func testPluggingInSipsOnce() {
        var watch = ChargingWatch()
        XCTAssertFalse(watch.update(onCharger: false, at: start))
        XCTAssertTrue(watch.update(onCharger: true, at: at(10)), "battery to charger is a plug-in")
        XCTAssertFalse(watch.update(onCharger: true, at: at(20)), "still on the charger: once per plug-in")
        XCTAssertFalse(watch.update(onCharger: true, at: at(600)))
    }

    func testLaunchingOnAChargerOrWithoutABatteryPlaysNothing() {
        var watch = ChargingWatch()
        XCTAssertFalse(watch.update(onCharger: true, at: start), "the first reading is only the baseline")
        XCTAssertFalse(watch.update(onCharger: true, at: at(60)), "a desktop Mac never switches")
    }

    func testEachNewPlugInSipsAgain() {
        var watch = ChargingWatch()
        _ = watch.update(onCharger: false, at: start)
        XCTAssertTrue(watch.update(onCharger: true, at: at(10)))
        XCTAssertFalse(watch.update(onCharger: false, at: at(3600)))
        XCTAssertTrue(watch.update(onCharger: true, at: at(7200)))
    }

    func testAWiggledCableSipsOncePerCooldown() {
        var watch = ChargingWatch()
        _ = watch.update(onCharger: false, at: start)
        XCTAssertTrue(watch.update(onCharger: true, at: at(1)))
        XCTAssertFalse(watch.update(onCharger: false, at: at(2)))
        XCTAssertFalse(watch.update(onCharger: true, at: at(3)), "too soon after the last sip")
        XCTAssertFalse(watch.update(onCharger: false, at: at(4)))
        XCTAssertTrue(watch.update(onCharger: true, at: at(1 + ChargingWatch.cooldown)))
    }

    func testAnUnreadableSourceKeepsTheLastReading() {
        var watch = ChargingWatch()
        _ = watch.update(onCharger: false, at: start)
        XCTAssertFalse(watch.update(onCharger: nil, at: at(5)))
        XCTAssertTrue(watch.update(onCharger: true, at: at(10)), "the battery reading still counts")
    }
}
