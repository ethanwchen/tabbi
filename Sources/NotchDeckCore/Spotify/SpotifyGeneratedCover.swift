import Foundation

/// Colors for a generated cover, drawn when a track has no artwork URL
/// (local files, podcasts without art, demo mode). Derived from the track id
/// so the same track always gets the same cover and glow.
public struct SpotifyGeneratedCover: Equatable, Sendable {
    /// Hue (0 ..< 1) of the top-leading corner of the gradient.
    public var startHue: Double
    /// Hue (0 ..< 1) of the bottom-trailing corner; always a clear step away
    /// from `startHue` so the gradient never looks flat.
    public var endHue: Double

    public init(seed: String) {
        let hash = Self.fnv1a(seed)
        startHue = Double(hash % 360) / 360
        // Step 50°...110° around the wheel for a rich, analogous gradient.
        let step = 50 + Double((hash / 360) % 61)
        endHue = (startHue + step / 360).truncatingRemainder(dividingBy: 1)
    }

    /// FNV-1a: stable across launches, unlike `Hasher`.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

/// Maps between scrubber geometry and playback time.
public enum SpotifyScrubber {
    /// Seconds for a drag at `x` along a track `width` points wide.
    public static func position(atX x: Double, width: Double, duration: TimeInterval) -> TimeInterval {
        guard width > 0, duration > 0, x.isFinite else { return 0 }
        return min(max(x / width, 0), 1) * duration
    }
}
