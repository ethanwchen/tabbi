import Foundation
@testable import TabbiKitCore

/// The modules Tabbi ships with, mirrored from the app's `ModuleList` so
/// core tests can resolve kits and layouts without the app target. The
/// app's own tests check the real list (`ModuleListTests`); this copy only
/// has to stay plausible.
extension ModuleCatalog {
    static let builtIn = ModuleCatalog([
        ModuleDescriptor(id: .spotify, title: "Now Playing", symbol: "music.note", category: .media,
                         accent: ModuleAccent(red: 0.12, green: 0.84, blue: 0.38), permissions: [.automation],
                         network: [ModuleNetworkAccess(host: "i.scdn.co", purpose: "Spotify album artwork")]),
        ModuleDescriptor(id: .system, title: "System", symbol: "cpu", category: .system,
                         accent: ModuleAccent(red: 0.35, green: 0.78, blue: 1.00)),
        ModuleDescriptor(id: .claudeUsage, title: "Claude Usage", symbol: "gauge.with.dots.needle.67percent",
                         category: .ai, accent: .claude, permissions: [.claudeCLI],
                         highlightTitle: "Claude usage above 80%"),
        ModuleDescriptor(id: .planner, title: "Today", symbol: "checklist", category: .productivity,
                         accent: ModuleAccent(red: 0.66, green: 0.55, blue: 1.00),
                         permissions: [.calendars, .notifications], kitSettings: TodayPlanSettings.kitSchema),
        ModuleDescriptor(id: .claudeAsk, title: "Ask Claude", symbol: "sparkles", category: .ai,
                         accent: .claude, permissions: [.claudeCLI]),
        ModuleDescriptor(id: .focus, title: "Focus", symbol: "hourglass", category: .productivity,
                         accent: ModuleAccent(red: 0.30, green: 0.84, blue: 0.76), permissions: [.notifications],
                         kitSettings: FocusSettings.kitSettings),
        ModuleDescriptor(id: .study, title: "Study", symbol: "timer", category: .study,
                         accent: ModuleAccent(red: 1.00, green: 0.62, blue: 0.26), ownsFocusClock: true,
                         kitSettings: KitSettingsSchema(StudyMethodMenu.kitSettingFields
                            .merging(["dailyGoalMinutes": StudyDailyGoal.kitSettingType]) { $1 })),
        ModuleDescriptor(id: .anki, title: "Anki", symbol: "rectangle.stack.fill", category: .study,
                         accent: ModuleAccent(red: 0.36, green: 0.62, blue: 1.00),
                         network: [ModuleNetworkAccess(host: "127.0.0.1", purpose: "your decks through AnkiConnect")]),
        ModuleDescriptor(id: .party, title: "Party", symbol: "person.3.fill", category: .study,
                         accent: ModuleAccent(red: 1.00, green: 0.42, blue: 0.62),
                         network: [ModuleNetworkAccess(host: "friends.example.com", purpose: "your presence and parties")]),
        ModuleDescriptor(id: .closet, title: "Closet", symbol: "pawprint.fill", category: .fun,
                         accent: ModuleAccent(red: 0.98, green: 0.80, blue: 0.30),
                         kitSettings: KitSettingsSchema(["coachLines": PetCoachMessages.kitSettingType,
                                                         "pet": PetProfile.kitSettingType])),
    ])
}

// Test-only shorthands that resolve against `ModuleCatalog.builtIn`. The
// production APIs take the catalog explicitly so a missed call site fails
// to compile.

extension ModuleLayout {
    /// The original five tabs with every other module parked switched off;
    /// the Productivity kit's layout.
    static let `default` = ModuleLayout(
        order: [.spotify, .system, .claudeUsage, .planner, .claudeAsk], disabled: []
    )

    init(order: [ModuleID], disabled: Set<ModuleID>) {
        self.init(order: order, disabled: disabled, catalog: .builtIn)
    }

    init(orderRawValues: [String], disabledRawValues: [String]) {
        self.init(orderRawValues: orderRawValues, disabledRawValues: disabledRawValues, catalog: .builtIn)
    }
}

extension KitManifest {
    func layout(answers: KitAnswers = [:]) -> ModuleLayout { layout(catalog: .builtIn, answers: answers) }
    func issues() -> [KitIssue] { issues(catalog: .builtIn) }
    func accentModule() -> ModuleID? { accentModule(catalog: .builtIn) }
}

extension AppSettings {
    static let `default` = AppSettings()

    init(
        kitID: String = KitLibrary.defaultKitID,
        hasChosenKit: Bool = false,
        kitAnswers: KitAnswers = [:],
        openOnHover: Bool = false,
        hapticsEnabled: Bool = true,
        launchAtLogin: Bool = false,
        hotkey: Hotkey = .default,
        claudePathOverride: String? = nil,
        preferredDisplay: DisplayPreference = .builtIn,
        notchPreview: NotchPreviewSettings = .default
    ) {
        self.init(kitID: kitID, hasChosenKit: hasChosenKit, kitAnswers: kitAnswers, modules: .default,
                  openOnHover: openOnHover, hapticsEnabled: hapticsEnabled, launchAtLogin: launchAtLogin,
                  hotkey: hotkey, claudePathOverride: claudePathOverride, preferredDisplay: preferredDisplay,
                  notchPreview: notchPreview)
    }

    mutating func apply(_ kit: KitManifest, answers: KitAnswers = [:]) {
        apply(kit, answers: answers, catalog: .builtIn)
    }

    func usesDefaults(of kit: KitManifest) -> Bool { usesDefaults(of: kit, catalog: .builtIn) }
}

extension SettingsRepository {
    init(defaults: UserDefaults = .standard, kits: KitLibrary = .bundled,
         defaultKitID: String = KitLibrary.defaultKitID) {
        self.init(defaults: defaults, catalog: .builtIn, kits: kits, defaultKitID: defaultKitID)
    }
}

extension TickerKind {
    /// Claude Usage's highlights.
    static let claudeUsage = TickerKind.highlights(from: .claudeUsage)
    /// Every kind the built-in catalog can show, in rotation order.
    static var allCases: [TickerKind] { all(in: .builtIn) }
}

extension NotchPreviewSettings {
    /// The built-in catalog's kinds the ticker may show.
    var enabledKinds: Set<TickerKind> { Set(TickerKind.allCases.filter(shows)) }
}

extension AppSettings {
    /// The built-in catalog's kinds the closed-notch preview may show.
    var previewKinds: Set<TickerKind> { Set(TickerKind.allCases.filter(showsPreview)) }
}

extension KitDefaults {
    var resolvedTicker: Set<TickerKind>? { resolvedTicker(catalog: .builtIn) }
}
