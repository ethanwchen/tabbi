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

    override func setUp() async throws {
        suiteName = "FocusControllerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
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

    // MARK: - Demo and snapshot runs

    func testDemoAndSnapshotRunsShowSamplesAndNeverSaveOrFocus() async throws {
        for runMode in [RunMode.demo, RunMode(isDemo: false, isSnapshot: true)] {
            let focus = FocusController(runMode: runMode, repository: FocusSettingsRepository(defaults: defaults))
            XCTAssertFalse(focus.settings.mix.isOff, "sample settings show a sound")
            XCTAssertNotNil(focus.settings.playlist)

            focus.settings.volume = 0.1
            focus.activityChanged(.focusing, from: .focusTimer)
            focus.setPreviewing(true)
            let result = await focus.testShortcut("Some Shortcut That Does Not Exist")
            try await settle()

            XCTAssertNil(savedSettings())
            XCTAssertFalse(focus.isFocusing)
            XCTAssertFalse(focus.isPreviewing)
            XCTAssertTrue(result.succeeded, "the Test button pretends, running no shortcut")
        }
    }

    // MARK: - Helpers

    private func liveController(settings: FocusSettings? = nil, offersDoNotDisturb: Bool = true) -> FocusController {
        let repository = FocusSettingsRepository(defaults: defaults)
        if let settings { repository.save(settings) }
        return FocusController(runMode: RunMode(isDemo: false, isSnapshot: false),
                               offersDoNotDisturb: offersDoNotDisturb, repository: repository)
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
