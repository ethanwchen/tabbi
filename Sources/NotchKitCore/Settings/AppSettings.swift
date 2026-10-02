import Foundation

/// Every user preference NotchDeck has, as one value.
public struct AppSettings: Equatable, Sendable {
    public var modules: ModuleLayout
    /// When on, resting the pointer on the closed notch for `hoverOpenDelay` opens it.
    public var openOnHover: Bool
    public var hapticsEnabled: Bool
    /// Mirrors the user's choice; the source of truth is `SMAppService.mainApp.status`.
    public var launchAtLogin: Bool
    public var hotkey: Hotkey
    /// Explicit path to the `claude` binary; `nil` means auto-discover.
    public var claudePathOverride: String? {
        didSet { claudePathOverride = Self.normalizedPath(claudePathOverride) }
    }
    public var preferredDisplay: DisplayPreference
    public var notchPreview: NotchPreviewSettings

    /// How long the pointer must rest on the closed notch before hover-to-open fires.
    public static let hoverOpenDelay: Duration = .milliseconds(250)

    public static let `default` = AppSettings()

    public init(
        modules: ModuleLayout = .default,
        openOnHover: Bool = false,
        hapticsEnabled: Bool = true,
        launchAtLogin: Bool = false,
        hotkey: Hotkey = .default,
        claudePathOverride: String? = nil,
        preferredDisplay: DisplayPreference = .builtIn,
        notchPreview: NotchPreviewSettings = .default
    ) {
        self.modules = modules
        self.openOnHover = openOnHover
        self.hapticsEnabled = hapticsEnabled
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
        self.claudePathOverride = Self.normalizedPath(claudePathOverride)
        self.preferredDisplay = preferredDisplay
        self.notchPreview = notchPreview
    }

    /// Kinds the closed-notch preview may show: the user's preview choices,
    /// minus items whose module is turned off, since clicking one would open
    /// a tab that isn't there.
    public var previewKinds: Set<TickerKind> {
        notchPreview.enabledKinds.filter { modules.isEnabled($0.module) }
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
public struct SettingsRepository {
    enum Key {
        static let moduleOrder = "settings.modules.order"
        static let disabledModules = "settings.modules.disabled"
        static let openOnHover = "settings.openOnHover"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let launchAtLogin = "settings.launchAtLogin"
        static let hotkey = "settings.hotkey"
        static let claudePathOverride = "settings.claudePathOverride"
        static let preferredDisplay = "settings.preferredDisplay"
        static let previewEnabled = "settings.preview.enabled"
        static let previewDisabledKinds = "settings.preview.disabledKinds"
        static let previewInterval = "settings.preview.interval"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        let fallback = AppSettings.default
        let hotkey = defaults.data(forKey: Key.hotkey)
            .flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) }
            .flatMap { $0.isValid ? $0 : nil }
        return AppSettings(
            modules: ModuleLayout(
                orderRawValues: defaults.stringArray(forKey: Key.moduleOrder) ?? [],
                disabledRawValues: defaults.stringArray(forKey: Key.disabledModules) ?? []
            ),
            openOnHover: bool(Key.openOnHover) ?? fallback.openOnHover,
            hapticsEnabled: bool(Key.hapticsEnabled) ?? fallback.hapticsEnabled,
            launchAtLogin: bool(Key.launchAtLogin) ?? fallback.launchAtLogin,
            hotkey: hotkey ?? fallback.hotkey,
            claudePathOverride: defaults.string(forKey: Key.claudePathOverride),
            preferredDisplay: defaults.string(forKey: Key.preferredDisplay)
                .flatMap(DisplayPreference.init(storageValue:)) ?? fallback.preferredDisplay,
            notchPreview: NotchPreviewSettings(
                isEnabled: bool(Key.previewEnabled) ?? fallback.notchPreview.isEnabled,
                // Unknown raw values (a kind removed in a later version) are dropped.
                disabledKinds: Set((defaults.stringArray(forKey: Key.previewDisabledKinds) ?? [])
                    .compactMap(TickerKind.init(rawValue:))),
                interval: (defaults.object(forKey: Key.previewInterval) as? Int)
                    .flatMap(TickerInterval.init(rawValue:)) ?? fallback.notchPreview.interval
            )
        )
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.modules.order.map(\.rawValue), forKey: Key.moduleOrder)
        defaults.set(settings.modules.order.filter { !settings.modules.isEnabled($0) }.map(\.rawValue),
                     forKey: Key.disabledModules)
        defaults.set(settings.openOnHover, forKey: Key.openOnHover)
        defaults.set(settings.hapticsEnabled, forKey: Key.hapticsEnabled)
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(try? JSONEncoder().encode(settings.hotkey), forKey: Key.hotkey)
        if let path = settings.claudePathOverride {
            defaults.set(path, forKey: Key.claudePathOverride)
        } else {
            defaults.removeObject(forKey: Key.claudePathOverride)
        }
        defaults.set(settings.preferredDisplay.storageValue, forKey: Key.preferredDisplay)
        defaults.set(settings.notchPreview.isEnabled, forKey: Key.previewEnabled)
        // Sorted so the stored value is stable across saves.
        defaults.set(settings.notchPreview.disabledKinds.map(\.rawValue).sorted(), forKey: Key.previewDisabledKinds)
        defaults.set(settings.notchPreview.interval.rawValue, forKey: Key.previewInterval)
    }

    /// `nil` when the key is absent or not a boolean, so defaults apply.
    private func bool(_ key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }
}
