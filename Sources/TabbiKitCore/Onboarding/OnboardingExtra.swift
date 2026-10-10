/// One line on onboarding's last screen, "A few extras": something optional
/// that is easy to miss (the desktop widget, the daily reminder, invite
/// links, syncing the pet), said in a line, with nothing to answer. Every
/// extra shares that one screen, so introducing a new one never makes
/// onboarding longer.
public struct OnboardingExtra: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// One short line: what it is and where to find it.
    public let detail: String
    /// SF Symbol for the row.
    public let symbol: String
    /// The tab the extra lives in; the row shows only while that tab is on.
    /// Nil for app-wide extras.
    public let module: ModuleID?

    public init(_ id: String, title: String, detail: String, symbol: String, module: ModuleID? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.module = module
    }
}

public extension OnboardingExtra {
    /// The pet, streak and focus clock on the desktop.
    static let widget = OnboardingExtra("widget", title: "Desktop widget",
                                        detail: "Right-click the desktop, Edit Widgets.",
                                        symbol: "rectangle.on.rectangle")
    /// The pet's once-a-day nudge, off until the user turns it on.
    static let reminder = OnboardingExtra("reminder", title: "Daily reminder",
                                          detail: "A daily nudge, in Closet options.",
                                          symbol: "bell.badge", module: .closet)
    /// A link a friend opens to add you or join a party in one click.
    static let invites = OnboardingExtra("invites", title: "Invite links",
                                         detail: "Share a link from Party.",
                                         symbol: "link", module: .party)
    /// The optional Sign in with Apple account that syncs the pet.
    static let sync = OnboardingExtra("sync", title: "Sync your pet",
                                      detail: "Optional, with your Apple Account.",
                                      symbol: "arrow.triangle.2.circlepath")

    /// Every extra, in the order the screen lists them.
    static let all: [OnboardingExtra] = [.widget, .reminder, .invites, .sync]
}
