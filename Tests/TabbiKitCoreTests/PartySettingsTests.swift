import XCTest
@testable import TabbiKitCore

final class PartySettingsTests: XCTestCase {
    func testBlankServerUsesTheProductionServer() {
        let settings = PartySettings(serverText: "  \n")
        XCTAssertTrue(settings.usesDefaultServer)
        XCTAssertEqual(settings.serverURL, PartyServer.productionURL)
        XCTAssertNil(settings.serverIssue)
        XCTAssertEqual(PartySettings.default.serverURL, PartyServer.productionURL)
    }

    func testCustomServerIsParsedAndBadOnesExplainWhy() {
        XCTAssertEqual(PartySettings(serverText: "friends.example.org/").serverURL?.absoluteString,
                       "https://friends.example.org")
        XCTAssertEqual(PartySettings(serverText: "http://localhost:8787").serverURL, PartyServer.localDevURL)

        let plainHTTP = PartySettings(serverText: "http://friends.example.org")
        XCTAssertNil(plainHTTP.serverURL)
        XCTAssertEqual(plainHTTP.serverIssue, "Use https:// (plain http:// only works for localhost).")

        let junk = PartySettings(serverText: "ftp://nope")
        XCTAssertNil(junk.serverURL)
        XCTAssertNotNil(junk.serverIssue)
    }

    func testNameIsCleanedLikeTheServerDoes() {
        XCTAssertNil(PartySettings(name: "   ").cleanedName)
        XCTAssertNil(PartySettings(name: "\u{200B}\u{200D}").cleanedName)
        XCTAssertEqual(PartySettings(name: "  An\u{200B}a\n ").cleanedName, "Ana")
        let long = PartySettings(name: String(repeating: "x", count: 40)).cleanedName
        XCTAssertEqual(long?.count, PartySettings.maxNameLength)
    }

    func testProfileUpdateCarriesNameAndPetOnly() throws {
        let pet = PetProfile(name: "Mochi", breed: .calico)
        let update = PartySettings(name: " Ana ").profileUpdate(for: pet)
        XCTAssertEqual(update.name, "Ana")
        XCTAssertEqual(update.petName, "Mochi")
        XCTAssertNil(update.points)

        let json = try JSONSerialization.jsonObject(with: PartyClient.makeEncoder().encode(update)) as? [String: Any]
        let allowed: Set<String> = ["name", "petName", "species", "breed", "colors", "costume", "accessories"]
        let keys = Set(try XCTUnwrap(json).keys)
        XCTAssertTrue(keys.isSubset(of: allowed), "\(keys.sorted())")

        XCTAssertNil(PartySettings().profileUpdate(for: pet).name, "a blank name keeps the server's")
    }

    func testNamesTheFilterRejectsAreLeftOutAndReported() throws {
        let fine = PetProfile(name: "Mochi", breed: .calico)
        let rude = PetProfile(name: "Sh1t", breed: .calico)

        let settings = PartySettings(name: "F u c k")
        XCTAssertEqual(settings.refusedNames(for: fine), .name)
        XCTAssertNil(settings.profileUpdate(for: fine).name)
        XCTAssertEqual(settings.profileUpdate(for: fine).petName, "Mochi")

        XCTAssertEqual(PartySettings(name: "Cassandra").refusedNames(for: rude), .petName)
        XCTAssertEqual(PartySettings(name: "Cassandra").profileUpdate(for: rude).name, "Cassandra")
        XCTAssertNil(PartySettings(name: "Cassandra").profileUpdate(for: rude).petName)

        XCTAssertEqual(PartySettings().refusedNames(for: fine), [], "a blank name is never refused")
    }

    func testRefusalMessagesSayWhichNameToChange() {
        XCTAssertNil(PartyNameRefusal().message)
        XCTAssertEqual(PartyNameRefusal.name.message, "That name isn't allowed. Please pick another.")
        XCTAssertEqual(PartyNameRefusal.petName.message, "Your pet's name isn't allowed. Rename your pet in the Closet.")
        XCTAssertEqual(PartyNameRefusal([.name, .petName]).message,
                       "That name and your pet's name aren't allowed. Please pick others.")
        XCTAssertEqual(PartyNameRefusal(.nameNotAllowed), .name)
        XCTAssertEqual(PartyNameRefusal(.petNameNotAllowed), .petName)
        XCTAssertNil(PartyNameRefusal(.banned))
    }

    func testRepositoryRoundTripsAndToleratesMissingKeys() throws {
        let suite = "PartySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = PartySettingsRepository(defaults: defaults)

        XCTAssertEqual(repository.load(), .default)
        let saved = PartySettings(serverText: "http://localhost:8787", name: "Ana", invisible: true)
        repository.save(saved)
        XCTAssertEqual(repository.load(), saved)

        defaults.set(Data(#"{"name":"Ben"}"#.utf8), forKey: PartySettingsRepository.key)
        XCTAssertEqual(repository.load(), PartySettings(name: "Ben"))
    }

    func testIdentityKeyIgnoresCaseAndTrailingSlashes() {
        let a = URL(string: "HTTPS://Friends.Example.org/")!
        let b = URL(string: "https://friends.example.org")!
        XCTAssertEqual(PartyServer.identityKey(for: a), PartyServer.identityKey(for: b))
        XCTAssertNotEqual(PartyServer.identityKey(for: PartyServer.localDevURL),
                          PartyServer.identityKey(for: URL(string: "http://localhost:8788")!))
    }

    func testInMemoryStoreKeepsOneIdentityPerServer() {
        let store = InMemoryPartyCredentialStore()
        let local = PartyCredentials(token: String(repeating: "a", count: 64), code: "K7QW2MZD")
        store.save(local, for: PartyServer.localDevURL)
        XCTAssertNil(store.load(for: PartyServer.productionURL))
        XCTAssertEqual(store.load(for: URL(string: "http://LOCALHOST:8787/")!), local)
        store.delete(for: PartyServer.localDevURL)
        XCTAssertNil(store.load(for: PartyServer.localDevURL))
    }

    func testKeychainStoreSavesUpdatesAndDeletes() throws {
        let store = KeychainPartyCredentialStore(service: "dev.tabbi.tests.party.\(UUID().uuidString)")
        let server = URL(string: "https://friends.example.org")!
        defer { try? store.delete(for: server) }

        XCTAssertNil(store.load(for: server))
        do {
            try store.save(PartyCredentials(token: "first", code: "AAAAAAAA"), for: server)
        } catch let error as KeychainPartyCredentialStore.KeychainError {
            throw XCTSkip("Keychain unavailable in this environment (\(error.status))")
        }
        try store.save(PartyCredentials(token: "second", code: "BBBBBBBB"), for: server)
        XCTAssertEqual(store.load(for: server), PartyCredentials(token: "second", code: "BBBBBBBB"))
        XCTAssertNil(store.load(for: PartyServer.productionURL))
        try store.delete(for: server)
        XCTAssertNil(store.load(for: server))
        XCTAssertNoThrow(try store.delete(for: server), "deleting twice is fine")
    }
}
