import XCTest

/// Drives the app the way a person would for the end-to-end check in
/// ios/README.md: pick the Timer, set it to one minute, start it, lock
/// the phone, look at the Dynamic Island, and wait for the minute to run out.
///
/// When `TABBI_E2E_DIR` is set (pass `TEST_RUNNER_TABBI_E2E_DIR` to
/// xcodebuild), the test pauses at each moment worth a screenshot: it
/// writes `<step>.ready` into that folder and waits for `<step>.done`, so
/// ios/e2e.sh can take the shot with `xcrun simctl io booted
/// screenshot`. Without it, the test just runs through.
@MainActor
final class FoundationFlowTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-TabbiResetState"]
    }

    func testOneMinuteTimerRunsOnTheLockScreen() throws {
        app.launch()

        // A fresh install starts on the Pomodoro.
        let start = app.buttons["Start focus"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        checkpoint("01-app-idle")

        // Pick the Timer and step it down to one minute.
        app.buttons["Pomodoro"].tap()
        let timerRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Timer'")).firstMatch
        // The Timer is last in the half-height sheet; scroll down to it.
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<4 where !timerRow.isHittable { list.swipeUp() }
        XCTAssertTrue(timerRow.isHittable)
        timerRow.tap()
        let shorter = app.buttons["A shorter timer"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5))
        while shorter.isEnabled { shorter.tap() }
        XCTAssertTrue(app.staticTexts["1 min"].exists)
        checkpoint("02-app-timer-one-minute")

        app.buttons["Start timer"].tap()
        let startedAt = Date()
        allowNotificationsIfAsked()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        sleep(2)
        checkpoint("03-app-running")

        // Lock, then wake to the Lock Screen and its Live Activity. The
        // first activity asks whether to allow Live Activities from Tabbi.
        XCUIDevice.shared.press(.home)
        sleep(1)
        lock()
        wake()
        let allowActivities = springboard.buttons["Allow"]
        if allowActivities.waitForExistence(timeout: 3) { allowActivities.tap() }
        sleep(1)
        checkpoint("04-lock-screen-live-activity")

        // Unlocked, the Home Screen shows the countdown in the Dynamic Island.
        unlock()
        sleep(2)
        checkpoint("05-dynamic-island-compact")
        // Touch and hold the island for its expanded view.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        sleep(1)
        checkpoint("06-dynamic-island-expanded")
        XCUIDevice.shared.press(.home)
        sleep(1)

        // The minute runs out while locked: the notification arrives and
        // the Live Activity says the timer is done.
        lock()
        let left = 62 - Date().timeIntervalSince(startedAt)
        if left > 0 { usleep(useconds_t(left * 1_000_000)) }
        wake()
        sleep(2)
        checkpoint("07-lock-screen-phase-ended")
    }

    private func lock() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(1)
    }

    /// Lights the Lock Screen without unlocking.
    private func wake() {
        XCUIDevice.shared.press(.home)
        sleep(2)
    }

    /// The simulator has no passcode, so a swipe up from the bottom unlocks.
    private func unlock() {
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        bottom.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(1)
    }

    /// Taps Allow on the notification permission alert, which shows the
    /// first time a session starts.
    private func allowNotificationsIfAsked() {
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// Lets the host script screenshot this moment (see the type's comment).
    private func checkpoint(_ step: String) {
        guard let folder = ProcessInfo.processInfo.environment["TABBI_E2E_DIR"], !folder.isEmpty else { return }
        let base = URL(fileURLWithPath: folder)
        FileManager.default.createFile(atPath: base.appendingPathComponent("\(step).ready").path, contents: nil)
        let done = base.appendingPathComponent("\(step).done").path
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: done), Date() < deadline {
            usleep(200_000)
        }
    }
}
