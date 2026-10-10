import XCTest
@testable import TabbiKitCore

final class PartyAgeCheckTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testEligibilityStartsTheMonthAfterTheThirteenthBirthdayMonth() {
        XCTAssertEqual(PartyAgeCheck.eligibleFrom(birthMonth: 3, year: 2013, calendar: calendar), date(2026, 4, 1))
        XCTAssertEqual(PartyAgeCheck.eligibleFrom(birthMonth: 12, year: 2013, calendar: calendar), date(2027, 1, 1))
        XCTAssertNil(PartyAgeCheck.eligibleFrom(birthMonth: 13, year: 2013, calendar: calendar))
        XCTAssertNil(PartyAgeCheck.eligibleFrom(birthMonth: 0, year: 2013, calendar: calendar))
    }

    func testStatusFollowsTheSavedDay() {
        let eligible = date(2026, 4, 1)
        XCTAssertEqual(PartyAgeCheck.status(eligibleFrom: nil, at: date(2026, 1, 1)), .unanswered)
        XCTAssertEqual(PartyAgeCheck.status(eligibleFrom: eligible, at: date(2026, 3, 31)), .tooYoung(until: eligible))
        XCTAssertEqual(PartyAgeCheck.status(eligibleFrom: eligible, at: eligible), .passed)
    }

    func testTheYearPickerSuggestsNoAnswer() {
        let years = PartyAgeCheck.birthYears(at: date(2026, 10, 9), calendar: calendar)
        XCTAssertEqual(years.first, 2026)
        XCTAssertEqual(years.last, 1926)
        XCTAssertEqual(years.count, 101)
    }

    func testTheQuestionIsGregorianWhateverTheMacsCalendar() {
        XCTAssertEqual(PartyAgeCheck.birthCalendar.identifier, .gregorian)
        // 9 October 2026 is in the year 1448 of the Islamic calendar and 5787
        // of the Hebrew one; the picker still offers 2026 and twelve months.
        XCTAssertEqual(PartyAgeCheck.birthYears(at: date(2026, 10, 9)).first, 2026)
        XCTAssertEqual(PartyAgeCheck.monthNames(locale: Locale(identifier: "he_IL@calendar=hebrew")).count, 12)
        XCTAssertEqual(PartyAgeCheck.monthNames(locale: Locale(identifier: "en_US@calendar=japanese")).first, "January")
        XCTAssertNotNil(PartyAgeCheck.eligibleFrom(birthMonth: 3, year: 2013))
    }

    func testOpensTextNamesTheMonthAndYear() {
        XCTAssertEqual(PartyAgeCheck.opensText(date(2028, 5, 1), calendar: calendar,
                                               locale: Locale(identifier: "en_US")), "May 2028")
    }

    func testPartyWaitsForTheAgeCheckBeforeConnecting() {
        let now = date(2026, 10, 9)
        XCTAssertEqual(PartyState(settings: PartySettings(), at: now).connection, .ageCheck(tooYoungUntil: nil))
        let young = PartySettings(ageEligibleFrom: date(2028, 5, 1))
        XCTAssertEqual(PartyState(settings: young, at: now).connection, .ageCheck(tooYoungUntil: date(2028, 5, 1)))
        XCTAssertEqual(PartyState(settings: young, at: date(2028, 5, 1)).connection, .connecting)
        // A server setting that can't work is said first, since nothing could connect anyway.
        XCTAssertEqual(PartyState(settings: PartySettings(serverText: "http://example.com"), at: now).connection,
                       .invalidServer(PartySettings(serverText: "http://example.com").serverIssue!))
    }

    func testAFailedConnectNeverHidesTheAgeCheck() {
        var state = PartyState(settings: PartySettings())
        state.didFailToConnect(.unreachable)
        XCTAssertTrue(state.awaitsAgeCheck)
    }

    func testTheAnswerIsSavedAndOlderSettingsAskAgain() throws {
        let settings = PartySettings(name: "Ana", ageEligibleFrom: date(2020, 1, 1))
        let decoded = try JSONDecoder().decode(PartySettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
        let older = try JSONDecoder().decode(PartySettings.self, from: Data(#"{"name":"Ana","invisible":false}"#.utf8))
        XCTAssertNil(older.ageEligibleFrom)
        XCTAssertEqual(older.ageStatus(at: Date()), .unanswered)
    }

    func testConnectionsAndInvitesSayPartyWaitsForTheAgeCheck() {
        let unanswered = PartyConnectionState.resolve(.ageCheck(tooYoungUntil: nil), friendCode: nil, hasChosenName: true)
        XCTAssertEqual(unanswered, .ageCheck(tooYoungUntil: nil))
        XCTAssertEqual(unanswered.connectionStatus.light, .notSetUp)
        XCTAssertEqual(unanswered.diagnosis.checks.first?.outcome, .failed)

        var flow = PartyInviteFlow(invite: .addFriend(code: "AVA7K3RN"), partyIsOn: true)
        flow.update(with: PartyState(settings: PartySettings()), blocked: nil)
        XCTAssertEqual(flow.stage, .ageCheck(tooYoungUntil: nil))
        XCTAssertEqual(flow.primaryTitle, "Open Party")
        XCTAssertFalse(flow.isDone)

        let until = date(2028, 5, 1)
        var young = PartyInviteFlow(invite: .joinParty(code: "ZX7M2P"), partyIsOn: true)
        young.update(with: PartyState(settings: PartySettings(ageEligibleFrom: until), at: date(2026, 1, 1)), blocked: nil)
        XCTAssertEqual(young.stage, .ageCheck(tooYoungUntil: until))
        XCTAssertNil(young.primaryTitle)
        XCTAssertTrue(young.isDone)
        XCTAssertEqual(young.title, "Party isn't available")
    }
}

extension PartySettings {
    /// Settings that passed the age check long ago, for tests about what
    /// comes after it.
    static let oldEnough = PartySettings(ageEligibleFrom: .distantPast)
}
