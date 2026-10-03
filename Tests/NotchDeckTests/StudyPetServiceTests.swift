import Combine
import Foundation
import XCTest
import NotchKitCore
@testable import NotchDeck

/// The study pet has one owner, `context.studyPet` (the Closet's store):
/// every module gets the same instance, and Study and Party show the pet
/// through its `profiles` instead of reading the Closet's save.
@MainActor
final class StudyPetServiceTests: XCTestCase {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("study-pet-\(UUID().uuidString)")

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testEveryModuleSharesOnePet() {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        let shared = SharedServices()
        func context(_ id: ModuleID) -> ModuleContext {
            ModuleContext(id: id, edition: .notchDeck, settings: settings, providers: ProviderHub(), shared: shared,
                          runMode: .demo)
        }
        XCTAssertTrue(context(.closet).studyPet === context(.study).studyPet)
        XCTAssertTrue(context(.party).studyPet === context(.closet).studyPet)
    }

    func testProfilesFollowEditsAndKitStarters() {
        let store = ClosetStore(storage: EditionStorage(root: folder), runMode: .live, starter: .starter(.cat))
        var seen: [PetProfile] = []
        let subscription = store.profiles.sink { seen.append($0) }
        defer { subscription.cancel() }
        store.useStarter(.starter(.dog))
        store.rename("Waffles")
        XCTAssertEqual(seen.map(\.species), [.cat, .dog, .dog])
        XCTAssertEqual(seen.last?.name, "Waffles")
    }

    func testStudysCornerPetWearsTheSharedLook() {
        let pets = CurrentValueSubject<PetProfile, Never>(.starter(.cat))
        let store = StudyStore(storage: EditionStorage(root: folder), petProfile: pets.value,
                               runMode: RunMode(isDemo: false, isSnapshot: true))
        store.follow(pet: pets.eraseToAnyPublisher())
        let dressed = PetProfile(name: "Waffles", breed: .corgi, outfit: .none)
        pets.send(dressed)
        XCTAssertEqual(store.pet.profile, dressed)
    }

    func testStudysDemoKeepsItsSamplePet() {
        let store = StudyStore(storage: EditionStorage(root: folder), runMode: .demo)
        let sample = store.pet.profile
        store.follow(pet: Just(.starter(.dog)).eraseToAnyPublisher())
        XCTAssertEqual(store.pet.profile, sample)
    }

    func testPartySharesTheDressedPetWithFriends() {
        let store = PartyStore(runMode: .demo, environment: [:])
        let pets = PassthroughSubject<PetProfile, Never>()
        store.follow(pet: pets.eraseToAnyPublisher())
        pets.send(PetProfile.starter(.dog))
        XCTAssertEqual(store.pet, .starter(.dog))
    }
}
