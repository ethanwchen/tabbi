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
    /// What the open notch shows instead of the tabs while
    /// `NotchViewModel.showsTakeover` is true, such as first-run onboarding;
    /// nil when the app has nothing of the kind.
    public var takeover: NotchTakeover?

    public init(
        appName: String,
        catalog: ModuleCatalog,
        panel: @escaping (ModuleID) -> AnyView,
        nowPlayingLeading: @escaping () -> AnyView,
        nowPlayingTrailing: @escaping () -> AnyView,
        openSettings: @escaping () -> Void,
        takeover: NotchTakeover? = nil
    ) {
        self.appName = appName
        self.catalog = catalog
        self.panel = panel
        self.nowPlayingLeading = nowPlayingLeading
        self.nowPlayingTrailing = nowPlayingTrailing
        self.openSettings = openSettings
        self.takeover = takeover
    }
}

/// A flow that fills the whole open notch for a while (first-run setup):
/// its own header wings beside the hardware notch and a body in the panel
/// canvas. The tab bar, tab keys and swipes pause until it ends, so the
/// notch itself is the setup surface and no extra window is needed.
@MainActor
public struct NotchTakeover {
    /// Left of the notch, where the tab bar usually sits.
    public var leading: () -> AnyView
    /// Right of the notch, where the tab's title usually sits.
    public var trailing: () -> AnyView
    /// The panel canvas below the header.
    public var body: () -> AnyView

    public init(leading: @escaping () -> AnyView, trailing: @escaping () -> AnyView, body: @escaping () -> AnyView) {
        self.leading = leading
        self.trailing = trailing
        self.body = body
    }
}
