import Foundation

/// Bar heights for the closed-notch equalizer. A pure function of time, so the
/// view can draw it from a `TimelineView` that simply stops when playback
/// pauses, and the motion stays smooth without any stored animation state.
public enum SpotifyEqualizer {
    /// Bars drawn in the compact wing.
    public static let barCount = 4
    /// Lowest level a bar reaches; keeps every bar visible as a short pill.
    public static let minimumLevel = 0.22

    /// Short, staggered heights shown while paused, so the bars read as
    /// "resting" rather than broken.
    public static func restingLevels(count: Int = barCount) -> [Double] {
        (0..<max(count, 0)).map { minimumLevel + 0.08 * Double($0 % 2) }
    }

    /// Levels in `minimumLevel ... 1` for each bar at `time` seconds. Each bar
    /// mixes two sines at unrelated frequencies with smooth pseudo-random
    /// noise: the sines keep a steady pulse, and the noise makes every peak a
    /// slightly different height so the bars feel alive instead of looping.
    /// The noise is hashed from time, so the same `time` always gives the
    /// same levels and no random state has to be stored.
    public static func levels(at time: TimeInterval, count: Int = barCount) -> [Double] {
        guard time.isFinite else { return restingLevels(count: count) }
        return (0..<max(count, 0)).map { index in
            let i = Double(index)
            let slow = sin(time * (5.1 + i * 1.3) + i * 1.7)
            let fast = sin(time * (8.3 + i * 0.9) + i * 2.9)
            let pulse = (slow * 0.6 + fast * 0.4 + 1) / 2 // 0 ... 1
            let jitter = noise(at: time * (3.7 + i * 0.6) + i * 13.1, bar: index)
            let mixed = pulse * 0.6 + jitter * 0.4
            return minimumLevel + (1 - minimumLevel) * min(max(mixed, 0), 1)
        }
    }

    /// One bar's heights over a loop that repeats without a seam, sampled
    /// at `frameRate`, for a Core Animation keyframe animation that the
    /// render server plays on its own, so a playing track never wakes the
    /// app (a `TimelineView` at 30 fps redrew the notch about 30 times a
    /// second, some 3% CPU for as long as music played).
    ///
    /// The values follow `levels(at:)` and, over the last `blend` seconds,
    /// ease into the loop's own start, so the last value equals the first
    /// and the bar never jumps when the loop comes round. Returns
    /// `duration * frameRate + 1` values, the first and last equal.
    public static func loop(bar: Int, duration: TimeInterval = 30, frameRate: Double = 30,
                            blend: TimeInterval = 1, count: Int = barCount) -> [Double] {
        guard duration > 0, frameRate > 0, (0..<count).contains(bar) else { return [] }
        let frames = Int((duration * frameRate).rounded())
        let blend = min(max(blend, 0), duration)
        return (0...frames).map { frame in
            let time = Double(frame) / frameRate
            let level = levels(at: time, count: count)[bar]
            let into = time - (duration - blend)
            guard blend > 0, into > 0 else { return level }
            let t = min(into / blend, 1)
            let eased = t * t * (3 - 2 * t)
            return level + (levels(at: time - duration, count: count)[bar] - level) * eased
        }
    }

    /// 1D value noise in `0 ... 1`: a random target per whole beat, eased
    /// between neighbors with smoothstep so the motion has no jumps.
    private static func noise(at beat: Double, bar: Int) -> Double {
        // Wrap so the beat index always fits in Int64; the seam is days apart.
        let wrapped = beat.truncatingRemainder(dividingBy: 1_099_511_627_776) // 2^40
        let floor = wrapped.rounded(.down)
        let t = wrapped - floor
        let eased = t * t * (3 - 2 * t)
        let index = Int64(floor)
        let a = random(index, bar: bar)
        let b = random(index + 1, bar: bar)
        return a + (b - a) * eased
    }

    /// SplitMix64 hash of (beat, bar) mapped to `0 ... 1`.
    private static func random(_ beat: Int64, bar: Int) -> Double {
        var z = UInt64(bitPattern: beat) &+ UInt64(bar) &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
