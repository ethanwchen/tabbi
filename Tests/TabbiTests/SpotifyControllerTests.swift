import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// Drives the Now Playing controller against scripted players at a fake
/// clock: which app it follows, optimistic commands and the stale reads
/// that must not undo them, the volume drag that coalesces Apple Events,
/// quits, permission errors, SoundCloud's opt-in and demo mode. No real
/// Spotify, Music, browser or Apple Event is touched.
@MainActor
final class SpotifyControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var controllers: [SpotifyController] = []

    override func setUp() async throws {
        suiteName = "SpotifyControllerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        for controller in controllers { controller.setPanelVisible(false) }
        controllers = []
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeController(_ players: FakePlayers, runMode: RunMode = .live,
                                allowsBrowsers: Bool = true) -> SpotifyController {
        let controller = SpotifyController(runMode: runMode, allowsBrowsers: allowsBrowsers,
                                           host: players.host, defaults: defaults)
        controllers.append(controller)
        return controller
    }

    // MARK: - Following players

    func testWithNoPlayerRunningNothingIsScripted() async throws {
        let players = FakePlayers()
        let controller = makeController(players)
        controller.setPanelVisible(true)

        XCTAssertEqual(controller.status, .notRunning)
        XCTAssertNil(controller.source)
        XCTAssertEqual(controller.installedSources, [.spotify, .music])
        XCTAssertFalse(controller.showsCompactActivity)
        XCTAssertNil(controller.pollTimerInterval, "nothing runs, so nothing is polled")
        await settle()
        XCTAssertTrue(players.log.isEmpty, "an Apple Event to a quit app would launch it")

        let bare = FakePlayers()
        bare.installed = []
        let empty = makeController(bare)
        XCTAssertEqual(empty.status, .notInstalled)
        XCTAssertEqual(empty.installedSources, [])
    }

    func testARunningSpotifyIsReadAndFollowed() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead(position: 30, volume: 60))
        let controller = makeController(players)

        XCTAssertEqual(controller.status, .connecting, "shown at once, before the first read answers")
        try await waitUntil { controller.status.playback != nil }
        let playback = try XCTUnwrap(controller.status.playback)
        XCTAssertEqual(controller.source, .spotify)
        XCTAssertEqual(playback.track?.title, "Teardrop")
        XCTAssertEqual(playback.position, 30)
        XCTAssertEqual(playback.volume, 60)
        XCTAssertTrue(controller.showsCompactActivity)
        XCTAssertEqual(players.reads(of: .music), 0, "Music isn't running, so it is never scripted")
    }

    func testTheAppThatStartedPlayingLastIsFollowed() async throws {
        let players = FakePlayers()
        players.running = [.spotify, .music]
        players.reads[.spotify] = .success(spotifyRead(state: "paused"))
        players.reads[.music] = .success(musicRead())
        let controller = makeController(players)
        try await waitUntil { players.completed == 2 }
        await settle()
        XCTAssertEqual(controller.source, .music)

        players.now += 60
        players.reads[.spotify] = .success(spotifyRead())
        controller.playbackStateChanged(Notification(name: Notification.Name("com.spotify.client.PlaybackStateChanged")))
        try await waitUntil { controller.source == .spotify }
        XCTAssertTrue(controller.status.isPlaying)
    }

    func testAQuitPlayerIsReleasedAtOnce() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead())
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }

        players.running = []
        controller.applicationChanged(bundleIdentifier: SpotifyScript.bundleIdentifier, terminated: true)
        XCTAssertEqual(controller.status, .notRunning)
        XCTAssertNil(controller.source)
        XCTAssertFalse(controller.showsCompactActivity, "the closed notch's music wings go away")

        // Launching it again reads it at once.
        players.running = [.spotify]
        controller.applicationChanged(bundleIdentifier: SpotifyScript.bundleIdentifier, terminated: false)
        XCTAssertEqual(controller.status, .connecting)
        try await waitUntil { controller.status.isPlaying }
    }

    func testAnUnreadableReplyKeepsTheLastTrack() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead())
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }

        for reply: Result<String, SpotifyScriptError> in [.success("playing\u{1F}half a record"),
                                                        .failure(.other(code: -1728))] {
            players.reads[.spotify] = reply
            let before = players.completed
            controller.refresh()
            try await waitUntil { players.completed == before + 1 }
            await settle()
            XCTAssertEqual(controller.status.playback?.track?.title, "Teardrop", "\(reply)")
        }
    }

    func testDeniedAutomationShowsThePermissionState() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .failure(.permissionDenied)
        let controller = makeController(players)
        try await waitUntil { controller.status == .permissionDenied }
        XCTAssertEqual(controller.source, .spotify, "the panel shows how to allow it")

        players.reads[.spotify] = .success(spotifyRead(volume: 60))
        controller.refresh()
        try await waitUntil { controller.status.isPlaying }

        // A denied command needs no read to show it.
        players.commandResult = .failure(.permissionDenied)
        let reads = players.reads(of: .spotify)
        controller.setVolume(20)
        try await waitUntil { controller.status == .permissionDenied }
        await settle()
        XCTAssertEqual(players.reads(of: .spotify), reads)
    }

    // MARK: - Commands

    func testPositionAdvancesWithTheClockBetweenReads() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead(position: 30))
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }

        players.now += 10
        players.holdsScripts = true
        controller.playPause()
        let paused = try XCTUnwrap(controller.status.playback)
        XCTAssertEqual(paused.state, .paused, "the button flips before Spotify answers")
        XCTAssertEqual(paused.position, 40, accuracy: 0.001, "the position ran on with the clock")
        XCTAssertFalse(controller.showsCompactActivity)
        players.holdsScripts = false
        players.releaseAll()
    }

    func testAStaleReadNeverUndoesAPlayPause() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead())
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }

        // A read leaves before the click and answers after it, still playing.
        players.holdsScripts = true
        controller.refresh()
        try await waitUntil { players.heldCount == 1 }
        controller.playPause()
        try await waitUntil { players.heldCount == 2 }
        players.release(first: 1)
        try await waitUntil { players.completed == 2 }
        await settle()
        XCTAssertEqual(controller.status.playback?.state, .paused, "the late read is dropped")

        // Spotify confirms the pause on the read after the command.
        players.reads[.spotify] = .success(spotifyRead(state: "paused"))
        players.holdsScripts = false
        players.releaseAll()
        try await waitUntil { players.completed == 4 }
        await settle()
        XCTAssertEqual(controller.status.playback?.state, .paused)
        XCTAssertEqual(players.commands, [SpotifyScript.playPause])
    }

    func testSeekIsClampedToTheTrack() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead(position: 30))
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }
        players.holdsScripts = true

        controller.seek(to: 999)
        XCTAssertEqual(controller.status.playback?.position, 200)
        controller.seek(to: -5)
        XCTAssertEqual(controller.status.playback?.position, 0)
        try await waitUntil { players.heldCount == 2 }
        XCTAssertEqual(players.commands, [SpotifyScript.seek(to: 200), SpotifyScript.seek(to: 0)])
        players.holdsScripts = false
        players.releaseAll()
    }

    func testAVolumeDragSendsOnlyTheFirstAndLatestValue() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead(volume: 60))
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }

        players.holdsScripts = true
        for volume in [10, 20, 30, 130] { controller.setVolume(volume) }
        XCTAssertEqual(controller.status.playback?.volume, 100, "the slider follows at once, clamped")
        try await waitUntil { players.heldCount == 1 }
        XCTAssertEqual(players.commands, [MediaSource.spotify.setVolumeScript(10)])

        players.reads[.spotify] = .success(spotifyRead(volume: 100))
        players.holdsScripts = false
        players.releaseAll()
        try await waitUntil { players.reads(of: .spotify) == 2 }
        await settle()
        XCTAssertEqual(players.commands, [MediaSource.spotify.setVolumeScript(10),
                                          MediaSource.spotify.setVolumeScript(100)],
                       "values passed during a drag are never sent")
        XCTAssertEqual(controller.status.playback?.volume, 100)
    }

    func testMuteRestoresTheLevelItHad() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead(volume: 60))
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }
        players.holdsScripts = true

        controller.toggleMute()
        XCTAssertEqual(controller.status.playback?.volume, 0)
        controller.toggleMute()
        XCTAssertEqual(controller.status.playback?.volume, 60)
        players.holdsScripts = false
        players.releaseAll()
    }

    func testShuffleShowsTheClickUntilThePlayerSettles() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead())
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }

        // Spotify applies shuffle a moment after the command returns, so
        // the read right after it still says off.
        controller.toggleShuffle()
        XCTAssertEqual(controller.status.playback?.isShuffling, true)
        try await waitUntil { players.reads(of: .spotify) == 2 }
        await settle()
        XCTAssertEqual(controller.status.playback?.isShuffling, true, "an early read doesn't undo the click")
        XCTAssertEqual(players.commands, [MediaSource.spotify.setShuffleScript(true)])

        // Once the settle time has passed, the player's own state wins.
        players.now += PendingMediaModes.settleTime + 1
        try await waitUntil(timeout: 5) { players.reads(of: .spotify) == 3 }
        await settle()
        XCTAssertEqual(controller.status.playback?.isShuffling, false)
    }

    // MARK: - Polling and SoundCloud

    func testPollingRunsOnlyWhileThePanelShows() async throws {
        let players = FakePlayers()
        players.running = [.spotify]
        players.reads[.spotify] = .success(spotifyRead())
        let controller = makeController(players)
        try await waitUntil { controller.status.isPlaying }
        XCTAssertNil(controller.pollTimerInterval, "Spotify posts notifications, so a hidden panel never polls")

        controller.setPanelVisible(true)
        XCTAssertEqual(controller.pollTimerInterval, 5)
        try await waitUntil { players.reads(of: .spotify) == 2 }

        controller.setPanelVisible(false)
        XCTAssertNil(controller.pollTimerInterval)
    }

    func testSoundCloudIsReadOnlyOnceTurnedOn() async throws {
        let safari = NowPlayingSource.soundCloud(.safari)
        let players = FakePlayers()
        players.running = [safari]
        players.reads[safari] = .success("no-tab")
        let controller = makeController(players)
        await settle()
        XCTAssertEqual(players.reads(of: safari), 0, "reading Safari asks for Automation access")
        XCTAssertNil(controller.pollTimerInterval)

        controller.preferences.showsSoundCloud = true
        try await waitUntil { players.completed == 1 }
        XCTAssertTrue(NowPlayingPreferencesStorage(defaults: defaults).load().showsSoundCloud)
        XCTAssertNil(controller.source, "a browser without a SoundCloud tab is no player")
        XCTAssertEqual(controller.pollTimerInterval, 10, "browsers post no notifications, so the tab is polled")

        controller.preferences.showsSoundCloud = false
        XCTAssertNil(controller.pollTimerInterval)

        // The App Store edition never scripts browsers, whatever was saved.
        let storeBuild = FakePlayers()
        storeBuild.running = [safari]
        defaults.removePersistentDomain(forName: suiteName)
        NowPlayingPreferencesStorage(defaults: defaults).save(NowPlayingPreferences(showsSoundCloud: true))
        _ = makeController(storeBuild, allowsBrowsers: false)
        await settle()
        XCTAssertTrue(storeBuild.log.isEmpty)
    }

    // MARK: - Demo

    func testDemoNeverTouchesThePlayers() async throws {
        let players = FakePlayers()
        players.running = [.spotify, .music]
        let controller = makeController(players, runMode: .demo)
        controller.setPanelVisible(true)

        XCTAssertEqual(controller.source, .music)
        XCTAssertEqual(controller.status.playback?.track, SpotifyPlayback.demo.track)
        XCTAssertNil(controller.pollTimerInterval)

        controller.next()
        XCTAssertEqual(controller.status.playback?.position, 0, "the demo track starts over")
        controller.setVolume(10)
        controller.preferences.showsSoundCloud = true
        controller.refresh()
        let artwork = await controller.artworkData(for: try XCTUnwrap(SpotifyPlayback.demo.track))
        XCTAssertNil(artwork)
        await settle()

        XCTAssertTrue(players.log.isEmpty)
        XCTAssertEqual(players.runningChecks, 0)
        XCTAssertNil(defaults.data(forKey: NowPlayingPreferencesStorage.key), "demo settings stay in memory")
    }

    // MARK: - Helpers

    /// A Spotify `readState` record: a 200 s track, shuffle and repeat off.
    private func spotifyRead(state: String = "playing", position: Double = 30, volume: Int = 60) -> String {
        ["\(state)", "spotify:track:1", "Teardrop", "Massive Attack", "Mezzanine",
         "https://i.scdn.co/image/1", "200000", "\(position)", "false", "false", "\(volume)"]
            .joined(separator: String(SpotifyScript.fieldSeparator))
    }

    /// A Music `readState` record for a playing 180 s track.
    private func musicRead() -> String {
        ["playing", "5A1D3E0C7B92F416", "Midnight City", "M83", "Hurry Up, We're Dreaming",
         "180", "12", "false", "off", "40", "false"]
            .joined(separator: String(SpotifyScript.fieldSeparator))
    }

    /// Lets tasks the controller started run to their end.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(30))
        for _ in 0..<10 { await Task.yield() }
    }

    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("condition not met in \(timeout) s", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// Scripted Spotify, Music and browsers. Reads answer with `reads` as it is
/// when the script is let go, so a held read can turn stale; every other
/// script answers `commandResult`.
@MainActor
private final class FakePlayers {
    var running: Set<NowPlayingSource> = []
    var installed: Set<NowPlayingSource> = [.spotify, .music]
    var reads: [NowPlayingSource: Result<String, SpotifyScriptError>] = [:]
    var commandResult: Result<String, SpotifyScriptError> = .success("")
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// When true, each script waits until `release` lets it answer.
    var holdsScripts = false

    private(set) var log: [(script: String, source: NowPlayingSource)] = []
    private(set) var completed = 0
    private(set) var runningChecks = 0
    private var held: [CheckedContinuation<Void, Never>] = []

    var heldCount: Int { held.count }

    var commands: [String] {
        log.filter { $0.script != $0.source.readStateScript }.map(\.script)
    }

    func reads(of source: NowPlayingSource) -> Int {
        log.filter { $0.source == source && $0.script == source.readStateScript }.count
    }

    func release(first count: Int) {
        let released = held.prefix(count)
        held.removeFirst(released.count)
        for continuation in released { continuation.resume() }
    }

    func releaseAll() { release(first: held.count) }

    var host: MediaPlayerHost {
        MediaPlayerHost(
            isRunning: { source in
                self.runningChecks += 1
                return self.running.contains(source)
            },
            isInstalled: { self.installed.contains($0) },
            run: { script, source in await self.run(script, on: source) },
            runForData: { script, source in
                _ = await self.run(script, on: source)
                return nil
            },
            now: { self.now },
            observesSystem: false
        )
    }

    private func run(_ script: String, on source: NowPlayingSource) async -> Result<String, SpotifyScriptError> {
        log.append((script, source))
        if holdsScripts { await withCheckedContinuation { held.append($0) } }
        completed += 1
        guard running.contains(source) else { return .failure(.notRunning) }
        if script == source.readStateScript { return reads[source] ?? .failure(.other(code: -1728)) }
        return commandResult
    }
}
