import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A snapshot run must leave no trace, so rendering the Party tab never
/// rewrites the presence (focus time, streak) the real app keeps.
@MainActor
final class PartySnapshotTraceTests: XCTestCase {
    private let key = "party.presence"
    /// Each test keeps its own presence, so parallel runs never share it.
    private let defaults = InMemoryDefaults()

    func testASnapshotRunSavesNoPresence() {
        let store = PartyStore(runMode: RunMode(isSnapshot: true), environment: [:], defaults: defaults)
        let focus = ProvidedFocus(source: ModuleID("focus"), phase: .focus,
                                  clock: .countdown(endsAt: Date().addingTimeInterval(1500)), phaseLength: 1500)
        store.followFocus(from: Just(focus).eraseToAnyPublisher())
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testALiveRunKeepsItsPresence() {
        let store = PartyStore(runMode: .live, environment: [:], defaults: defaults)
        let focus = ProvidedFocus(source: ModuleID("focus"), phase: .focus,
                                  clock: .countdown(endsAt: Date().addingTimeInterval(1500)), phaseLength: 1500)
        store.followFocus(from: Just(focus).eraseToAnyPublisher())
        XCTAssertNotNil(defaults.data(forKey: key))
    }
}
