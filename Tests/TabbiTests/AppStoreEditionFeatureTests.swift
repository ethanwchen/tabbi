import XCTest
import TabbiKitCore
@testable import Tabbi

/// A sandboxed App Store build can't run command line tools, so each
/// feature takes its sandboxed path instead of offering buttons that can't
/// work: Do Not Disturb runs through Shortcuts Events after macOS asks, AI
/// Usage reads the folders the user picks, and Today's and the Schedule's AI
/// features reach the AI through the provider the user picks (an API or
/// Ollama there). Party is the same as in the direct download.
@MainActor
final class AppStoreEditionFeatureTests: XCTestCase {
    private func context(_ id: ModuleID, edition: Edition) -> ModuleContext {
        ModuleContext(id: id, edition: edition, settings: SettingsStore.ephemeral(catalog: ModuleList.catalog),
                      providers: ProviderHub(), shared: SharedServices(), runMode: .demo)
    }

    private var appStore: Edition {
        get throws { try XCTUnwrap(Edition.named("appstore")) }
    }

    func testTheAppStoreEditionRunsDoNotDisturbThroughShortcutsEvents() throws {
        let focusMode = context(.focus, edition: try appStore).focusMode
        XCTAssertTrue(focusMode.offersDoNotDisturb)
        XCTAssertTrue(focusMode.needsShortcutsAccess, "macOS asks before the first shortcut runs")
        XCTAssertEqual(focusMode.shortcutsAccess, .granted, "demo runs show it ready")
        XCTAssertTrue(focusMode.doNotDisturb)
        XCTAssertTrue(ShortcutsEvents.runner(for: try appStore) is ShortcutsEvents.Runner)

        // The direct download runs `/usr/bin/shortcuts`; an App Store build is
        // sandboxed whatever edition it resolves to.
        let direct = context(.focus, edition: .tabbi).focusMode
        XCTAssertTrue(direct.offersDoNotDisturb)
        XCTAssertTrue(direct.doNotDisturb)
        #if APPSTORE
        XCTAssertTrue(direct.needsShortcutsAccess)
        XCTAssertTrue(ShortcutsEvents.runner(for: .tabbi) is ShortcutsEvents.Runner)
        #else
        XCTAssertFalse(direct.needsShortcutsAccess)
        XCTAssertNil(direct.shortcutsAccess)
        XCTAssertTrue(ShortcutsEvents.runner(for: .tabbi) is FocusShortcutRunner)
        #endif
    }

    func testCelebrationsAndModulesShareOneFocusModeBuiltForTheEdition() throws {
        // Whichever asks first, the celebrations or Focus, gets the same
        // focus mode, set up for the App Store's Shortcuts Events.
        let shared = SharedServices()
        let settings = SettingsStore.ephemeral(catalog: ModuleList.catalog)
        _ = shared.celebrations(settings: settings, runMode: .demo, edition: try appStore)
        let focus = ModuleContext(id: .focus, edition: try appStore, settings: settings, providers: ProviderHub(),
                                  shared: shared, runMode: .demo).focusMode
        XCTAssertTrue(focus.needsShortcutsAccess)
    }

    func testTheAppStoreEditionIsSandboxed() throws {
        XCTAssertTrue(try appStore.isSandboxed)
        #if APPSTORE
        XCTAssertTrue(Edition.tabbi.isSandboxed, "an App Store build is sandboxed whatever edition it resolves to")
        #else
        XCTAssertFalse(Edition.tabbi.isSandboxed)
        #endif
    }

    func testTheAppStoreEditionHasPartyWithItsAgeCheck() throws {
        let edition = try appStore
        XCTAssertTrue(ModuleList.catalog(for: edition).contains(.party))
        let party = PartyModule(context: context(.party, edition: edition))
        XCTAssertEqual(PartyModule.descriptor.setup, [.party], "onboarding asks about Party only when it is on")
        XCTAssertNotNil(party.makeSettingsPane(), "report, block and the friends server live there")
    }

    func testTheAppStoreEditionReadsAIUsageOnlyFromPickedFolders() throws {
        let module = ClaudeUsageModule(context: context(.claudeUsage, edition: try appStore))
        XCTAssertTrue(module.store.isSandboxed)
        XCTAssertEqual(module.makeSettingsPane()?.id, "aiUsage")
        let direct = ClaudeUsageModule(context: context(.claudeUsage, edition: .tabbi))
        #if APPSTORE
        XCTAssertTrue(direct.store.isSandboxed, "an App Store build is sandboxed whatever edition it resolves to")
        #else
        XCTAssertFalse(direct.store.isSandboxed)
        XCTAssertNil(direct.makeSettingsPane())
        #endif
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
