import Combine
import SwiftUI
import NotchKitCore
import NotchKit

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

    /// Hooks the shared `NotchView` up to this app: registered module panels,
    /// the music wings and the Settings window.
    @MainActor
    static func notchContent(services: AppServices) -> NotchContent {
        NotchContent(
            appName: Edition.current.name,
            catalog: services.settings.catalog,
            panel: { services.modules.panel(for: $0) },
            nowPlayingLeading: { AnyView(compactLeading(services: services)) },
            nowPlayingTrailing: { AnyView(compactTrailing(services: services)) },
            openSettings: { services.openSettings() }
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
            previewVisible: { services.ticker.setActive($0) }
        )
    }
}
