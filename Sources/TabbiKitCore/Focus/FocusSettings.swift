import Foundation

/// The user's focus mode preferences: what to play and whether to turn on
/// Do Not Disturb while the focus timer runs.
///
/// Everything is opt-in. The defaults play nothing and leave Do Not
/// Disturb alone, so updating the app never makes a focus session louder.
public struct FocusSettings: Codable, Equatable, Sendable {
    /// Suggested shortcut names; Settings explains how to create them.
    /// Every save writes the names, so settings saved before the rename
    /// keep the old "NotchDeck Focus On/Off" that match the user's Shortcuts.
    public static let suggestedOnShortcut = "Tabbi Focus On"
    public static let suggestedOffShortcut = "Tabbi Focus Off"

    public static let `default` = FocusSettings()

    /// The generated focus sound. Empty means Off.
    public var mix: FocusMix
    /// Blends the user saved by name. Kits never touch them.
    public var presets: FocusMixPresets
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
        presets: FocusMixPresets = .empty,
        volume: Float = 0.5,
        playlistText: String = "",
        doNotDisturb: Bool = false,
        onShortcut: String = FocusSettings.suggestedOnShortcut,
        offShortcut: String = FocusSettings.suggestedOffShortcut
    ) {
        self.mix = mix
        self.presets = presets
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

    /// These settings with a kit's focus sound applied. A kit without one
    /// keeps the current mix; volume, playlist and shortcuts are the user's.
    public func applying(_ kit: KitDefaults) -> FocusSettings {
        var settings = self
        if let mix = Self.kitMix(of: kit) { settings.mix = mix }
        return settings
    }

    /// The focus sound a kit sets in its Focus section
    /// (`moduleSettings.focus.sounds`: a list of `sound` and an optional
    /// `level` from 0 to 1, default 1), with unknown sounds skipped and
    /// levels clamped by `FocusMix`. Nil when the kit sets no sound; an
    /// empty list turns the sound off.
    public static func kitMix(of kit: KitDefaults) -> FocusMix? {
        kit.settings(for: .focus)?["sounds"]?.arrayValue.map { entries in
            FocusMix(entries.compactMap { entry in
                guard let sound = entry["sound"]?.stringValue.flatMap(FocusSound.init(rawValue:)) else { return nil }
                let level = entry["level"]?.numberValue ?? 1
                return FocusMix.Layer(sound: sound, level: level.isFinite ? Float(level) : 1)
            })
        }
    }

    /// The keys `kitMix(of:)` reads, for the Focus descriptor.
    public static let kitSettings = KitSettingsSchema([
        "sounds": .list(.object([
            "sound": .choice(FocusSound.allCases.map(\.rawValue)),
            "level": .number(0...1),
        ]), maxCount: FocusMix.maxLayers),
    ])

    /// Switches to the preset in `slot`; an empty slot changes nothing.
    public mutating func apply(preset slot: Int) {
        guard presets.slots.indices.contains(slot), let preset = presets.slots[slot] else { return }
        mix = preset.mix
    }

    /// True when applying `kit` would leave these settings unchanged.
    public func usesDefaults(of kit: KitDefaults) -> Bool {
        applying(kit) == self
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
        case mix, presets, volume, playlistText, doNotDisturb, onShortcut, offShortcut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = FocusSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ defaultValue: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? defaultValue
        }
        self.init(
            mix: value(.mix, fallback.mix),
            presets: value(.presets, fallback.presets),
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
