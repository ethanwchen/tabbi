import XCTest
@testable import TabbiKitCore

final class NowPlayingSourceTests: XCTestCase {
    private let safari = NowPlayingSource.soundCloud(.safari)
    private let t0 = Date(timeIntervalSinceReferenceDate: 10_000)

    private func record(_ fields: [String]) -> String {
        fields.joined(separator: String(SpotifyScript.fieldSeparator))
    }

    private var playingRecord: String {
        record(["playing", "/forss/flickermood", "Flickermood", "Forss", "", "213", "8", "false", "off", "true"])
    }

    private func resolve(_ source: NowPlayingSource, read: Result<String, SpotifyScriptError>?,
                         previous: SpotifyStatus = .notRunning) -> SpotifyStatus {
        SpotifyStatus.resolve(source: source, isRunning: true, isInstalled: true, read: read, previous: previous)
    }

    private func track(_ id: String, isFavorite: Bool?) -> SpotifyTrack {
        SpotifyTrack(id: id, title: "t", artist: "a", album: "", artworkURL: nil, duration: 100,
                     isFavorite: isFavorite)
    }

    private func playback(_ state: SpotifyPlayerState) -> SpotifyStatus {
        .connected(SpotifyPlayback(state: state, track: track("x", isFavorite: nil), position: 0,
                                   isShuffling: false, repeatMode: .off))
    }

    // MARK: - Identity

    func testSoundCloudRunsInItsBrowser() {
        XCTAssertEqual(safari.displayName, "SoundCloud")
        XCTAssertEqual(safari.bundleIdentifier, "com.apple.Safari")
        XCTAssertNil(safari.app)
        XCTAssertEqual(NowPlayingSource.spotify.app, .spotify)
        XCTAssertEqual(NowPlayingSource.all.first, .spotify, "apps come before browsers")
        XCTAssertEqual(NowPlayingSource.all.count, MediaSource.allCases.count + SoundCloudBrowser.allCases.count)
    }

    // MARK: - Reading

    func testSoundCloudReadsResolve() {
        let playing = resolve(safari, read: .success(playingRecord))
        XCTAssertTrue(playing.isPlaying)
        XCTAssertEqual(playing.playback?.track?.id, "soundcloud:/forss/flickermood")
        XCTAssertEqual(resolve(safari, read: .success("javascript-off")), .scriptingDisabled)
        XCTAssertEqual(resolve(safari, read: .success("stopped")), .connected(.nothingPlaying))
        // A browser without a SoundCloud tab counts as not running.
        XCTAssertEqual(resolve(safari, read: .success("no-tab"), previous: playing), .notRunning)
    }

    func testABrowserIsNeverConnectingBeforeItsFirstRead() {
        XCTAssertEqual(resolve(safari, read: nil), .notRunning)
        XCTAssertEqual(resolve(safari, read: nil, previous: .notInstalled), .notRunning)
        XCTAssertEqual(resolve(safari, read: nil, previous: .scriptingDisabled), .scriptingDisabled)
        // Apps still show that they are connecting.
        XCTAssertEqual(resolve(.music, read: nil), .connecting)
    }

    func testInconclusiveBrowserReadsDontInventAPlayer() {
        XCTAssertEqual(resolve(safari, read: .failure(SpotifyScriptError(code: -2700))), .notRunning)
        XCTAssertEqual(resolve(safari, read: .success("garbage")), .notRunning)
        XCTAssertEqual(resolve(safari, read: .failure(SpotifyScriptError(code: -1743))), .permissionDenied)
        // Music errors right after launch, which means nothing is loaded yet.
        XCTAssertEqual(resolve(.music, read: .failure(SpotifyScriptError(code: -2700))),
                       .connected(.nothingPlaying))
    }

    // MARK: - Commands

    func testAppCommandsAreTheAppsOwnScripts() {
        let song = track("A1B2", isFavorite: true)
        XCTAssertEqual(NowPlayingSource.spotify.playPauseScript, SpotifyScript.playPause)
        XCTAssertEqual(NowPlayingSource.spotify.seekScript(to: 12, in: song), SpotifyScript.seek(to: 12))
        XCTAssertEqual(NowPlayingSource.music.setRepeatScript(.one), MediaSource.music.setRepeatScript(.one))
        XCTAssertEqual(NowPlayingSource.music.setFavoriteScript(true, for: song),
                       MusicScript.setFavorite(true, forTrackID: "A1B2"))
        XCTAssertNotNil(NowPlayingSource.music.setVolumeScript(40))
    }

    func testSoundCloudCommandsRunInTheBrowserTab() {
        let liked = track("soundcloud:/forss/flickermood", isFavorite: false)
        XCTAssertEqual(safari.playPauseScript, SoundCloudScript.playPause(in: .safari))
        XCTAssertEqual(safari.nextTrackScript, SoundCloudScript.nextTrack(in: .safari))
        XCTAssertEqual(NowPlayingSource.soundCloud(.chrome).previousTrackScript,
                       SoundCloudScript.previousTrack(in: .chrome))
        XCTAssertEqual(safari.seekScript(to: 30, in: liked),
                       SoundCloudScript.seek(to: 30, forTrackID: liked.id, in: .safari))
        XCTAssertEqual(safari.setFavoriteScript(true, for: liked),
                       SoundCloudScript.setLiked(true, forTrackID: liked.id, in: .safari))
        XCTAssertEqual(safari.setShuffleScript(true), SoundCloudScript.setShuffle(true, in: .safari))
        // Signed out there is no like, and the web player has no volume.
        XCTAssertNil(safari.setFavoriteScript(true, for: track(liked.id, isFavorite: nil)))
        XCTAssertNil(safari.setVolumeScript(40))
    }

    func testSoundCloudRepeatStepsLikeItsButton() {
        XCTAssertEqual(safari.repeatMode(after: .off), .one)
        XCTAssertEqual(safari.repeatMode(after: .one), .all)
        XCTAssertEqual(safari.repeatMode(after: .all), .off)
        XCTAssertEqual(NowPlayingSource.music.repeatMode(after: .off), .all)
        XCTAssertEqual(NowPlayingSource.spotify.repeatMode(after: .all), .off)
    }

    // MARK: - Choosing a player

    func testPlayingSoundCloudWinsOverAPausedApp() {
        var tracker = MediaSourceTracker()
        tracker.update(.spotify, status: playback(.paused), at: t0)
        tracker.update(safari, status: resolve(safari, read: .success(playingRecord)), at: t0 + 1)
        XCTAssertEqual(tracker.selected, safari)
        // Closing the tab hands the panel back to Spotify.
        tracker.update(safari, status: .notRunning, at: t0 + 2)
        XCTAssertEqual(tracker.selected, .spotify)
    }

    func testABrowserWithoutSoundCloudIsNeverFollowed() {
        var tracker = MediaSourceTracker()
        tracker.update(.spotify, status: .notInstalled, at: t0)
        tracker.update(.music, status: .notRunning, at: t0)
        tracker.update(safari, status: .notRunning, at: t0)
        XCTAssertNil(tracker.selected)
        XCTAssertEqual(tracker.status, .notRunning)
        XCTAssertEqual(tracker.installedSources, [.music], "a browser is not a music app to open")

        var browsersOnly = MediaSourceTracker()
        browsersOnly.update(safari, status: .notRunning, at: t0)
        XCTAssertEqual(browsersOnly.status, .notInstalled)
    }

    func testJavaScriptHintDoesNotHideALoadedTrack() {
        var tracker = MediaSourceTracker()
        tracker.update(.music, status: playback(.paused), at: t0)
        tracker.update(safari, status: .scriptingDisabled, at: t0)
        XCTAssertEqual(tracker.selected, .music)

        var idle = MediaSourceTracker()
        idle.update(.music, status: .connected(.nothingPlaying), at: t0)
        idle.update(safari, status: .scriptingDisabled, at: t0)
        XCTAssertEqual(idle.status, .scriptingDisabled, "the hint beats an app with nothing loaded")
    }
}
