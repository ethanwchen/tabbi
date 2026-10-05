import Combine
import SwiftUI
import XCTest
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
