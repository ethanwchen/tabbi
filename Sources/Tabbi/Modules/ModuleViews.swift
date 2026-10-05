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
    /// (each a stage for celebrations), the music wings, the Settings window
    /// and first-run onboarding.
    @MainActor
    static func notchContent(services: AppServices) -> NotchContent {
        NotchContent(
            appName: Edition.current.name,
            catalog: services.settings.catalog,
            panel: { AnyView(services.modules.panel(for: $0).celebrationStage(services.celebrations)) },
            nowPlayingLeading: { AnyView(compactLeading(services: services)) },
            nowPlayingTrailing: { AnyView(compactTrailing(services: services)) },
            openSettings: { services.openSettings() },
            takeover: OnboardingViews.takeover(store: services.onboarding, modules: services.modules),
            checkForUpdates: AppUpdater.shared.isAvailable ? { AppUpdater.shared.checkForUpdates() } : nil,
            celebrations: services.celebrations
        )
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
            previewVisible: { services.ticker.setActive($0) },
            takeover: services.onboarding.$flow.map { $0 != nil }.eraseToAnyPublisher()
        )
    }
}
