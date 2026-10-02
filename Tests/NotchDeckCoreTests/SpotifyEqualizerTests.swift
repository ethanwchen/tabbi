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
