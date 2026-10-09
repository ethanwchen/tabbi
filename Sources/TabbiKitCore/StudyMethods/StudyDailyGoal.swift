import Foundation

/// How many minutes a day the user means to study.
///
/// A kit sets it under `moduleSettings.study.dailyGoalMinutes`, so a
/// Med School kit can aim for a long board-prep day while a general student
/// kit stays modest. The Study timer shares the day's minutes against it as
/// a progress goal, which is how Today and Plan my day learn about study
/// time without knowing the Study module.
public struct StudyDailyGoal: Codable, Hashable, Sendable {
    /// Shortest and longest goal; anything outside is clamped.
    public static let range: ClosedRange<Int> = 15...720
    /// Goals snap to quarter hours, matching a stepper.
    public static let step = 15
    /// Two hours: used when the kit says nothing.
    public static let standard = StudyDailyGoal(minutes: 120)

    /// The progress item's id, stable so Today updates the same row.
    public static let progressID = "minutes"
    /// The unit the progress item counts in.
    public static let unit = DurationFormat.minuteUnit

    public let minutes: Int

    /// Clamps to `range` and snaps to the nearest `step`.
    public init(minutes: Int) {
        let snapped = Int((Double(minutes) / Double(Self.step)).rounded()) * Self.step
        self.minutes = min(max(snapped, Self.range.lowerBound), Self.range.upperBound)
    }

    /// The kit's goal, or `standard` when the kit has none or gives a value
    /// that isn't a finite number.
    public init(kit defaults: KitDefaults?) {
        guard let value = defaults?.settings(for: .study)?["dailyGoalMinutes"]?.numberValue,
              value.isFinite else {
            self = .standard
            return
        }
        self.init(minutes: Int(min(max(value, -1e6), 1e6)))
    }

    /// How a kit writes the goal (`moduleSettings.study.dailyGoalMinutes`).
    public static let kitSettingType = KitSettingType.number(
        Double(range.lowerBound)...Double(range.upperBound)
    )

    private enum CodingKeys: String, CodingKey { case minutes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(minutes: try container.decodeIfPresent(Int.self, forKey: .minutes) ?? Self.standard.minutes)
    }

    /// The goal moved by `steps` quarter hours, clamped to `range`.
    public func stepped(by steps: Int) -> StudyDailyGoal {
        StudyDailyGoal(minutes: minutes + steps * Self.step)
    }

    /// The day's study minutes against this goal, for `ModuleProvision.progress`.
    /// Shown by Today as e.g. "Focus time, 1h 15m left", and beside the
    /// closed notch only once the day's first minutes are in.
    public func progressItem(for day: StudyDayTally, source: ModuleID = .study) -> ProgressItem {
        ProgressItem(id: Self.progressID, source: source, title: "Focus time",
                     completed: max(day.minutes, 0), target: minutes, unit: Self.unit, waitsForStart: true)
    }
}
