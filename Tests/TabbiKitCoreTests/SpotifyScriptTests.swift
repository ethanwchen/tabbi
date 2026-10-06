import XCTest
@testable import TabbiKitCore

final class SpotifyScriptTests: XCTestCase {
    private func record(_ fields: [String]) -> String {
        fields.joined(separator: String(SpotifyScript.fieldSeparator))
    }

    func testParsesPlayingTrack() throws {
        let output = record([
            "playing", "spotify:track:abc", "Midnight City", "M83", "Hurry Up, We're Dreaming",
            "https://i.scdn.co/image/ab67", "243960", "87.25", "true", "false", "64",
        ])
        let playback = try XCTUnwrap(SpotifyScript.parse(output))
        XCTAssertEqual(playback.state, .playing)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.track?.id, "spotify:track:abc")
        XCTAssertEqual(playback.track?.title, "Midnight City")
        XCTAssertEqual(playback.track?.artist, "M83")
        XCTAssertEqual(playback.track?.album, "Hurry Up, We're Dreaming")
        XCTAssertEqual(playback.track?.artworkURL, URL(string: "https://i.scdn.co/image/ab67"))
        XCTAssertEqual(try XCTUnwrap(playback.track?.duration), 243.96, accuracy: 0.0001)
        XCTAssertEqual(playback.position, 87.25, accuracy: 0.0001)
        XCTAssertTrue(playback.isShuffling)
        XCTAssertEqual(playback.repeatMode, .off)
    }

    func testOddCharactersInTitlesSurvive() throws {
        let title = "Don't Stop | \"Live\" (feat. Ñoño & 坂本龍一)\tPart 2\nReprise \u{1F3A7}"
        let output = record([
            "paused", "spotify:track:x", title, "Sigur Rós, Björk", "Ágætis byrjun \u{2014} Remaster",
            "", "60000", "0", "false", "true", "64",
        ]) + "\n"
        let playback = try XCTUnwrap(SpotifyScript.parse(output))
        XCTAssertEqual(playback.state, .paused)
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.track?.title, title)
        XCTAssertEqual(playback.track?.artist, "Sigur Rós, Björk")
        XCTAssertEqual(playback.track?.album, "Ágætis byrjun \u{2014} Remaster")
        XCTAssertNil(playback.track?.artworkURL)
        XCTAssertEqual(playback.repeatMode, .all)
    }

    func testEmptyTitleFieldsAreKept() throws {
        let output = record(["playing", "spotify:ad:1", "", "", "", "", "30000", "3", "false", "false", "64"])
        let playback = try XCTUnwrap(SpotifyScript.parse(output))
        XCTAssertEqual(playback.track?.title, "")
        XCTAssertEqual(playback.track?.duration, 30)
    }

    func testCommaDecimalAndExponentPositions() throws {
        let comma = record(["playing", "id", "t", "a", "b", "", "200000", "12,5", "false", "false", "64"])
        XCTAssertEqual(try XCTUnwrap(SpotifyScript.parse(comma)).position, 12.5, accuracy: 0.0001)
        let exponent = record(["playing", "id", "t", "a", "b", "", "200000", "1.0E-3", "false", "false", "64"])
        XCTAssertEqual(try XCTUnwrap(SpotifyScript.parse(exponent)).position, 0.001, accuracy: 0.00001)
    }

    func testPositionIsClampedToDuration() throws {
        let output = record(["playing", "id", "t", "a", "b", "", "10000", "12", "false", "false", "64"])
        XCTAssertEqual(try XCTUnwrap(SpotifyScript.parse(output)).position, 10)
    }

    func testStopped() {
        XCTAssertEqual(
            SpotifyScript.parse("stopped\n"),
            SpotifyPlayback(state: .stopped, track: nil, position: 0, isShuffling: false, repeatMode: .off)
        )
    }

    func testRejectsMalformedOutput() {
        XCTAssertNil(SpotifyScript.parse(""))
        XCTAssertNil(SpotifyScript.parse("buffering"))
        XCTAssertNil(SpotifyScript.parse("playing"))
        XCTAssertNil(SpotifyScript.parse(record(["playing", "id", "t"])))
    }

    func testSeekScriptUsesDotDecimal() {
        XCTAssertEqual(
            SpotifyScript.seek(to: 61.5),
            #"tell application id "com.spotify.client" to set player position to 61.500"#
        )
        XCTAssertTrue(SpotifyScript.seek(to: -4).hasSuffix("to 0.000"))
    }

    func testErrorCodes() {
        XCTAssertEqual(SpotifyScriptError(code: -1743), .permissionDenied)
        XCTAssertEqual(SpotifyScriptError(code: -600), .notRunning)
        XCTAssertEqual(SpotifyScriptError(code: -1728), .other(code: -1728))
    }
}

final class SpotifyPlaybackTests: XCTestCase {
    private func playback(state: SpotifyPlayerState = .playing, position: TimeInterval = 10,
                          duration: TimeInterval = 100) -> SpotifyPlayback {
        SpotifyPlayback(
            state: state,
            track: SpotifyTrack(id: "id", title: "t", artist: "a", album: "b", artworkURL: nil, duration: duration),
            position: position, isShuffling: false, repeatMode: .off
        )
    }

    func testAdvanceMovesOnlyWhilePlaying() {
        XCTAssertEqual(playback().advanced(by: 1.5).position, 11.5)
        XCTAssertEqual(playback(state: .paused).advanced(by: 5).position, 10)
        XCTAssertEqual(playback().advanced(by: -3).position, 10)
    }

    func testAdvanceStopsAtEndOfTrack() {
        XCTAssertEqual(playback(position: 99).advanced(by: 5).position, 100)
    }

    func testUnknownDurationIsUnbounded() {
        let stream = playback(position: 500, duration: 0)
        XCTAssertEqual(stream.advanced(by: 1).position, 501)
        XCTAssertEqual(stream.progress, 0)
    }

    func testProgress() {
        XCTAssertEqual(playback(position: 25).progress, 0.25)
        XCTAssertEqual(playback(position: 0).progress, 0)
    }

    func testDemoIsPlayingWithoutNetworkArtwork() {
        XCTAssertTrue(SpotifyPlayback.demo.isPlaying)
        XCTAssertNil(SpotifyPlayback.demo.track?.artworkURL)
    }

    func testTimeFormatting() {
        XCTAssertEqual(PlaybackTimeFormatter.string(0), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.string(87.9), "1:27")
        XCTAssertEqual(PlaybackTimeFormatter.string(3725), "1:02:05")
        XCTAssertEqual(PlaybackTimeFormatter.string(-3), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.string(.nan), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.remaining(position: 10.4, duration: 180), "-2:50")
        XCTAssertEqual(PlaybackTimeFormatter.remaining(position: 200, duration: 180), "-0:00")
    }
}
