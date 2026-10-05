import XCTest
import TabbiKitCore

/// Answers `guiDeckReview` from a script, one reply per call, repeating
/// the last; records the deck names asked for.
private final class ScriptedTransport: AnkiConnectTransport, @unchecked Sendable {
    enum Reply {
        case result(Bool)
        case error(String)
        case refused
        case timedOut
    }

    private let lock = NSLock()
    private var script: [Reply]
    private var asked: [String] = []
    /// Called before each reply, so a test can see the clock at that moment.
    var onRequest: (@Sendable () -> Void)?

    init(_ script: [Reply]) { self.script = script }

    var deckNames: [String] { lock.withLock { asked } }

    func post(_ body: Data, timeout: TimeInterval) async throws -> AnkiConnectHTTPResponse {
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        let params = object["params"] as? [String: Any]
        let reply: Reply = lock.withLock {
            asked.append(params?["name"] as? String ?? "")
            return script.count > 1 ? script.removeFirst() : script[0]
        }
        onRequest?()
        switch reply {
        case .result(let found):
            return AnkiConnectHTTPResponse(statusCode: 200, body: Data(#"{"result":\#(found),"error":null}"#.utf8))
        case .error(let message):
            return AnkiConnectHTTPResponse(statusCode: 200, body: Data(#"{"result":null,"error":"\#(message)"}"#.utf8))
        case .refused:
            throw AnkiConnectTransportError.connectionRefused
        case .timedOut:
            throw AnkiConnectTransportError.timedOut
        }
    }
}

/// An Anki that is installed or not, running or not, and records launches
/// and activations.
private final class FakeLauncher: AnkiAppLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private var installed: Bool
    private var startedAt: Date?
    private let launches: Bool
    private let clock: TestClock
    private(set) var launchCount = 0
    private(set) var activateCount = 0

    init(installed: Bool = true, runningSince: Date? = nil, launches: Bool = true, clock: TestClock) {
        self.installed = installed
        self.startedAt = runningSince
        self.launches = launches
        self.clock = clock
    }

    func isInstalled() async -> Bool { lock.withLock { installed } }
    func runningSince() async -> Date? { lock.withLock { startedAt } }

    func launch() async -> Bool {
        lock.withLock {
            launchCount += 1
            if launches { startedAt = clock.current }
            return launches
        }
    }

    func activate() async { lock.withLock { activateCount += 1 } }
}

/// A clock whose sleeps advance time instantly.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = Date(timeIntervalSince1970: 1_800_000_000)
    private(set) var sleeps: [TimeInterval] = []

    var current: Date { lock.withLock { instant } }

    var clock: AnkiOpenClock {
        AnkiOpenClock(now: { self.current }, sleep: { seconds in
            try Task.checkCancellation()
            self.lock.withLock {
                self.sleeps.append(seconds)
                self.instant = self.instant.addingTimeInterval(seconds)
            }
        })
    }
}

/// Lets a transport cancel the task that is calling it, even if the
/// request comes before the task is stored.
private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<AnkiOpenOutcome, Error>?
    private var cancelled = false

    func set(_ task: Task<AnkiOpenOutcome, Error>) {
        let cancelNow = lock.withLock { self.task = task; return cancelled }
        if cancelNow { task.cancel() }
    }

    func cancel() {
        let task = lock.withLock { cancelled = true; return self.task }
        task?.cancel()
    }
}

/// Collects the phases the flow reports.
private actor PhaseLog {
    var phases: [AnkiOpenPhase] = []
    func append(_ phase: AnkiOpenPhase) { phases.append(phase) }
}

final class AnkiDeckOpenerTests: XCTestCase {
    private func opener(_ transport: ScriptedTransport, _ launcher: FakeLauncher, _ clock: TestClock) -> AnkiDeckOpener {
        let client = AnkiConnectClient(transport: transport, isAnkiRunning: { await launcher.runningSince() != nil })
        return AnkiDeckOpener(client: client, launcher: launcher, clock: clock.clock, launchTimeout: 30, pollInterval: 0.5)
    }

    func testRunningAnkiOpensTheDeckAndComesForward() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(runningSince: clock.current.addingTimeInterval(-3600), clock: clock)
        let transport = ScriptedTransport([.result(true)])
        let log = PhaseLog()

        let outcome = try await opener(transport, launcher, clock).open(deck: "Step1::Cardio") { await log.append($0) }

        XCTAssertEqual(outcome, .opened(deck: "Step1::Cardio"))
        XCTAssertEqual(transport.deckNames, ["Step1::Cardio"])
        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(launcher.activateCount, 1)
        let phases = await log.phases
        XCTAssertEqual(phases, [.opening])
        XCTAssertTrue(clock.sleeps.isEmpty)
    }

    func testClosedAnkiIsLaunchedThenPolledUntilAnkiConnectAnswers() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(clock: clock)
        // Refused while Anki starts, then busy loading the profile, then ready.
        let transport = ScriptedTransport([.refused, .refused, .refused, .error("collection is not available"), .result(true)])
        let log = PhaseLog()

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm") { await log.append($0) }

        XCTAssertEqual(outcome, .opened(deck: "Pharm"))
        XCTAssertEqual(launcher.launchCount, 1)
        XCTAssertEqual(launcher.activateCount, 1, "Brought forward again once the review is open")
        XCTAssertEqual(transport.deckNames.count, 5)
        XCTAssertEqual(clock.sleeps, [0.5, 0.5, 0.5, 0.5])
        let phases = await log.phases
        XCTAssertEqual(phases, [.launching])
    }

    func testAnAddOnThatNeverAnswersGivesUpAtTheTimeoutWithAnkiInFront() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(clock: clock)
        let transport = ScriptedTransport([.refused])
        let start = clock.current

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .addOnMissing)
        XCTAssertEqual(launcher.activateCount, 1)
        XCTAssertEqual(clock.current.timeIntervalSince(start), 30, accuracy: 0.001)
        XCTAssertEqual(transport.deckNames.count, 61, "One try every half second for 30 s, plus the first")
    }

    func testLongRunningAnkiWithoutTheAddOnFailsAtOnce() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(runningSince: clock.current.addingTimeInterval(-600), clock: clock)
        let transport = ScriptedTransport([.refused])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .addOnMissing)
        XCTAssertEqual(transport.deckNames.count, 1)
        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertEqual(launcher.activateCount, 1, "The click still brings Anki forward")
    }

    func testAnkiStartedMomentsAgoGetsTheStartupWait() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(runningSince: clock.current.addingTimeInterval(-2), clock: clock)
        let transport = ScriptedTransport([.refused, .timedOut, .result(true)])
        let log = PhaseLog()

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm") { await log.append($0) }

        XCTAssertEqual(outcome, .opened(deck: "Pharm"))
        XCTAssertEqual(launcher.launchCount, 0)
        let phases = await log.phases
        XCTAssertEqual(phases, [.launching])
    }

    func testUnknownLaunchDateCountsAsLongRunning() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(runningSince: .distantPast, clock: clock)
        let transport = ScriptedTransport([.timedOut])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .failed(.timeout))
        XCTAssertEqual(transport.deckNames.count, 1)
    }

    func testMissingDeckIsReportedWithAnkiInFront() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(runningSince: .distantPast, clock: clock)
        let transport = ScriptedTransport([.result(false)])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Old deck")

        XCTAssertEqual(outcome, .deckNotFound("Old deck"))
        XCTAssertEqual(launcher.activateCount, 1)
    }

    func testOtherAnkiErrorsStopTheWaitAtOnce() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(clock: clock)
        let transport = ScriptedTransport([.refused, .error("valid api key must be provided")])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .failed(.apiKeyRequired))
        XCTAssertEqual(transport.deckNames.count, 2)
    }

    func testProfilePickerStillOpenAtTheTimeoutIsExplained() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(clock: clock)
        let transport = ScriptedTransport([.error("collection is not available")])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .failed(.collectionUnavailable))
    }

    func testNoDeckJustOpensAnki() async throws {
        let clock = TestClock()
        let closed = FakeLauncher(clock: clock)
        let transport = ScriptedTransport([.result(true)])

        let launched = try await opener(transport, closed, clock).open(deck: nil)
        XCTAssertEqual(launched, .openedApp)
        XCTAssertEqual(closed.launchCount, 1)

        let running = FakeLauncher(runningSince: .distantPast, clock: clock)
        let activated = try await opener(transport, running, clock).open(deck: "  ")
        XCTAssertEqual(activated, .openedApp)
        XCTAssertEqual(running.activateCount, 1)
        XCTAssertTrue(transport.deckNames.isEmpty, "No deck means no AnkiConnect call")
    }

    func testAnkiThatIsNotInstalledIsNotLaunched() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(installed: false, clock: clock)
        let transport = ScriptedTransport([.result(true)])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .notInstalled)
        XCTAssertEqual(launcher.launchCount, 0)
        XCTAssertTrue(transport.deckNames.isEmpty)
    }

    func testALaunchMacOSRefusesIsReported() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(launches: false, clock: clock)
        let transport = ScriptedTransport([.result(true)])

        let outcome = try await opener(transport, launcher, clock).open(deck: "Pharm")

        XCTAssertEqual(outcome, .launchFailed)
        XCTAssertTrue(transport.deckNames.isEmpty)
    }

    func testCancellingStopsTheWait() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(clock: clock)
        let transport = ScriptedTransport([.refused])
        let subject = opener(transport, launcher, clock)
        let holder = TaskHolder()
        transport.onRequest = { if transport.deckNames.count == 3 { holder.cancel() } }
        let task = Task { try await subject.open(deck: "Pharm") }
        holder.set(task)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertLessThanOrEqual(transport.deckNames.count, 4)
        XCTAssertEqual(launcher.activateCount, 0)
    }

    func testSubdecksAreOpenedByTheirFullTrimmedName() async throws {
        let clock = TestClock()
        let launcher = FakeLauncher(runningSince: .distantPast, clock: clock)
        let transport = ScriptedTransport([.result(true)])

        let outcome = try await opener(transport, launcher, clock).open(deck: " Step1 :: Cardio::Arrhythmias ")

        XCTAssertEqual(outcome, .opened(deck: "Step1::Cardio::Arrhythmias"))
        XCTAssertEqual(transport.deckNames, ["Step1::Cardio::Arrhythmias"])
    }

    // MARK: Deck names

    func testDeckNameComponentsAndNormalizing() {
        XCTAssertEqual(AnkiDeckName.components("Step1::Cardio::Arrhythmias"), ["Step1", "Cardio", "Arrhythmias"])
        XCTAssertEqual(AnkiDeckName.normalized(" Step1 :: Cardio "), "Step1::Cardio")
        XCTAssertEqual(AnkiDeckName.normalized("Step1::::Cardio"), "Step1::Cardio")
        XCTAssertEqual(AnkiDeckName.normalized("Default"), "Default")
        XCTAssertNil(AnkiDeckName.normalized(""))
        XCTAssertNil(AnkiDeckName.normalized(" :: "))
        XCTAssertEqual(AnkiDeckName.normalized("Japanese: Kanji"), "Japanese: Kanji", "A single colon is part of the name")
    }

    func testDeckNameLeaf() {
        XCTAssertEqual(AnkiDeckName.leaf("Step1::Cardio::Arrhythmias"), "Arrhythmias")
        XCTAssertEqual(AnkiDeckName.leaf("Pharm"), "Pharm")
    }

    // MARK: Outcome wording

    func testOnlyFailuresHaveANoticeAndANextStep() {
        for outcome in [AnkiOpenOutcome.opened(deck: "Pharm"), .openedApp] {
            XCTAssertTrue(outcome.isSuccess)
            XCTAssertNil(outcome.title)
            XCTAssertNil(outcome.suggestion)
        }
        let failures: [AnkiOpenOutcome] = [.addOnMissing, .deckNotFound("Pharm"), .failed(.collectionUnavailable), .notInstalled, .launchFailed]
        for outcome in failures {
            XCTAssertFalse(outcome.isSuccess)
            XCTAssertFalse(outcome.title?.isEmpty ?? true, "\(outcome)")
            XCTAssertFalse(outcome.suggestion?.isEmpty ?? true, "\(outcome)")
        }
    }

    func testAddOnMissingNamesTheOneNextStepAndTheCode() {
        let suggestion = AnkiOpenOutcome.addOnMissing.suggestion ?? ""
        XCTAssertTrue(suggestion.hasPrefix("Install the AnkiConnect add-on to open decks directly"))
        XCTAssertTrue(suggestion.contains(AnkiConnectClient.addOnCode))
    }

    func testAMissingSubdeckIsNamedByItsFullPath() {
        let outcome = AnkiOpenOutcome.deckNotFound("Step1::Cardio::Arrhythmias")
        XCTAssertTrue(outcome.suggestion?.contains("Step1::Cardio::Arrhythmias") ?? false)
        XCTAssertEqual(AnkiOpenOutcome.failed(.timeout).title, AnkiConnectError.timeout.title)
    }

    func testPreviewNamesPinEachOutcome() {
        XCTAssertEqual(AnkiOpenOutcome(previewName: "addOnMissing", deck: "Pharm"), .addOnMissing)
        XCTAssertEqual(AnkiOpenOutcome(previewName: "decknotfound", deck: "Pharm"), .deckNotFound("Pharm"))
        XCTAssertEqual(AnkiOpenOutcome(previewName: "opened", deck: "Pharm"), .opened(deck: "Pharm"))
        XCTAssertNil(AnkiOpenOutcome(previewName: "launching", deck: "Pharm"))
    }
}
