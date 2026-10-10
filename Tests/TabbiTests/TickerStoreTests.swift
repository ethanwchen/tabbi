import Combine
import SwiftUI
import XCTest
import TabbiKit
import TabbiKitCore
@testable import Tabbi

/// A module the ticker has never heard of, with one line to show.
@MainActor
private final class HighlightingModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "highlighting", title: "Highlighting", symbol: "star", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.5), highlightTitle: "Daily star"
    )
    static let line = TickerHighlight(id: "daily", source: "unset", text: "1 star left")

    init(context: ModuleContext) {}

    func makePanel() -> AnyView { AnyView(EmptyView()) }
    var provision: AnyPublisher<ModuleProvision, Never>? {
        Just(ModuleProvision(highlights: [Self.line])).eraseToAnyPublisher()
    }
}

@MainActor
final class TickerStoreTests: XCTestCase {
    private let kind = TickerKind.highlights(from: "highlighting")

    private func makeTicker() -> (TickerStore, SettingsStore, ClosedNotchPreview) {
        let settings = SettingsStore.ephemeral(catalog: ModuleCatalog([HighlightingModule.descriptor]))
        _ = settings.settings.modules.setEnabled("highlighting", true)
        let hub = ProviderHub()
        let shared = SharedServices()
        let module = HighlightingModule(context: ModuleContext(
            id: "highlighting", edition: .tabbi, settings: settings, providers: hub, shared: shared,
            runMode: .demo))
        hub.attach(ModuleRegistry([module]))
        hub.update(enabled: ["highlighting"])
        let ticker = TickerStore(settings: settings, providers: hub, preview: shared.closedNotchPreview)
        return (ticker, settings, shared.closedNotchPreview)
    }

    func testAModulesHighlightShowsWithNoTickerCode() {
        let (ticker, _, _) = makeTicker()
        var expected = HighlightingModule.line
        expected.source = "highlighting"
        XCTAssertEqual(ticker.item, .highlight(expected))
        XCTAssertEqual(ticker.item?.module, "highlighting")
    }

    func testTheUserCanTurnAModulesHighlightsOff() {
        let (ticker, settings, _) = makeTicker()
        settings.settings.notchPreview.setEnabled(kind, false)
        XCTAssertNil(ticker.item)
    }

    func testModulesLearnWhichPreviewsCanShowWhileTheNotchIsClosed() {
        let (ticker, settings, preview) = makeTicker()
        XCTAssertTrue(preview.watchedKinds.contains(kind))
        ticker.setActive(false)
        XCTAssertEqual(preview.watchedKinds, [], "Nothing shows while the notch is open")
        ticker.setActive(true)
        settings.settings.notchPreview.isEnabled = false
        XCTAssertEqual(preview.watchedKinds, [])
    }
}

/// A module with a pet to show, standing in for the Closet.
@MainActor
private final class PetModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .closet, title: "Pet", symbol: "pawprint", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.5)
    )
    static let presence = PetPresence(profile: .starter(.cat), lastActive: Date())

    init(context: ModuleContext) {}

    func makePanel() -> AnyView { AnyView(EmptyView()) }
    var provision: AnyPublisher<ModuleProvision, Never>? {
        Just(ModuleProvision(pet: Self.presence, highlights: [HighlightingModule.line])).eraseToAnyPublisher()
    }
}

/// A swipe down or a middle-click on the closed notch shows the next item.
@MainActor
final class TickerCycleTests: XCTestCase {
    private func makeTicker() -> TickerStore {
        let settings = SettingsStore.ephemeral(catalog: ModuleCatalog([PetModule.descriptor]))
        _ = settings.settings.modules.setEnabled(.closet, true)
        let hub = ProviderHub()
        let shared = SharedServices()
        let module = PetModule(context: ModuleContext(
            id: .closet, edition: .tabbi, settings: settings, providers: hub, shared: shared, runMode: .demo))
        hub.attach(ModuleRegistry([module]))
        hub.update(enabled: [.closet])
        return TickerStore(settings: settings, providers: hub, preview: shared.closedNotchPreview)
    }

    func testCyclingStepsThroughTheItemsAndWrapsAround() {
        let ticker = makeTicker()
        guard case .highlight = ticker.item else { return XCTFail("the highlight leads, got \(String(describing: ticker.item))") }
        XCTAssertTrue(ticker.cycle())
        guard case .pet = ticker.item else { return XCTFail("expected the pet, got \(String(describing: ticker.item))") }
        XCTAssertTrue(ticker.cycle())
        guard case .highlight = ticker.item else { return XCTFail("expected the highlight again") }
    }

    func testTheOpenNotchDoesNotCycle() {
        let ticker = makeTicker()
        let before = ticker.item
        ticker.setActive(false)
        XCTAssertFalse(ticker.cycle())
        XCTAssertEqual(ticker.item, before)
    }
}

/// A finished focus session's cheer takes the closed notch for a moment.
@MainActor
final class TickerCheerTests: XCTestCase {
    private func makeTicker(cheerStartedAt: Date) -> (TickerStore, CelebrationCenter) {
        let settings = SettingsStore.ephemeral(catalog: ModuleCatalog([PetModule.descriptor]))
        _ = settings.settings.modules.setEnabled(.closet, true)
        let hub = ProviderHub()
        let shared = SharedServices()
        let module = PetModule(context: ModuleContext(
            id: .closet, edition: .tabbi, settings: settings, providers: hub, shared: shared, runMode: .demo))
        hub.attach(ModuleRegistry([module]))
        hub.update(enabled: [.closet])
        let center = CelebrationCenter(hapticsEnabled: { false }, now: { cheerStartedAt })
        let ticker = TickerStore(settings: settings, providers: hub, preview: shared.closedNotchPreview,
                                 celebrations: center)
        return (ticker, center)
    }

    func testTheCheeringPetTakesTheNotch() {
        let (ticker, center) = makeTicker(cheerStartedAt: Date())
        let before = ticker.item
        XCTAssertNotNil(before)
        center.cheer(.dance, hasOwnSound: true)
        guard case .pet(let pet) = ticker.item else {
            return XCTFail("expected the cheering pet, got \(String(describing: ticker.item))")
        }
        XCTAssertEqual(pet.cheer?.kind, .dance)
        XCTAssertEqual(pet.profile, PetModule.presence.profile)
    }

    func testAnOverCheerLeavesTheRotationAlone() {
        let (ticker, center) = makeTicker(cheerStartedAt: Date().addingTimeInterval(-PetCheer.duration - 1))
        let before = ticker.item
        center.cheer(.dance)
        XCTAssertEqual(ticker.item, before)
    }

    func testAnOpenNotchShowsNoCheerLater() {
        let (ticker, center) = makeTicker(cheerStartedAt: Date())
        ticker.setActive(false)
        let before = ticker.item
        center.cheer(.dance)
        XCTAssertEqual(ticker.item, before, "the open notch hides the closed preview")
    }
}

/// A calendar with a call that starts in four minutes.
@MainActor
private final class MeetingModule: NotchModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: .planner, title: "Today", symbol: "calendar", category: .productivity,
        accent: ModuleAccent(red: 0.5, green: 0.5, blue: 0.9)
    )
    static let call = MeetingLink(provider: .zoom, url: URL(string: "https://zoom.us/j/1")!)

    init(context: ModuleContext) {}

    func makePanel() -> AnyView { AnyView(EmptyView()) }
    var provision: AnyPublisher<ModuleProvision, Never>? {
        let start = Date().addingTimeInterval(4 * 60)
        let standup = UpcomingEvent(id: "standup", title: "Standup", start: start,
                                    end: start.addingTimeInterval(15 * 60), meetingLink: Self.call)
        return Just(ModuleProvision(events: [standup])).eraseToAnyPublisher()
    }
}

@MainActor
final class TickerMeetingNudgeTests: XCTestCase {
    private func makeTicker(doNotDisturb: Bool) -> TickerStore {
        let settings = SettingsStore.ephemeral(catalog: ModuleCatalog([MeetingModule.descriptor]))
        _ = settings.settings.modules.setEnabled(.planner, true)
        let hub = ProviderHub()
        let shared = SharedServices()
        let module = MeetingModule(context: ModuleContext(
            id: .planner, edition: .tabbi, settings: settings, providers: hub, shared: shared, runMode: .demo))
        hub.attach(ModuleRegistry([module]))
        hub.update(enabled: [.planner])
        let center = CelebrationCenter(hapticsEnabled: { false }, isHushed: { doNotDisturb })
        return TickerStore(settings: settings, providers: hub, preview: shared.closedNotchPreview,
                           celebrations: center)
    }

    func testAMeetingAboutToStartGlowsWithAJoinButton() {
        guard case .meeting(let meeting) = makeTicker(doNotDisturb: false).item else {
            return XCTFail("expected the meeting preview")
        }
        XCTAssertTrue(meeting.isNudging)
        XCTAssertTrue(meeting.offersJoin)
        XCTAssertEqual(meeting.link, MeetingModule.call)
    }

    func testDoNotDisturbKeepsTheMeetingStill() {
        guard case .meeting(let meeting) = makeTicker(doNotDisturb: true).item else {
            return XCTFail("expected the meeting preview")
        }
        XCTAssertFalse(meeting.isNudging)
        XCTAssertTrue(meeting.offersJoin, "the Join button still helps")
    }
}
