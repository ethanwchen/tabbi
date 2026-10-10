import XCTest
import TabbiKitCore
@testable import Tabbi

/// Party's age check in the app: the panel asks before Party joins, an old
/// enough answer opens Party, and an under-13 answer keeps it closed with
/// no second try.
@MainActor
final class PartyAgeCheckAppTests: XCTestCase {
    private func makeStore() -> PartyStore {
        PartyStore(runMode: .demo, environment: ["TABBI_PARTY_PREVIEW": "ageCheck"])
    }

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    func testPartyAsksBeforeJoining() {
        let party = makeStore()
        XCTAssertEqual(party.state.connection, .ageCheck(tooYoungUntil: nil))
        XCTAssertNil(party.state.friendCode)
    }

    func testAnOldEnoughAnswerOpensParty() {
        let party = makeStore()
        party.answerAge(birthMonth: 6, year: thisYear - 20)
        XCTAssertEqual(party.state.connection, .connected)
        XCTAssertEqual(party.settings.ageStatus(at: Date()), .passed)
    }

    func testAnUnderThirteenAnswerKeepsPartyClosedForGood() throws {
        let party = makeStore()
        party.answerAge(birthMonth: 6, year: thisYear - 10)
        guard case .ageCheck(let until?) = party.state.connection else {
            return XCTFail("expected Party to stay closed, got \(party.state.connection)")
        }
        XCTAssertGreaterThan(until, Date())

        // Answering again changes nothing.
        party.answerAge(birthMonth: 6, year: thisYear - 30)
        XCTAssertEqual(party.state.connection, .ageCheck(tooYoungUntil: until))
    }

    func testOtherDemoScreensHavePassedTheCheck() {
        let party = PartyStore(runMode: .demo, environment: [:])
        XCTAssertEqual(party.settings.ageStatus(at: Date()), .passed)
        XCTAssertEqual(party.state.connection, .connected)
    }
}
