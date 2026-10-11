import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// `FocusController` is the one focus mode Today, Focus and Study drive.
/// These tests run a live controller with its settings in a private
/// `UserDefaults` suite and no sound, playlist or shortcut set, so a focus
/// phase starts and ends without touching audio, music apps or Shortcuts.
@MainActor
final class FocusControllerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    /// Stands in for Spotify and Music, so no test ever scripts a real app.
    private var apps: FakeMusicApps!

    override func setUp() async throws {
        suiteName = "FocusControllerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        apps = FakeMusicApps()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Settings

    func testAFreshInstallStartsQuietAndWritesNothing() {
        let focus = liveController()
        XCTAssertEqual(focus.settings, .default)
        XCTAssertTrue(focus.settings.mix.isOff, "updating never makes a focus session louder")
        XCTAssertFalse(focus.doNotDisturb)
        XCTAssertFalse(focus.isFocusing)
        XCTAssertFalse(focus.isPreviewing)
        XCTAssertNil(savedSettings(), "nothing is saved until the user changes something")
    }

    func testAChangeIsSavedAndReadBackOnTheNextLaunch() {
        let focus = liveController()
        focus.settings.volume = 0.3
        focus.settings.playlistText = "https://open.spotify.com/playlist/0vvXsWCC9xrXsKd4FyS8kM"
        XCTAssertEqual(savedSettings()?.volume, 0.3)

        let relaunched = liveController()
        XCTAssertEqual(relaunched.settings, focus.settings)
        XCTAssertEqual(relaunched.settings.playlist?.source, .spotify)
    }

    func testSettingTheSameValueWritesNothing() {
        let focus = liveController()
        focus.settings = focus.settings
        focus.settings.volume = FocusSettings.default.volume
        XCTAssertNil(savedSettings())
    }

    func testAnUnreadableSaveFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "focus.settings")
        XCTAssertEqual(liveController().settings, .default)
    }

    // MARK: - Following the timers

    func testAFocusPhaseTurnsFocusModeOnAndABreakOrResetTurnsItOff() async throws {
        let focus = liveController()
        focus.activityChanged(.focusing, from: .focusTimer)
        try await waitUntil("focusing") { focus.isFocusing }

        focus.activityChanged(.interrupted, from: .focusTimer)
        try await waitUntil("on a break") { !focus.isFocusing }

        focus.activityChanged(.focusing, from: .focusTimer)
        try await waitUntil("focusing again") { focus.isFocusing }
        focus.activityChanged(.idle, from: .focusTimer)
        try await waitUntil("reset") { !focus.isFocusing }
    }

    func testFocusModeStaysOnWhileAnyTimerIsFocusing() async throws {
        let focus = liveController()
        focus.activityChanged(.focusing, from: .focusTimer)
        focus.activityChanged(.focusing, from: .study)
        try await waitUntil("focusing") { focus.isFocusing }

        // The Pomodoro's break does not end Study's deep focus block.
        focus.activityChanged(.interrupted, from: .focusTimer)
        try await settle()
        XCTAssertTrue(focus.isFocusing)

        focus.activityChanged(.idle, from: .study)
        try await waitUntil("both stopped focusing") { !focus.isFocusing }
    }

    func testTransitionsLandInTheOrderTheyWereAskedFor() async throws {
        let focus = liveController()
        for _ in 0..<5 {
            focus.activityChanged(.focusing, from: .focusTimer)
            focus.activityChanged(.interrupted, from: .focusTimer)
        }
        focus.activityChanged(.focusing, from: .focusTimer)
        try await settle()
        XCTAssertTrue(focus.isFocusing, "the last request wins, never an earlier one landing late")
    }

    // MARK: - Do Not Disturb

    func testCelebrationsStayQuietOnlyWhileAFocusPhaseHoldsDoNotDisturb() async throws {
        let focus = liveController(settings: FocusSettings(doNotDisturb: true, onShortcut: "", offShortcut: ""))
        XCTAssertTrue(focus.doNotDisturb)
        XCTAssertFalse(focus.holdsDoNotDisturb, "not focusing yet")

        focus.activityChanged(.focusing, from: .focusTimer)
        try await waitUntil("focusing") { focus.isFocusing }
        XCTAssertTrue(focus.holdsDoNotDisturb)

        focus.activityChanged(.interrupted, from: .focusTimer)
        try await waitUntil("on a break") { !focus.isFocusing }
        XCTAssertFalse(focus.holdsDoNotDisturb)
    }

    func testABuildWithoutDoNotDisturbIgnoresTheSavedSwitch() async throws {
        // A sandboxed build reads the same preferences as a direct one, so
        // the switch can be on from a direct build it can never apply.
        let focus = liveController(settings: FocusSettings(doNotDisturb: true, onShortcut: "", offShortcut: ""),
                                   offersDoNotDisturb: false)
        XCTAssertFalse(focus.doNotDisturb)

        focus.activityChanged(.focusing, from: .focusTimer)
        try await waitUntil("focusing") { focus.isFocusing }
        XCTAssertFalse(focus.holdsDoNotDisturb, "celebrations play, since Do Not Disturb was never turned on")
    }

    // MARK: - Preview

    func testPreviewPlaysOnlyOutsideAFocusPhase() async throws {
        let focus = liveController()
        focus.setPreviewing(true)
        XCTAssertTrue(focus.isPreviewing)
        focus.setPreviewing(false)
        XCTAssertFalse(focus.isPreviewing)

        focus.activityChanged(.focusing, from: .focusTimer)
        try await waitUntil("focusing") { focus.isFocusing }
        focus.setPreviewing(true)
        XCTAssertFalse(focus.isPreviewing, "the sound is already playing while focusing")
    }

    // MARK: - Picking a playlist

    private let lofi = FocusPlaylistPreset.all[0]
    private let deepFocus = FocusPlaylistPreset.all[2]

    func testPickingAPlaylistPlaysItRightAwayAndSavesIt() async throws {
        let focus = liveController()
        focus.choosePlaylist(lofi.link)
        XCTAssertEqual(focus.settings.playlistText, lofi.link)
        XCTAssertEqual(savedSettings()?.playlistText, lofi.link, "kept for every focus block")
        try await waitUntil("the play script ran") { !apps.calls.isEmpty }
        let call = try XCTUnwrap(apps.calls.first)
        XCTAssertEqual(call.script, FocusPlaylistScript.play(try XCTUnwrap(lofi.playlist)))
        XCTAssertEqual(call.source, .spotify)
        XCTAssertTrue(call.launching, "a pick may open Spotify, since the click asked for it")
        XCTAssertNil(focus.playlistIssue)
    }

    func testPickingMidPhasePlaysNowAndTurningItOffPausesIt() async throws {
        let focus = liveController()
        focus.activityChanged(.focusing, from: .study)
        try await waitUntil("focusing") { focus.isFocusing }
        focus.choosePlaylist(deepFocus.link)
        try await waitUntil("playing") { apps.calls.count == 1 }

        focus.choosePlaylist("")
        try await waitUntil("paused") { apps.calls.count == 2 }
        XCTAssertEqual(apps.calls.last?.script, FocusPlaylistScript.pause(.spotify))
        XCTAssertEqual(focus.settings.playlistText, "")
    }

    func testAPlaylistWithoutAutomationAccessSaysSoUntilTheNextPick() async throws {
        let focus = liveController()
        apps.result = .failed(code: -1743)
        focus.choosePlaylist(lofi.link)
        try await waitUntil("the issue shows") { focus.playlistIssue != nil }
        XCTAssertEqual(focus.playlistIssue, .permissionDenied(.spotify))

        apps.result = .output("")
        focus.choosePlaylist(deepFocus.link)
        XCTAssertNil(focus.playlistIssue, "a new pick clears it")
        try await waitUntil("played") { apps.calls.count == 2 }
        try await settle()
        XCTAssertNil(focus.playlistIssue)
    }

    func testAMissingAppIsReportedWithoutScriptingIt() async throws {
        let focus = liveController()
        apps.installed = [.music]
        focus.choosePlaylist(lofi.link)
        try await waitUntil("the issue shows") { focus.playlistIssue != nil }
        XCTAssertEqual(focus.playlistIssue, .notInstalled(.spotify))
        XCTAssertTrue(apps.calls.isEmpty, "never sends an Apple Event to an app that isn't there")
        focus.dismissPlaylistIssue()
        XCTAssertNil(focus.playlistIssue)
    }

    func testTypingALinkInSettingsPlaysNothing() async throws {
        let focus = liveController()
        focus.settings.playlistText = lofi.link
        try await settle()
        XCTAssertTrue(apps.calls.isEmpty, "only a pick in the mixer plays right away")
    }

    // MARK: - Demo and snapshot runs

    func testDemoAndSnapshotRunsShowSamplesAndNeverSaveOrFocus() async throws {
        for runMode in [RunMode.demo, RunMode(isDemo: false, isSnapshot: true)] {
            let focus = FocusController(runMode: runMode, repository: FocusSettingsRepository(defaults: defaults),
                                        musicApps: apps.value)
            XCTAssertFalse(focus.settings.mix.isOff, "sample settings show a sound")
            XCTAssertNotNil(focus.settings.playlist)

            focus.settings.volume = 0.1
            focus.choosePlaylist(FocusPlaylistPreset.all[1].link)
            XCTAssertEqual(focus.settings.playlistText, FocusPlaylistPreset.all[1].link, "the pick still shows")
            focus.activityChanged(.focusing, from: .focusTimer)
            focus.setPreviewing(true)
            let result = await focus.testShortcut("Some Shortcut That Does Not Exist")
            try await settle()

            XCTAssertNil(savedSettings())
            XCTAssertFalse(focus.isFocusing)
            XCTAssertFalse(focus.isPreviewing)
            XCTAssertTrue(result.succeeded, "the Test button pretends, running no shortcut")
            XCTAssertTrue(apps.calls.isEmpty, "and no music app is scripted")
        }
    }

    // MARK: - Helpers

    private func liveController(settings: FocusSettings? = nil, offersDoNotDisturb: Bool = true) -> FocusController {
        let repository = FocusSettingsRepository(defaults: defaults)
        if let settings { repository.save(settings) }
        return FocusController(runMode: RunMode(isDemo: false, isSnapshot: false),
                               offersDoNotDisturb: offersDoNotDisturb, repository: repository,
                               musicApps: apps.value)
    }

    private func savedSettings() -> FocusSettings? {
        defaults.data(forKey: "focus.settings").flatMap { try? JSONDecoder().decode(FocusSettings.self, from: $0) }
    }

    private func waitUntil(_ message: String, timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("Timed out waiting: \(message)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Lets queued transitions run, for checks that something did not change.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }
}

/// A fake Spotify and Music: records each script and answers with `result`.
/// Neither app ever reads as running, so phases never wait on a player state.
private final class FakeMusicApps: @unchecked Sendable {
    struct Call: Equatable {
        let script: String
        let source: MediaSource
        let launching: Bool
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var answer: FocusScriptResult = .output("")
    private var present: Set<MediaSource> = Set(MediaSource.allCases)

    var calls: [Call] { lock.withLock { recorded } }
    var result: FocusScriptResult {
        get { lock.withLock { answer } }
        set { lock.withLock { answer = newValue } }
    }
    var installed: Set<MediaSource> {
        get { lock.withLock { present } }
        set { lock.withLock { present = newValue } }
    }

    var value: FocusMusicApps {
        FocusMusicApps(
            isInstalled: { [unowned self] in installed.contains($0) },
            isRunning: { _ in false },
            run: { [unowned self] script, source, launching in
                lock.withLock {
                    recorded.append(Call(script: script, source: source, launching: launching))
                    return answer
                }
            }
        )
    }
}
