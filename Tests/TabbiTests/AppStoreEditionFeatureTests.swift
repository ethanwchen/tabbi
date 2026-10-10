import XCTest
import TabbiKitCore
@testable import Tabbi

/// A sandboxed App Store build can't run command line tools or Shortcuts,
/// so focus mode hides what needs them instead of offering buttons that
/// can't work. Today's and the Schedule's AI features stay, since they
/// reach the AI through the provider the user picks (an API or Ollama there).
@MainActor
final class AppStoreEditionFeatureTests: XCTestCase {
    private func context(_ id: ModuleID, edition: Edition) -> ModuleContext {
        ModuleContext(id: id, edition: edition, settings: SettingsStore.ephemeral(catalog: ModuleList.catalog),
                      providers: ProviderHub(), shared: SharedServices(), runMode: .demo)
    }

    private var appStore: Edition {
        get throws { try XCTUnwrap(Edition.named("appstore")) }
    }

    func testTheAppStoreEditionHidesDoNotDisturb() throws {
        let focusMode = context(.focus, edition: try appStore).focusMode
        XCTAssertFalse(focusMode.offersDoNotDisturb)
        XCTAssertTrue(focusMode.settings.doNotDisturb, "the demo settings have it on")
        XCTAssertFalse(focusMode.doNotDisturb, "but focus phases never turn it on")

        let direct = context(.focus, edition: .tabbi).focusMode
        XCTAssertTrue(direct.offersDoNotDisturb)
        XCTAssertTrue(direct.doNotDisturb)
    }

    func testBothEditionsOfferToRefineAPlanWithTheirAI() throws {
        XCTAssertTrue(ScheduleModule(context: context(.schedule, edition: try appStore)).store.aiReady)
        XCTAssertTrue(ScheduleModule(context: context(.schedule, edition: .tabbi)).store.aiReady)
        XCTAssertTrue(TodayModule(context: context(.planner, edition: try appStore)).store.plan.canRefine)
    }

    func testTheAppStoreEditionOffersAskThroughSandboxedProvidersOnly() throws {
        let edition = try appStore
        XCTAssertTrue(ModuleList.catalog(for: edition).contains(.claudeAsk))
        let store = SettingsStore.ephemeral(catalog: ModuleList.catalog(for: edition))
        let ai = AIService(settings: store, keys: InMemoryAIKeyStore(), sandboxed: true)
        XCTAssertEqual(ai.availableProviders, [.anthropic, .openAI, .gemini, .ollama])
        // A Claude Code choice saved before (say, by the direct download)
        // counts as no choice, so Ask shows its setup state and sends nothing.
        store.settings.ai.choose(.claudeCLI)
        XCTAssertEqual(ai.setupState, .notChosen)
        XCTAssertNil(ai.provider)
        store.settings.ai.choose(.ollama)
        XCTAssertEqual(ai.setupState, .ready(.ollama))
        XCTAssertNotNil(ai.provider)
    }

    func testTheAppStoreEditionNeverOffersSoundCloud() throws {
        let appStoreModule = NowPlayingModule(context: context(.spotify, edition: try appStore))
        XCTAssertFalse(appStoreModule.controller.allowsBrowsers, "no Automation of Safari or Chrome")
        XCTAssertNil(appStoreModule.makeSettingsPane(), "so there is no SoundCloud switch to show")

        let direct = NowPlayingModule(context: context(.spotify, edition: .tabbi))
        XCTAssertTrue(direct.controller.allowsBrowsers)
        XCTAssertEqual(direct.makeSettingsPane()?.id, "nowPlaying")
    }

    func testWrapUpShowsTheLocalSummaryAtOnceWithoutAnAI() {
        let review = DayReviewStore(storage: EditionStorage(root: FileManager.default.temporaryDirectory),
                                    ai: nil, runMode: .demo)
        review.wrapUp(day: .sample(on: PlannerDayKey(date: Date()), kind: .work), activity: [])
        XCTAssertTrue(review.isActive)
        XCTAssertFalse(review.isSummarizing, "no shimmer waiting for an AI")
    }
}
