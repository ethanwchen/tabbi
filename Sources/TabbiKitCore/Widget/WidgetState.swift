import Foundation

/// What the desktop widget shows, written by the app into the App Group
/// container and read by the sandboxed widget extension.
///
/// The app writes it only when something the widget shows changes (a
/// session starts, pauses or ends, the pet's look changes, today's minutes
/// grow), so the widget never polls. Values that go stale on their own (a
/// countdown that ran out, minutes and a streak after midnight) are worked
/// out at the entry's date with `minutes(at:)`, `streak(at:)` and
/// `timer(at:)`, so the widget stays right while the app is not running.
public struct WidgetState: Hashable, Codable, Sendable {
    /// The clock the widget shows while a focus or break timer runs.
    public struct Timer: Hashable, Codable, Sendable {
        public enum Clock: Hashable, Codable, Sendable {
            /// Counting down to a wall-clock end.
            case countdown(endsAt: Date)
            /// An open-ended phase counting up from a wall-clock start.
            case countUp(since: Date)
            /// Stopped part-way, showing a frozen clock.
            case paused(shown: TimeInterval)
        }

        public var phase: FocusPhase
        /// The engine's name for the phase, such as "Focus" or "Long break".
        public var label: String
        public var clock: Clock

        /// Dates are kept in whole seconds, so the state reads back from
        /// its ISO 8601 file exactly as it was written.
        public init(phase: FocusPhase, label: String, clock: Clock) {
            self.phase = phase
            self.label = label
            switch clock {
            case .countdown(let end): self.clock = .countdown(endsAt: Self.wholeSeconds(end))
            case .countUp(let start): self.clock = .countUp(since: Self.wholeSeconds(start))
            case .paused: self.clock = clock
            }
        }

        private static func wholeSeconds(_ date: Date) -> Date {
            Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded())
        }

        /// The widget's view of a running clock; nil for an idle one, which
        /// the widget does not show.
        public init?(_ focus: ProvidedFocus) {
            let clock: Clock
            switch focus.clock {
            case .idle: return nil
            case .countdown(let end): clock = .countdown(endsAt: end)
            case .countUp(let start): clock = .countUp(since: start)
            case .paused(let shown): clock = .paused(shown: shown)
            }
            self.init(phase: focus.phase, label: focus.label, clock: clock)
        }
    }

    /// The pet as dressed in the Closet.
    public var pet: PetProfile
    /// The day `focusMinutes` counts.
    public var day: PlannerDayKey
    /// Minutes focused on `day`.
    public var focusMinutes: Int
    /// Days in a row with focus, ending on `lastFocusDay`.
    public var streakDays: Int
    /// The latest day with focus, or nil before the first session.
    public var lastFocusDay: PlannerDayKey?
    /// The running clock, or nil when no timer runs.
    public var timer: Timer?

    public init(pet: PetProfile, day: PlannerDayKey, focusMinutes: Int = 0, streakDays: Int = 0,
                lastFocusDay: PlannerDayKey? = nil, timer: Timer? = nil) {
        self.pet = pet
        self.day = day
        self.focusMinutes = max(focusMinutes, 0)
        self.streakDays = max(streakDays, 0)
        self.lastFocusDay = lastFocusDay
        self.timer = timer
    }

    /// The format of the shared file; a change to it is a new step here.
    public static let schema = VersionedJSON(current: 1)
    /// The file's name inside the App Group container.
    public static let fileName = "WidgetState.json"
    /// The App Group the app and the widget share (both entitlements files
    /// list it). The team-prefixed form needs no provisioning profile for a
    /// Developer ID build on macOS.
    public static let appGroup = "B9VRALHV8S.dev.tabbi.Tabbi"

    // MARK: Shown at a date

    /// Minutes focused on the day containing `date`: none once `day` is over.
    public func minutes(at date: Date, calendar: Calendar = .current) -> Int {
        day == PlannerDayKey(date: date, calendar: calendar) ? focusMinutes : 0
    }

    /// The streak on the day containing `date`. It still counts on the day
    /// after the last focus (there is time left to keep it) and is 0 after.
    public func streak(at date: Date, calendar: Calendar = .current) -> Int {
        guard let last = lastFocusDay else { return 0 }
        let today = PlannerDayKey(date: date, calendar: calendar)
        return last == today || last == today.adding(days: -1, calendar: calendar) ? streakDays : 0
    }

    /// The timer at `date`: nil once a countdown has run out, since the app
    /// may not be running to say what came next.
    public func timer(at date: Date) -> Timer? {
        guard let timer else { return nil }
        if case .countdown(let end) = timer.clock, end <= date { return nil }
        return timer
    }

    /// The dates after `now` at which what the widget shows changes without
    /// a new write from the app: the end of a countdown and the next
    /// midnight. The widget's timeline has an entry at `now` and at each.
    public func changeDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        if case .countdown(let end)? = timer?.clock, end > now { dates.append(end) }
        let midnight = PlannerDayKey(date: now, calendar: calendar).adding(days: 1, calendar: calendar)
            .startDate(calendar: calendar)
        dates.append(midnight)
        return Array(Set(dates)).sorted()
    }

    // MARK: Streak

    /// The streak and its last day from the days that had focus, as of
    /// `today`: consecutive days ending on the latest focus day on or before
    /// `today`. Days after `today` (a clock set back) are ignored.
    public static func streak(focusDays: Set<PlannerDayKey>, today: PlannerDayKey,
                              calendar: Calendar = .current) -> (days: Int, last: PlannerDayKey?) {
        guard let last = focusDays.filter({ $0 <= today }).max() else { return (0, nil) }
        var count = 0
        var day = last
        while focusDays.contains(day) {
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return (count, last)
    }

    // MARK: Encoding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try Self.schema.encode(self, using: encoder)
    }

    public static func decode(_ data: Data) throws -> WidgetState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try schema.decode(WidgetState.self, from: data, using: decoder)
    }

    // MARK: Sample

    /// What the widget shows before the app has written anything: the
    /// starter cat with no focus yet.
    public static func empty(at now: Date = Date(), calendar: Calendar = .current) -> WidgetState {
        WidgetState(pet: .starter(.cat), day: PlannerDayKey(date: now, calendar: calendar))
    }

    /// Demo and widget gallery data: the starter cat on a five day streak,
    /// mid-way through a focus block.
    public static func sample(at now: Date = Date(), calendar: Calendar = .current) -> WidgetState {
        let today = PlannerDayKey(date: now, calendar: calendar)
        let end = now.addingTimeInterval(18 * 60)
        return WidgetState(pet: .starter(.cat), day: today, focusMinutes: 85, streakDays: 5, lastFocusDay: today,
                           timer: Timer(phase: .focus, label: "Focus", clock: .countdown(endsAt: end)))
    }
}

/// Reads and writes the shared `WidgetState` file in a folder (the App Group
/// container in the app and the widget, a temporary folder in tests).
public struct WidgetStateFile: Sendable {
    public let url: URL

    public init(folder: URL) {
        url = folder.appendingPathComponent(WidgetState.fileName)
    }

    /// The saved state, or nil when there is none or it can't be read.
    public func read() -> WidgetState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetState.decode(data)
    }

    /// Saves `state` unless the file already holds it. Returns whether it
    /// wrote, so the app reloads the widget's timeline only on a change.
    @discardableResult
    public func write(_ state: WidgetState) throws -> Bool {
        if read() == state { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try state.encoded().write(to: url, options: .atomic)
        return true
    }
}
