import Combine
import XCTest
import AppKit
import TabbiKitCore
@testable import Tabbi

/// Drives `ConnectionsStore` through the parts that never probe the Mac:
/// demo mode, the Party row (fed by the Party tab, no probe), counting the
/// views that watch a row, and the Do Not Disturb switch while nobody
/// watches it. The probed rows need real apps and permissions and are
/// checked by hand in Settings > Connections.
@MainActor
final class ConnectionsStoreTests: XCTestCase {
    /// A snapshot run looks at the Mac but saves nothing, and these tests
    /// only touch the Party row, so no probe ever runs.
    private let liveMode = RunMode(isSnapshot: true)

    /// A stand-in for the Party tab's publishers and buttons.
    private final class PartyTab {
        let state: CurrentValueSubject<PartyConnectionState, Never>
        let name = CurrentValueSubject<String, Never>("Ana")
        let species = CurrentValueSubject<PetSpecies, Never>(.cat)
        var started: [(String, PetSpecies, PartyAgeCheck.Birth?)] = []
        var retries = 0

        init(_ state: PartyConnectionState = .connecting) {
            self.state = CurrentValueSubject(state)
        }

        @MainActor func connect(_ store: ConnectionsStore) {
            store.follow(party: state.eraseToAnyPublisher(), name: name.eraseToAnyPublisher(),
                         species: species.eraseToAnyPublisher(),
                         start: { [unowned self] in started.append(($0, $1, $2)) },
                         retry: { [unowned self] in retries += 1 })
        }
    }

    // MARK: Demo

    func testDemoShowsSampleRowsAndNeverActs() {
        let store = ConnectionsStore(runMode: .demo)
        for kind in ConnectionKind.allCases {
            XCTAssertEqual(store.status(of: kind), kind.demoStatus, "\(kind)")
            XCTAssertEqual(store.diagnosis(of: kind), kind.demoDiagnosis, "\(kind)")
        }
        let shown = store.diagnoses

        store.beginWatching(ConnectionKind.allCases)
        store.refresh(ConnectionKind.allCases)
        store.beginWaiting(for: .anki)
        store.perform(.checkAgain, for: .spotify)
        XCTAssertTrue(store.running.isEmpty, "a demo run never starts a check")
        XCTAssertEqual(store.diagnoses, shown)
        store.endWaiting(for: .anki)
        store.endWatching(ConnectionKind.allCases)

        // The Party tab may still report in; demo keeps its sample row.
        let tab = PartyTab(.offline)
        tab.connect(store)
        XCTAssertEqual(store.diagnosis(of: .party), ConnectionKind.party.demoDiagnosis)
        XCTAssertEqual(store.partyState, .connected(friendCode: "PUFF-42"))
        store.startParty(name: "Ben", species: .dog, birth: nil)
        store.perform(.checkAgain, for: .party)
        XCTAssertTrue(tab.started.isEmpty)
        XCTAssertEqual(tab.retries, 0)

        store.testDoNotDisturb()
        XCTAssertEqual(store.doNotDisturbTest, .passed, "the demo pretends the test worked")

        let details = try? XCTUnwrap(store.details(of: .party))
        XCTAssertTrue(details?.contains(", demo") == true, "copied details say they came from a demo")
    }

    // MARK: Party row

    func testPartyRowFollowsTheTabWithoutAProbe() throws {
        let store = ConnectionsStore(runMode: liveMode)
        XCTAssertNil(store.diagnosis(of: .party))
        XCTAssertEqual(store.status(of: .party).light, .checking, "before any answer the row says checking")
        XCTAssertNil(store.details(of: .party), "nothing to copy before the first answer")
        store.refresh([.party])
        XCTAssertNil(store.diagnosis(of: .party), "without the tab there is nothing to show yet")
        XCTAssertTrue(store.running.isEmpty)

        let tab = PartyTab(.notSetUp)
        tab.connect(store)
        XCTAssertEqual(store.diagnosis(of: .party), PartyConnectionState.notSetUp.diagnosis)
        XCTAssertEqual(store.partyState, .notSetUp)
        XCTAssertNotNil(store.checkedAt[.party])

        for state: PartyConnectionState in [.connecting, .offline, .connected(friendCode: "ANA-12")] {
            tab.state.send(state)
            XCTAssertEqual(store.diagnosis(of: .party), state.diagnosis)
            XCTAssertEqual(store.partyState, state)
        }
        XCTAssertTrue(store.running.isEmpty, "the Party row never runs a probe")

        let details = try XCTUnwrap(store.details(of: .party))
        XCTAssertTrue(details.contains("Connection: \(ConnectionKind.party.title)"), details)
        XCTAssertTrue(details.contains(PartyConnectionState.connected(friendCode: "ANA-12").connectionStatus.headline), details)
        XCTAssertFalse(details.contains(", demo"), details)
    }

    func testARepeatedPartyStateDoesNotRewriteTheRow() {
        let store = ConnectionsStore(runMode: liveMode)
        let tab = PartyTab(.offline)
        tab.connect(store)
        var updates = 0
        let watch = store.$diagnoses.dropFirst().sink { _ in updates += 1 }
        defer { watch.cancel() }

        tab.state.send(.offline)
        tab.state.send(.offline)
        XCTAssertEqual(updates, 0)
        tab.state.send(.connecting)
        XCTAssertEqual(updates, 1)
    }

    func testSetupSheetStartsAndRetriesThroughTheTab() {
        let store = ConnectionsStore(runMode: liveMode)
        store.startParty(name: "Ana", species: .cat, birth: nil)
        store.perform(.checkAgain, for: .party)
        XCTAssertEqual(store.partyDraft.name, "", "no draft before the tab reports in")
        XCTAssertEqual(store.partyDraft.species, .cat)
        XCTAssertEqual(store.partyState, .connecting)

        let tab = PartyTab(.notSetUp)
        tab.connect(store)
        tab.name.send("Mochi")
        tab.species.send(.dog)
        XCTAssertEqual(store.partyDraft.name, "Mochi")
        XCTAssertEqual(store.partyDraft.species, .dog)

        store.startParty(name: "Mochi", species: .dog, birth: PartyAgeCheck.Birth(month: 4, year: 2001))
        XCTAssertEqual(tab.started.count, 1)
        XCTAssertEqual(tab.started.first?.0, "Mochi")
        XCTAssertEqual(tab.started.first?.1, .dog)
        XCTAssertEqual(tab.started.first?.2, PartyAgeCheck.Birth(month: 4, year: 2001))

        store.perform(.checkAgain, for: .party)
        XCTAssertEqual(tab.retries, 1, "Check again on Party asks the server again")
        XCTAssertTrue(store.running.isEmpty, "instead of starting a probe")
    }

    func testFollowingAgainDropsTheOldTab() {
        let store = ConnectionsStore(runMode: liveMode)
        let old = PartyTab(.offline)
        old.connect(store)
        let new = PartyTab(.connected(friendCode: "NEW-1"))
        new.connect(store)

        old.state.send(.notSetUp)
        old.name.send("Old")
        XCTAssertEqual(store.partyState, .connected(friendCode: "NEW-1"), "the replaced tab no longer moves the row")
        XCTAssertEqual(store.diagnosis(of: .party), PartyConnectionState.connected(friendCode: "NEW-1").diagnosis)
        XCTAssertEqual(store.partyDraft.name, "Ana")

        store.startParty(name: "Ben", species: .cat, birth: nil)
        store.perform(.checkAgain, for: .party)
        XCTAssertTrue(old.started.isEmpty)
        XCTAssertEqual(old.retries, 0)
        XCTAssertEqual(new.started.count, 1)
        XCTAssertEqual(new.retries, 1)
    }

    // MARK: Watching

    func testReturningToTabbiChecksOnlyWhileARowIsWatched() async {
        let store = ConnectionsStore(runMode: liveMode)
        PartyTab(.offline).connect(store)
        var updates = 0
        let watch = store.$diagnoses.dropFirst().sink { _ in updates += 1 }
        defer { watch.cancel() }

        // Two views show the Party row; the first one checks it at once.
        store.beginWatching([.party])
        XCTAssertEqual(updates, 1)
        store.beginWatching([.party])
        XCTAssertEqual(updates, 1, "a row already shown is not checked again on appear")

        await becomeActive()
        XCTAssertEqual(updates, 2, "returning to Tabbi checks every watched row")

        // One view goes; the other still shows the row.
        store.endWatching([.party])
        await becomeActive()
        XCTAssertEqual(updates, 3)

        // The last one goes: returning no longer checks anything.
        store.endWatching([.party])
        await becomeActive()
        XCTAssertEqual(updates, 3)

        // Ending a row nobody watches is harmless, and watching starts over.
        store.endWatching([.party, .anki])
        store.beginWatching([.party])
        XCTAssertEqual(updates, 4)
        store.endWatching([.party])
        XCTAssertTrue(store.running.isEmpty)
    }

    func testDoNotDisturbSwitchChecksNothingWhileItsRowIsHidden() async {
        let store = ConnectionsStore(runMode: liveMode)
        let isOn = CurrentValueSubject<Bool, Never>(false)
        var turnedOn = 0
        store.follow(doNotDisturb: isOn.eraseToAnyPublisher(), turnOn: { turnedOn += 1 })

        // Another row is shown, but not Do Not Disturb.
        PartyTab().connect(store)
        store.beginWatching([.party])
        defer { store.endWatching([.party]) }

        isOn.send(true)
        isOn.send(false)
        await drainMainQueue()
        XCTAssertTrue(store.running.isEmpty, "flipping the switch probes only a shown Do Not Disturb row")
        XCTAssertNil(store.diagnosis(of: .doNotDisturb))

        store.perform(.turnOnDoNotDisturb, for: .doNotDisturb)
        XCTAssertEqual(turnedOn, 1, "Turn on flips focus mode's own switch")
        XCTAssertTrue(store.running.isEmpty, "and lets the switch report back instead of probing")
    }

    // MARK: Helpers

    /// Posts what macOS posts when the user comes back to Tabbi, then lets
    /// the main queue run the store's observer.
    private func becomeActive() async {
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await drainMainQueue()
    }

    /// Waits until everything already queued on the main queue has run.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
