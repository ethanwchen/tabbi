import XCTest
@testable import TabbiKitCore

final class HistorySeriesTests: XCTestCase {
    func testPartialHistoryIsRightAligned() {
        let series = HistorySeries([0.1, 0.2, 0.3], capacity: 60)
        XCTAssertEqual(series.points.map(\.x), [57, 58, 59])
        XCTAssertEqual(series.points.map(\.y), [0.1, 0.2, 0.3])
    }

    func testKeepsOnlyNewestValuesWhenOverCapacity() {
        let series = HistorySeries([0.1, 0.2, 0.3, 0.4], capacity: 2)
        XCTAssertEqual(series.points, [.init(x: 0, y: 0.3), .init(x: 1, y: 0.4)])
    }

    func testClampsAndDropsNonFiniteValues() {
        let series = HistorySeries([-0.5, .nan, 1.7, .infinity], capacity: 4)
        XCTAssertEqual(series.points.map(\.y), [0, 1])
        XCTAssertEqual(series.points.map(\.x), [2, 3])
    }

    func testPeakAndAverage() {
        let series = HistorySeries([0.2, 0.6, 0.4], capacity: 10)
        XCTAssertEqual(series.peak, 0.6)
        XCTAssertEqual(series.average ?? 0, 0.4, accuracy: 1e-9)
    }

    func testEmptyHistoryHasNoSummary() {
        let series = HistorySeries([], capacity: 10)
        XCTAssertTrue(series.isEmpty)
        XCTAssertNil(series.peak)
        XCTAssertNil(series.average)
    }
}
