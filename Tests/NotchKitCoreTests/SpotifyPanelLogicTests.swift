import XCTest
@testable import NotchKitCore

final class SpotifyPanelLogicTests: XCTestCase {
    func testGeneratedCoverIsStableForTheSameSeed() {
        XCTAssertEqual(SpotifyGeneratedCover(seed: "spotify:track:demo"),
                       SpotifyGeneratedCover(seed: "spotify:track:demo"))
    }

    func testGeneratedCoverDiffersBetweenTracks() {
        XCTAssertNotEqual(SpotifyGeneratedCover(seed: "spotify:track:a"),
                          SpotifyGeneratedCover(seed: "spotify:track:b"))
    }

    func testGeneratedCoverHuesStayInRangeAndApart() {
        for seed in ["", "x", "spotify:local:::Song:180", "🎧 曲", String(repeating: "z", count: 500)] {
            let cover = SpotifyGeneratedCover(seed: seed)
            XCTAssert((0..<1).contains(cover.startHue), seed)
            XCTAssert((0..<1).contains(cover.endHue), seed)
            var gap = cover.endHue - cover.startHue
            if gap < 0 { gap += 1 }
            XCTAssert((50.0 / 360 - 1e-9...110.0 / 360 + 1e-9).contains(gap), "\(seed): \(gap)")
        }
    }

    func testScrubberMapsDragToTime() {
        XCTAssertEqual(SpotifyScrubber.position(atX: 50, width: 200, duration: 240), 60)
        XCTAssertEqual(SpotifyScrubber.position(atX: 200, width: 200, duration: 240), 240)
    }

    func testScrubberClampsOutsideTheTrack() {
        XCTAssertEqual(SpotifyScrubber.position(atX: -30, width: 200, duration: 240), 0)
        XCTAssertEqual(SpotifyScrubber.position(atX: 900, width: 200, duration: 240), 240)
    }

    func testScrubberHandlesDegenerateInput() {
        XCTAssertEqual(SpotifyScrubber.position(atX: 10, width: 0, duration: 240), 0)
        XCTAssertEqual(SpotifyScrubber.position(atX: 10, width: 200, duration: 0), 0)
        XCTAssertEqual(SpotifyScrubber.position(atX: .nan, width: 200, duration: 240), 0)
    }
}
