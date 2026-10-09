import Foundation

/// What the Study tab's one sound button says about the shared
/// `FocusSettings` (the same sound the Focus timer plays).
///
/// The Timer panel keeps a single button for focus sound, so the dial and
/// the method stay the panel's focus; the button opens the in-notch mixer,
/// where sounds, levels and the playlist are picked.
public struct StudySoundLabel: Equatable, Sendable {
    /// Short text on the button: "Sound" when nothing plays, the sound's
    /// name, "2 sounds" for a blend, or "Playlist" for a playlist alone.
    public let title: String
    public let symbolName: String
    /// True when a sound or a playlist plays with focus, so the button
    /// shows in the accent.
    public let isOn: Bool
    /// True when a playlist starts alongside a sound, so the button adds a
    /// small note after the sound's name.
    public let addsPlaylist: Bool

    public init(_ settings: FocusSettings) {
        let layers = settings.mix.layers
        let hasPlaylist = settings.playlist != nil
        switch layers.count {
        case 0 where hasPlaylist:
            title = "Playlist"
            symbolName = "music.note.list"
        case 0:
            title = "Sound"
            symbolName = "speaker.slash"
        case 1:
            title = layers[0].sound.displayName
            symbolName = layers[0].sound.symbolName
        default:
            title = "\(layers.count) sounds"
            symbolName = "slider.horizontal.3"
        }
        isOn = !layers.isEmpty || hasPlaylist
        addsPlaylist = !layers.isEmpty && hasPlaylist
    }

    /// The tooltip: what plays with focus, and that a click opens the mixer.
    public static func help(for settings: FocusSettings, playlistName: String?) -> String {
        var parts: [String] = []
        if !settings.mix.isOff { parts.append(settings.mix.summary) }
        if settings.playlist != nil { parts.append(playlistName ?? "your playlist") }
        guard !parts.isEmpty else { return "Pick a focus sound or a playlist" }
        return "Plays \(parts.joined(separator: " and ")) with focus. Click to change it"
    }

    /// A 0...1 level from a drag at `x` across a slider `width` wide, for
    /// the mixer's hand-drawn sliders. Out-of-range and degenerate input
    /// clamps, so a drag past either end pins the level.
    public static func level(atX x: Double, width: Double) -> Float {
        guard width > 0, x.isFinite else { return x > 0 ? 1 : 0 }
        return Float(min(max(x / width, 0), 1))
    }
}
