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
}

/// Sign in with Apple never asks for a birthday (App Review guideline
/// 5.1.1(v)): signing in works with no answer at all, and only an answer
/// under 13 given in Party keeps it off, deleting an account that was
/// already signed in.
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

    /// The App Store build has no Party, so nothing ever answers there.
    func testSigningInNeedsNoBirthday() async {
        let server = FakeAccountServer()
        let store = makeStore(.fixed(), server: server)
        XCTAssertEqual(store.ageStatus, .unanswered)

        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: "Ana")
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertGreaterThan(server.requestCount, 0)
    }

    func testAppleWebPageOpensWithoutAnAnswer() async {
        var opened = 0
        let store = makeStore(.fixed(), server: FakeAccountServer(), pagesOpened: { opened += 1 })
        await store.signInOnWeb()
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(store.phase, .signedOut, "closing the page is not an error")
        XCTAssertNil(store.notice)
    }

    func testAnUnderThirteenAnswerFromPartyKeepsSigningInOff() async throws {
        let server = FakeAccountServer()
        var opened = 0
        let eligibleFrom = try XCTUnwrap(PartyAgeCheck.eligibleFrom(birthMonth: 3, year: thisYear - 9))
        let store = makeStore(.fixed(eligibleFrom), server: server, pagesOpened: { opened += 1 })
        XCTAssertEqual(store.ageStatus, .tooYoung(until: eligibleFrom))

        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: nil)
        await store.signInOnWeb()
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(server.requestCount, 0)
        XCTAssertEqual(opened, 0, "Apple's page does not open either")
        XCTAssertTrue(AccountAgeText.tooYoung(until: eligibleFrom).contains("13 and older"))
    }

    /// Someone signed in who later answers under 13 in Party: syncing stops
    /// and the account is deleted on the server.
    func testAnUnderThirteenAnswerGivenWhileSignedInDeletesTheAccount() async throws {
        final class Box { var value: Date? }
        let box = Box()
        let server = FakeAccountServer()
        let store = makeStore(AccountAgeAnswer(load: { box.value }), server: server)
        await store.signIn(identityToken: "jwt", authorizationCode: nil, name: "Ana")
        XCTAssertEqual(store.phase, .signedIn)
        for _ in 0..<200 where store.isSyncing || store.lastSyncedAt == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let eligibleFrom = try XCTUnwrap(PartyAgeCheck.eligibleFrom(birthMonth: 3, year: thisYear - 9))
        box.value = eligibleFrom
        store.refreshAgeStatus()
        for _ in 0..<200 where store.phase != .signedOut {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(server.deletedWith, "t-acct")
        XCTAssertEqual(store.ageStatus, .tooYoung(until: eligibleFrom))

        let before = server.requestCount
        store.syncNow()
        XCTAssertEqual(server.requestCount, before, "nothing more is sent")
    }

    /// The account reads the answer Party keeps.
    func testTheAnswerIsTheOnePartyKeeps() throws {
        let suite = "account-age-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = PartySettingsRepository(defaults: defaults)
        XCTAssertEqual(makeStore(.partySettings(repository), server: FakeAccountServer()).ageStatus, .unanswered)

        var settings = PartySettings(name: "Ana")
        settings.ageEligibleFrom = try XCTUnwrap(PartyAgeCheck.eligibleFrom(birthMonth: 3, year: thisYear - 20))
        repository.save(settings)
        XCTAssertEqual(makeStore(.partySettings(repository), server: FakeAccountServer()).ageStatus, .passed)
    }
}

/// Apple's button in the account row, in the App Store build's native flow:
/// it goes straight to Apple's sheet (no question first), a cancel is no
/// error, and a failure says so in the row instead of doing nothing.
@MainActor
final class AppleNativeSignInFlowTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-sign-in-\(UUID().uuidString)")
    private let serverURL = URL(string: "https://party.example.test")!

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private struct SheetFailed: Error {}

    private func makeStore(method: AppleSignInMethod = .native, server: FakeAccountServer,
                           pagesOpened: @escaping @MainActor () -> Void = {},
                           sheet: @escaping @MainActor (NSWindow?) async throws -> AppleNativeCredential?) -> SyncStore {
        let storage = EditionStorage(root: folder)
        let pet = ClosetStore(storage: storage, runMode: .live, starter: .starter(.cat))
        return SyncStore(storage: storage, runMode: .live, pet: pet, signInMethod: method,
                         webCallback: { _ in pagesOpened(); return nil },
                         nativeCredential: sheet,
                         server: { [serverURL] in serverURL }, credentials: InMemoryPartyCredentialStore(),
                         ageAnswer: .fixed(), transport: { _ in server })
    }

    func testTheButtonOpensApplesSheetAndSignsIn() async {
        let server = FakeAccountServer()
        var sheets = 0
        let store = makeStore(server: server) { _ in
            sheets += 1
            return AppleNativeCredential(identityToken: "jwt", authorizationCode: "code", name: "Ana")
        }
        await store.signInWithApple(from: nil)
        XCTAssertEqual(sheets, 1)
        XCTAssertEqual(store.phase, .signedIn)
        XCTAssertEqual(store.name, "Ana")
        XCTAssertNil(store.notice)
    }

    func testCancellingTheSheetIsNotAnError() async {
        let server = FakeAccountServer()
        let store = makeStore(server: server) { _ in nil }
        await store.signInWithApple(from: nil)
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertNil(store.notice)
        XCTAssertEqual(server.requestCount, 0)
    }

    func testASheetThatFailsSaysSoInTheRow() async {
        let server = FakeAccountServer()
        let store = makeStore(server: server) { _ in throw SheetFailed() }
        await store.signInWithApple(from: nil)
        XCTAssertEqual(store.phase, .signedOut)
        XCTAssertEqual(store.notice, "Couldn't sign in with Apple. Try again.")
        XCTAssertEqual(server.requestCount, 0)
    }

    func testTheWebBuildOpensApplesPageInstead() async {
        var opened = 0
        let store = makeStore(method: .web, server: FakeAccountServer(), pagesOpened: { opened += 1 }) { _ in
            XCTFail("the web build has no native sheet")
            return nil
        }
        await store.signInWithApple(from: nil)
        XCTAssertEqual(opened, 1)
    }
}
