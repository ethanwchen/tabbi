import Foundation

/// The user's focus mode preferences: what to play and whether to turn on
/// Do Not Disturb while the focus timer runs.
///
/// Everything is opt-in. The defaults play nothing and leave Do Not
/// Disturb alone, so updating the app never makes a focus session louder.
public struct FocusSettings: Codable, Equatable, Sendable {
    /// Suggested shortcut names; Settings explains how to create them.
    public static let suggestedOnShortcut = "NotchDeck Focus On"
    public static let suggestedOffShortcut = "NotchDeck Focus Off"

    public static let `default` = FocusSettings()

    /// The generated focus sound. Empty means Off.
    public var mix: FocusMix
    /// Master volume for the generated sound, 0...1.
    public var volume: Float {
        didSet { volume = Self.clampVolume(volume) }
    }
    /// The playlist field's raw text, kept as typed so the field round-trips
    /// exactly. Use `playlist` for the parsed value.
    public var playlistText: String
    public var doNotDisturb: Bool
    /// Shortcut names run when focus starts and ends. Blank skips that step.
    public var onShortcut: String
    public var offShortcut: String

    public init(
        mix: FocusMix = .off,
        volume: Float = 0.5,
        playlistText: String = "",
        doNotDisturb: Bool = false,
        onShortcut: String = FocusSettings.suggestedOnShortcut,
        offShortcut: String = FocusSettings.suggestedOffShortcut
    ) {
        self.mix = mix
        self.volume = Self.clampVolume(volume)
        self.playlistText = playlistText
        self.doNotDisturb = doNotDisturb
        self.onShortcut = onShortcut
        self.offShortcut = offShortcut
    }

    /// The playlist to start with focus, or nil when the field is blank or
    /// unrecognizable.
    public var playlist: FocusPlaylist? { FocusPlaylist(playlistText) }

    /// The shortcut to run when focus starts, or nil when DND is off or the
    /// name is blank (both mean "skip silently").
    public var activeOnShortcut: String? { activeShortcut(onShortcut) }

    /// The shortcut to run when focus ends, under the same rules.
    public var activeOffShortcut: String? { activeShortcut(offShortcut) }

    /// True when starting focus would do anything at all.
    public var hasEffect: Bool {
        !mix.isOff || playlist != nil || activeOnShortcut != nil || activeOffShortcut != nil
    }

    private func activeShortcut(_ name: String) -> String? {
        guard doNotDisturb else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clampVolume(_ volume: Float) -> Float {
        volume.isFinite ? min(max(volume, 0), 1) : FocusSettings.default.volume
    }

    // Decoding falls back per field, so one bad or missing value (say, from
    // an older version) never resets the rest.
    private enum CodingKeys: String, CodingKey {
        case mix, volume, playlistText, doNotDisturb, onShortcut, offShortcut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = FocusSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
        }
        self.init(
            mix: value(.mix, fallback.mix),
            volume: value(.volume, fallback.volume),
            playlistText: value(.playlistText, fallback.playlistText),
            doNotDisturb: value(.doNotDisturb, fallback.doNotDisturb),
            onShortcut: value(.onShortcut, fallback.onShortcut),
            offShortcut: value(.offShortcut, fallback.offShortcut)
        )
    }
}

/// Loads and saves `FocusSettings` as one JSON value in `UserDefaults`,
/// under a key of its own so focus mode never touches `AppSettings`.
public struct FocusSettingsRepository {
    static let key = "focus.settings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> FocusSettings {
        defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(FocusSettings.self, from: $0) } ?? .default
    }

    public func save(_ settings: FocusSettings) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
    }
}
