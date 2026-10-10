import Combine
import XCTest
import TabbiKitCore
@testable import Tabbi

/// A snapshot run must leave no trace, so rendering the Party tab never
/// rewrites the presence (focus time, streak) the real app keeps.
@MainActor
final class PartySnapshotTraceTests: XCTestCase {
    private let key = "party.presence"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testASnapshotRunSavesNoPresence() {
        let store = PartyStore(runMode: RunMode(isSnapshot: true), environment: [:])
        let focus = ProvidedFocus(source: ModuleID("focus"), phase: .focus,
                                  clock: .countdown(endsAt: Date().addingTimeInterval(1500)), phaseLength: 1500)
        store.followFocus(from: Just(focus).eraseToAnyPublisher())
        XCTAssertNil(UserDefaults.standard.data(forKey: key))
    }

    func testALiveRunKeepsItsPresence() {
        let store = PartyStore(runMode: .live, environment: [:])
        let focus = ProvidedFocus(source: ModuleID("focus"), phase: .focus,
                                  clock: .countdown(endsAt: Date().addingTimeInterval(1500)), phaseLength: 1500)
        store.followFocus(from: Just(focus).eraseToAnyPublisher())
        XCTAssertNotNil(UserDefaults.standard.data(forKey: key))
    }
}
