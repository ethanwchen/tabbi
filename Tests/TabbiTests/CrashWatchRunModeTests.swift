import XCTest
import TabbiKitCore
@testable import Tabbi

/// Launch decides from the process's own environment and arguments whether
/// to install the crash handler, offer a pending report and watch for hangs.
/// Demo and snapshot runs must do none of it, or a demo crash would land in
/// the user's crash log and a snapshot run would stop to ask about it.
final class CrashWatchRunModeTests: XCTestCase {
    private func watches(environment: [String: String] = [:], arguments: [String] = ["Tabbi"]) -> Bool {
        AppDelegate.watchesForCrashes(in: RunMode(environment: environment, arguments: arguments))
    }

    func testTheRealAppWatchesForCrashes() {
        XCTAssertTrue(watches())
        XCTAssertTrue(AppDelegate.watchesForCrashes(in: .live))
    }

    func testDemoModeNeverWatches() {
        XCTAssertFalse(watches(environment: [RunMode.demoVariable: "1"]))
        XCTAssertFalse(AppDelegate.watchesForCrashes(in: .demo))
    }

    func testASnapshotRunNeverWatches() {
        XCTAssertFalse(watches(arguments: ["Tabbi", RunMode.snapshotFlag, "snapshots"]))
        XCTAssertFalse(watches(environment: [RunMode.demoVariable: "1"],
                               arguments: ["Tabbi", RunMode.snapshotFlag, "snapshots-demo"]))
    }

    /// Only the exact value turns demo mode on, so any other value still
    /// leaves the real app watching for crashes.
    func testADemoVariableThatIsNotOneStillWatches() {
        XCTAssertTrue(watches(environment: [RunMode.demoVariable: "0"]))
        XCTAssertTrue(watches(environment: [RunMode.demoVariable: ""]))
    }
}
