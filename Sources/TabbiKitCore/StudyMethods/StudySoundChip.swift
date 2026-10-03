import Foundation

/// One chip in the Study tab's focus-sound row: off, a single sound, the
/// mixer, or the playlist.
///
/// The row is a shortcut onto the shared `FocusSettings` (the same sound
/// the Focus timer plays), so a sound chip replaces the mix with that one
/// sound, while Mix and Playlist open the in-notch mixer to edit a blend or
/// pick a playlist.
public enum StudySoundChip: String, CaseIterable, Sendable, Identifiable {
    case off
    case brown
    case rain
    case fireplace
    case cafe
    case mix
    case playlist

    public var id: String { rawValue }

    /// The sound this chip plays on its own, or nil for off, mix and playlist.
    public var sound: FocusSound? {
        switch self {
        case .brown: .brown
        case .rain: .rain
        case .fireplace: .fireplace
        case .cafe: .cafe
        case .off, .mix, .playlist: nil
        }
    }

    /// True for the chips that open the mixer instead of choosing a sound.
    public var opensMixer: Bool { self == .mix || self == .playlist }

    public var title: String {
        switch self {
        case .off: "Off"
        case .mix: "Mix"
        case .playlist: "Playlist"
        default: sound?.displayName ?? ""
        }
    }

    public var symbolName: String {
        switch self {
        case .off: "speaker.slash"
        case .mix: "slider.horizontal.3"
        case .playlist: "music.note.list"
        default: sound?.symbolName ?? ""
        }
    }

    /// Whether the chip shows as on for `settings`. Exactly one of the
    /// sound chips (off, a sound, or mix) is on at a time; mix covers blends
    /// and sounds without a chip of their own, such as pink noise. The
    /// playlist chip is independent, since a playlist plays alongside any sound.
    public func isSelected(in settings: FocusSettings) -> Bool {
        let layers = settings.mix.layers
        switch self {
        case .off:
            return layers.isEmpty
        case .mix:
            return layers.count > 1 || (layers.count == 1 && Self.chip(for: layers[0].sound) == nil)
        case .playlist:
            return settings.playlist != nil
        default:
            return layers.count == 1 && layers[0].sound == sound
        }
    }

    /// The settings after tapping a sound chip: off empties the mix and a
    /// sound becomes the only layer at full level. Mix and playlist leave the
    /// settings alone, since they open the mixer.
    public func applying(to settings: FocusSettings) -> FocusSettings {
        var next = settings
        switch self {
        case .off: next.mix = .off
        case .mix, .playlist: break
        default: if let sound { next.mix = .single(sound) }
        }
        return next
    }

    /// The chip that stands for `sound` on its own, if the row has one.
    public static func chip(for sound: FocusSound) -> StudySoundChip? {
        allCases.first { $0.sound == sound }
    }

    /// A 0...1 level from a drag at `x` across a slider `width` wide, for
    /// the mixer's hand-drawn sliders. Out-of-range and degenerate input
    /// clamps, so a drag past either end pins the level.
    public static func level(atX x: Double, width: Double) -> Float {
        guard width > 0, x.isFinite else { return x > 0 ? 1 : 0 }
        return Float(min(max(x / width, 0), 1))
    }
}
