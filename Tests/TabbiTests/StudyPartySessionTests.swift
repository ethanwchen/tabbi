import Combine
import Foundation
import XCTest
import TabbiKitCore
@testable import Tabbi

/// The Timer tab shows a party's shared session from the provider snapshot
/// while the user is in it, and gives the user's own timer back after.
@MainActor
final class StudyPartySessionTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("study-party-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func snapshot(_ session: ProvidedPartySession?) -> ProviderSnapshot {
        let party = ProvidedParty(pets: [], session: session)
        return ProviderSnapshot([(.party, ModuleProvision(focus: session?.focus(by: .party), party: party))])
    }

    func testTheTimerShowsTheSharedSessionAndKeepsTheOwnTimer() {
        let store = StudyStore(storage: EditionStorage(root: folder), runMode: RunMode(isDemo: false, isSnapshot: true))
        store.choose(.timer)
        store.startTimer(StudyTimerLength(minutes: 10))
        let own = store.session
        let snapshots = CurrentValueSubject<ProviderSnapshot, Never>(ProviderSnapshot())
        store.followParty(from: snapshots)
        XCTAssertNil(store.partySession)

        let now = Date()
        let session = ProvidedPartySession(method: "pomodoro", startedAt: now, endsAt: now.addingTimeInterval(25 * 60),
                                           friendCount: 2, hostName: "Maya")
        snapshots.send(snapshot(session))
        XCTAssertEqual(store.partySession, session)
        XCTAssertEqual(store.session, own, "The shared session never touches the user's own timer")

        // The session ended, or the user stepped out: the own timer is back.
        snapshots.send(snapshot(nil))
        XCTAssertNil(store.partySession)
        XCTAssertTrue(store.session.isRunning)
    }
}
