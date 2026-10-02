import XCTest
@testable import NotchKitCore

final class MediaVolumeTests: XCTestCase {
    private func record(_ fields: [String]) -> String {
        fields.joined(separator: String(SpotifyScript.fieldSeparator))
    }

    func testBothPlayersReportTheirVolume() throws {
        let spotify = record(["playing", "id", "t", "a", "b", "", "200000", "1", "false", "false", "73\n"])
        XCTAssertEqual(try XCTUnwrap(SpotifyScript.parse(spotify)).volume, 73)
        let music = record(["playing", "A", "t", "a", "b", "10", "1", "false", "off", "0"])
        XCTAssertEqual(try XCTUnwrap(MusicScript.parse(music)).volume, 0)
    }

    func testUnreadableVolumeIsUnknownNotSilent() throws {
        // Music's script falls back to -1 when `sound volume` can't be read.
        let music = record(["playing", "A", "t", "a", "b", "10", "1", "false", "off", "-1"])
        XCTAssertNil(try XCTUnwrap(MusicScript.parse(music)).volume)
        let spotify = record(["playing", "id", "t", "a", "b", "", "200000", "1", "false", "false", ""])
        XCTAssertNil(try XCTUnwrap(SpotifyScript.parse(spotify)).volume)
        XCTAssertNil(SpotifyPlayback.nothingPlaying.volume)
    }

    func testParseAcceptsRealsAndClamps() {
        XCTAssertEqual(MediaVolume.parse("64.6"), 65)
        XCTAssertEqual(MediaVolume.parse("12,0"), 12)
        XCTAssertEqual(MediaVolume.parse("140"), 100)
        XCTAssertNil(MediaVolume.parse("loud"))
        XCTAssertEqual(SpotifyPlayback(state: .paused, track: nil, position: 0, isShuffling: false,
                                       isRepeating: false, volume: 300).volume, 100)
    }

    func testSliderMapsPointerToVolume() {
        XCTAssertEqual(MediaVolume.volume(atX: 30, width: 60), 50)
        XCTAssertEqual(MediaVolume.volume(atX: -10, width: 60), 0)
        XCTAssertEqual(MediaVolume.volume(atX: 90, width: 60), 100)
        XCTAssertEqual(MediaVolume.volume(atX: 10, width: 0), 0)
    }

    func testLevelsPickTheSpeakerGlyph() {
        XCTAssertEqual([0, 1, 33, 34, 66, 67, 100].map(MediaVolume.level), [0, 1, 1, 2, 2, 3, 3])
    }

    func testMuteToggleRestoresThePreviousLevel() {
        XCTAssertEqual(MediaVolume.togglingMute(64, previous: nil), 0)
        XCTAssertEqual(MediaVolume.togglingMute(0, previous: 64), 64)
        // Nothing audible to restore: unmute to a sensible default.
        XCTAssertEqual(MediaVolume.togglingMute(0, previous: nil), MediaVolume.unmuteFallback)
        XCTAssertEqual(MediaVolume.togglingMute(0, previous: 0), MediaVolume.unmuteFallback)
    }

    func testOptimisticVolumeChange() {
        XCTAssertEqual(SpotifyPlayback.demo.settingVolume(20).volume, 20)
        XCTAssertEqual(SpotifyPlayback.demo.settingVolume(-5).volume, 0)
        // No known volume means no control, so nothing to change.
        XCTAssertNil(SpotifyPlayback.nothingPlaying.settingVolume(40).volume)
    }
}
