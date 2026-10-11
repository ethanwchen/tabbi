import Foundation

/// The rare lines the cat says in its speech bubble right after a focus
/// session ends ("Cat wisdom"). The lines are fixed copy approved by the
/// maintainer; `CatWisdomSchedule` decides when one shows.
public enum CatWisdom {
    /// Lines for the first completed session of an ordinary day.
    public static let daily: [String] = [
        "The pawn keeps moving forward. One square at a time, it can become anything it wants.",
        "Nobody sees roots growing. Then one day there's a tree.",
        "You didn't feel like it, and you did it anyway. That's the whole secret.",
        "Water carves canyons by never skipping a day.",
        "The person you're becoming is built in quiet hours like this one.",
        "Talent is a head start. Showing up is the whole race.",
        "The work no one sees is the work that changes you.",
        "You're not behind. You're on your own clock, and it only moves forward.",
        "Stars don't rush. They just keep burning.",
        "Every hour you give your future, it gives back with interest.",
        "Hard things get easy the same way paths get worn: one step, many times.",
        "Most people wait to feel ready. You just started. That's the difference.",
    ]

    /// Lines for the first completed session after two or more days without one.
    public static let comeback: [String] = [
        "Falling off isn't failing. Staying off is. And look, you're back.",
        "Cats land on their feet because they never stop turning toward the ground. Welcome back.",
    ]

    /// The gentle line after a session stopped early that still earned points.
    public static let earlyStop = "Some is infinitely more than none. Rest. The board will be here."

    /// The line for a session completed late at night.
    public static let lateNight = "Sleep is part of the work. Go dream up tomorrow's moves."

    /// One line from the daily pool for the weekly recap card, the same for
    /// every look at the same week and a different one week to week.
    public static func recapLine(forWeekStarting weekStart: Date, calendar: Calendar = .current) -> String {
        let day = PlannerDayKey(date: weekStart, calendar: calendar).startDate(calendar: calendar)
        let weeks = Int((day.timeIntervalSinceReferenceDate / (7 * 86_400)).rounded(.down))
        let index = ((weeks % daily.count) + daily.count) % daily.count
        return daily[index]
    }
}

/// A study milestone the cat marks with its own line, once, the first time
/// it is reached.
public enum CatWisdomMilestone: String, CaseIterable, Codable, Sendable {
    case sevenDayStreak
    case thirtyDayStreak
    case tenHours
    case fiftyHours
    /// A 100-day streak or 100 hours focused, whichever comes first: the
    /// pawn reaching the last square.
    case lastSquare

    public var line: String {
        switch self {
        case .sevenDayStreak: "Seven days. You're not trying anymore. You're becoming."
        case .thirtyDayStreak: "Thirty days ago this was hard. Notice that it isn't anymore."
        case .tenHours: "Ten hours of betting on yourself. Keep betting."
        case .fiftyHours: "The pawn has crossed half the board. The far side is closer than it looks."
        case .lastSquare: "The pawn reached the last square. Now it can move any way it wants. So can you."
        }
    }

    /// Whether a user with this streak (days) and total focus (minutes) has
    /// reached the milestone.
    public func isReached(streakDays: Int, focusMinutes: Int) -> Bool {
        switch self {
        case .sevenDayStreak: streakDays >= 7
        case .thirtyDayStreak: streakDays >= 30
        case .tenHours: focusMinutes >= 10 * 60
        case .fiftyHours: focusMinutes >= 50 * 60
        case .lastSquare: streakDays >= 100 || focusMinutes >= 100 * 60
        }
    }
}

/// Why a wisdom line showed, for tests and for the bubble's styling.
public enum CatWisdomKind: Hashable, Sendable {
    case milestone(CatWisdomMilestone)
    case comeback
    case lateNight
    case firstOfDay
    case earlyStop
}

/// A line to show and why.
public struct CatWisdomLine: Hashable, Sendable {
    public var kind: CatWisdomKind
    public var text: String

    public init(kind: CatWisdomKind, text: String) {
        self.kind = kind
        self.text = text
    }

    /// The line in the user's language. `text` is the approved English,
    /// which the schedule and tests work with, so the translation is looked
    /// up by it, as seasonal event names are; a line the catalog lacks
    /// shows as written.
    public var displayText: String {
        Bundle.tabbi.localizedString(forKey: text, value: text, table: nil)
    }
}

/// A focus session that just ended, as the wisdom schedule sees it.
public struct CatWisdomSession: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        /// The focus phase ran to its end.
        case completed
        /// The user stopped early and the session still earned points.
        case stoppedWithPoints
    }

    public var outcome: Outcome
    /// When the session ended.
    public var end: Date
    /// When the completed session before this one ended, or nil if there was none.
    public var previousCompletion: Date?
    /// The study streak in days, this session included.
    public var streakDays: Int
    /// Minutes focused in total, this session included.
    public var totalFocusMinutes: Int

    public init(outcome: Outcome, end: Date, previousCompletion: Date?, streakDays: Int, totalFocusMinutes: Int) {
        self.outcome = outcome
        self.end = end
        self.previousCompletion = previousCompletion
        self.streakDays = streakDays
        self.totalFocusMinutes = totalFocusMinutes
    }
}

/// When the cat says a wisdom line, and which one. Persisted, so the
/// rotation and the caps survive a restart.
///
/// Rules (the maintainer's design, with no guilt mechanics):
/// - Only right after a focus session ends; never during focus, on launch
///   or as a notification. At most one line per calendar day.
/// - Priority: an unshown milestone, then a comeback (the first completed
///   session after two or more days without one), then a late-night line
///   (a session completed from 11 PM, at most once a week), then on the
///   first completed session of the day a daily line with `ordinaryChance`.
/// - A session stopped early with points may get the early-stop line, with
///   the same chance as an ordinary day; it counts toward the daily cap.
/// - Each pool rotates without repeats until every line has shown.
/// - Milestones show once each. Those already reached on the first look
///   (an existing user) or while the toggle is off are marked as seen
///   silently, so turning the feature on never brings a backlog.
public struct CatWisdomSchedule: Codable, Hashable, Sendable {
    /// The chance of a daily or early-stop line on an ordinary day, which
    /// lands about 3 to 4 lines in a week of study.
    public static let ordinaryChance = 0.5
    /// Days between late-night lines.
    public static let lateNightGapDays = 7
    /// Days without a completed session that make the next one a comeback.
    public static let comebackGapDays = 2

    public static let schema = VersionedJSON(current: 1)

    /// The day the last line showed.
    public private(set) var lastShownDay: PlannerDayKey?
    /// The day the last late-night line showed.
    public private(set) var lastLateNightDay: PlannerDayKey?
    /// Indices into `CatWisdom.daily` shown in the current rotation.
    public private(set) var dailyShown: [Int]
    /// Indices into `CatWisdom.comeback` shown in the current rotation.
    public private(set) var comebackShown: [Int]
    /// Milestones already shown or passed silently.
    public private(set) var milestonesSeen: Set<CatWisdomMilestone>
    /// Whether milestones reached before the first look have been marked.
    public private(set) var baselined: Bool

    public init() {
        dailyShown = []
        comebackShown = []
        milestonesSeen = []
        baselined = false
    }

    /// The line to show for `session`, or nil, updating the rotation and
    /// caps when one shows. With `enabled` off it shows nothing and only
    /// marks reached milestones as seen.
    public mutating func line<G: RandomNumberGenerator>(
        for session: CatWisdomSession,
        enabled: Bool = true,
        calendar: Calendar = .current,
        using generator: inout G
    ) -> CatWisdomLine? {
        let reached = CatWisdomMilestone.allCases.filter {
            $0.isReached(streakDays: session.streakDays, focusMinutes: session.totalFocusMinutes)
        }
        guard enabled, baselined else {
            baselined = true
            milestonesSeen.formUnion(reached)
            guard enabled else { return nil }
            return line(for: session, enabled: true, calendar: calendar, using: &generator)
        }
        let today = PlannerDayKey(date: session.end, calendar: calendar)
        guard lastShownDay != today else { return nil }

        let picked: CatWisdomLine?
        switch session.outcome {
        case .stoppedWithPoints:
            picked = Double.random(in: 0..<1, using: &generator) < Self.ordinaryChance
                ? CatWisdomLine(kind: .earlyStop, text: CatWisdom.earlyStop) : nil
        case .completed:
            picked = completedLine(for: session, today: today, reached: reached, calendar: calendar, using: &generator)
        }
        if picked != nil { lastShownDay = today }
        return picked
    }

    private mutating func completedLine<G: RandomNumberGenerator>(
        for session: CatWisdomSession, today: PlannerDayKey, reached: [CatWisdomMilestone],
        calendar: Calendar, using generator: inout G
    ) -> CatWisdomLine? {
        if let milestone = reached.first(where: { !milestonesSeen.contains($0) }) {
            milestonesSeen.insert(milestone)
            return CatWisdomLine(kind: .milestone(milestone), text: milestone.line)
        }
        let previousDay = session.previousCompletion.map { PlannerDayKey(date: $0, calendar: calendar) }
        if let previousDay, previousDay.adding(days: Self.comebackGapDays + 1, calendar: calendar) <= today {
            let index = Self.next(in: CatWisdom.comeback.count, shown: &comebackShown, using: &generator)
            return CatWisdomLine(kind: .comeback, text: CatWisdom.comeback[index])
        }
        if Self.isLateNight(session.end, calendar: calendar),
           lastLateNightDay.map({ $0.adding(days: Self.lateNightGapDays, calendar: calendar) <= today }) ?? true {
            lastLateNightDay = today
            return CatWisdomLine(kind: .lateNight, text: CatWisdom.lateNight)
        }
        guard previousDay != today,
              Double.random(in: 0..<1, using: &generator) < Self.ordinaryChance else { return nil }
        let index = Self.next(in: CatWisdom.daily.count, shown: &dailyShown, using: &generator)
        return CatWisdomLine(kind: .firstOfDay, text: CatWisdom.daily[index])
    }

    /// Late night: from 11 PM to 4 AM local time.
    static func isLateNight(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 23 || hour < 4
    }

    /// An index not shown in this rotation, starting a new rotation (that
    /// still skips the last one shown) once every line has been used.
    private static func next<G: RandomNumberGenerator>(in count: Int, shown: inout [Int],
                                                        using generator: inout G) -> Int {
        shown = shown.filter { (0..<count).contains($0) }
        var candidates = (0..<count).filter { !shown.contains($0) }
        if candidates.isEmpty {
            let last = shown.last
            shown = []
            candidates = (0..<count).filter { $0 != last || count == 1 }
        }
        let index = candidates.randomElement(using: &generator)!
        shown.append(index)
        return index
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastShownDay = try container.decodeIfPresent(PlannerDayKey.self, forKey: .lastShownDay)
        lastLateNightDay = try container.decodeIfPresent(PlannerDayKey.self, forKey: .lastLateNightDay)
        dailyShown = try container.decodeIfPresent([Int].self, forKey: .dailyShown) ?? []
        comebackShown = try container.decodeIfPresent([Int].self, forKey: .comebackShown) ?? []
        let milestones = try container.decodeIfPresent([String].self, forKey: .milestonesSeen) ?? []
        milestonesSeen = Set(milestones.compactMap(CatWisdomMilestone.init(rawValue:)))
        baselined = try container.decodeIfPresent(Bool.self, forKey: .baselined) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastShownDay, forKey: .lastShownDay)
        try container.encodeIfPresent(lastLateNightDay, forKey: .lastLateNightDay)
        try container.encode(dailyShown, forKey: .dailyShown)
        try container.encode(comebackShown, forKey: .comebackShown)
        try container.encode(milestonesSeen.map(\.rawValue).sorted(), forKey: .milestonesSeen)
        try container.encode(baselined, forKey: .baselined)
    }

    private enum CodingKeys: String, CodingKey {
        case lastShownDay, lastLateNightDay, dailyShown, comebackShown, milestonesSeen, baselined
    }
}

extension CatWisdomSession {
    /// The session behind a study award the pet just credited, read from
    /// what the pet already tracks: its streak and focus totals from the
    /// activity log, and the last completion the coach saw.
    ///
    /// Nil for an award with no session to speak of (a Party stay is
    /// celebrated by Party itself). A completed session counts today toward
    /// the streak, and its minutes count toward the total when today's log
    /// cannot hold them yet, so a milestone is never shown early (at worst
    /// one session late, when the log is behind on a busy day).
    ///
    /// - Parameter lastCompletion: when the coach last saw a session end on
    ///   time. Nil on a first look, which falls back to the last study day
    ///   before today in `progress`.
    public init?(award: PetStudyAward, at end: Date, lastCompletion: Date?, streak: StudyStreak,
                 progress: PetMilestoneProgress, calendar: Calendar = .current) {
        guard award.points > 0 else { return nil }
        let completed = award.completedSessions > 0
        let today = PlannerDayKey(date: end, calendar: calendar)
        let previous = lastCompletion ?? progress.studyDays.filter { $0 < today }.max()?.startDate(calendar: calendar)
        let todayMinutes = progress.minutesByDay[today] ?? 0
        // The log already holds this session once today's minutes cover it.
        let logged = todayMinutes >= Double(award.minutes)
        let streakDays = streak.length + (completed && !streak.studiedToday ? 1 : 0)
        let total = Int(progress.focusMinutes) + (logged ? 0 : award.minutes)
        self.init(outcome: completed ? .completed : .stoppedWithPoints, end: end, previousCompletion: previous,
                  streakDays: streakDays, totalFocusMinutes: total)
    }
}
