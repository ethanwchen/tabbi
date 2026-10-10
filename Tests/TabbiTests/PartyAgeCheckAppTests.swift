import Foundation
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

    /// An answer given before Sign in with Apple (`SyncStore.ageAnswered`)
    /// counts for Party too, so the question is asked once.
    func testPartyAdoptsTheAnswerGivenAtSignIn() {
        let party = makeStore()
        party.adoptAgeAnswer(eligibleFrom: .distantPast)
        XCTAssertEqual(party.state.connection, .connected)

        // An answer is never replaced.
        party.adoptAgeAnswer(eligibleFrom: .distantFuture)
        XCTAssertEqual(party.settings.ageStatus(at: Date()), .passed)
    }
}

/// The same age check before Sign in with Apple: nothing reaches the
/// friends server until it passed, under 13 keeps signing in off for good,
/// and the answer is the one Party keeps.
@MainActor
final class AccountAgeCheckTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("account-age-\(UUID().uuidString)")
    private let serverURL = URL(string: "https://party.example.test")!
    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeStore(_ ageAnswer: AccountAgeAnswer, server: FakeAccountServer,
                           pagesOpened: @escaping @MainActor () -> Void = {}) -> SyncStore {
        let storage = EditionStorage(root: folder)
        let pet = ClosetStore(storage: storage, runMode: .live, starter: .starter(.cat))
        return SyncStore(storage: storage, runMode: .live, pet: pet, signInMethod: .web,
                         webCallback: { _ in pagesOpened(); return nil },
                         server: { [serverURL] in serverURL }, credentials: InMemoryPartyCredentialStore(),
                         ageAnswer: ageAnswer, transport: { _ in server })
    }

    func testSigningInWaitsForTheAgeCheck() async {
        let server = FakeAccountServer()
        var opened = 0
        let store = makeStore(.inMemory(), server: server, pagesOpened: { opened += 1 })
        XCTAssertEqual(store.ageStatus, .unanswered)

        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        await store.signInOnWeb()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(server.requestCount, 0)
        XCTAssertEqual(opened, 0, "Apple's page does not open either")
    }

    func testAnOldEnoughAnswerLetsTheUserSignInAndTellsParty() async {
        let server = FakeAccountServer()
        let answer = AccountAgeAnswer.inMemory()
        let store = makeStore(answer, server: server)
        var told: [Date] = []
        let watch = store.ageAnswered.sink { told.append($0) }
        defer { watch.cancel() }

        store.answerAge(birthMonth: 3, year: thisYear - 20)
        XCTAssertEqual(store.ageStatus, .passed)
        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(answer.load(), told.first, "only the day the user is surely 13 is kept")

        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: "Ana")
        XCTAssertEqual(store.phase, .signedIn)
    }

    func testAnUnderThirteenAnswerKeepsSigningInOffForGood() async {
        let server = FakeAccountServer()
        let store = makeStore(.inMemory(), server: server)
        store.answerAge(birthMonth: 3, year: thisYear - 9)
        guard case .tooYoung(let until) = store.ageStatus else {
            return XCTFail("expected too young, got \(store.ageStatus)")
        }

        store.answerAge(birthMonth: 3, year: thisYear - 30)
        XCTAssertEqual(store.ageStatus, .tooYoung(until: until), "no second try")
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(server.requestCount, 0)
        XCTAssertTrue(AccountAgeText.tooYoung(until: until).contains("13 and older"))
    }

    /// The account reads Party's saved answer, so someone who answered in
    /// Party is not asked again, and the answer it takes Party reads too.
    func testTheAnswerIsTheOnePartyKeeps() throws {
        let suite = "account-age-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = PartySettingsRepository(defaults: defaults)
        repository.save(PartySettings(name: "Ana"))

        let store = makeStore(.partySettings(repository), server: FakeAccountServer())
        store.answerAge(birthMonth: 3, year: thisYear - 20)
        XCTAssertEqual(repository.load().ageStatus(at: Date()), .passed)
        XCTAssertEqual(repository.load().name, "Ana", "the rest of Party's settings stay")

        let answeredInParty = PartySettingsRepository(defaults: defaults)
        let again = makeStore(.partySettings(answeredInParty), server: FakeAccountServer())
        XCTAssertEqual(again.ageStatus, .passed)
    }
}
