import XCTest
@testable import NotchDeckCore

final class SpotifyEqualizerTests: XCTestCase {
    func testLevelsStayInRangeOverTime() {
        for step in 0..<2_000 {
            let levels = SpotifyEqualizer.levels(at: Double(step) * 0.037)
            XCTAssertEqual(levels.count, SpotifyEqualizer.barCount)
            for level in levels {
                XCTAssert((SpotifyEqualizer.minimumLevel...1).contains(level), "\(level)")
            }
        }
    }

    func testLevelsAreDeterministic() {
        XCTAssertEqual(SpotifyEqualizer.levels(at: 12.34), SpotifyEqualizer.levels(at: 12.34))
    }

    func testBarsMoveOverTimeAndNotInLockstep() {
        let a = SpotifyEqualizer.levels(at: 1.0)
        let b = SpotifyEqualizer.levels(at: 1.2)
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThan(Set(a).count, 1, "bars should differ from each other")
    }

    func testBarsCoverMostOfTheirRange() {
        let samples = (0..<1_000).flatMap { SpotifyEqualizer.levels(at: Double($0) * 0.05) }
        XCTAssertLessThan(samples.min()!, 0.35)
        XCTAssertGreaterThan(samples.max()!, 0.9)
    }

    func testMotionIsSmoothBetweenFrames() {
        // At 30 fps no bar should jump more than a fraction of its range.
        let frame = 1.0 / 30
        for step in 0..<3_000 {
            let time = 812_345_678.0 + Double(step) * frame
            let now = SpotifyEqualizer.levels(at: time)
            let next = SpotifyEqualizer.levels(at: time + frame)
            for (a, b) in zip(now, next) {
                XCTAssertLessThan(abs(a - b), 0.25, "jump at \(time)")
            }
        }
    }

    func testHugeTimesStayInRange() {
        for time in [1e12, -1e12, 1e18, 812_345_678.9] {
            let levels = SpotifyEqualizer.levels(at: time)
            XCTAssertEqual(levels.count, SpotifyEqualizer.barCount)
            XCTAssert(levels.allSatisfy { (SpotifyEqualizer.minimumLevel...1).contains($0) })
        }
    }

    func testRestingLevelsAreShortAndVisible() {
        let resting = SpotifyEqualizer.restingLevels()
        XCTAssertEqual(resting.count, SpotifyEqualizer.barCount)
        XCTAssert(resting.allSatisfy { $0 >= SpotifyEqualizer.minimumLevel && $0 < 0.4 })
    }

    func testNonFiniteTimeFallsBackToResting() {
        XCTAssertEqual(SpotifyEqualizer.levels(at: .nan), SpotifyEqualizer.restingLevels())
        XCTAssertEqual(SpotifyEqualizer.levels(at: 0, count: 0), [])
    }
}
