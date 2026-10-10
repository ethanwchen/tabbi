import Combine
import SwiftUI
import TabbiKitCore
import TabbiKit

/// The closed notch's live-activity wings. Open panels come from each
/// module via `ModuleRegistry`.
enum ModuleViews {
    /// Left wing of the closed notch while a live activity is showing.
    @MainActor @ViewBuilder
    static func compactLeading(services: AppServices) -> some View {
        if let controller = services.modules.module(NowPlayingModule.self)?.controller {
            SpotifyCompactLeading(controller: controller)
        }
    }

    /// Right wing of the closed notch while a live activity is showing.
    @MainActor @ViewBuilder
    static func compactTrailing(services: AppServices) -> some View {
        if let controller = services.modules.module(NowPlayingModule.self)?.controller {
            SpotifyCompactTrailing(controller: controller)
        }
    }

    /// Hooks the shared `NotchView` up to this app: registered module panels
    /// (each a stage for celebrations, with the user's pet in their empty
    /// and error states), the music wings, the Settings window,
    /// first-run onboarding and the weekly recap.
    @MainActor
    static func notchContent(services: AppServices) -> NotchContent {
        NotchContent(
            appName: Edition.current.name,
            catalog: services.settings.catalog,
            panel: { id in
                AnyView(StatusPetProvider(providers: services.providers) {
                    services.modules.panel(for: id).celebrationStage(services.celebrations)
                })
            },
            nowPlayingLeading: { AnyView(compactLeading(services: services)) },
            nowPlayingTrailing: { AnyView(compactTrailing(services: services)) },
            openSettings: { services.openSettings() },
            takeover: AppTakeover.takeover(
                onboarding: OnboardingViews.takeover(store: services.onboarding, modules: services.modules,
                                                     providers: services.providers),
                store: services.onboarding, recaps: services.recaps, providers: services.providers),
            setNotchMode: { services.settings.settings.notchMode = $0 },
            checkForUpdates: checkForUpdates,
            suggestFeedback: { Feedback.open() },
            celebrations: services.celebrations,
            runAction: ModuleActionRunner { [weak services] module, action in
                services?.modules.perform(action, on: module)
            }
        )
    }

    /// "Check for Updates…" in the notch's context menu, while the updater
    /// runs. The App Store build has none: the App Store updates the app.
    @MainActor
    private static var checkForUpdates: (() -> Void)? {
        #if APPSTORE
        nil
        #else
        AppUpdater.shared.isAvailable ? { AppUpdater.shared.checkForUpdates() } : nil
        #endif
    }

    /// Hands panels (and onboarding) the shared pet (`ProviderSnapshot.pet`)
    /// as `statusPet`, following it as the user restyles or turns it off.
    struct StatusPetProvider<Content: View>: View {
        @ObservedObject var providers: ProviderHub
        @ViewBuilder let content: Content

        var body: some View {
            content.environment(\.statusPet, providers.snapshot.pet?.profile)
        }
    }

    /// Feeds `NotchController` the settings, hotkey recorder and ticker
    /// state it follows.
    @MainActor
    static func notchInputs(services: AppServices) -> NotchInputs {
        let store = services.settings
        return NotchInputs(
            settings: store.$settings.eraseToAnyPublisher(),
            currentSettings: { store.settings },
            isRecordingHotkey: store.$isRecordingHotkey.eraseToAnyPublisher(),
            hotkeyRegistered: { store.hotkeyIsRegistered = $0 },
            preview: services.ticker.$item.eraseToAnyPublisher(),
            previewVisible: { visible in
                services.ticker.setActive(visible)
                // The preview hides exactly when the notch opens.
                if !visible { services.recaps.notchOpened() }
            },
            takeover: AppTakeover.isActive(onboarding: services.onboarding, recaps: services.recaps)
        )
    }
}
