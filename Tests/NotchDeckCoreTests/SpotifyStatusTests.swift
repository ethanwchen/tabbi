import XCTest
@testable import NotchDeckCore

final class SpotifyStatusTests: XCTestCase {
    private let playingOutput = [
        "playing", "spotify:track:abc", "Midnight City", "M83", "Hurry Up, We're Dreaming",
        "", "243960", "87.25", "false", "false",
    ].joined(separator: String(SpotifyScript.fieldSeparator))

    private func resolve(running: Bool = true, installed: Bool = true,
                         read: Result<String, SpotifyScriptError>?,
                         previous: SpotifyStatus = .connecting) -> SpotifyStatus {
        SpotifyStatus.resolve(isRunning: running, isInstalled: installed, read: read, previous: previous)
    }

    func testNotRunningNeverReadsAndDistinguishesNotInstalled() {
        XCTAssertEqual(resolve(running: false, read: nil, previous: .connected(.demo)), .notRunning)
        XCTAssertEqual(resolve(running: false, installed: false, read: nil), .notInstalled)
        // Even a late successful read loses to "the process is gone".
        XCTAssertEqual(resolve(running: false, read: .success(playingOutput)), .notRunning)
    }

    func testRunningWithoutReadIsConnectingUntilFirstResult() {
        XCTAssertEqual(resolve(read: nil, previous: .notRunning), .connecting)
        XCTAssertEqual(resolve(read: nil, previous: .connected(.demo)), .connected(.demo))
        XCTAssertEqual(resolve(read: nil, previous: .permissionDenied), .permissionDenied)
    }

    func testSuccessfulReadConnects() {
        let status = resolve(read: .success(playingOutput))
        XCTAssertTrue(status.isPlaying)
        XCTAssertEqual(status.playback?.track?.title, "Midnight City")
        XCTAssertEqual(resolve(read: .success("stopped")), .connected(.nothingPlaying))
        XCTAssertFalse(SpotifyStatus.connected(.nothingPlaying).isPlaying)
    }

    func testPermissionDenied() {
        let status = resolve(read: .failure(SpotifyScriptError(code: -1743)), previous: .connected(.demo))
        XCTAssertEqual(status, .permissionDenied)
        XCTAssertNil(status.playback)
        XCTAssertFalse(status.isPlaying)
    }

    func testSpotifyQuittingMidReadIsNotRunning() {
        XCTAssertEqual(resolve(read: .failure(.notRunning)), .notRunning)
    }

    func testInconclusiveReadsKeepThePreviousPlayback() {
        XCTAssertEqual(resolve(read: .success("garbage"), previous: .connected(.demo)), .connected(.demo))
        XCTAssertEqual(resolve(read: .failure(.other(code: -1728)), previous: .connected(.demo)),
                       .connected(.demo))
        // Fresh launch with nothing loaded: Spotify errors on `current track`.
        XCTAssertEqual(resolve(read: .failure(.other(code: -1728))), .connected(.nothingPlaying))
    }

    func testTogglingPlayPause() {
        XCTAssertEqual(SpotifyPlayback.demo.togglingPlayPause().state, .paused)
        XCTAssertEqual(SpotifyPlayback.demo.togglingPlayPause().togglingPlayPause(), .demo)
        XCTAssertEqual(SpotifyPlayback.nothingPlaying.togglingPlayPause(), .nothingPlaying)
    }

    func testSeekingClampsToTrack() {
        XCTAssertEqual(SpotifyPlayback.demo.seeking(to: 30).position, 30)
        XCTAssertEqual(SpotifyPlayback.demo.seeking(to: -5).position, 0)
        XCTAssertEqual(SpotifyPlayback.demo.seeking(to: 9_999).position, 243.96)
    }

    func testClockExtrapolatesOnlyWhilePlaying() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var clock = SpotifyPlaybackClock(anchor: .demo, at: start)
        XCTAssertEqual(clock.playback(at: start.addingTimeInterval(3)).position, 90.4, accuracy: 0.0001)
        XCTAssertEqual(clock.playback(at: start.addingTimeInterval(10_000)).position, 243.96)
        // A clock running behind the anchor (e.g. system clock change) doesn't rewind.
        XCTAssertEqual(clock.playback(at: start.addingTimeInterval(-5)).position, 87.4, accuracy: 0.0001)

        clock.sync(SpotifyPlayback.demo.togglingPlayPause(), at: start)
        XCTAssertEqual(clock.playback(at: start.addingTimeInterval(3)).position, 87.4, accuracy: 0.0001)
    }
}
