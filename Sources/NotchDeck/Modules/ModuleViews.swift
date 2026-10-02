import SwiftUI
import NotchKitCore
import NotchKit

/// The closed notch's live-activity wings. Open panels come from each
/// module via `ModuleRegistry`.
enum ModuleViews {
    /// Left wing of the closed notch while a live activity is showing.
    @MainActor @ViewBuilder
    static func compactLeading(services: AppServices) -> some View {
        SpotifyCompactLeading(controller: services.spotify)
    }

    /// Right wing of the closed notch while a live activity is showing.
    @MainActor @ViewBuilder
    static func compactTrailing(services: AppServices) -> some View {
        SpotifyCompactTrailing(controller: services.spotify)
    }

    /// Hooks the shared `NotchView` up to this app: registered module panels,
    /// the music wings and the Settings window.
    @MainActor
    static func notchContent(services: AppServices) -> NotchContent {
        NotchContent(
            appName: Edition.current.name,
            panel: { services.modules.panel(for: $0) },
            nowPlayingLeading: { AnyView(compactLeading(services: services)) },
            nowPlayingTrailing: { AnyView(compactTrailing(services: services)) },
            openSettings: { services.openSettings() }
        )
    }
}
