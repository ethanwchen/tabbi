import SwiftUI
import NotchKitCore

/// Maps each module to its views. Every panel is laid out inside the same
/// fixed canvas (see `Theme.Layout.expandedSize`), already inset by the notch.
enum ModuleViews {
    @MainActor @ViewBuilder
    static func panel(for module: ModuleID, services: AppServices) -> some View {
        switch module {
        case .spotify: SpotifyPanel(controller: services.spotify)
        case .system: SystemPanel(monitor: services.system)
        case .claudeUsage: ClaudeUsagePanel(store: services.claudeUsage)
        case .planner: PlannerPanel(store: services.planner)
        case .claudeAsk: ClaudeAskPanel(session: services.claudeAsk)
        case .study: StudyPanel()
        case .anki: AnkiPanel()
        case .party: PartyPanel()
        case .closet: ClosetPanel()
        default: ModulePlaceholder(module: module, detail: "This module isn't available in this build")
        }
    }

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
}
