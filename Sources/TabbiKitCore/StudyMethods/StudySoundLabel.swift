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
            title = String(localized: "Playlist", bundle: .tabbi)
            symbolName = "music.note.list"
        case 0:
            title = String(localized: "Sound", bundle: .tabbi)
            symbolName = "speaker.slash"
        case 1:
            title = layers[0].sound.displayName
            symbolName = layers[0].sound.symbolName
        default:
            title = String(localized: "\(layers.count) sounds", bundle: .tabbi)
            symbolName = "slider.horizontal.3"
        }
        isOn = !layers.isEmpty || hasPlaylist
        addsPlaylist = !layers.isEmpty && hasPlaylist
    }

    /// The tooltip: what plays with focus, and that a click opens the mixer.
    public static func help(for settings: FocusSettings, playlistName: String?) -> String {
        var parts: [String] = []
        if !settings.mix.isOff { parts.append(settings.mix.summary) }
        if settings.playlist != nil { parts.append(playlistName ?? String(localized: "your playlist", bundle: .tabbi)) }
        guard !parts.isEmpty else { return String(localized: "Pick a focus sound or a playlist", bundle: .tabbi) }
        return String(localized: "Plays \(parts.formatted(.list(type: .and))) with focus. Click to change it", bundle: .tabbi)
    }
}
