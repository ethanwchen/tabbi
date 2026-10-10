import XCTest
@testable import TabbiKitCore

final class MusicScriptTests: XCTestCase {
    private func record(_ fields: [String]) -> String {
        fields.joined(separator: String(SpotifyScript.fieldSeparator))
    }

    func testParsesPlayingTrack() throws {
        let output = record([
            "playing", "8F3A2B1C9D0E7F65", "Teardrop", "Massive Attack", "Mezzanine",
            "330.5", "42.25", "true", "all", "64", "true",
        ])
        let playback = try XCTUnwrap(MusicScript.parse(output))
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(playback.track?.id, "music:8F3A2B1C9D0E7F65")
        XCTAssertEqual(playback.track?.title, "Teardrop")
        XCTAssertEqual(playback.track?.artist, "Massive Attack")
        XCTAssertEqual(playback.track?.album, "Mezzanine")
        XCTAssertNil(playback.track?.artworkURL)
        XCTAssertEqual(try XCTUnwrap(playback.track?.duration), 330.5, accuracy: 0.0001)
        XCTAssertEqual(playback.position, 42.25, accuracy: 0.0001)
        XCTAssertTrue(playback.isShuffling)
        XCTAssertEqual(playback.repeatMode, .all)
    }

    func testRepeatModesAndPausedState() throws {
        let off = try XCTUnwrap(MusicScript.parse(record(["paused", "A", "t", "a", "b", "10", "1", "false", "off", "64", ""])))
        XCTAssertEqual(off.state, .paused)
        XCTAssertEqual(off.repeatMode, .off)
        XCTAssertFalse(off.isShuffling)
        let one = try XCTUnwrap(MusicScript.parse(record(["paused", "A", "t", "a", "b", "10", "1", "false", "one", "64", "false\n"])))
        XCTAssertEqual(one.repeatMode, .one)
        XCTAssertTrue(one.isRepeating)
    }

    func testSeekingStatesCountAsPlaying() throws {
        for state in ["fast forwarding", "rewinding"] {
            let output = record([state, "A", "t", "a", "b", "10", "1", "false", "off", "64", ""])
            XCTAssertEqual(try XCTUnwrap(MusicScript.parse(output)).state, .playing, state)
        }
    }

    func testRadioStreamWithoutDurationOrID() throws {
        let output = record(["playing", "", "Beats 1", "", "", "0", "0", "false", "off", "64", ""])
        let playback = try XCTUnwrap(MusicScript.parse(output))
        XCTAssertEqual(playback.track?.id, "music:Beats 1")
        XCTAssertEqual(playback.track?.duration, 0)
        // Unknown duration: the position keeps ticking instead of pinning at 0.
        XCTAssertEqual(playback.advanced(by: 3).position, 3)
    }

    func testCommaDecimalsAndClamping() throws {
        let output = record(["playing", "A", "t", "a", "b", "200,5", "250,25", "false", "off", "64", ""])
        let playback = try XCTUnwrap(MusicScript.parse(output))
        XCTAssertEqual(try XCTUnwrap(playback.track?.duration), 200.5, accuracy: 0.0001)
        XCTAssertEqual(playback.position, 200.5, accuracy: 0.0001)
    }

    func testStoppedAndMalformed() {
        XCTAssertEqual(MusicScript.parse("stopped\n"), .nothingPlaying)
        XCTAssertNil(MusicScript.parse(""))
        XCTAssertNil(MusicScript.parse("playing"))
        XCTAssertNil(MusicScript.parse(record(["buffering", "A", "t", "a", "b", "1", "0", "false", "off", "64", ""])))
        // Spotify's 10-field record is not a Music record.
        XCTAssertNil(MusicScript.parse(record(["playing", "id", "t", "a", "b", "", "1000", "0", "false", "false", "64"])))
    }

    func testCommandsTargetMusic() {
        XCTAssertEqual(MusicScript.seek(to: 61.5),
                       #"tell application id "com.apple.Music" to set player position to 61.500"#)
        XCTAssertEqual(MediaSource.music.playPauseScript, #"tell application id "com.apple.Music" to playpause"#)
        XCTAssertEqual(MediaSource.spotify.nextTrackScript, SpotifyScript.nextTrack)
        XCTAssertEqual(MediaSource.music.setVolumeScript(140),
                       #"tell application id "com.apple.Music" to set sound volume to 100"#)
        XCTAssertTrue(MediaSource.spotify.setVolumeScript(-3).hasSuffix("to 0"))
    }

    func testArtworkReadIsPinnedToTheTrack() throws {
        let id = try XCTUnwrap(MusicScript.parse(record(["playing", "8F3A2B1C9D0E7F65", "t", "a", "b", "10", "1",
                                                         "false", "off", "64", ""]))?.track?.id)
        XCTAssertEqual(MusicScript.readArtwork(forTrackID: id), """
        tell application id "com.apple.Music"
            if (persistent ID of current track) is not "8F3A2B1C9D0E7F65" then return missing value
            if (count of artworks of current track) is 0 then return missing value
            return raw data of artwork 1 of current track
        end tell
        """)
        // Spotify ids, streams keyed by title, and injected quotes never read.
        XCTAssertNil(MusicScript.readArtwork(forTrackID: "spotify:track:abc"))
        XCTAssertNil(MusicScript.readArtwork(forTrackID: "music:Radio One"))
        XCTAssertNil(MusicScript.readArtwork(forTrackID: #"music:A" then beep"#))
        XCTAssertNil(MusicScript.readArtwork(forTrackID: "music:"))
    }

    func testReadsWhetherTheTrackIsFavorited() throws {
        func favorite(_ id: String, _ field: String) throws -> Bool? {
            try XCTUnwrap(MusicScript.parse(record(["playing", id, "t", "a", "b", "10", "1", "false", "off", "64", field])))
                .track?.isFavorite
        }
        XCTAssertEqual(try favorite("A1", "true"), true)
        XCTAssertEqual(try favorite("A1", "false\n"), false)
        XCTAssertNil(try favorite("A1", ""), "an unreadable value hides the heart")
        XCTAssertNil(try favorite("", "false"), "a stream without a persistent ID can't be favorited")
        XCTAssertNil(MusicScript.parse(record(["playing", "A1", "t", "a", "b", "10", "1", "false", "off", "64", "64"])))
    }

    func testFavoritingIsPinnedToTheTrack() throws {
        let playback = try XCTUnwrap(MusicScript.parse(record(["playing", "8F3A2B1C9D0E7F65", "t", "a", "b", "10", "1",
                                                               "false", "off", "64", "false"])))
        let track = try XCTUnwrap(playback.track)
        XCTAssertEqual(MediaSource.music.setFavoriteScript(true, for: track), """
        tell application id "com.apple.Music"
            if (persistent ID of current track) is not "8F3A2B1C9D0E7F65" then return
            set «class pLov» of current track to true
        end tell
        """)
        XCTAssertTrue(try XCTUnwrap(MediaSource.music.setFavoriteScript(false, for: track)).contains("to false"))
        XCTAssertEqual(playback.settingFavorite(true).track?.isFavorite, true)

        // Spotify's scripting can't like, and unknown or stream tracks can't either.
        XCTAssertNil(MediaSource.spotify.setFavoriteScript(true, for: SpotifyTrack(
            id: "spotify:track:1", title: "t", artist: "a", album: "b", artworkURL: nil, duration: 1, isFavorite: false)))
        var unknown = track
        unknown.isFavorite = nil
        XCTAssertNil(MediaSource.music.setFavoriteScript(true, for: unknown))
        XCTAssertNil(MusicScript.setFavorite(true, forTrackID: "music:Radio One"))
        let stream = SpotifyPlayback(state: .playing, track: unknown, position: 0, isShuffling: false, repeatMode: .off)
        XCTAssertNil(stream.settingFavorite(true).track?.isFavorite, "no optimistic heart where there is none")
    }

    func testDemoTrackShowsAWorkingHeart() throws {
        let track = try XCTUnwrap(SpotifyPlayback.demo.track)
        XCTAssertEqual(track.isFavorite, true, "demo shots show the like button")
        XCTAssertNotNil(MediaSource.music.setFavoriteScript(false, for: track),
                        "the demo track is a Music track the heart can act on")
        XCTAssertEqual(SpotifyPlayback.demo.settingFavorite(false).track?.isFavorite, false)
    }

    func testStatusResolvesWithTheSourcesParser() {
        let output = record(["playing", "A", "Teardrop", "a", "b", "10", "1", "false", "off", "64", ""])
        let status = SpotifyStatus.resolve(source: .music, isRunning: true, isInstalled: true,
                                           read: .success(output), previous: .connecting)
        XCTAssertEqual(status.playback?.track?.title, "Teardrop")
    }
}

final class MediaSourceTrackerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    private func playback(_ state: SpotifyPlayerState, id: String = "x") -> SpotifyStatus {
        .connected(SpotifyPlayback(
            state: state,
            track: SpotifyTrack(id: id, title: id, artist: "", album: "", artworkURL: nil, duration: 100),
            position: 0, isShuffling: false, repeatMode: .off
        ))
    }

    func testNothingRunning() {
        var tracker = MediaSourceTracker()
        XCTAssertEqual(tracker.status, .notInstalled)
        tracker.update(.spotify, status: .notInstalled, at: t0)
        tracker.update(.music, status: .notRunning, at: t0)
        XCTAssertNil(tracker.selected)
        XCTAssertEqual(tracker.status, .notRunning)
        XCTAssertEqual(tracker.installedSources, [.music])
    }

    func testPlayingSourceWins() {
        var tracker = MediaSourceTracker()
        tracker.update(.spotify, status: playback(.paused, id: "s"), at: t0)
        tracker.update(.music, status: playback(.playing, id: "m"), at: t0)
        XCTAssertEqual(tracker.selected, .music)
        XCTAssertEqual(tracker.status.playback?.track?.id, "m")
    }

    func testMostRecentlyStartedWinsWhenBothPlay() {
        var tracker = MediaSourceTracker()
        tracker.update(.music, status: playback(.playing), at: t0)
        tracker.update(.spotify, status: playback(.playing), at: t0 + 5)
        XCTAssertEqual(tracker.selected, .spotify)
        // Music's later reads don't steal focus back; it didn't restart.
        tracker.update(.music, status: playback(.playing), at: t0 + 10)
        XCTAssertEqual(tracker.selected, .spotify)
    }

    func testBothPausedPrefersMostRecentlyActive() {
        var tracker = MediaSourceTracker()
        tracker.update(.music, status: playback(.playing), at: t0)
        tracker.update(.spotify, status: playback(.playing), at: t0 + 3)
        tracker.update(.spotify, status: playback(.paused), at: t0 + 4)
        XCTAssertEqual(tracker.selected, .music)
        // Music pauses last, so it stays the one shown.
        tracker.update(.music, status: playback(.paused), at: t0 + 8)
        XCTAssertEqual(tracker.selected, .music)
        XCTAssertFalse(tracker.status.isPlaying)
    }

    func testIdleTiesPreferALoadedTrackThenStayPut() {
        var tracker = MediaSourceTracker()
        tracker.update(.spotify, status: .connected(.nothingPlaying), at: t0)
        tracker.update(.music, status: playback(.paused), at: t0)
        XCTAssertEqual(tracker.selected, .music)

        var idle = MediaSourceTracker()
        idle.update(.music, status: .connected(.nothingPlaying), at: t0)
        XCTAssertEqual(idle.selected, .music)
        idle.update(.spotify, status: .connected(.nothingPlaying), at: t0)
        XCTAssertEqual(idle.selected, .music, "an equally idle app doesn't take over")
    }

    func testQuittingFallsBackToTheOtherApp() {
        var tracker = MediaSourceTracker()
        tracker.update(.spotify, status: playback(.paused), at: t0)
        tracker.update(.music, status: playback(.playing), at: t0)
        tracker.update(.music, status: .notRunning, at: t0 + 1)
        XCTAssertEqual(tracker.selected, .spotify)
        tracker.update(.spotify, status: .notRunning, at: t0 + 2)
        XCTAssertNil(tracker.selected)
        XCTAssertEqual(tracker.status, .notRunning)
    }

    func testPermissionPromptBeatsAnIdleApp() {
        var tracker = MediaSourceTracker()
        tracker.update(.spotify, status: .connected(.nothingPlaying), at: t0)
        tracker.update(.music, status: .permissionDenied, at: t0)
        XCTAssertEqual(tracker.status, .permissionDenied)
        // ...but not an app that is playing.
        tracker.update(.spotify, status: playback(.playing), at: t0 + 1)
        XCTAssertEqual(tracker.selected, .spotify)
    }

    func testNamesReadAsASentence() {
        XCTAssertEqual(MediaSource.names([.music]), "Music")
        XCTAssertEqual(MediaSource.names([.spotify, .music]), "Spotify or Music")
        XCTAssertEqual(MediaSource.names([]), "Spotify or Music", "no installed app falls back to every app")
    }
}
