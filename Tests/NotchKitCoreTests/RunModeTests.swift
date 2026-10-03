import XCTest
import NotchKitCore

final class RunModeTests: XCTestCase {
    func testAPlainLaunchIsLive() {
        let mode = RunMode(environment: [:], arguments: ["Tabbi"])
        XCTAssertEqual(mode, .live)
        XCTAssertFalse(mode.isEphemeral)
    }

    func testDemoNeedsTheVariableSetToOne() {
        XCTAssertEqual(RunMode(environment: ["NOTCHDECK_DEMO": "1"], arguments: []), .demo)
        XCTAssertEqual(RunMode(environment: ["NOTCHDECK_DEMO": "0"], arguments: []), .live)
        XCTAssertEqual(RunMode(environment: ["NOTCHDECK_DEMO": "true"], arguments: []), .live)
    }

    func testTheSnapshotFlagMakesASnapshotRunThatSavesNothing() {
        let mode = RunMode(environment: [:], arguments: ["Tabbi", "--snapshot", "snapshots"])
        XCTAssertTrue(mode.isSnapshot)
        XCTAssertFalse(mode.isDemo)
        XCTAssertTrue(mode.isEphemeral)
    }

    func testDemoSnapshotsAreBoth() {
        let mode = RunMode(environment: ["NOTCHDECK_DEMO": "1"], arguments: ["--snapshot", "snapshots-demo"])
        XCTAssertEqual(mode, RunMode(isDemo: true, isSnapshot: true))
        XCTAssertTrue(mode.isEphemeral)
    }

    func testASnapshotFolderNamedLikeTheFlagIsNotTheFlag() {
        // Only an exact `--snapshot` argument counts.
        XCTAssertEqual(RunMode(environment: [:], arguments: ["--snapshots"]), .live)
    }
}
