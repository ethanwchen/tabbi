import Foundation

/// Turns the shared focus timer into heartbeats, so friends see when the
/// user studies without the Party module knowing which module runs the timer.
///
/// The app feeds it every timer change (`observe`) and asks it for the body
/// of each heartbeat (`heartbeat`). It decides:
///
/// - Status: a running focus phase is `studying`, a running break or a paused
///   timer is `break`, no session is `idle`, and going invisible is `offline`.
/// - When to send at once: `observe` returns `true` when status, method or
///   phase end changed since it last said so (and on the first call, for the
///   heartbeat at launch), which the polling guidance asks to report at once.
///   Counters alone never trigger a heartbeat; they ride on scheduled ones.
/// - Minutes: wall-clock time spent in running focus phases, clipped to each
///   phase's end, so a sleep or a missed tick never over-counts. Minutes are
///   split at local midnight, and `todayMinutes` restarts each local day.
/// - Streak: consecutive local days with any focus time; it stays visible on
///   the day after the last study day and drops to 0 once a day is missed.
///
/// Codable so the app can persist today's minutes and the streak across
/// launches. Only timer state and minute counts are kept: nothing about what
/// is studied, cards or decks.
public struct PartyPresenceTracker: Codable, Hashable, Sendable {
    /// The `catalog.studyMethods` id reported while studying or on a break.
    public var method: String
    public private(set) var isInvisible = false

    /// What friends currently see, from the last observation.
    public private(set) var status: PartyStatus = .idle
    public private(set) var phaseEndsAt: Date?

    /// The signature last reported as changed, so edits made between
    /// observations (such as a new `method`) are caught by the next one.
    private var announced: [String?] = []
    private var lastObserved: Date?
    /// End of the focus phase that was running at `lastObserved`, if any.
    private var focusEndsAt: Date?
    private var sessionSeconds: TimeInterval = 0
    private var todaySeconds: TimeInterval = 0
    /// The local day `todaySeconds` belongs to.
    private var day: String?
    /// The last local day with focus time, and the streak ending on it.
    private var lastStudyDay: String?
    private var streak = 0

    public init(method: String = "pomodoro") {
        self.method = method
    }

    /// Records the timer at `now` and credits focus time since the last
    /// observation. Returns `true` when friends should hear about it now.
    @discardableResult
    public mutating func observe(_ timer: ProvidedFocus?, at now: Date, calendar: Calendar = .current) -> Bool {
        credit(until: now, calendar: calendar)
        switch timer?.clock {
        case .countdown(let endsAt)? where endsAt <= now:
            // The phase ran out between ticks and its module hasn't moved
            // on yet: a finished focus phase leads to a break, a finished
            // break to no session.
            status = timer?.phase == .focus ? .onBreak : .idle
            phaseEndsAt = nil
            focusEndsAt = nil
            if status == .idle { sessionSeconds = 0 }
        case .countdown(let endsAt)?:
            let focusing = timer?.phase == .focus
            status = focusing ? .studying : .onBreak
            phaseEndsAt = Date(timeIntervalSince1970: endsAt.timeIntervalSince1970.rounded())
            focusEndsAt = focusing ? endsAt : nil
        case .countUp?:
            // Open-ended: no end to report, and focus time runs until the
            // next observation says otherwise.
            let focusing = timer?.phase == .focus
            status = focusing ? .studying : .onBreak
            phaseEndsAt = nil
            focusEndsAt = focusing ? .distantFuture : nil
        case .paused?:
            status = .onBreak
            phaseEndsAt = nil
            focusEndsAt = nil
        case .idle?, nil:
            status = .idle
            phaseEndsAt = nil
            focusEndsAt = nil
            sessionSeconds = 0
        }
        lastObserved = now
        return takeChange()
    }

    /// Going invisible reports `offline` (send it once, then stop); coming
    /// back reports the current status. Returns `true` when that changed.
    @discardableResult
    public mutating func setInvisible(_ invisible: Bool) -> Bool {
        isInvisible = invisible
        return takeChange()
    }

    /// The body of a heartbeat at `now`, crediting focus time up to then.
    /// Call `observe` with the current timer first so the status is fresh.
    public mutating func heartbeat(at now: Date, calendar: Calendar = .current) -> PartyHeartbeat {
        credit(until: now, calendar: calendar)
        guard !isInvisible else { return .offline }
        let today = Self.dayString(now, calendar: calendar)
        let active = status == .studying || status == .onBreak
        return PartyHeartbeat(
            status: status,
            method: active ? method : nil,
            phaseEndsAt: active ? phaseEndsAt : nil,
            sessionMinutes: active ? Self.minutes(sessionSeconds) : 0,
            todayMinutes: day == today ? Self.minutes(todaySeconds) : 0,
            streakDays: streakDays(on: today, calendar: calendar),
            day: today
        )
    }

    /// Whole minutes studied today, for showing the user their own numbers.
    public func todayMinutes(at now: Date, calendar: Calendar = .current) -> Int {
        day == Self.dayString(now, calendar: calendar) ? Self.minutes(todaySeconds) : 0
    }

    /// The streak as of `now`: kept through the day after the last study
    /// day, so it does not vanish before the user had a chance to study.
    public func streakDays(at now: Date, calendar: Calendar = .current) -> Int {
        streakDays(on: Self.dayString(now, calendar: calendar), calendar: calendar)
    }

    /// `YYYY-MM-DD` of `date` in `calendar`'s time zone, as the server expects.
    public static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Private

    /// What a heartbeat must report at once when it changes.
    private var signature: [String?] {
        if isInvisible { return [PartyStatus.offline.rawValue] }
        return [status.rawValue, method, phaseEndsAt.map { String(Int($0.timeIntervalSince1970)) }]
    }

    /// Whether the signature differs from the last one reported, marking
    /// the current one as reported.
    private mutating func takeChange() -> Bool {
        let current = signature
        defer { announced = current }
        return current != announced
    }

    /// Adds the focus time between the last observation and `now`.
    private mutating func credit(until now: Date, calendar: Calendar) {
        guard let start = lastObserved, let focusEnd = focusEndsAt else { return }
        let end = min(now, focusEnd)
        if end > start {
            sessionSeconds += end.timeIntervalSince(start)
            // Split at local midnights so each day gets its own minutes.
            var from = start
            while from < end {
                let nextMidnight = calendar.nextDate(
                    after: from, matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) ?? end
                let to = min(end, nextMidnight)
                add(to.timeIntervalSince(from), on: Self.dayString(from, calendar: calendar), calendar: calendar)
                from = to
            }
        }
        if now >= focusEnd { focusEndsAt = nil }
        lastObserved = now
    }

    private mutating func add(_ seconds: TimeInterval, on day: String, calendar: Calendar) {
        guard seconds > 0 else { return }
        if self.day != day {
            self.day = day
            todaySeconds = 0
        }
        todaySeconds += seconds
        if lastStudyDay != day {
            streak = lastStudyDay.map { Self.isDay($0, before: day, calendar: calendar) } == true ? streak + 1 : 1
            lastStudyDay = day
        }
    }

    private func streakDays(on today: String, calendar: Calendar) -> Int {
        guard let last = lastStudyDay else { return 0 }
        return last == today || Self.isDay(last, before: today, calendar: calendar) ? streak : 0
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        min(1440, Int(seconds / 60))
    }

    /// Whether `earlier` is the calendar day right before `later`.
    private static func isDay(_ earlier: String, before later: String, calendar: Calendar) -> Bool {
        guard let date = date(of: later, calendar: calendar),
              let previous = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        return dayString(previous, calendar: calendar) == earlier
    }

    private static func date(of day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
