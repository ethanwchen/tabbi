import XCTest
@testable import TabbiKitCore

final class SoundCloudScriptTests: XCTestCase {
    private struct NotPlayback: Error { let output: String }

    private func record(_ fields: [String]) -> String {
        fields.joined(separator: String(SpotifyScript.fieldSeparator))
    }

    private func playback(_ output: String) throws -> SpotifyPlayback {
        guard case .playback(let playback) = try XCTUnwrap(SoundCloudScript.parse(output)) else {
            throw NotPlayback(output: output)
        }
        return playback
    }

    func testParsesPlayingTrack() throws {
        let playback = try playback(record([
            "playing", "/forss/flickermood", "Flickermood", "Forss",
            "https://i1.sndcdn.com/artworks-000067273316-smsiqx-t500x500.jpg",
            "213", "8", "true", "one", "false",
        ]))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.track?.id, "soundcloud:/forss/flickermood")
        XCTAssertEqual(playback.track?.title, "Flickermood")
        XCTAssertEqual(playback.track?.artist, "Forss")
        XCTAssertEqual(playback.track?.album, "")
        XCTAssertEqual(playback.track?.artworkURL?.host, "i1.sndcdn.com")
        XCTAssertEqual(playback.track?.duration, 213)
        XCTAssertEqual(playback.position, 8)
        XCTAssertTrue(playback.isShuffling)
        XCTAssertEqual(playback.repeatMode, .one)
        XCTAssertEqual(playback.track?.isFavorite, false)
        // The web player has no volume Tabbi can set.
        XCTAssertNil(playback.volume)
    }

    func testSignedOutTrackHasNoHeart() throws {
        let playback = try playback(record(["paused", "/a/b", "t", "a", "", "60", "61", "false", "off", ""]))
        XCTAssertEqual(playback.state, .paused)
        XCTAssertNil(playback.track?.isFavorite)
        XCTAssertNil(playback.track?.artworkURL)
        // The position never runs past the end.
        XCTAssertEqual(playback.position, 60)
    }

    func testMarkersAndStopped() {
        XCTAssertEqual(SoundCloudScript.parse("no-tab"), .noTab)
        XCTAssertEqual(SoundCloudScript.parse("javascript-off\n"), .javaScriptOff)
        XCTAssertEqual(SoundCloudScript.parse("stopped"), .playback(.nothingPlaying))
    }

    func testRejectsMalformedRecords() {
        XCTAssertNil(SoundCloudScript.parse(""))
        XCTAssertNil(SoundCloudScript.parse("ok"))
        XCTAssertNil(SoundCloudScript.parse(record(["playing", "/a/b", "t", "a", "", "1", "0", "false", "off"])))
        XCTAssertNil(SoundCloudScript.parse(record(["buffering", "/a/b", "t", "a", "", "1", "0", "false", "off", ""])))
        XCTAssertNil(SoundCloudScript.parse(record(["stopped", "/a/b", "t", "a", "", "1", "0", "false", "off", ""])))
        XCTAssertNil(SoundCloudScript.parse(record(["playing", "", "t", "a", "", "1", "0", "false", "off", ""])))
        XCTAssertNil(SoundCloudScript.parse(record(["playing", "/a/b", "t", "a", "", "1", "0", "false", "off", "yes"])))
    }

    func testScriptsTargetTheBrowserAndFindTheSoundCloudTab() {
        let safari = SoundCloudScript.readState(in: .safari)
        XCTAssertTrue(safari.hasPrefix(#"tell application id "com.apple.Safari""#))
        XCTAssertTrue(safari.contains("do JavaScript"))
        XCTAssertTrue(safari.contains(#"starts with "https://soundcloud.com/""#))
        let chrome = SoundCloudScript.playPause(in: .chrome)
        XCTAssertTrue(chrome.hasPrefix(#"tell application id "com.google.Chrome""#))
        XCTAssertTrue(chrome.contains("execute t javascript"))
        XCTAssertTrue(chrome.contains("player('playpause', null, '');"))
    }

    func testPinnedActionsCarryTheTrackPath() {
        XCTAssertEqual(SoundCloudScript.Action.seek(seconds: 61.5, trackID: "soundcloud:/forss/flickermood").call,
                       #"player('seek', 61.500, "\/forss\/flickermood")"#)
        XCTAssertEqual(SoundCloudScript.Action.like(true, trackID: "soundcloud:/a/b").call,
                       #"player('like', true, "\/a\/b")"#)
        // A Music or Spotify id never matches a SoundCloud path.
        XCTAssertEqual(SoundCloudScript.Action.like(true, trackID: "music:ABC").call, "player('like', true, '-')")
        XCTAssertEqual(SoundCloudScript.Action.repeatMode(.all).call, "player('repeat', 'all', '')")
    }

    func testAppleScriptLiteralEscapesQuotesAndBackslashes() {
        XCTAssertEqual(SoundCloudScript.appleScriptLiteral(#"a "b" \c"#), #""a \"b\" \\c""#)
        // A path with a quote stays inside its JavaScript string after both escapes.
        let script = SoundCloudScript.setLiked(false, forTrackID: #"soundcloud:/x/"quoted""#, in: .safari)
        XCTAssertTrue(script.contains(#"player('like', false, \"\\/x\\/\\\"quoted\\\"\");"#))
    }
}
