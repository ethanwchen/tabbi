import XCTest

/// Plays the Pet Cam like a person, with one-minute blocks
/// (`-PetCamQuickBlocks`, debug builds only): a catch, a miss, an early
/// stop, more blocks until a callback caption shows, the mugshot wall, a
/// replay and a video export, with the Lock Screen, the Dynamic Island and
/// the end notification along the way.
///
/// `-PetCamTestHooks` lets the test read where the pet will strike, so it
/// can play a sure catch and a sure miss. With `TABBI_E2E_DIR` set it pauses
/// at each checkpoint for ios/e2e.sh to take a screenshot (see
/// `FoundationFlowTests`); a checkpoint named `video-start-<name>` starts a
/// screen recording and `video-stop` ends it.
@MainActor
final class PetCamFlowTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// Every caption the tapes burned in, for the callback check.
    private var captions: [String] = []

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-TabbiResetState", "-TabbiDemoPet", "-PetCamQuickBlocks", "-PetCamTestHooks",
                               "-PetCamSeed", "00000000000051de"]
    }

    func testPlayingSeveralLoops() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Start focus"].waitForExistence(timeout: 10))
        checkpoint("01-home-frozen-frame")

        // The debug tuning panel hides behind a long press on the camera's name.
        app.descendants(matching: .any)["feed.burnIn"].firstMatch.press(forDuration: 1.2)
        if app.navigationBars["Pet Cam tuning"].waitForExistence(timeout: 3) {
            checkpoint("02-debug-tuning-panel")
            app.buttons["Done"].firstMatch.tap()
        }

        // One-minute Timer blocks.
        app.buttons["Pomodoro"].tap()
        let timerRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Timer'")).firstMatch
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<4 where !timerRow.isHittable { list.swipeUp() }
        timerRow.tap()
        let shorter = app.buttons["A shorter timer"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5))
        while shorter.isEnabled { shorter.tap() }
        XCTAssertTrue(app.staticTexts["1 min"].exists)

        // Loop 1: a catch. Hide the camera where the pet will strike and
        // say what is being avoided.
        hideCamera(catching: true)
        type(dodge: "my tax return")
        checkpoint("03-home-camera-hidden")
        app.buttons["Start timer"].tap()
        allowNotificationsIfAsked()
        XCTAssertTrue(app.staticTexts["Recording. The tape plays when the block is done."].waitForExistence(timeout: 5))
        checkpoint("04-recording")
        let started = Date()
        visitLockScreenAndIsland()
        // The minute runs out while locked: the end notification.
        lock()
        wait(untilSecondsSince: started, 63)
        wake()
        sleep(2)
        checkpoint("08-lock-screen-tape-ready")
        unlock()
        checkpoint("video-start-tape-catch")
        app.activate()
        watchTape(named: "catch", first: 9)

        checkpoint("20-home-after-catch")

        // Loop 2: a miss, in the app the whole time.
        hideCamera(catching: false)
        app.buttons["Start timer"].tap()
        let missStart = Date()
        XCTAssertTrue(app.staticTexts["Recording. The tape plays when the block is done."].waitForExistence(timeout: 5))
        wait(untilSecondsSince: missStart, 56)
        checkpoint("video-start-tape-miss")
        watchTape(named: "miss", first: 21)
        checkpoint("30-home-after-miss")

        // Loop 3: stopped early. One frozen still, no tape.
        app.buttons["Start timer"].tap()
        let stopStart = Date()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        wait(untilSecondsSince: stopStart, 15)
        app.buttons["Stop"].tap()
        let still = app.descendants(matching: .any)["tape.caption"].firstMatch
        XCTAssertTrue(still.waitForExistence(timeout: 5))
        XCTAssertTrue(still.label.contains("NO TAPE THIS TIME."), still.label)
        sleep(1)
        checkpoint("31-early-stop-still")
        // The still closes by itself after a few seconds.
        XCTAssertTrue(still.waitForNonExistence(timeout: 10))
        sleep(1)

        // Loops 4 and 5: keep catching until the history gives a callback.
        for (loop, step) in [(4, 40), (5, 60)] {
            hideCamera(catching: true)
            app.buttons["Start timer"].tap()
            let start = Date()
            XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
            wait(untilSecondsSince: start, 56)
            checkpoint("video-start-tape-catch-\(loop)")
            watchTape(named: "catch-\(loop)", first: step, share: loop == 5)
        }
        let callbacks = captions.filter {
            $0.contains(" TODAY") || $0.contains(" AGAIN") || $0.contains("RIGHT NEXT TO") || $0.contains("LAST CAUGHT")
        }
        print("Pet Cam UI test captions: \(captions)")
        XCTAssertFalse(callbacks.isEmpty, "a callback caption after several blocks: \(captions)")

        // The mugshot wall, and a replay from it.
        let wall = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mugshot wall'")).firstMatch
        XCTAssertTrue(wall.waitForExistence(timeout: 5))
        wall.tap()
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS 'CASE 001'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        checkpoint("80-mugshot-wall")
        first.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        checkpoint("81-replay-from-wall")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5), "back on the wall")
        app.buttons["Done"].firstMatch.tap()

        // The breed picker.
        app.buttons.matching(NSPredicate(format: "label ENDSWITH 'pts'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Your pet"].waitForExistence(timeout: 5))
        checkpoint("82-pet-picker")
        app.buttons["Done"].firstMatch.tap()
    }

    // MARK: Steps

    /// Taps the spot where the pet will strike (or another one).
    private func hideCamera(catching: Bool) {
        let hook = app.staticTexts["debug.strike"]
        XCTAssertTrue(hook.waitForExistence(timeout: 5))
        let strike = hook.label
        let spots = ["counter": "counter", "shelf": "shelf", "table": "side table"]
        let target = catching ? strike : (strike == "counter" ? "shelf" : "counter")
        let button = app.buttons["Hide the camera at the \(spots[target] ?? target)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if !button.isSelected { button.tap() }
    }

    private func type(dodge: String) {
        let field = app.textFields["What are you avoiding?"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(dodge + "\n")
    }

    /// Waits for the tape, takes a screenshot of each still and records the
    /// whole tape on video; optionally exports and shares it at the end.
    private func watchTape(named name: String, first: Int, share: Bool = false) {
        let progress = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Still '")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 30), "the \(name) tape starts by itself")
        let total = Int(progress.label.split(separator: " ").last ?? "5") ?? 5
        for index in 1...total {
            // A still that already went by (while the test looked away) is skipped.
            let reached = stillShown(progress)
            if reached > index { continue }
            XCTAssertGreaterThanOrEqual(waitForStill(progress, index), index, "still \(index) of the \(name) tape")
            if stillShown(progress) > index { continue }
            usleep(600_000)
            captions.append(app.descendants(matching: .any)["tape.caption"].firstMatch.label)
            checkpoint(String(format: "%02d-tape-\(name)-still-%d", first + index - 1, index))
        }
        if share {
            app.buttons["Share"].tap()
            let sheet = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier == 'ActivityListView' OR label == 'Save Video' OR label == 'Copy'")).firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the video export opens the share sheet")
            sleep(1)
            checkpoint("70-share-sheet")
            checkpoint("video-stop")
            if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
            sleep(1)
            app.buttons["Done"].firstMatch.tap()
        } else {
            // It ends on its own and goes back to the room.
            XCTAssertTrue(progress.waitForNonExistence(timeout: 25), "the \(name) tape ends by itself")
            sleep(1)
            checkpoint("video-stop")
        }
        sleep(1)
    }

    /// Which still the tape's progress says it shows (1 for the first).
    private func stillShown(_ progress: XCUIElement) -> Int {
        guard progress.exists else { return 0 }
        return Int(progress.label.split(separator: " ").dropFirst().first ?? "0") ?? 0
    }

    /// Polls the progress until it reaches still `index` (or one after it).
    private func waitForStill(_ progress: XCUIElement, _ index: Int, timeout: TimeInterval = 10) -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var shown = stillShown(progress)
        while shown < index, Date() < deadline {
            usleep(100_000)
            shown = stillShown(progress)
        }
        return shown
    }

    private func visitLockScreenAndIsland() {
        XCUIDevice.shared.press(.home)
        sleep(1)
        lock()
        wake()
        let allowActivities = springboard.buttons["Allow"]
        if allowActivities.waitForExistence(timeout: 3) { allowActivities.tap() }
        sleep(1)
        checkpoint("05-lock-screen-live-activity")
        unlock()
        sleep(2)
        checkpoint("06-dynamic-island-compact")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        sleep(1)
        checkpoint("07-dynamic-island-expanded")
        XCUIDevice.shared.press(.home)
        sleep(1)
    }

    private func wait(untilSecondsSince start: Date, _ seconds: TimeInterval) {
        let left = seconds - Date().timeIntervalSince(start)
        if left > 0 { usleep(useconds_t(left * 1_000_000)) }
    }

    private func lock() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(1)
    }

    private func wake() {
        XCUIDevice.shared.press(.home)
        sleep(2)
    }

    private func unlock() {
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        bottom.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(1)
    }

    private func allowNotificationsIfAsked() {
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

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
