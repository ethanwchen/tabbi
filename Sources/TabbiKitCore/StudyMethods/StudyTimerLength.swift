import Foundation

/// How long the plain Timer method counts down, in whole minutes.
///
/// The Timer is the everyday side of the Study tab: one countdown with no
/// breaks or rounds. One click picks a common length from `presets`, and the
/// stepper reaches any other in a few clicks (single minutes up to 10, then
/// steps of 5), so there is no separate custom screen. Clamped on init and
/// on decode, so a saved value can never make a zero-length countdown.
public struct StudyTimerLength: Codable, Hashable, Sendable {
    /// Allowed lengths, in minutes.
    public static let range = 1...180
    /// The one-click lengths the Timer offers.
    public static let presets = [5, 10, 25]
    /// Where a fresh Timer starts.
    public static let standard = StudyTimerLength(minutes: 10)

    public let minutes: Int

    public init(minutes: Int) {
        self.minutes = min(max(minutes, Self.range.lowerBound), Self.range.upperBound)
    }

    public init(from decoder: Decoder) throws {
        self.init(minutes: try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(minutes)
    }

    /// Whether this is one of the one-click `presets`.
    public var isPreset: Bool { Self.presets.contains(minutes) }

    /// The length one stepper click up (`up`) or down: single minutes below
    /// 10, steps of 5 from there, snapping an odd value like 23 to 20 or 25.
    public func stepped(up: Bool) -> StudyTimerLength {
        let value: Int
        if up {
            value = minutes < 10 ? minutes + 1 : (minutes / 5 + 1) * 5
        } else {
            value = minutes <= 10 ? minutes - 1 : ((minutes - 1) / 5) * 5
        }
        return StudyTimerLength(minutes: value)
    }

    /// Whether one click in that direction would change the length.
    public func canStep(up: Bool) -> Bool { stepped(up: up) != self }

    /// The Timer method this length makes.
    public var method: StudyMethod { .timer(TimeInterval(minutes * 60)) }
}
