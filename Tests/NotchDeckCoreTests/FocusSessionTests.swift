import XCTest
import NotchDeckCore

final class FocusPlaylistScriptTests: XCTestCase {
    func testSpotifyPlaysTheURIAsAContext() {
        let script = FocusPlaylistScript.play(.spotify(uri: "spotify:playlist:abc123"))
        XCTAssertEqual(script, #"tell application id "com.spotify.client" to play track "spotify:playlist:abc123""#)
        XCTAssertTrue(FocusPlaylistScript.startsPlayback(.spotify(uri: "spotify:playlist:abc123")))
    }

    func testLibraryNamesAreEscapedSoTheyCantBreakTheScript() {
        let script = FocusPlaylistScript.play(.musicLibrary(name: #"Say "hi" \ bye"#))
        XCTAssertEqual(script, #"tell application id "com.apple.Music" to play playlist "Say \"hi\" \\ bye""#)
        XCTAssertEqual(FocusPlaylistScript.quoted("a\nb"), #""a b""#)
    }

    func testAppleMusicLinksOpenInMusicWithoutAutoPlaying() throws {
        let playlist = try XCTUnwrap(FocusPlaylist("https://music.apple.com/us/playlist/pure-focus/pl.abc?l=en"))
        XCTAssertEqual(FocusPlaylistScript.play(playlist),
                       #"tell application id "com.apple.Music" to open location "music://music.apple.com/us/playlist/pure-focus/pl.abc?l=en""#)
        XCTAssertFalse(FocusPlaylistScript.startsPlayback(playlist))
    }

    func testPauseNeverToggles() {
        XCTAssertEqual(FocusPlaylistScript.pause(.music), #"tell application id "com.apple.Music" to pause"#)
        XCTAssertEqual(FocusPlaylistScript.pause(.spotify), #"tell application id "com.spotify.client" to pause"#)
    }
}

final class FocusSessionTests: XCTestCase {
    private let spotify = FocusPlaylist.spotify(uri: "spotify:playlist:abc")
    private var full: FocusSettings {
        FocusSettings(mix: .single(.rain), volume: 0.4, playlistText: "spotify:playlist:abc",
                      doNotDisturb: true, onShortcut: "On", offShortcut: "Off")
    }

    private func go(_ session: inout FocusSession, _ activity: FocusActivity,
                    settings: FocusSettings? = nil, playing: Set<MediaSource> = []) -> [FocusSessionAction] {
        session.transition(to: activity, settings: settings ?? full) { playing.contains($0) }
    }

    func testActivityFollowsTheTimer() {
        let now = Date()
        var timer = FocusTimer()
        XCTAssertEqual(FocusActivity(timer), .idle)
        timer.start(at: now)
        XCTAssertEqual(FocusActivity(timer), .focusing)
        timer.pause(at: now)
        XCTAssertEqual(FocusActivity(timer), .interrupted)
        timer.start(at: now)
        timer.advance(to: now.addingTimeInterval(timer.config.focusDuration + 1))
        XCTAssertEqual(timer.phase, .rest)
        XCTAssertEqual(FocusActivity(timer), .interrupted)
        timer.reset()
        XCTAssertEqual(FocusActivity(timer), .idle)
    }

    func testFocusStartsEverythingAndBreakUndoesIt() {
        var session = FocusSession()
        XCTAssertEqual(go(&session, .focusing), [
            .startSound(.single(.rain), volume: 0.4), .playPlaylist(spotify), .runShortcut("On"),
        ])
        XCTAssertTrue(session.isFocusing)
        XCTAssertEqual(go(&session, .focusing), [], "repeated updates are no-ops")
        XCTAssertEqual(go(&session, .interrupted), [.stopSound, .pausePlaylist(.spotify), .runShortcut("Off")])
        XCTAssertEqual(go(&session, .idle), [])
    }

    func testDefaultSettingsDoNothing() {
        var session = FocusSession()
        XCTAssertEqual(go(&session, .focusing, settings: .default), [])
        XCTAssertEqual(go(&session, .idle, settings: .default), [])
    }

    func testEndUsesTheSettingsCapturedAtStart() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        // Turning everything off mid-phase must still undo what started.
        XCTAssertEqual(go(&session, .idle, settings: .default),
                       [.stopSound, .pausePlaylist(.spotify), .runShortcut("Off")])
    }

    func testOffShortcutOnlyRunsIfOnShortcutRan() {
        var session = FocusSession()
        var settings = full
        settings.onShortcut = " "
        XCTAssertFalse(go(&session, .focusing, settings: settings).contains(.runShortcut("On")))
        XCTAssertFalse(go(&session, .interrupted).contains(.runShortcut("Off")))
    }

    func testDoesntStartAPlaylistOverMusicTheUserIsPlaying() {
        var session = FocusSession()
        let actions = go(&session, .focusing, playing: [.spotify])
        XCTAssertFalse(actions.contains(.playPlaylist(spotify)))
        XCTAssertFalse(go(&session, .interrupted).contains(.pausePlaylist(.spotify)),
                       "their music isn't ours to pause")
    }

    func testManualPauseIsRespectedUntilTheSessionEnds() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        session.observe(.paused, of: .spotify)
        XCTAssertEqual(go(&session, .interrupted), [.stopSound, .runShortcut("Off")], "no pause, it's already theirs")
        XCTAssertFalse(go(&session, .focusing).contains(.playPlaylist(spotify)), "not restarted after the break")
        XCTAssertFalse(go(&session, .interrupted).contains(.pausePlaylist(.spotify)))
        _ = go(&session, .idle)
        XCTAssertTrue(go(&session, .focusing).contains(.playPlaylist(spotify)), "a new session starts it again")
    }

    func testOurOwnPauseAtTheBreakIsntMistakenForTheUsers() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        _ = go(&session, .interrupted)
        session.observe(.paused, of: .spotify)
        XCTAssertTrue(go(&session, .focusing).contains(.playPlaylist(spotify)))
    }

    func testOtherAppsAndPreStartPausesDontCountAsDeclining() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.paused, of: .spotify)  // still loading
        session.observe(.paused, of: .music)
        XCTAssertTrue(go(&session, .interrupted).contains(.pausePlaylist(.spotify)))
    }

    func testAppleMusicLinkIsOnlyPausedOnceSeenPlaying() {
        var settings = full
        settings.playlistText = "https://music.apple.com/us/playlist/focus/pl.abc"
        var session = FocusSession()
        XCTAssertTrue(go(&session, .focusing, settings: settings).contains { if case .playPlaylist = $0 { true } else { false } })
        XCTAssertFalse(go(&session, .interrupted).contains(.pausePlaylist(.music)), "the user may have played something else")

        _ = go(&session, .focusing, settings: settings)
        session.observe(.playing, of: .music)
        XCTAssertTrue(go(&session, .interrupted).contains(.pausePlaylist(.music)))
    }
}
