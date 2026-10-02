import Foundation

/// The lengths a user picks for the Custom study method.
///
/// Kept in whole minutes on coarse steps, so a few clicks of a stepper
/// reach any sensible rhythm and the timer never shows odd seconds. Every
/// value is clamped on init and on decode, so a saved or hand-edited value
/// can never make a zero-length phase. The long break keeps its length and
/// spacing while it is switched off, so turning it back on restores them.
public struct StudyCustomRhythm: Codable, Hashable, Sendable {
    /// One adjustable length or count.
    public enum Field: String, CaseIterable, Sendable {
        case focus
        case shortBreak
        case longBreak
        case longBreakEvery

        /// Allowed values, in minutes (or rounds for `longBreakEvery`).
        public var range: ClosedRange<Int> {
            switch self {
            case .focus: 5...180
            case .shortBreak: 1...60
            case .longBreak: 5...60
            case .longBreakEvery: 2...8
            }
        }

        /// How far one stepper click moves the value.
        public var step: Int {
            switch self {
            case .focus, .longBreak: 5
            case .shortBreak, .longBreakEvery: 1
            }
        }
    }

    public let focusMinutes: Int
    public let breakMinutes: Int
    public let longBreakMinutes: Int
    /// A long break replaces every this-many-th regular break.
    public let longBreakEvery: Int
    public let hasLongBreak: Bool

    public init(focusMinutes: Int, breakMinutes: Int, longBreakMinutes: Int = 15,
                longBreakEvery: Int = 4, hasLongBreak: Bool = false) {
        self.focusMinutes = Self.clamp(focusMinutes, .focus)
        self.breakMinutes = Self.clamp(breakMinutes, .shortBreak)
        self.longBreakMinutes = Self.clamp(longBreakMinutes, .longBreak)
        self.longBreakEvery = Self.clamp(longBreakEvery, .longBreakEvery)
        self.hasLongBreak = hasLongBreak
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.standard
        self.init(
            focusMinutes: try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? fallback.focusMinutes,
            breakMinutes: try container.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? fallback.breakMinutes,
            longBreakMinutes: try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? fallback.longBreakMinutes,
            longBreakEvery: try container.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? fallback.longBreakEvery,
            hasLongBreak: try container.decodeIfPresent(Bool.self, forKey: .hasLongBreak) ?? fallback.hasLongBreak
        )
    }

    /// 30 min focus, 5 min break, no long break.
    public static let standard = StudyCustomRhythm(focusMinutes: 30, breakMinutes: 5)

    /// The value of `field`.
    public subscript(field: Field) -> Int {
        switch field {
        case .focus: focusMinutes
        case .shortBreak: breakMinutes
        case .longBreak: longBreakMinutes
        case .longBreakEvery: longBreakEvery
        }
    }

    /// Whether moving `field` by `steps` clicks would change it.
    public func canStep(_ field: Field, by steps: Int) -> Bool {
        stepped(field, by: steps) != self
    }

    /// The rhythm with `field` moved by `steps` clicks, snapped to the
    /// field's step and kept in its range.
    public func stepped(_ field: Field, by steps: Int) -> StudyCustomRhythm {
        let current = self[field]
        // Snap first, so a decoded 23 min focus steps to 25 or 20, not 28 or 18.
        let snapped = (current / field.step) * field.step
        let target: Int
        if steps > 0 {
            target = snapped + steps * field.step
        } else if steps < 0, snapped < current {
            target = snapped + (steps + 1) * field.step
        } else {
            target = snapped + steps * field.step
        }
        return setting(field, to: target)
    }

    /// The rhythm with `field` set to `value`, clamped to its range.
    public func setting(_ field: Field, to value: Int) -> StudyCustomRhythm {
        StudyCustomRhythm(
            focusMinutes: field == .focus ? value : focusMinutes,
            breakMinutes: field == .shortBreak ? value : breakMinutes,
            longBreakMinutes: field == .longBreak ? value : longBreakMinutes,
            longBreakEvery: field == .longBreakEvery ? value : longBreakEvery,
            hasLongBreak: hasLongBreak
        )
    }

    /// The rhythm with the long break switched on or off.
    public func withLongBreak(_ on: Bool) -> StudyCustomRhythm {
        StudyCustomRhythm(focusMinutes: focusMinutes, breakMinutes: breakMinutes,
                          longBreakMinutes: longBreakMinutes, longBreakEvery: longBreakEvery, hasLongBreak: on)
    }

    /// The Custom study method these lengths make.
    public var method: StudyMethod {
        .custom(
            focus: TimeInterval(focusMinutes * 60),
            breakLength: TimeInterval(breakMinutes * 60),
            longBreak: hasLongBreak ? StudyLongBreak(duration: TimeInterval(longBreakMinutes * 60), every: longBreakEvery) : nil
        )
    }

    private static func clamp(_ value: Int, _ field: Field) -> Int {
        min(max(value, field.range.lowerBound), field.range.upperBound)
    }
}

public extension StudyMethod {
    /// The method for `kind`: the preset, or the user's own lengths for Custom.
    static func preset(_ kind: StudyMethodKind, custom: StudyCustomRhythm) -> StudyMethod {
        kind == .custom ? custom.method : preset(kind)
    }
}

public extension StudyMethodMenu {
    /// The offered methods for the picker, with Custom on the user's lengths.
    func methods(custom: StudyCustomRhythm) -> [StudyMethod] {
        kinds.map { StudyMethod.preset($0, custom: custom) }
    }
}
