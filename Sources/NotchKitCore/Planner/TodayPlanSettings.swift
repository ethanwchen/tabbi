import Foundation

/// How Today's Plan My Day works for the active kit, read from the kit's
/// `moduleSettings.planner` section, for example:
///
/// ```json
/// "moduleSettings": {
///   "planner": { "planMode": "study", "reviewsFirst": true, "eventBufferMinutes": 10,
///                "studyBlockTitle": "Study block", "secondsPerCard": 10,
///                "upNextEvents": "lectures, labs, and shifts", "dayEndHour": 21,
///                "sampleDay": "medicine" }
/// }
/// ```
///
/// Every key is optional. Kits without the section keep the Claude planner,
/// so nothing here is specific to medicine; a study kit opts in.
public struct TodayPlanSettings: Hashable, Sendable {
    public enum PlanMode: String, Hashable, Sendable {
        /// Ask the local `claude` CLI to schedule the checklist.
        case claude
        /// Plan on device with `StudyDayPlanner`: review blocks, study
        /// blocks of the kit's study method length, and breaks.
        case study
    }

    public var planMode: PlanMode
    /// The method whose block and break lengths study blocks use.
    public var studyMethod: StudyMethod
    public var reviewsFirst: Bool
    public var eventBufferMinutes: Int
    /// Title for study blocks once every open task has one, e.g. "Study block".
    public var studyBlockTitle: String
    /// Typical time to answer one review card, for sizing review blocks.
    public var secondsPerCard: TimeInterval
    /// What the user's calendar holds, lowercase, for the Up next card's
    /// empty states: "meetings and calls", or "lectures, labs, and shifts".
    public var upNextEvents: String
    /// When planned work usually stops, 0-22 (6 pm by default); see
    /// `DayPlanner.dayEnd`.
    public var dayEndHour: Int
    /// The day demo mode shows on Today; never affects real data.
    public var sampleDay: PlannerSampleDay

    public init(
        planMode: PlanMode = .claude,
        studyMethod: StudyMethod = .pomodoro,
        reviewsFirst: Bool = true,
        eventBufferMinutes: Int = 10,
        studyBlockTitle: String = "Study block",
        secondsPerCard: TimeInterval = StudyDayPreferences.defaultSecondsPerCard,
        upNextEvents: String = "meetings and calls",
        dayEndHour: Int = DayPlanner.defaultDayEndHour,
        sampleDay: PlannerSampleDay = .work
    ) {
        self.planMode = planMode
        self.studyMethod = studyMethod
        self.reviewsFirst = reviewsFirst
        self.eventBufferMinutes = max(eventBufferMinutes, 0)
        self.studyBlockTitle = PlannerDay.normalized(studyBlockTitle) ?? "Study block"
        self.secondsPerCard = max(secondsPerCard, 1)
        self.upNextEvents = PlannerDay.normalized(upNextEvents) ?? "meetings and calls"
        self.dayEndHour = min(max(dayEndHour, 0), DayPlanner.latestDayEndHour)
        self.sampleDay = sampleDay
    }

    /// The kit's settings; values of the wrong type or unknown modes fall
    /// back to the defaults rather than failing the whole kit. The study
    /// method is the kit's starting one (`KitDefaults.resolvedStudyMethod`).
    public init(kit: KitDefaults?) {
        let section = kit?.settings(for: .planner)
        let defaults = TodayPlanSettings()
        self.init(
            planMode: section?["planMode"]?.stringValue.flatMap(PlanMode.init(rawValue:)) ?? defaults.planMode,
            studyMethod: kit?.resolvedStudyMethod.map(StudyMethod.preset) ?? defaults.studyMethod,
            reviewsFirst: section?["reviewsFirst"]?.boolValue ?? defaults.reviewsFirst,
            eventBufferMinutes: section?["eventBufferMinutes"]?.numberValue.flatMap { Self.wholeNumber($0, upTo: 240) }
                ?? defaults.eventBufferMinutes,
            studyBlockTitle: section?["studyBlockTitle"]?.stringValue ?? defaults.studyBlockTitle,
            secondsPerCard: section?["secondsPerCard"]?.numberValue ?? defaults.secondsPerCard,
            upNextEvents: section?["upNextEvents"]?.stringValue ?? defaults.upNextEvents,
            dayEndHour: section?["dayEndHour"]?.numberValue.flatMap { Self.wholeNumber($0, upTo: 24) } ?? defaults.dayEndHour,
            sampleDay: section?["sampleDay"]?.stringValue.flatMap(PlannerSampleDay.init(rawValue:)) ?? defaults.sampleDay
        )
    }

    /// `value` rounded and clamped to 0...`limit` before it becomes an Int,
    /// since converting an out-of-range Double traps. Nil for NaN.
    private static func wholeNumber(_ value: Double, upTo limit: Int) -> Int? {
        guard !value.isNaN else { return nil }
        return Int(min(max(value.rounded(), 0), Double(limit)))
    }

    /// Block lengths and wording for `StudyDayPlanner`.
    public var preferences: StudyDayPreferences {
        StudyDayPreferences(method: studyMethod, reviewsFirst: reviewsFirst,
                            eventBufferMinutes: eventBufferMinutes, studyTitle: studyBlockTitle)
    }

    /// A study-aware plan for `context`: one review block per unfinished
    /// shared goal (say, Anki reviews), then study blocks and breaks.
    public func studyPlan(context: DayPlanContext, progress: [ProgressItem]) -> StudyDayPlan {
        StudyDayPlanner.plan(context: context,
                             reviews: progress.compactMap { $0.reviewWork(secondsPerUnit: secondsPerCard) },
                             preferences: preferences)
    }
}
