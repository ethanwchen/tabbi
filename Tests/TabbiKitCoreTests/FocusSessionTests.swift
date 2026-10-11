import XCTest
import TabbiKitCore

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

    func testResumeContinuesWithoutRestarting() {
        XCTAssertEqual(FocusPlaylistScript.resume(.spotify), #"tell application id "com.spotify.client" to play"#)
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
        XCTAssertTrue(go(&session, .focusing).contains(.resumePlaylist(.spotify)))
    }

    func testAPlaylistPausedAtTheBreakResumesWhereItLeftOff() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        _ = go(&session, .interrupted)
        let next = go(&session, .focusing)
        XCTAssertTrue(next.contains(.resumePlaylist(.spotify)))
        XCTAssertFalse(next.contains(.playPlaylist(spotify)), "not restarted from the first track")
        session.observe(.paused, of: .spotify)  // resume still landing
        session.observe(.playing, of: .spotify)
        XCTAssertTrue(go(&session, .interrupted).contains(.pausePlaylist(.spotify)), "paused again at the next break")
        _ = go(&session, .idle)
        XCTAssertTrue(go(&session, .focusing).contains(.playPlaylist(spotify)), "a new session starts fresh")
    }

    func testPlayingOrQuittingDuringTheBreakStartsThePlaylistFresh() {
        for state in [SpotifyPlayerState.playing, .stopped] {
            var session = FocusSession()
            _ = go(&session, .focusing)
            session.observe(.playing, of: .spotify)
            _ = go(&session, .interrupted)
            session.observe(state, of: .spotify)
            XCTAssertTrue(go(&session, .focusing).contains(.playPlaylist(spotify)), "\(state)")
        }
    }

    func testAChangedPlaylistIsPlayedRatherThanResumed() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        _ = go(&session, .interrupted)
        var settings = full
        settings.playlistText = "spotify:playlist:other"
        XCTAssertTrue(go(&session, .focusing, settings: settings).contains(.playPlaylist(.spotify(uri: "spotify:playlist:other"))))
    }

    func testAPlaylistNeverSeenPlayingIsStartedFreshNextTime() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        _ = go(&session, .interrupted)
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

    // MARK: - Picking a playlist in the mixer

    private func picking(_ text: String) -> FocusSettings {
        var settings = full
        settings.playlistText = text
        return settings
    }

    func testAPickOutsideFocusPlaysRightAway() {
        var session = FocusSession()
        XCTAssertEqual(session.choosePlaylist(in: full), [.playPlaylist(spotify)], "the click asked for it")
    }

    func testAPhaseStartingAfterAPickLeavesItPlayingAndPausesItAtTheBreak() {
        var session = FocusSession()
        _ = session.choosePlaylist(in: full)
        let start = go(&session, .focusing, playing: [.spotify])
        XCTAssertFalse(start.contains(.playPlaylist(spotify)), "already playing, not restarted")
        session.observe(.playing, of: .spotify)
        XCTAssertTrue(go(&session, .interrupted).contains(.pausePlaylist(.spotify)), "focus mode looks after it")
    }

    func testAPhaseStartingWhileAPickIsStillLoadingDoesntStartItTwice() {
        var session = FocusSession()
        _ = session.choosePlaylist(in: full)
        XCTAssertFalse(go(&session, .focusing).contains(.playPlaylist(spotify)))
    }

    func testAPickMidPhasePlaysNowAndBecomesThePhasesPlaylist() {
        var session = FocusSession()
        _ = go(&session, .focusing, settings: .default)
        let other = FocusPlaylist.spotify(uri: "spotify:playlist:other")
        XCTAssertEqual(session.choosePlaylist(in: picking("spotify:playlist:other").withoutSound), [.playPlaylist(other)])
        session.observe(.playing, of: .spotify)
        XCTAssertEqual(go(&session, .interrupted), [.pausePlaylist(.spotify)], "paused at the break like one the phase started")
        // The picked playlist is in the settings now, which the next phase reads.
        XCTAssertEqual(go(&session, .focusing, settings: picking("spotify:playlist:other").withoutSound),
                       [.resumePlaylist(.spotify)], "and resumed after it, though the phase started without one")
    }

    func testAPickPlaysEvenOverMusicTheUserDeclinedEarlier() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        session.observe(.paused, of: .spotify)  // declined for this session
        XCTAssertEqual(session.choosePlaylist(in: picking("spotify:playlist:other")),
                       [.playPlaylist(.spotify(uri: "spotify:playlist:other"))])
    }

    func testSwitchingAppsPausesThePlaylistFocusModeStarted() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        let music = "https://music.apple.com/us/playlist/focus/pl.abc"
        let actions = session.choosePlaylist(in: picking(music))
        XCTAssertEqual(actions.first, .pausePlaylist(.spotify))
        XCTAssertEqual(actions.count, 2)
    }

    func testTurningThePlaylistOffPausesOnlyWhatFocusModeStarted() {
        var session = FocusSession()
        _ = session.choosePlaylist(in: full)
        session.observe(.playing, of: .spotify)
        XCTAssertEqual(session.choosePlaylist(in: picking("")), [.pausePlaylist(.spotify)])

        var theirs = FocusSession()
        _ = go(&theirs, .focusing, playing: [.spotify])  // their own music, never ours
        XCTAssertEqual(theirs.choosePlaylist(in: picking("")), [], "never pause music focus mode didn't start")
        XCTAssertEqual(go(&theirs, .interrupted), [.stopSound, .runShortcut("Off")])
    }

    func testTurningItOffMidPhaseLeavesNothingToPauseAtTheBreak() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        XCTAssertEqual(session.choosePlaylist(in: picking("")), [.pausePlaylist(.spotify)])
        XCTAssertEqual(go(&session, .interrupted), [.stopSound, .runShortcut("Off")])
    }

    func testPickingThePlaylistPausedAtTheBreakResumesIt() {
        var session = FocusSession()
        _ = go(&session, .focusing)
        session.observe(.playing, of: .spotify)
        _ = go(&session, .interrupted)
        XCTAssertEqual(session.choosePlaylist(in: full), [.resumePlaylist(.spotify)])
    }

    func testPausingAPickOutsideFocusHandsItBack() {
        var session = FocusSession()
        _ = session.choosePlaylist(in: full)
        session.observe(.playing, of: .spotify)
        session.observe(.paused, of: .spotify)
        XCTAssertEqual(session.choosePlaylist(in: picking("")), [], "theirs again: nothing of ours to pause")
        _ = session.choosePlaylist(in: full)
        session.observe(.playing, of: .spotify)
        session.observe(.paused, of: .spotify)
        XCTAssertTrue(go(&session, .focusing).contains(.playPlaylist(spotify)), "the next phase starts it fresh")
    }
}

private extension FocusSettings {
    /// Only the playlist: no sound and no shortcuts, so a phase's actions are the playlist's alone.
    var withoutSound: FocusSettings {
        FocusSettings(playlistText: playlistText)
    }
}
