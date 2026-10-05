import Foundation

/// The clock behind Tabbi's paw print loader, as pure functions of time.
///
/// The loader is for longer waits (Claude thinking, Anki starting up): a
/// short trail of paw prints that appear one after another, left, right,
/// left, right, as if the pet were trotting past, then fade behind it. A
/// spinner says "busy"; the trail says "on its way", which suits a wait of
/// several seconds. Like the other loaders it draws from a `TimelineView`,
/// so the same date always renders the same frame.
public enum PawTrail {
    /// How many prints the trail has.
    public static let stepCount = 4
    /// The time between one print and the next, in seconds: a calm trot.
    public static let stepInterval: Double = 0.32
    /// How long a print takes to press in, in seconds.
    public static let pressDuration: Double = 0.12
    /// How long a print takes to fade once it is pressed, in seconds.
    public static let fadeDuration: Double = 1.1
    /// One full walk, in seconds: every print, plus a short pause with the
    /// trail fading so each walk reads as a new one.
    public static let cycle: Double = Double(stepCount + 3) * stepInterval
    /// A loader that would show for less than this is never shown at all,
    /// so a fast answer doesn't flash a loader.
    public static let revealDelay: Double = 0.3
    /// How long the loader takes to fade in once the delay has passed.
    public static let revealDuration: Double = 0.2

    /// The opacity of print `step` (0 is the first) at `time`, in `0...1`.
    ///
    /// Each print presses in quickly, then fades out over `fadeDuration`.
    /// Out-of-range steps are never drawn.
    public static func opacity(ofStep step: Int, at time: TimeInterval) -> Double {
        guard (0..<stepCount).contains(step) else { return 0 }
        let phase = time.truncatingRemainder(dividingBy: cycle)
        let age = (phase < 0 ? phase + cycle : phase) - Double(step) * stepInterval
        guard age >= 0 else { return 0 }
        let pressed = min(1, age / pressDuration)
        let faded = max(0, 1 - max(0, age - pressDuration) / fadeDuration)
        return pressed * faded
    }

    /// The scale of print `step` at `time`: it lands slightly large and
    /// settles to full size as it presses in, which reads as a footfall.
    public static func scale(ofStep step: Int, at time: TimeInterval) -> Double {
        guard (0..<stepCount).contains(step) else { return 1 }
        let phase = time.truncatingRemainder(dividingBy: cycle)
        let age = (phase < 0 ? phase + cycle : phase) - Double(step) * stepInterval
        guard age >= 0, age < pressDuration else { return 1 }
        return 1 + 0.15 * (1 - age / pressDuration)
    }

    /// Which side of the trail print `step` falls on: even steps are left
    /// feet, odd ones right, so the trail zigzags like a real one.
    public static func isLeftFoot(_ step: Int) -> Bool { step.isMultiple(of: 2) }

    /// The whole loader's opacity `elapsed` seconds after it was asked to
    /// show: nothing until `delay`, then a quick fade in.
    public static func revealOpacity(elapsed: TimeInterval, delay: Double = revealDelay) -> Double {
        guard elapsed >= delay else { return 0 }
        return min(1, (elapsed - delay) / revealDuration)
    }
}
