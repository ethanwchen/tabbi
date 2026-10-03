import XCTest
import NotchKitCore

final class PartyRefreshPlanTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_123)

    func testHiddenPanelFetchesNothing() {
        let plan = PartyRefreshPlan()
        XCTAssertEqual(plan.due(at: t0), [])
        XCTAssertNil(plan.nextDue())
    }

    func testOpeningFetchesFriendsAndPartyOnce() {
        var plan = PartyRefreshPlan()
        plan.setVisible(true)
        XCTAssertEqual(plan.due(at: t0), [.friends, .party])

        plan.didFetch(.friends, at: t0)
        plan.didFetch(.party, at: t0)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(59)), [])
        // Not in a party: the party is not polled again, friends every 60 s.
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(60)), [.friends])
        XCTAssertEqual(plan.nextDue(), t0.addingTimeInterval(60))
    }

    func testInPartyPollsThePartyEvery30Seconds() {
        var plan = PartyRefreshPlan()
        plan.inParty = true
        plan.setVisible(true)
        plan.didFetch(.friends, at: t0)
        plan.didFetch(.party, at: t0)

        XCTAssertEqual(plan.nextDue(), t0.addingTimeInterval(30))
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(30)), [.party])
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(60)), [.friends, .party])
    }

    func testHidingStopsAndReopeningRefreshesImmediately() {
        var plan = PartyRefreshPlan()
        plan.inParty = true
        plan.setVisible(true)
        plan.didFetch(.friends, at: t0)
        plan.didFetch(.party, at: t0)

        plan.setVisible(false)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(600)), [])
        XCTAssertNil(plan.nextDue())

        plan.setVisible(true)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(5)), [.friends, .party])
    }

    func testRedundantVisibleKeepsTheSchedule() {
        var plan = PartyRefreshPlan()
        plan.setVisible(true)
        plan.didFetch(.friends, at: t0)
        plan.didFetch(.party, at: t0)
        plan.setVisible(true)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(1)), [])
    }

    func testInvalidateMakesAFeedDueNow() {
        var plan = PartyRefreshPlan()
        plan.setVisible(true)
        plan.didFetch(.friends, at: t0)
        plan.didFetch(.party, at: t0)

        plan.invalidate(.party)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(1)), [.party])
    }

    func testHiddenPanelFetchesThePartyOnceAfterConnecting() {
        var plan = PartyRefreshPlan()
        plan.inParty = true
        plan.invalidate(.party)
        XCTAssertEqual(plan.due(at: t0), [.party])

        plan.didFetch(.party, at: t0)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(600)), [])
        XCTAssertNil(plan.nextDue())
    }

    func testOpeningTheNotchOnAnyTabFetchesThePartyOnce() {
        var plan = PartyRefreshPlan()
        plan.inParty = true
        plan.notchDidOpen()
        XCTAssertEqual(plan.due(at: t0), [.party])

        plan.didFetch(.party, at: t0)
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(600)), [])

        plan.notchDidOpen()
        XCTAssertEqual(plan.due(at: t0.addingTimeInterval(601)), [.party])
    }
}
