import XCTest
import NotchKitCore

final class FocusPlaylistTests: XCTestCase {
    func testSpotifyLinksAndURIsNormalizeToURIs() {
        let expected = FocusPlaylist.spotify(uri: "spotify:playlist:37i9dQZF1DWZeKCadgRdKQ")
        XCTAssertEqual(FocusPlaylist("spotify:playlist:37i9dQZF1DWZeKCadgRdKQ"), expected)
        XCTAssertEqual(FocusPlaylist("  https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ?si=abc123 \n"), expected)
        XCTAssertEqual(FocusPlaylist("https://open.spotify.com/intl-de/playlist/37i9dQZF1DWZeKCadgRdKQ"), expected)
        XCTAssertEqual(FocusPlaylist("spotify:user:someone:playlist:37i9dQZF1DWZeKCadgRdKQ"), expected)
        XCTAssertEqual(FocusPlaylist("https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy"),
                       .spotify(uri: "spotify:album:4aawyAB9vmqN3uQ7FjRGTy"))
        XCTAssertEqual(expected.source, .spotify)
    }

    func testMalformedSpotifyReferencesAreRejectedNotTreatedAsNames() {
        XCTAssertNil(FocusPlaylist("spotify:playlist:"))
        XCTAssertNil(FocusPlaylist("spotify:podcast:abc"))
        XCTAssertNil(FocusPlaylist("https://open.spotify.com/"))
        XCTAssertNil(FocusPlaylist("https://open.spotify.com/playlist/bad-id!"))
    }

    func testAppleMusicLinksAndLibraryNames() {
        let link = "https://music.apple.com/us/playlist/pure-focus/pl.abc123"
        XCTAssertEqual(FocusPlaylist(link), .appleMusicLink(URL(string: link)!))
        XCTAssertEqual(FocusPlaylist(" Deep Work "), .musicLibrary(name: "Deep Work"))
        XCTAssertEqual(FocusPlaylist("Chill"), .musicLibrary(name: "Chill"))
        XCTAssertEqual(FocusPlaylist("Chill")?.source, .music)
    }

    func testBlankAndUnsupportedLinksYieldNothing() {
        XCTAssertNil(FocusPlaylist(""))
        XCTAssertNil(FocusPlaylist("   \n"))
        XCTAssertNil(FocusPlaylist("https://www.youtube.com/watch?v=jfKfPfyJRdk"))
    }
}

final class FocusSettingsTests: XCTestCase {
    func testDefaultsAreOptIn() {
        let settings = FocusSettings.default
        XCTAssertTrue(settings.mix.isOff)
        XCTAssertNil(settings.playlist)
        XCTAssertFalse(settings.doNotDisturb)
        XCTAssertNil(settings.activeOnShortcut)
        XCTAssertFalse(settings.hasEffect)
        XCTAssertEqual(settings.onShortcut, "NotchDeck Focus On")
        XCTAssertEqual(settings.offShortcut, "NotchDeck Focus Off")
    }

    func testShortcutsOnlyRunWhenDoNotDisturbIsOnAndNamed() {
        var settings = FocusSettings(onShortcut: "  Focus On ", offShortcut: "")
        XCTAssertNil(settings.activeOnShortcut)
        settings.doNotDisturb = true
        XCTAssertEqual(settings.activeOnShortcut, "Focus On")
        XCTAssertNil(settings.activeOffShortcut)
        XCTAssertTrue(settings.hasEffect)
    }

    func testVolumeIsClamped() {
        var settings = FocusSettings(volume: 3)
        XCTAssertEqual(settings.volume, 1)
        settings.volume = -1
        XCTAssertEqual(settings.volume, 0)
        settings.volume = .nan
        XCTAssertEqual(settings.volume, FocusSettings.default.volume)
    }

    func testRepositoryRoundTripsEveryField() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FocusSettingsTests.roundTrip"))
        defaults.removePersistentDomain(forName: "FocusSettingsTests.roundTrip")
        let repository = FocusSettingsRepository(defaults: defaults)
        XCTAssertEqual(repository.load(), .default)

        let settings = FocusSettings(
            mix: FocusMix([.init(sound: .rain), .init(sound: .fireplace, level: 0.4)]),
            volume: 0.7,
            playlistText: "https://open.spotify.com/playlist/37i9dQZF1DWZeKCadgRdKQ",
            doNotDisturb: true,
            onShortcut: "Work On",
            offShortcut: "Work Off"
        )
        repository.save(settings)
        XCTAssertEqual(FocusSettingsRepository(defaults: defaults).load(), settings)
    }

    func testDecodingFallsBackPerField() throws {
        let json = #"{"volume": "loud", "doNotDisturb": true, "mix": {"layers": [{"sound": "unknown", "level": 1}]}}"#
        let settings = try JSONDecoder().decode(FocusSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.volume, FocusSettings.default.volume)
        XCTAssertTrue(settings.doNotDisturb)
        XCTAssertTrue(settings.mix.isOff)
        XCTAssertEqual(settings.onShortcut, FocusSettings.suggestedOnShortcut)
    }
}

final class FocusShortcutRunnerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FocusShortcutRunnerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stand-in for `/usr/bin/shortcuts` that runs `body` as a shell script.
    private func fakeShortcuts(_ body: String) throws -> URL {
        let url = directory.appendingPathComponent("shortcuts-\(UUID().uuidString)")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testPassesTheNameAndReportsSuccess() async throws {
        let log = directory.appendingPathComponent("args")
        let runner = FocusShortcutRunner(executable: try fakeShortcuts(#"printf '%s|' "$@" > "\#(log.path)""#))
        let result = await runner.run("  NotchDeck Focus On ")
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(try String(contentsOf: log, encoding: .utf8), "run|NotchDeck Focus On|")
    }

    func testMissingShortcutIsReportedAsNotFound() async throws {
        let script = #"echo "Error: The operation couldn’t be completed. Couldn’t find shortcut" >&2; exit 1"#
        let runner = FocusShortcutRunner(executable: try fakeShortcuts(script))
        let result = await runner.run("Nope")
        XCTAssertEqual(result, .notFound(name: "Nope"))
        XCTAssertTrue(result.message.contains("Nope"))
    }

    func testOtherFailuresCarryTheToolsMessage() async throws {
        let runner = FocusShortcutRunner(executable: try fakeShortcuts(#"echo "Error: Focus is not allowed" >&2; exit 1"#))
        let result = await runner.run("Focus")
        XCTAssertEqual(result, .failed(message: "Focus is not allowed"))
        XCTAssertEqual(result.message, "Focus is not allowed")
    }

    func testSlowShortcutTimesOutAndIsStopped() async throws {
        let marker = directory.appendingPathComponent("finished")
        let runner = FocusShortcutRunner(
            executable: try fakeShortcuts("sleep 5; touch \"\(marker.path)\""),
            timeout: .milliseconds(200)
        )
        let start = Date()
        let result = await runner.run("Slow")
        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testMissingToolAndBlankNameNeverLaunchAnything() async {
        let missing = FocusShortcutRunner(executable: directory.appendingPathComponent("no-such-tool"))
        let unavailable = await missing.run("Focus")
        XCTAssertEqual(unavailable, .unavailable)
        let blank = await FocusShortcutRunner().run("   ")
        XCTAssertEqual(blank, .notFound(name: ""))
    }

    /// Exercises the real `shortcuts` tool with a name nobody has, which must
    /// fail gracefully rather than hang or crash.
    func testRealShortcutsToolReportsAMissingShortcut() async throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: FocusShortcutRunner.systemExecutable.path))
        let name = "NotchDeck Test Missing \(UUID().uuidString)"
        let result = await FocusShortcutRunner().run(name)
        XCTAssertEqual(result, .notFound(name: name))
    }
}
