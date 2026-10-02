import Foundation

/// How Today's Plan My Day works for the active kit, read from the kit's
/// `moduleSettings.planner` section, for example:
///
/// ```json
/// "moduleSettings": {
///   "planner": { "planMode": "study", "reviewsFirst": true, "eventBufferMinutes": 10,
///                "studyBlockTitle": "Study block", "secondsPerCard": 10,
///                "upNextEvents": "lectures, labs, and shifts" }
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

    public init(
        planMode: PlanMode = .claude,
        studyMethod: StudyMethod = .pomodoro,
        reviewsFirst: Bool = true,
        eventBufferMinutes: Int = 10,
        studyBlockTitle: String = "Study block",
        secondsPerCard: TimeInterval = StudyDayPreferences.defaultSecondsPerCard,
        upNextEvents: String = "meetings and calls"
    ) {
        self.planMode = planMode
        self.studyMethod = studyMethod
        self.reviewsFirst = reviewsFirst
        self.eventBufferMinutes = max(eventBufferMinutes, 0)
        self.studyBlockTitle = PlannerDay.normalized(studyBlockTitle) ?? "Study block"
        self.secondsPerCard = max(secondsPerCard, 1)
        self.upNextEvents = PlannerDay.normalized(upNextEvents) ?? "meetings and calls"
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
            eventBufferMinutes: section?["eventBufferMinutes"]?.numberValue.map { Int($0.rounded()) }
                ?? defaults.eventBufferMinutes,
            studyBlockTitle: section?["studyBlockTitle"]?.stringValue ?? defaults.studyBlockTitle,
            secondsPerCard: section?["secondsPerCard"]?.numberValue ?? defaults.secondsPerCard,
            upNextEvents: section?["upNextEvents"]?.stringValue ?? defaults.upNextEvents
        )
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
