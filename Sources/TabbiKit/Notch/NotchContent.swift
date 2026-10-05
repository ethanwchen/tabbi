import SwiftUI
import TabbiKitCore

/// What an app plugs into the shared `NotchView`: the open panel for each
/// module, the music wings of the closed notch, and the Settings action.
/// Closures keep TabbiKit free of the app's module registry and services.
@MainActor
public struct NotchContent {
    /// The app or edition name shown in the Quit item and Settings tooltip.
    public var appName: String
    /// The modules this build has (from the app's registry): their titles,
    /// symbols and accents for the tab bar, previews and placeholders.
    public var catalog: ModuleCatalog
    /// The open panel for a module id; the app falls back to a placeholder
    /// for ids it has no module for.
    public var panel: (ModuleID) -> AnyView
    /// Left wing of the closed notch while music is the live activity.
    public var nowPlayingLeading: () -> AnyView
    /// Right wing of the closed notch while music is the live activity.
    public var nowPlayingTrailing: () -> AnyView
    /// Opens the app's Settings window (the notch closes first).
    public var openSettings: () -> Void
    /// Checks for a newer version of the app; nil hides "Check for Updates…"
    /// (development builds, demo and snapshot runs).
    public var checkForUpdates: (() -> Void)?

    public init(
        appName: String,
        catalog: ModuleCatalog,
        panel: @escaping (ModuleID) -> AnyView,
        nowPlayingLeading: @escaping () -> AnyView,
        nowPlayingTrailing: @escaping () -> AnyView,
        openSettings: @escaping () -> Void,
        checkForUpdates: (() -> Void)? = nil
    ) {
        self.appName = appName
        self.catalog = catalog
        self.panel = panel
        self.nowPlayingLeading = nowPlayingLeading
        self.nowPlayingTrailing = nowPlayingTrailing
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
    }
}
