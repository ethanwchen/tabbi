import XCTest
import NotchKitCore

/// The party a Party module shares with the rest of the app, and the
/// closed-notch preview built from it.
final class PartyProvisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func profile(_ code: String, _ name: String, breed: String = "tabby") -> PartyProfile {
        PartyProfile(code: code, name: name, petName: name, species: breed == "corgi" ? "dog" : "cat", breed: breed)
    }

    private func member(_ code: String, _ name: String, host: Bool = false, online: Bool = true,
                        breed: String = "tabby") -> PartyMember {
        PartyMember(profile: profile(code, name, breed: breed), joinedAt: now, host: host,
                    presence: PartyPresence(status: .studying, day: "2026-09-21", lastSeen: now), online: online)
    }

    private func party(_ members: [PartyMember]) -> Party {
        Party(code: "Q4RT8M", host: members.first { $0.host }?.profile.code ?? "", createdAt: now, lastActive: now,
              expiresAt: now.addingTimeInterval(3600), maxMembers: 8, session: nil, members: members)
    }

    private func pet(_ id: String) -> ProvidedPartyPet {
        ProvidedPartyPet(id: id, name: id, pet: .starter(.cat))
    }

    func testProvidesMyPetFirstThenOthersAndOfflineMembersDoze() throws {
        let me = profile("ME0000", "Ana")
        let state = PartyState(profile: me, friends: [], party: party([
            member("HOST00", "Zoe", host: true, breed: "corgi"),
            member("ME0000", "Ana"),
            member("AWAY00", "Bo", online: false),
        ]))

        let provided = try XCTUnwrap(state.provided)
        XCTAssertEqual(provided.pets.map(\.name), ["Ana", "Zoe", "Bo"])
        XCTAssertEqual(provided.pets.map(\.isAway), [false, false, true])
        XCTAssertEqual(provided.pets[1].pet, PartyPetAppearance.pet(for: profile("HOST00", "Zoe", breed: "corgi")))
        XCTAssertEqual(provided.memberCount, 3)
    }

    func testProvidesNothingOutsideAParty() {
        let state = PartyState(profile: profile("ME0000", "Ana"), friends: [], party: nil)
        XCTAssertNil(state.provided)
        XCTAssertNil(PartyState(settings: PartySettings()).provided)
    }

    func testSnapshotKeepsTheFirstPartyInTabOrder() {
        let first = ProvidedParty(pets: [pet("a"), pet("b")])
        let snapshot = ProviderSnapshot([
            (.planner, ModuleProvision()),
            (.party, ModuleProvision(party: first)),
            (ModuleID("other"), ModuleProvision(party: ProvidedParty(pets: [pet("c")]))),
        ])
        XCTAssertEqual(snapshot.party, first)
    }

    func testTickerShowsPartyPetsOnlyWithCompany() {
        let alone = TickerSources(party: ProvidedParty(pets: [pet("me")]))
        XCTAssertTrue(alone.items(at: now).isEmpty, "a party of one has no pets to show beside mine")

        let pair = TickerSources(party: ProvidedParty(pets: [pet("me"), pet("zoe")]))
        XCTAssertEqual(pair.items(at: now), [.party(TickerParty(pets: [pet("me"), pet("zoe")], memberCount: 2))])
        XCTAssertEqual(pair.items(at: now).first?.kind.module, .party)
        XCTAssertTrue(pair.items(at: now, enabled: [.focus]).isEmpty)
        XCTAssertNil(pair.nextChange(after: now), "party pets never need a clock")
    }

    func testTickerCapsPetsButCountsEveryone() {
        let ids = (0..<8).map { "m\($0)" }
        let sources = TickerSources(party: ProvidedParty(pets: ids.map(pet)))
        guard case .party(let party) = sources.items(at: now).first else { return XCTFail("expected a party item") }
        XCTAssertEqual(party.pets.map(\.id), Array(ids.prefix(TickerParty.maxPets)))
        XCTAssertEqual(party.memberCount, 8)
        XCTAssertEqual(TickerFormat.partySize(party.memberCount), "8 in party")
    }
}
