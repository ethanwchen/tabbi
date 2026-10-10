import XCTest
@testable import TabbiKitCore

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

    func testLoopRepeatsWithoutASeam() {
        for bar in 0..<SpotifyEqualizer.barCount {
            let loop = SpotifyEqualizer.loop(bar: bar, duration: 30, frameRate: 30)
            XCTAssertEqual(loop.count, 901)
            XCTAssertEqual(loop.first!, loop.last!, accuracy: 1e-12, "bar \(bar) jumps when the loop restarts")
            XCTAssert(loop.allSatisfy { (SpotifyEqualizer.minimumLevel...1).contains($0) })
            // Smooth everywhere, including the blend into the loop's start.
            for (a, b) in zip(loop, loop.dropFirst()) {
                XCTAssertLessThan(abs(a - b), 0.25, "bar \(bar)")
            }
        }
    }

    func testLoopFollowsTheLiveLevelsBeforeTheBlend() {
        let loop = SpotifyEqualizer.loop(bar: 2, duration: 10, frameRate: 30, blend: 1)
        for frame in stride(from: 0, to: 270, by: 7) {
            XCTAssertEqual(loop[frame], SpotifyEqualizer.levels(at: Double(frame) / 30)[2])
        }
    }

    func testLoopBarsDifferAndInvalidInputsAreEmpty() {
        XCTAssertNotEqual(SpotifyEqualizer.loop(bar: 0), SpotifyEqualizer.loop(bar: 1))
        XCTAssertEqual(SpotifyEqualizer.loop(bar: SpotifyEqualizer.barCount), [])
        XCTAssertEqual(SpotifyEqualizer.loop(bar: 0, duration: 0), [])
        XCTAssertEqual(SpotifyEqualizer.loop(bar: 0, frameRate: 0), [])
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
