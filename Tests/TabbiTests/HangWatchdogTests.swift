import XCTest
import TabbiKitCore
@testable import Tabbi

/// The watchdog leaves a hang log while the main thread is stuck, holding
/// the main thread's own stack, and takes it back once the thread answers.
/// The tests block the main thread (the one XCTest runs on) for real.
final class HangWatchdogTests: XCTestCase {
    private var storage: EditionStorage!
    private var watchdog: HangWatchdog!
    private let environment = DiagnosticEnvironment(appVersion: "1.4.0 (52)", systemVersion: "15.1.0", edition: "tabbi")

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = EditionStorage(root: root)
        CrashHandler.prepare(in: storage, environment: environment)
        watchdog = HangWatchdog(interval: .milliseconds(50), ticksToHang: 3)
    }

    override func tearDownWithError() throws {
        watchdog.stop()
        try? FileManager.default.removeItem(at: storage.root)
    }

    private var log: String? {
        (try? Data(contentsOf: CrashHandler.logURL(in: storage))).map { String(decoding: $0, as: UTF8.self) }
    }

    private func spinMainRunLoop(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testAnAnsweringMainThreadLeavesNoLog() {
        watchdog.start()
        spinMainRunLoop(for: 0.5)
        XCTAssertNil(log)
    }

    func testAHangLeavesTheMainThreadsStackUntilItEnds() throws {
        watchdog.start()
        spinMainRunLoop(for: 0.1)
        // The hang: the main thread answers no ping for a second.
        Thread.sleep(forTimeInterval: 1)
        let text = try XCTUnwrap(log, "a hang that lasts leaves a log")
        let report = try XCTUnwrap(CrashLog.report(from: text))
        XCTAssertEqual(report.environment, environment)
        XCTAssertEqual(report.kind, .hang)
        XCTAssertEqual(report.name, CrashHandler.hangName)
        XCTAssertEqual(report.threads.map(\.name), [CrashHandler.mainThreadName])
        XCTAssertTrue(report.threads[0].crashed)
        let frames = report.threads[0].frames
        XCTAssertGreaterThan(frames.count, 3)
        XCTAssertTrue(frames.contains { $0.contains("testAHangLeavesTheMainThreadsStack") }, "the stack is the stuck main thread's: \(frames)")
        XCTAssertFalse(frames.contains { $0.contains("copyReturnAddresses") }, "not the watchdog's own")

        spinMainRunLoop(for: 0.5)
        XCTAssertNil(log, "a hang the app recovers from is not offered")
    }

    func testAHangNeverOverwritesACrashLog() throws {
        CrashHandler.writeExceptionLog(name: "NSInvalidArgumentException", frames: ["0   Tabbi   0x00000002 main + 12"])
        watchdog.start()
        spinMainRunLoop(for: 0.1)
        Thread.sleep(forTimeInterval: 1)
        spinMainRunLoop(for: 0.5)
        let report = try XCTUnwrap(CrashHandler.takePendingReport(in: storage))
        XCTAssertEqual(report.kind, .exception)
    }

    func testStoppingDuringAHangTakesTheLogBack() {
        watchdog.start()
        spinMainRunLoop(for: 0.1)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotNil(log)
        watchdog.stop()
        XCTAssertNil(log)
    }
}
