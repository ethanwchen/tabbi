import Foundation

/// Every user preference Tabbi has, as one value.
public struct AppSettings: Equatable, Sendable {
    /// The user's name, kept as typed so the field round-trips. Party shows
    /// it to friends and Tabbi greets the user with it; `cleanedDisplayName`
    /// is the form they use. Blank means no name yet.
    public var displayName: String
    /// The kit the user (or edition) picked. Its layout seeds `modules`, and
    /// "reset to kit defaults" goes back to it.
    public var kitID: String
    /// False until the user picks a kit, so the first launch can ask which
    /// kit to start from. Settings saved before kits existed count as picked.
    public var hasChosenKit: Bool
    /// The user's answers to the kit's onboarding questions, kept so "reset
    /// to kit defaults" rebuilds the tabs those answers chose.
    public var kitAnswers: KitAnswers
    public var modules: ModuleLayout
    /// When on, resting the pointer on the closed notch for `hoverOpenDelay` opens it.
    public var openOnHover: Bool
    public var hapticsEnabled: Bool
    /// A soft sound under celebrations that have none of their own (an
    /// unlock, a streak milestone).
    public var celebrationSoundEnabled: Bool
    /// The weekly recap: built every Sunday evening from the activity log
    /// and shown once in the open notch. Off means no card and no building.
    public var weeklyRecapEnabled: Bool
    /// Mirrors the user's choice; the source of truth is `SMAppService.mainApp.status`.
    public var launchAtLogin: Bool
    public var hotkey: Hotkey
    /// Explicit path to the `claude` binary; `nil` means auto-discover.
    public var claudePathOverride: String? {
        didSet { claudePathOverride = Self.normalizedPath(claudePathOverride) }
    }
    public var preferredDisplay: DisplayPreference
    /// When off, the notch only appears on a built-in display (see `NotchVisibility`).
    public var showOnExternalDisplays: Bool
    /// When on, the notch steps aside while an app is fullscreen on its screen.
    public var hideInFullscreen: Bool
    /// When on, the notch is left out of screenshots, recordings and shared
    /// screens (`NSWindow.sharingType = .none`), so a student sharing their
    /// screen in class doesn't show their tabs. Off by default.
    public var hideFromScreenCapture: Bool
    /// When on, the notch steps aside while Mission Control is open instead
    /// of staying drawn over the spaces. Off by default.
    public var hideInMissionControl: Bool
    /// Whether the closed notch is always drawn, only on hover, or only
    /// after the global shortcut (see `NotchVisibility.isShown`).
    public var notchMode: NotchMode
    /// The size of the open notch, the same for every tab.
    public var panelSize: PanelSize
    /// How lively animations are (`MotionPace`). Reduce Motion in System
    /// Settings still calms Smooth and Fast to a short crossfade.
    public var motionPace: MotionPace
    public var notchPreview: NotchPreviewSettings
    /// The look of the open panel. Kept as saved even when this build lacks
    /// it (a theme from a newer Tabbi); `ThemeCatalog.resolve` draws the
    /// default then.
    public var themeID: ThemeID
    /// The AI provider and models for Ask AI, Plan my day, Day review and
    /// Refine. API keys live in the Keychain (`AIKeyStore`), never here.
    public var ai: AISettings

    /// How long the pointer must rest on the closed notch before hover-to-open fires.
    public static let hoverOpenDelay: Duration = .milliseconds(250)

    /// - Parameter modules: the tab layout; there is no default because
    ///   the modules a build has come from its module registry.
    public init(
        displayName: String = "",
        kitID: String = KitLibrary.defaultKitID,
        hasChosenKit: Bool = false,
        kitAnswers: KitAnswers = [:],
        modules: ModuleLayout,
        openOnHover: Bool = false,
        hapticsEnabled: Bool = true,
        celebrationSoundEnabled: Bool = true,
        weeklyRecapEnabled: Bool = true,
        launchAtLogin: Bool = false,
        hotkey: Hotkey = .default,
        claudePathOverride: String? = nil,
        preferredDisplay: DisplayPreference = .builtIn,
        showOnExternalDisplays: Bool = true,
        hideInFullscreen: Bool = true,
        hideFromScreenCapture: Bool = false,
        hideInMissionControl: Bool = false,
        notchMode: NotchMode = .default,
        panelSize: PanelSize = .default,
        motionPace: MotionPace = .default,
        notchPreview: NotchPreviewSettings = .default,
        themeID: ThemeID = ThemeCatalog.defaultID,
        ai: AISettings = AISettings()
    ) {
        self.displayName = displayName
        self.kitID = kitID
        self.hasChosenKit = hasChosenKit
        self.kitAnswers = kitAnswers
        self.modules = modules
        self.openOnHover = openOnHover
        self.hapticsEnabled = hapticsEnabled
        self.celebrationSoundEnabled = celebrationSoundEnabled
        self.weeklyRecapEnabled = weeklyRecapEnabled
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
        self.claudePathOverride = Self.normalizedPath(claudePathOverride)
        self.preferredDisplay = preferredDisplay
        self.showOnExternalDisplays = showOnExternalDisplays
        self.hideInFullscreen = hideInFullscreen
        self.hideFromScreenCapture = hideFromScreenCapture
        self.hideInMissionControl = hideInMissionControl
        self.notchMode = notchMode
        self.panelSize = panelSize
        self.motionPace = motionPace
        self.notchPreview = notchPreview
        self.themeID = themeID
        self.ai = ai
    }

    /// The name as Party and greetings use it (`DisplayName.cleaned`), or
    /// nil when the user has not given one.
    public var cleanedDisplayName: String? { DisplayName.cleaned(displayName) }

    /// Whether the closed-notch preview may show `kind`: the user's preview
    /// choices, minus items whose module is turned off, since clicking one
    /// would open a tab that isn't there.
    public func showsPreview(_ kind: TickerKind) -> Bool {
        notchPreview.shows(kind) && (kind.module.map(modules.isEnabled) ?? true)
    }

    /// Switches to `kit`: replaces the tab layout with the one it produces
    /// for `answers`, and the closed-notch previews with the kit's when it
    /// lists any, and the theme with the kit's when it names one this build
    /// has. Used both to switch kits and to reset to the current kit's
    /// defaults; other preferences are kept. Either way the user has now
    /// picked a kit.
    public mutating func apply(_ kit: KitManifest, answers: KitAnswers = [:], catalog: ModuleCatalog) {
        kitID = kit.id
        hasChosenKit = true
        kitAnswers = answers
        modules = kit.layout(catalog: catalog, answers: answers)
        if let kinds = kit.defaults.resolvedTicker(catalog: catalog) {
            notchPreview.disabledKinds = Set(TickerKind.all(in: catalog)).subtracting(kinds)
        }
        if let theme = kit.defaults.theme.flatMap(ThemeCatalog.id(forKitValue:)) {
            themeID = theme
        }
    }

    /// The preferences a kit sets (`apply(_:answers:catalog:)`), so undoing
    /// a kit switch puts back only these and keeps everything the user
    /// changed elsewhere since (hotkey, hover, launch at login).
    public struct KitState: Equatable, Sendable {
        public var kitID: String
        public var hasChosenKit: Bool
        public var kitAnswers: KitAnswers
        public var modules: ModuleLayout
        public var disabledPreviews: Set<TickerKind>
        public var themeID: ThemeID
    }

    public var kitState: KitState {
        get {
            KitState(kitID: kitID, hasChosenKit: hasChosenKit, kitAnswers: kitAnswers,
                     modules: modules, disabledPreviews: notchPreview.disabledKinds, themeID: themeID)
        }
        set {
            kitID = newValue.kitID
            hasChosenKit = newValue.hasChosenKit
            kitAnswers = newValue.kitAnswers
            modules = newValue.modules
            notchPreview.disabledKinds = newValue.disabledPreviews
            themeID = newValue.themeID
        }
    }

    /// True when `kit` is the active kit and the tabs (and previews, if the
    /// kit sets them) and theme (likewise) are still exactly the ones it produces for the saved
    /// answers, so "Reset to kit defaults" would change nothing here.
    public func usesDefaults(of kit: KitManifest, catalog: ModuleCatalog) -> Bool {
        var reset = self
        reset.apply(kit, answers: kitAnswers, catalog: catalog)
        return kitID == kit.id && reset.modules == modules && reset.notchPreview == notchPreview
            && reset.themeID == themeID
    }

    /// Puts General's settings back to how a fresh install has them, with
    /// the live activity items `kit` picks (all of them without a kit or when
    /// it names none). Launch at login is kept: it is a system login item the
    /// user turned on deliberately, and turning it off silently would surprise.
    /// So is the user's name, which is who they are rather than a preference.
    /// Tabs, theme and the AI provider belong to other sections.
    public mutating func resetGeneral(to kit: KitManifest?, catalog: ModuleCatalog) {
        let fresh = AppSettings(modules: modules)
        openOnHover = fresh.openOnHover
        hapticsEnabled = fresh.hapticsEnabled
        celebrationSoundEnabled = fresh.celebrationSoundEnabled
        weeklyRecapEnabled = fresh.weeklyRecapEnabled
        hotkey = fresh.hotkey
        preferredDisplay = fresh.preferredDisplay
        showOnExternalDisplays = fresh.showOnExternalDisplays
        hideInFullscreen = fresh.hideInFullscreen
        hideFromScreenCapture = fresh.hideFromScreenCapture
        hideInMissionControl = fresh.hideInMissionControl
        notchMode = fresh.notchMode
        panelSize = fresh.panelSize
        motionPace = fresh.motionPace
        notchPreview = fresh.notchPreview
        if let kinds = kit?.defaults.resolvedTicker(catalog: catalog) {
            notchPreview.disabledKinds = Set(TickerKind.all(in: catalog)).subtracting(kinds)
        }
    }

    /// True when General's "Reset to Defaults" would change nothing.
    public func usesGeneralDefaults(of kit: KitManifest?, catalog: ModuleCatalog) -> Bool {
        var reset = self
        reset.resetGeneral(to: kit, catalog: catalog)
        return reset == self
    }

    /// The theme Look's "Reset to Default" picks: `kit`'s when it names one
    /// this build has, else the app's default.
    public static func defaultTheme(for kit: KitManifest?) -> ThemeID {
        kit?.defaults.theme.flatMap(ThemeCatalog.id(forKitValue:)) ?? ThemeCatalog.defaultID
    }

    /// Trims whitespace and expands `~`; blank means "no override".
    static func normalizedPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return (trimmed as NSString).expandingTildeInPath
    }
}

/// Loads and saves `AppSettings` in `UserDefaults`.
///
/// Each preference lives under its own key so a single malformed value falls
/// back to its default instead of resetting everything. Pass a dedicated suite
/// in tests.
///
/// With no saved tab layout (first run), the layout comes from the saved or
/// default kit, so a branded edition opens on its own kit's tabs.
///
/// Loading first brings the stored keys up to `SettingsSchema.current`.
/// Saving keeps the stored position and on/off state of modules this build
/// doesn't know, so they come back where they were in a build that has them.
public struct SettingsRepository {
    enum Key {
        static let displayName = "settings.displayName"
        static let kitID = "settings.kit"
        static let hasChosenKit = "settings.kit.chosen"
        static let kitAnswers = "settings.kit.answers"
        static let moduleOrder = "settings.modules.order"
        static let disabledModules = "settings.modules.disabled"
        static let openOnHover = "settings.openOnHover"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let celebrationSoundEnabled = "settings.celebrationSoundEnabled"
        static let weeklyRecapEnabled = "settings.weeklyRecapEnabled"
        static let launchAtLogin = "settings.launchAtLogin"
        static let hotkey = "settings.hotkey"
        static let claudePathOverride = "settings.claudePathOverride"
        static let preferredDisplay = "settings.preferredDisplay"
        static let showOnExternalDisplays = "settings.showOnExternalDisplays"
        static let hideInFullscreen = "settings.hideInFullscreen"
        static let hideFromScreenCapture = "settings.hideFromScreenCapture"
        static let hideInMissionControl = "settings.hideInMissionControl"
        static let notchMode = "settings.notchMode"
        static let panelSize = "settings.panelSize"
        static let motionPace = "settings.motionPace"
        static let previewEnabled = "settings.preview.enabled"
        static let previewDisabledKinds = "settings.preview.disabledKinds"
        static let previewInterval = "settings.preview.interval"
        static let theme = "settings.theme"
        static let aiProvider = "settings.ai.provider"
        static let aiModels = "settings.ai.models"
    }

    private let defaults: UserDefaults
    private let catalog: ModuleCatalog
    private let kits: KitLibrary
    private let defaultKitID: String

    /// - Parameters:
    ///   - catalog: the modules this build has (from its module registry);
    ///     saved ids it doesn't know are skipped.
    ///   - kits: the kits a saved kit id is resolved against.
    ///   - defaultKitID: the kit used before the user picks one, e.g. the
    ///     edition's kit.
    public init(
        defaults: UserDefaults = .standard,
        catalog: ModuleCatalog,
        kits: KitLibrary = .bundled,
        defaultKitID: String = KitLibrary.defaultKitID
    ) {
        self.defaults = defaults
        self.catalog = catalog
        self.kits = kits
        self.defaultKitID = defaultKitID
    }

    public func load() -> AppSettings {
        SettingsSchema.migrate(defaults)
        let fallback = AppSettings(modules: ModuleLayout(catalog: catalog))
        let hotkey = defaults.data(forKey: Key.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
        // An unknown saved id (an imported kit that was removed) falls back
        // to the default kit.
        let kit = kits.kit(defaults.string(forKey: Key.kitID) ?? defaultKitID)
        let savedOrder = defaults.stringArray(forKey: Key.moduleOrder)
        let modules = savedOrder.map {
            ModuleLayout(orderRawValues: $0, disabledRawValues: defaults.stringArray(forKey: Key.disabledModules) ?? [],
                         catalog: catalog)
        }
        return AppSettings(
            displayName: defaults.string(forKey: Key.displayName) ?? fallback.displayName,
            kitID: kit?.id ?? defaultKitID,
            hasChosenKit: bool(Key.hasChosenKit) ?? false,
            kitAnswers: (defaults.dictionary(forKey: Key.kitAnswers) as? [String: [String]])?
                .mapValues(Set.init) ?? [:],
            modules: modules ?? kit?.layout(catalog: catalog) ?? fallback.modules,
            openOnHover: bool(Key.openOnHover) ?? fallback.openOnHover,
            hapticsEnabled: bool(Key.hapticsEnabled) ?? fallback.hapticsEnabled,
            celebrationSoundEnabled: bool(Key.celebrationSoundEnabled) ?? fallback.celebrationSoundEnabled,
            weeklyRecapEnabled: bool(Key.weeklyRecapEnabled) ?? fallback.weeklyRecapEnabled,
            launchAtLogin: bool(Key.launchAtLogin) ?? fallback.launchAtLogin,
            hotkey: hotkey ?? fallback.hotkey,
            claudePathOverride: defaults.string(forKey: Key.claudePathOverride),
            preferredDisplay: defaults.string(forKey: Key.preferredDisplay)
                .flatMap(DisplayPreference.init(storageValue:)) ?? fallback.preferredDisplay,
            showOnExternalDisplays: bool(Key.showOnExternalDisplays) ?? fallback.showOnExternalDisplays,
            hideInFullscreen: bool(Key.hideInFullscreen) ?? fallback.hideInFullscreen,
            hideFromScreenCapture: bool(Key.hideFromScreenCapture) ?? fallback.hideFromScreenCapture,
            hideInMissionControl: bool(Key.hideInMissionControl) ?? fallback.hideInMissionControl,
            notchMode: defaults.string(forKey: Key.notchMode).flatMap(NotchMode.init(rawValue:)) ?? fallback.notchMode,
            panelSize: defaults.string(forKey: Key.panelSize).flatMap(PanelSize.init(rawValue:)) ?? fallback.panelSize,
            motionPace: defaults.string(forKey: Key.motionPace).flatMap(MotionPace.init(rawValue:)) ?? fallback.motionPace,
            notchPreview: NotchPreviewSettings(
                isEnabled: bool(Key.previewEnabled) ?? fallback.notchPreview.isEnabled,
                // Unknown raw values (a kind removed in a later version) are dropped.
                disabledKinds: Set((defaults.stringArray(forKey: Key.previewDisabledKinds) ?? [])
                    .map(TickerKind.init(rawValue:))),
                interval: (defaults.object(forKey: Key.previewInterval) as? Int)
                    .flatMap(TickerInterval.init(rawValue:)) ?? fallback.notchPreview.interval
            ),
            // Before the user picks one, the kit's theme.
            themeID: defaults.string(forKey: Key.theme).map(ThemeID.init(rawValue:))
                ?? kit?.defaults.theme.flatMap(ThemeCatalog.id(forKitValue:)) ?? fallback.themeID,
            ai: AISettings(
                provider: defaults.string(forKey: Key.aiProvider).flatMap(AIProviderID.init(rawValue:)),
                // Entries for providers this build doesn't know are dropped.
                models: Dictionary(uniqueKeysWithValues: ((defaults.dictionary(forKey: Key.aiModels) as? [String: String]) ?? [:])
                    .compactMap { key, value in AIProviderID(rawValue: key).map { ($0, value) } })
            )
        )
    }

    public func save(_ settings: AppSettings) {
        // Never lower it: a newer build that wrote these settings must not
        // run its migrations again after the user goes back to it.
        defaults.set(max(SettingsSchema.current, SettingsSchema.storedVersion(in: defaults)),
                     forKey: SettingsSchema.versionKey)
        defaults.set(settings.displayName, forKey: Key.displayName)
        defaults.set(settings.kitID, forKey: Key.kitID)
        defaults.set(settings.hasChosenKit, forKey: Key.hasChosenKit)
        // Sorted so the stored value is stable across saves.
        defaults.set(settings.kitAnswers.mapValues { $0.sorted() }, forKey: Key.kitAnswers)
        let isKnown = { catalog.contains(ModuleID(rawValue: $0)) }
        let storedOrder = defaults.stringArray(forKey: Key.moduleOrder) ?? []
        let unknownDisabled = (defaults.stringArray(forKey: Key.disabledModules) ?? []).filter { !isKnown($0) }
        let order = SettingsSchema.storedOrder(settings.modules.order.map(\.rawValue),
                                               keepingUnknownFrom: storedOrder, isKnown: isKnown)
        let disabled = Set(settings.modules.disabled.map(\.rawValue) + unknownDisabled)
        defaults.set(order, forKey: Key.moduleOrder)
        defaults.set(order.filter(disabled.contains), forKey: Key.disabledModules)
        defaults.set(settings.openOnHover, forKey: Key.openOnHover)
        defaults.set(settings.hapticsEnabled, forKey: Key.hapticsEnabled)
        defaults.set(settings.celebrationSoundEnabled, forKey: Key.celebrationSoundEnabled)
        defaults.set(settings.weeklyRecapEnabled, forKey: Key.weeklyRecapEnabled)
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(try? JSONEncoder().encode(settings.hotkey), forKey: Key.hotkey)
        if let path = settings.claudePathOverride {
            defaults.set(path, forKey: Key.claudePathOverride)
        } else {
            defaults.removeObject(forKey: Key.claudePathOverride)
        }
        defaults.set(settings.preferredDisplay.storageValue, forKey: Key.preferredDisplay)
        defaults.set(settings.showOnExternalDisplays, forKey: Key.showOnExternalDisplays)
        defaults.set(settings.hideInFullscreen, forKey: Key.hideInFullscreen)
        defaults.set(settings.hideFromScreenCapture, forKey: Key.hideFromScreenCapture)
        defaults.set(settings.hideInMissionControl, forKey: Key.hideInMissionControl)
        defaults.set(settings.notchMode.rawValue, forKey: Key.notchMode)
        defaults.set(settings.panelSize.rawValue, forKey: Key.panelSize)
        defaults.set(settings.motionPace.rawValue, forKey: Key.motionPace)
        defaults.set(settings.notchPreview.isEnabled, forKey: Key.previewEnabled)
        // Sorted so the stored value is stable across saves.
        defaults.set(settings.notchPreview.disabledKinds.map(\.rawValue).sorted(), forKey: Key.previewDisabledKinds)
        defaults.set(settings.notchPreview.interval.rawValue, forKey: Key.previewInterval)
        defaults.set(settings.themeID.rawValue, forKey: Key.theme)
        if let provider = settings.ai.provider {
            defaults.set(provider.rawValue, forKey: Key.aiProvider)
        } else {
            defaults.removeObject(forKey: Key.aiProvider)
        }
        defaults.set(Dictionary(uniqueKeysWithValues: settings.ai.models.map { ($0.key.rawValue, $0.value) }),
                     forKey: Key.aiModels)
    }

    /// `nil` when the key is absent or not a boolean, so defaults apply.
    private func bool(_ key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }
}
