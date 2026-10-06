import XCTest
@testable import TabbiKitCore

final class MediaModesTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 50_000)

    func testRepeatCyclesThroughEachAppsModes() {
        XCTAssertEqual(MediaSource.spotify.repeatMode(after: .off), .all)
        XCTAssertEqual(MediaSource.spotify.repeatMode(after: .all), .off)
        // Spotify can't repeat one track over scripting; a stray `one` resets.
        XCTAssertEqual(MediaSource.spotify.repeatMode(after: .one), .off)

        XCTAssertEqual(MediaSource.music.repeatMode(after: .off), .all)
        XCTAssertEqual(MediaSource.music.repeatMode(after: .all), .one)
        XCTAssertEqual(MediaSource.music.repeatMode(after: .one), .off)
    }

    func testSpotifyScripts() {
        XCTAssertEqual(MediaSource.spotify.setShuffleScript(true),
                       "tell application id \"com.spotify.client\" to set shuffling to true")
        XCTAssertEqual(MediaSource.spotify.setShuffleScript(false),
                       "tell application id \"com.spotify.client\" to set shuffling to false")
        XCTAssertEqual(MediaSource.spotify.setRepeatScript(.all),
                       "tell application id \"com.spotify.client\" to set repeating to true")
        XCTAssertEqual(MediaSource.spotify.setRepeatScript(.one),
                       "tell application id \"com.spotify.client\" to set repeating to true")
        XCTAssertEqual(MediaSource.spotify.setRepeatScript(.off),
                       "tell application id \"com.spotify.client\" to set repeating to false")
    }

    func testMusicScripts() {
        XCTAssertEqual(MediaSource.music.setShuffleScript(true),
                       "tell application id \"com.apple.Music\" to set shuffle enabled to true")
        XCTAssertEqual(MediaSource.music.setShuffleScript(false),
                       "tell application id \"com.apple.Music\" to set shuffle enabled to false")
        for mode in MediaRepeatMode.allCases {
            XCTAssertEqual(MediaSource.music.setRepeatScript(mode),
                           "tell application id \"com.apple.Music\" to set song repeat to \(mode.rawValue)")
        }
    }

    func testRepeatModeParsing() {
        XCTAssertEqual(MediaRepeatMode(scriptValue: "one\n"), .one)
        XCTAssertEqual(MediaRepeatMode(scriptValue: " all"), .all)
        XCTAssertEqual(MediaRepeatMode(scriptValue: "off"), .off)
        XCTAssertEqual(MediaRepeatMode(scriptValue: "missing value"), .off)
    }

    func testOptimisticModeChanges() {
        let playback = SpotifyPlayback.demo
        XCTAssertFalse(playback.settingShuffle(false).isShuffling)
        XCTAssertEqual(playback.settingRepeat(.one).repeatMode, .one)
        XCTAssertTrue(playback.settingRepeat(.one).isRepeating)
        XCTAssertEqual(playback.settingShuffle(false).track, playback.track)
    }

    func testPendingModesHoldOverStaleReadsUntilTheySettle() {
        let stale = SpotifyPlayback.demo.settingShuffle(false)
        let pending = PendingMediaModes(deadline: t0).adding(shuffle: true, at: t0)
        XCTAssertTrue(pending.applied(to: stale, at: t0 + 0.2).isShuffling)
        // The repeat mode wasn't requested, so the read's value stands.
        XCTAssertEqual(pending.applied(to: stale.settingRepeat(.all), at: t0 + 0.2).repeatMode, .all)
        // Past the deadline the player's answer wins, even if it refused.
        XCTAssertFalse(pending.applied(to: stale, at: t0 + PendingMediaModes.settleTime).isShuffling)
    }

    func testPendingModesCombineAndExpire() {
        let first = PendingMediaModes(deadline: t0).adding(shuffle: true, at: t0)
        let both = first.adding(repeatMode: .one, at: t0 + 1)
        XCTAssertEqual(both.shuffle, true)
        XCTAssertEqual(both.repeatMode, .one)
        XCTAssertEqual(both.deadline, t0 + 1 + PendingMediaModes.settleTime)

        // A request after the earlier one settled doesn't revive it.
        let later = first.adding(repeatMode: .all, at: t0 + 10)
        XCTAssertNil(later.shuffle)
        XCTAssertEqual(later.repeatMode, .all)
    }
}
