import XCTest
import TabbiKitCore
@testable import Tabbi

/// The crash handler's two writers leave a log the next launch turns into
/// exactly one report, carrying the crashed run's facts and no reason text.
/// The tests call the writers directly, so no signal handler is installed.
final class CrashHandlerTests: XCTestCase {
    private var storage: EditionStorage!
    private let environment = DiagnosticEnvironment(appVersion: "1.4.0 (52)", systemVersion: "15.1.0", edition: "tabbi")

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storage = EditionStorage(root: root)
        CrashHandler.prepare(in: storage, environment: environment)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storage.root)
    }

    func testNoCrashMeansNoReport() {
        XCTAssertNil(CrashHandler.takePendingReport(in: storage))
    }

    func testSignalLogBecomesAReportOnce() throws {
        CrashHandler.writeSignalLog(SIGSEGV)
        let report = try XCTUnwrap(CrashHandler.takePendingReport(in: storage))
        XCTAssertEqual(report.environment, environment)
        XCTAssertEqual(report.kind, .signal)
        XCTAssertEqual(report.name, "SIGSEGV")
        XCTAssertEqual(report.threads.count, 1)
        XCTAssertTrue(report.threads[0].crashed)
        XCTAssertFalse(report.threads[0].frames.isEmpty)
        XCTAssertTrue(report.threads[0].frames.contains { $0.contains("writeSignalLog") }, "the stack is the crashing thread's own")
        XCTAssertNil(CrashHandler.takePendingReport(in: storage), "a crash is offered only once")
    }

    func testExceptionLogKeepsTheNameAndIsNotOverwrittenByTheAbort() throws {
        let frames = ["0   CoreFoundation   0x00000001 __exceptionPreprocess + 176", "1   Tabbi   0x00000002 main + 12"]
        CrashHandler.writeExceptionLog(name: "NSInvalidArgumentException", frames: frames)
        // An uncaught exception ends in abort(), which the signal path sees next.
        CrashHandler.writeSignalLog(SIGABRT)
        let report = try XCTUnwrap(CrashHandler.takePendingReport(in: storage))
        XCTAssertEqual(report.kind, .exception)
        XCTAssertEqual(report.name, "NSInvalidArgumentException")
        XCTAssertEqual(report.threads.first?.frames.count, 2)
        XCTAssertTrue(report.threads.first?.frames.last?.hasSuffix("main + 12") == true)
        XCTAssertEqual(report.threads.first?.name, Thread.isMainThread ? CrashHandler.mainThreadName : "")
    }

    func testUnknownSignalStillNamesTheKind() throws {
        CrashHandler.writeSignalLog(SIGUSR1)
        let report = try XCTUnwrap(CrashHandler.takePendingReport(in: storage))
        XCTAssertEqual(report.kind, .signal)
        XCTAssertEqual(report.name, "unknown")
    }

    func testABrokenLogIsDiscarded() throws {
        let url = CrashHandler.logURL(in: storage)
        try Data("tabbi-crash 1\nkind signal\n".utf8).write(to: url)
        XCTAssertNil(CrashHandler.takePendingReport(in: storage))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: A real crash

    /// The child run's crash, chosen by the parent test.
    private static let childVariable = "TABBI_CRASH_TEST_CHILD"
    private static let childFolderVariable = "TABBI_CRASH_TEST_FOLDER"

    /// Crashes a separate test process for real (the handlers installed, a
    /// bad memory access or a Swift trap) and reads what it left behind.
    func testARealCrashLeavesALogAndStillEndsTheProcess() throws {
        for (crash, signal, name) in [("segv", SIGSEGV, "SIGSEGV"), ("trap", SIGTRAP, "SIGTRAP")] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = ["xctest", "-XCTest", "TabbiTests.CrashHandlerTests/testCrashingChild", Bundle(for: Self.self).bundlePath]
            child.environment = ProcessInfo.processInfo.environment.merging([
                Self.childVariable: crash, Self.childFolderVariable: storage.root.path,
            ]) { $1 }
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            // A handler that never lets the process die must fail, not hang.
            let deadline = Date().addingTimeInterval(60)
            while child.isRunning, Date() < deadline { usleep(50_000) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()

            XCTAssertEqual(child.terminationReason, .uncaughtSignal, crash)
            XCTAssertEqual(child.terminationStatus, signal, "the default action still ends the process")
            let report = try XCTUnwrap(CrashHandler.takePendingReport(in: storage), crash)
            XCTAssertEqual(report.environment, environment)
            XCTAssertEqual(report.name, name)
            XCTAssertEqual(report.threads.first?.name, CrashHandler.mainThreadName)
            XCTAssertTrue(report.threads[0].frames.contains { $0.contains("testCrashingChild") }, crash)
        }
    }

    /// Runs only inside the child process the test above starts.
    func testCrashingChild() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let crash = environment[Self.childVariable], let folder = environment[Self.childFolderVariable] else {
            throw XCTSkip("Runs only as the crashing child of testARealCrashLeavesALogAndStillEndsTheProcess.")
        }
        CrashHandler.install(in: EditionStorage(root: URL(fileURLWithPath: folder)), environment: self.environment)
        if crash == "segv" {
            UnsafeMutablePointer<Int>(bitPattern: 8)!.pointee = 1
        } else {
            let values: [Int] = []
            _ = values[Int(environment.count)]
        }
    }
}
