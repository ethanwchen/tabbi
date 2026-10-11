import Foundation

/// Volume math shared by both players. Spotify and Music each keep their own
/// `sound volume` (0 ... 100), separate from the system volume.
public enum MediaVolume {
    public static let range = 0...100
    /// Where unmuting lands when there's no earlier level to restore (or it
    /// was itself silent), so the click is always audible.
    public static let unmuteFallback = 50

    public static func clamped(_ volume: Int) -> Int {
        min(max(volume, range.lowerBound), range.upperBound)
    }

    /// Reads a script's volume field. AppleScript may format it as a real
    /// (`64.0`, `64,0`); unreadable or negative values (Music's `-1`) are nil.
    public static func parse(_ text: String) -> Int? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return clamped(Int(value.rounded()))
    }

    /// Volume for a slider at `fraction` (0...1) of its track.
    public static func volume(at fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return clamped(Int((fraction * 100).rounded()))
    }

    /// 0 when muted, else 1 ... 3 by loudness; picks the speaker glyph.
    public static func level(_ volume: Int) -> Int {
        switch clamped(volume) {
        case 0: 0
        case 1..<34: 1
        case 34..<67: 2
        default: 3
        }
    }

    /// The speaker button's result: mutes an audible volume, or restores
    /// `previous` (the level before muting) when already silent.
    public static func togglingMute(_ volume: Int, previous: Int?) -> Int {
        guard volume <= 0 else { return 0 }
        guard let previous, previous > 0 else { return unmuteFallback }
        return clamped(previous)
    }
}

extension SpotifyPlayback {
    /// Optimistic result of setting the app's volume. Nothing changes when
    /// the volume is unknown, since there's no control to show it.
    public func settingVolume(_ volume: Int) -> SpotifyPlayback {
        guard self.volume != nil else { return self }
        var copy = self
        copy.volume = MediaVolume.clamped(volume)
        return copy
    }
}
