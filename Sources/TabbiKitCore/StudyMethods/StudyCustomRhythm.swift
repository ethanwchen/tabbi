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
        public var range: ClosedRange<Int> { stepper.min...stepper.max }

        /// How far one stepper click moves the value.
        public var step: Int { stepper.step }

        /// The field's limits from `study-methods.json`, which defines every field.
        private var stepper: StudyMethodFile.Stepper {
            guard let stepper = StudyMethodDefinitions.file.custom.fields[rawValue] else {
                preconditionFailure("study-methods.json has no custom field \"\(rawValue)\"")
            }
            return stepper
        }
    }

    public let focusMinutes: Int
    public let breakMinutes: Int
    public let longBreakMinutes: Int
    /// A long break replaces every this-many-th regular break.
    public let longBreakEvery: Int
    public let hasLongBreak: Bool

    /// The long break a fresh rhythm keeps ready (15 min after every 4th
    /// round), from `study-methods.json`.
    public static let defaultLongBreakMinutes = Int(StudyMethodDefinitions.file.custom.longBreak.minutes)
    public static let defaultLongBreakEvery = StudyMethodDefinitions.file.custom.longBreak.every

    public init(focusMinutes: Int, breakMinutes: Int, longBreakMinutes: Int = defaultLongBreakMinutes,
                longBreakEvery: Int = defaultLongBreakEvery, hasLongBreak: Bool = false) {
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

    /// The Custom preset's lengths (30 min focus, 5 min break), with no long break.
    public static let standard: StudyCustomRhythm = {
        let preset = StudyMethod.preset(.custom)
        let minutes = { (phase: StudyPhaseKind) in Int((preset.duration(of: phase) ?? 0) / 60) }
        return StudyCustomRhythm(focusMinutes: minutes(.focus), breakMinutes: minutes(.shortBreak))
    }()

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
    /// The method for `kind`: the preset, or the user's own lengths for
    /// Custom and the Timer.
    static func preset(_ kind: StudyMethodKind, custom: StudyCustomRhythm,
                       timer: StudyTimerLength = .standard) -> StudyMethod {
        switch kind {
        case .custom: custom.method
        case .timer: timer.method
        default: preset(kind)
        }
    }
}

public extension StudyMethodMenu {
    /// The offered methods for the picker, with Custom and the Timer on the
    /// user's lengths.
    func methods(custom: StudyCustomRhythm, timer: StudyTimerLength = .standard) -> [StudyMethod] {
        kinds.map { StudyMethod.preset($0, custom: custom, timer: timer) }
    }
}
