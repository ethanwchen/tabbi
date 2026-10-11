import XCTest
@testable import TabbiKitCore

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
        for seed in ["", "x", "spotify:local:::Song:180", "\u{1F3A7} 曲", String(repeating: "z", count: 500)] {
            let cover = SpotifyGeneratedCover(seed: seed)
            XCTAssert((0..<1).contains(cover.startHue), seed)
            XCTAssert((0..<1).contains(cover.endHue), seed)
            var gap = cover.endHue - cover.startHue
            if gap < 0 { gap += 1 }
            XCTAssert((50.0 / 360 - 1e-9...110.0 / 360 + 1e-9).contains(gap), "\(seed): \(gap)")
        }
    }
}
