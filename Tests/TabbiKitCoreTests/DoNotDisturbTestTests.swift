import XCTest
import TabbiKitCore

final class DoNotDisturbTestTests: XCTestCase {
    /// Records which shortcuts ran and which stages were shown.
    private actor Log {
        var ran: [String] = []
        var stages: [DoNotDisturbTest] = []
        func ran(_ name: String) { ran.append(name) }
        func showed(_ stage: DoNotDisturbTest) { stages.append(stage) }
    }

    private func runTest(results: [String: FocusShortcutResult]) async -> (DoNotDisturbTest, Log) {
        let log = Log()
        let result = await DoNotDisturbTest.run(onName: "On", offName: "Off", pause: .zero,
                                                run: { name in
                                                    await log.ran(name)
                                                    return results[name] ?? .succeeded
                                                },
                                                update: { await log.showed($0) })
        return (result, log)
    }

    func testRunsOnThenOffAndPasses() async {
        let (result, log) = await runTest(results: [:])
        XCTAssertEqual(result, .passed)
        let ran = await log.ran
        let stages = await log.stages
        XCTAssertEqual(ran, ["On", "Off"])
        XCTAssertEqual(stages, [.turningOn, .turningOff, .passed])
    }

    func testStopsWhenTheOnShortcutFails() async {
        let (result, log) = await runTest(results: ["On": .notFound(name: "On")])
        XCTAssertEqual(result, .failed(.on, name: "On", .notFound(name: "On")))
        let ran = await log.ran
        XCTAssertEqual(ran, ["On"], "Never runs the off shortcut when on failed")
        XCTAssertTrue(result.isFailure)
        XCTAssertFalse(result.isRunning)
    }

    func testReportsTheOffShortcutFailing() async {
        let (result, _) = await runTest(results: ["Off": .timedOut])
        XCTAssertEqual(result, .failed(.off, name: "Off", .timedOut))
        XCTAssertTrue(result.message.contains("\u{201C}Off\u{201D}"), "Names the shortcut to fix")
    }

    func testMessagesArePlainAndNeverEchoTheToolsWords() {
        let tool = "Couldn't communicate with a helper application."
        let banned = ["CLI", "API", "command line", "error", "\u{2014}"]
        for outcome in DoNotDisturbTest.everyOutcome(onName: "Tabbi Focus On", offName: "Tabbi Focus Off") {
            let message = outcome.message
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains(tool), "\(message) repeats the shortcuts tool's text")
            for term in banned {
                XCTAssertNil(message.range(of: term, options: .caseInsensitive), "\(message) uses \(term)")
            }
            XCTAssertLessThanOrEqual(message.count, 100, "\(message) is too long for one row")
            XCTAssertFalse(outcome.technical.contains("Tabbi Focus"), "Support labels leave out shortcut names")
        }
        let labels = DoNotDisturbTest.everyOutcome(onName: "On", offName: "Off").map(\.technical)
        XCTAssertEqual(Set(labels).count, labels.count, "Every outcome has its own support label")
    }

    func testAConnectedRowOffersTheTest() {
        let ready = FocusShortcutsState(onName: "On", offName: "Off", installed: ["On", "Off"]).connectionStatus
        XCTAssertEqual(ready.suggestion, .testDoNotDisturb)
        XCTAssertEqual(ConnectionAction.testDoNotDisturb.title, "Test it")
        let missing = FocusShortcutsState(onName: "On", offName: "Off", installed: ["On"]).connectionStatus
        XCTAssertNil(missing.suggestion, "Nothing to test until both shortcuts exist")
    }

    func testATurnedOffSwitchIsNeverConnected() {
        // Both shortcuts exist, but Tabbi won't run them while the switch is off.
        let off = FocusShortcutsState(onName: "On", offName: "Off", installed: ["On", "Off"], isTurnedOn: false)
        XCTAssertFalse(off.connectionStatus.isConnected)
        XCTAssertEqual(off.connectionStatus.headline, "Do Not Disturb is off")
        XCTAssertEqual(off.connectionStatus.action, .turnOnDoNotDisturb)
        XCTAssertNil(off.connectionStatus.suggestion, "Nothing to test while it is off")
        XCTAssertEqual(ConnectionAction.turnOnDoNotDisturb.title, "Turn on")
        XCTAssertEqual(off.diagnosis.firstFailure?.question, "Is Do Not Disturb turned on in Tabbi?")
        XCTAssertEqual(off.diagnosis.technical, "doNotDisturb.off")
        // Off wins even before the shortcuts are listed.
        let unlisted = FocusShortcutsState(onName: "On", offName: "Off", installed: nil, isTurnedOn: false)
        XCTAssertEqual(unlisted.connectionStatus.light, .notSetUp)
    }
}
