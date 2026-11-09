import XCTest

/// Plays the Pet Cam like a person, in five-minute blocks so the points
/// visibly move: three catches and three misses, which shows every tape
/// shape once (a shape is never one of the last two of its outcome), an
/// early stop, a dare stopped after its floor that still plays its tape
/// (`-PetCamQuickBlocks` makes that floor a minute and the stop's commit
/// point ten seconds, debug builds only), the case file, a replay, a video
/// export, the Lock Screen, the Dynamic Island and the end notification.
/// Every tape must draw its picture at the same size.
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
    /// Each tape's picture size: one frame for every tape.
    private var pictures: [String: CGSize] = [:]
    /// The length of every filmed block.
    private let block: TimeInterval = 300

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-TabbiResetState", "-TabbiDemoPet", "-PetCamQuickBlocks", "-PetCamTestHooks",
                               "-PetCamSeed", "00000000000051d5"]
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

        // The Timer, at five minutes for every block.
        app.buttons["Pomodoro"].tap()
        let timerRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Timer'")).firstMatch
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<4 where !timerRow.isHittable { list.swipeUp() }
        timerRow.tap()
        let shorter = app.buttons["A shorter timer"]
        XCTAssertTrue(shorter.waitForExistence(timeout: 5))
        for _ in 0..<6 where !shorter.isHittable { app.swipeUp() }
        for _ in 0..<40 where !app.staticTexts["5 min"].exists && shorter.isEnabled { shorter.tap() }
        XCTAssertTrue(app.staticTexts["5 min"].exists)

        // Catch 1: hide the camera where the pet will strike and say what is
        // being avoided.
        hideCamera(catching: true)
        type(dodge: "my tax return")
        checkpoint("03-home-camera-hidden")
        app.buttons["Start timer"].tap()
        allowNotificationsIfAsked()
        XCTAssertTrue(app.descendants(matching: .any)["recording.camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["RE: MY TAX RETURN"].exists, "the case title is the player's own words")
        checkpoint("04-recording")
        let started = Date()
        visitLockScreenAndIsland()
        // The block runs out while locked: the end notification.
        lock()
        wait(untilSecondsSince: started, block + 3)
        wake()
        sleep(2)
        checkpoint("08-lock-screen-tape-ready")
        unlock()
        checkpoint("video-start-tape-catch")
        app.activate()
        watchTape(named: "catch", first: 9)
        checkpoint("20-home-after-catch")

        // Miss 1, in the app the whole time.
        play(catching: false, name: "miss", first: 21)
        checkpoint("30-home-after-miss")

        // Stopped early: one frozen still, no tape.
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

        // The dare: "Just 5 minutes", stopped once its floor is in, plays
        // its whole tape.
        hideCamera(catching: true)
        app.buttons["Just 5 minutes"].tap()
        let dareStart = Date()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        checkpoint("32-dare-recording")
        wait(untilSecondsSince: dareStart, 64)
        app.buttons["Stop"].tap()
        let dareTape = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Still '")).firstMatch
        XCTAssertTrue(dareTape.waitForExistence(timeout: 10), "a dare stopped after its floor still plays its tape")
        XCTAssertGreaterThan(Int(dareTape.label.split(separator: " ").last ?? "1") ?? 1, 1)
        sleep(2)
        checkpoint("33-dare-tape")
        app.buttons["Done"].firstMatch.tap()
        sleep(2)

        // Two more catches and two more misses: every shape of both.
        play(catching: true, name: "catch-2", first: 40)
        play(catching: false, name: "miss-2", first: 50)
        play(catching: true, name: "catch-3", first: 60, share: true)
        play(catching: false, name: "miss-3", first: 90)
        checkpoint("97-home-after-six-tapes")

        let sizes = Set(pictures.values.map { "\(Int($0.width))x\(Int($0.height))" })
        print("Pet Cam UI test picture sizes: \(pictures)")
        XCTAssertEqual(sizes.count, 1, "every tape draws its picture at one size: \(pictures)")
        let callbacks = captions.filter {
            $0.contains(" TODAY") || $0.contains(" AGAIN") || $0.contains("RIGHT NEXT TO") || $0.contains("LAST CAUGHT")
        }
        print("Pet Cam UI test captions: \(captions)")
        XCTAssertFalse(callbacks.isEmpty, "a callback caption after several blocks: \(captions)")

        // The case file, and a replay from it.
        let wall = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mugshot wall'")).firstMatch
        XCTAssertTrue(wall.waitForExistence(timeout: 5))
        wall.tap()
        // The newest case sits at the top of the one-column timeline.
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS 'CASE 0'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        sleep(1)
        checkpoint("80-mugshot-wall")
        app.swipeUp()
        sleep(1)
        checkpoint("80-mugshot-wall-scrolled")
        app.swipeDown()
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
        sleep(1)
        checkpoint("82-pet-picker")
        app.buttons["Done"].firstMatch.tap()
    }

    /// One one-minute block, filmed where the pet strikes or elsewhere,
    /// recorded and watched to its end.
    private func play(catching: Bool, name: String, first: Int, share: Bool = false) {
        hideCamera(catching: catching)
        app.buttons["Start timer"].tap()
        let start = Date()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        wait(untilSecondsSince: start, block - 4)
        checkpoint("video-start-tape-\(name)")
        watchTape(named: name, first: first, share: share)
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
    /// It reads the tape's timing once and then only sleeps, because every
    /// query of the app while it plays can stall it, and the recording must
    /// run at the speed the code sets.
    private func watchTape(named name: String, first: Int, share: Bool = false) {
        let progress = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Still '")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 30), "the \(name) tape starts by itself")
        let began = Date()
        let hook = app.staticTexts["debug.tape"].label.components(separatedBy: "|")
        let durations = (hook.first ?? "").split(separator: ",").compactMap { Double($0) }
        XCTAssertFalse(durations.isEmpty, "the tape's timing: \(hook)")
        captions += hook.dropFirst()
        // The picture's size, on the first still (a stamp's tilted corners
        // would widen the element's frame).
        let picture = app.descendants(matching: .any)["tape.picture"].firstMatch
        if pictures[name] == nil, picture.exists { pictures[name] = picture.frame.size }
        // The player waits 0.6 s, then shows each still for its time with
        // 0.09 s of static at each cut. A screenshot lands about a quarter
        // second after it is asked for, so a still under 1.2 s is skipped.
        var start = 0.6
        for (index, duration) in durations.enumerated() {
            if index > 0 { start += 0.09 }
            if duration >= 1.2 {
                let wait = start + 0.15 - Date().timeIntervalSince(began)
                if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
                checkpoint(String(format: "%02d-tape-\(name)-still-%d", first + index, index + 1))
            }
            start += duration
        }
        if share {
            app.buttons["Share"].tap()
            let sheet = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier == 'ActivityListView' OR label == 'Save Video' OR label == 'Copy'")).firstMatch
            let tapped = Date()
            XCTAssertTrue(sheet.waitForExistence(timeout: 90), "the video export opens the share sheet")
            print("Pet Cam UI test: the export took \(String(format: "%.1f", Date().timeIntervalSince(tapped))) s")
            sleep(1)
            checkpoint("70-share-sheet")
            checkpoint("video-stop")
            if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown(velocity: .fast) }
            sleep(1)
            app.buttons["Done"].firstMatch.tap()
        } else {
            // It ends on its own, 0.3 s after its last still, and goes back
            // to the room.
            let left = start + 0.3 - Date().timeIntervalSince(began)
            if left > 0 { usleep(useconds_t(left * 1_000_000)) }
            XCTAssertTrue(progress.waitForNonExistence(timeout: 5), "the \(name) tape ends by itself")
            sleep(1)
            checkpoint("video-stop")
        }
        sleep(1)
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
            usleep(50_000)
        }
    }
}
