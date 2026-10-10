import XCTest
import Combine
import TabbiKitCore
import TabbiKit
@testable import Tabbi

/// What a `tabbi://` link does once the app has it: an invite fills the
/// notch with Party's confirmation, the widget's link opens the notch, and
/// anything else is ignored.
@MainActor
final class AppLinkRouterTests: XCTestCase {
    private let types: [any NotchModule.Type] = [PartyModule.self, ClosetModule.self]

    private func makeRouter() -> (AppLinkRouter, AppServices, NotchViewModel) {
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog(of: types))
        let services = AppServices(settings: settings, moduleTypes: types,
                                   environment: ["TABBI_DEMO": "1"], arguments: [])
        let geometry = NotchGeometry(notchSize: CGSize(width: 185, height: 32), hasHardwareNotch: true,
                                     screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117), centerX: 864)
        let model = NotchViewModel(geometry: geometry, layout: ModuleLayout(catalog: settings.catalog))
        return (AppLinkRouter(services: services, notch: model), services, model)
    }

    func testAnInviteShowsPartysConfirmationInTheNotch() throws {
        let (router, services, _) = makeRouter()
        let party = try XCTUnwrap(services.modules.module(PartyModule.self))
        var takeover: [Bool] = []
        let subscription = ModuleViews.notchInputs(services: services).takeover.sink { takeover.append($0) }
        defer { subscription.cancel() }

        XCTAssertTrue(router.open(URL(string: "tabbi://add/ava7-k3rn")!))
        XCTAssertEqual(party.store.invite?.invite, .addFriend(code: "AVA7K3RN"))
        XCTAssertEqual(takeover.last, true, "the confirmation fills the open notch")

        party.store.dismissInvite()
        XCTAssertEqual(takeover.last, false)
    }

    func testTheWidgetLinkOpensTheNotch() {
        let (router, _, model) = makeRouter()
        XCTAssertTrue(router.open(URL(string: "tabbi://open")!))
        XCTAssertTrue(model.isOpen)
    }

    func testOtherLinksDoNothing() throws {
        let (router, services, model) = makeRouter()
        XCTAssertFalse(router.open(URL(string: "tabbi://add/NOPE")!))
        XCTAssertFalse(router.open(URL(string: "tabbi://settings")!))
        XCTAssertFalse(model.isOpen)
        XCTAssertNil(try XCTUnwrap(services.modules.module(PartyModule.self)).store.invite)
    }
}
