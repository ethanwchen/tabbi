import Combine
import XCTest
import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// The notch's one takeover slot: onboarding first, then a Party invite's
/// confirmation, then the weekly recap.
@MainActor
final class AppTakeoverTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func tearDown() async throws {
        cancellables = []
    }

    func testOnboardingThenTheInviteThenTheRecap() throws {
        let recap = try XCTUnwrap(RecapArchive.demo(now: Date()).recaps.first)
        let shown = RecapMoment.Shown(recap: recap, cheer: .bestYet)
        XCTAssertNil(AppTakeover.owner(onboarding: false, invite: false, recap: nil))
        XCTAssertEqual(AppTakeover.owner(onboarding: false, invite: false, recap: shown), .recap(shown))
        XCTAssertEqual(AppTakeover.owner(onboarding: false, invite: true, recap: shown), .invite)
        XCTAssertEqual(AppTakeover.owner(onboarding: true, invite: true, recap: shown), .onboarding)
        XCTAssertEqual(AppTakeover.owner(onboarding: true, invite: false, recap: nil), .onboarding)
    }

    func testAnInviteHoldsTheSlotAndTheRecapWaitsForTheNextOpen() throws {
        let types: [any NotchModule.Type] = [ClosetModule.self, PartyModule.self]
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types, environment: ["TABBI_DEMO": "1"],
                                   arguments: [])
        let party = try XCTUnwrap(services.modules.module(PartyModule.self))
        let inputs = ModuleViews.notchInputs(services: services)
        var states: [Bool] = []
        inputs.takeover.removeDuplicates().sink { states.append($0) }.store(in: &cancellables)

        party.store.open(.addFriend(code: PartyProfile.demoInvitee.code), partyIsOn: true)
        XCTAssertEqual(states, [false, true], "The invite takes over the notch")

        inputs.previewVisible(false) // the notch opened
        XCTAssertNil(services.recaps.shown, "The recap never interrupts an invite")
        XCTAssertNotNil(services.recaps.store.unseen, "Still unseen for later")

        party.store.dismissInvite()
        XCTAssertEqual(states, [false, true, false])
        inputs.previewVisible(true)
        inputs.previewVisible(false)
        XCTAssertNotNil(services.recaps.shown, "The next open shows the recap")
        XCTAssertEqual(states, [false, true, false, true])
    }
}
