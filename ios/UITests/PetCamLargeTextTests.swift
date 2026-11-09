import XCTest

/// One short Pet Cam loop for the largest accessibility text size: run it
/// on a simulator set to it (`xcrun simctl ui <device> content_size
/// accessibility-extra-extra-extra-large`) through ios/e2e.sh, and look at
/// every screen for text that is cut off. It checks that the controls stay
/// reachable and the tape still plays and ends by itself.
@MainActor
final class PetCamLargeTextTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-TabbiResetState", "-TabbiDemoPet", "-PetCamQuickBlocks", "-PetCamTestHooks",
                               "-PetCamSeed", "00000000000051d5", "-TabbiTimerMinutes", "10"]
    }

    func testEveryScreenAtTheLargestTextSize() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 10))
        checkpoint("ax-01-home")
        app.swipeUp()
        checkpoint("ax-02-home-scrolled")
        app.swipeDown()

        // The Timer is already at ten minutes (`-TabbiTimerMinutes`).
        let page = app.scrollViews.firstMatch
        let hook = app.staticTexts["debug.strike"]
        XCTAssertTrue(hook.waitForExistence(timeout: 5))
        let spots = ["counter": "counter", "shelf": "shelf", "table": "side table"]
        app.buttons["Hide the camera at the \(spots[hook.label] ?? hook.label)"].tap()
        let start = app.buttons["Start timer"]
        for _ in 0..<10 where !start.isHittable { page.swipeUp(velocity: .slow) }
        start.tap()
        let allow = springboard.alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let began = Date()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5))
        checkpoint("ax-03-recording")

        let left = 598 - Date().timeIntervalSince(began)
        if left > 0 { usleep(useconds_t(left * 1_000_000)) }
        let progress = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Still '")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 30))
        let total = Int(progress.label.split(separator: " ").last ?? "6") ?? 6
        for index in [3, total] {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline, progress.exists,
                  (Int(progress.label.split(separator: " ").dropFirst().first ?? "0") ?? 0) < index {
                usleep(100_000)
            }
            usleep(600_000)
            // The caption sits whole above the pinned buttons while it plays.
            let caption = app.descendants(matching: .any)["tape.caption"]
            let done = app.buttons["Done"]
            if caption.exists, done.exists {
                let share = app.buttons["Share"]
                let top = share.exists ? min(share.frame.minY, done.frame.minY) : done.frame.minY
                XCTAssertLessThanOrEqual(caption.frame.maxY, top, "still \(index)'s caption runs under the buttons")
            }
            checkpoint("ax-04-tape-still-\(index)")
        }
        XCTAssertTrue(progress.waitForNonExistence(timeout: 25), "the tape ends by itself")
        sleep(1)

        // The wall's chip scrolls; Start stays pinned over the bottom, so
        // bring the chip clear above it before tapping.
        let wall = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mugshot wall'")).firstMatch
        XCTAssertTrue(wall.waitForExistence(timeout: 5))
        for _ in 0..<10 where !wall.isHittable || wall.frame.maxY > start.frame.minY - 4 {
            page.swipeUp(velocity: .slow)
        }
        for _ in 0..<10 where wall.frame.minY < 60 { page.swipeDown(velocity: .slow) }
        wall.tap()
        XCTAssertTrue(app.navigationBars["Case file"].waitForExistence(timeout: 5))
        sleep(1)
        checkpoint("ax-05-mugshot-wall")
        app.buttons["Done"].firstMatch.tap()
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
