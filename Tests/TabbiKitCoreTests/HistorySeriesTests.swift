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

    func testCurveNeedsTwoPoints() {
        XCTAssertTrue(HistorySeries([], capacity: 10).monotoneCurve.isEmpty)
        XCTAssertTrue(HistorySeries([0.5], capacity: 10).monotoneCurve.isEmpty)
    }

    func testCurvePassesThroughEveryPoint() {
        let series = HistorySeries([0.2, 0.9, 0.1, 0.4], capacity: 10)
        XCTAssertEqual(series.monotoneCurve.map(\.end.x), [7, 8, 9])
        XCTAssertEqual(series.monotoneCurve.map(\.end.y), [0.9, 0.1, 0.4])
    }

    func testTwoPointsMakeAStraightLine() {
        let segment = HistorySeries([0.0, 0.6], capacity: 2).monotoneCurve[0]
        XCTAssertEqual(segment.control1.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(segment.control2.y, 0.4, accuracy: 1e-9)
    }

    func testFlatRunStaysFlat() {
        let curve = HistorySeries([0.3, 0.3, 0.3], capacity: 3).monotoneCurve
        for segment in curve {
            XCTAssertEqual(segment.control1.y, 0.3, accuracy: 1e-9)
            XCTAssertEqual(segment.control2.y, 0.3, accuracy: 1e-9)
        }
    }

    /// A spike from 0 to 100% and back must not dip below 0 or rise past 1,
    /// which a plain spline would, drawing outside the card's plot.
    func testCurveNeverOvershootsItsPoints() {
        let values = [0.0, 0.0, 1.0, 1.0, 0.0, 0.5, 0.0, 1.0]
        let curve = HistorySeries(values, capacity: values.count).monotoneCurve
        var start = values[0]
        for segment in curve {
            let low = min(start, segment.end.y), high = max(start, segment.end.y)
            for control in [segment.control1.y, segment.control2.y] {
                XCTAssertGreaterThanOrEqual(control, low - 1e-9)
                XCTAssertLessThanOrEqual(control, high + 1e-9)
            }
            start = segment.end.y
        }
    }
}
