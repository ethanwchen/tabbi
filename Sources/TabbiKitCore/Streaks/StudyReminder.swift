import Foundation

/// The user's daily study reminder. It is off until the user turns it on,
/// and fires at most once a day at the time they pick.
public struct StudyReminderSettings: Codable, Hashable, Sendable {
    /// 7 pm: after school or work, with time left for a short session.
    public static let defaultMinuteOfDay = 19 * 60
    public static let off = StudyReminderSettings(isEnabled: false, minuteOfDay: defaultMinuteOfDay)

    public var isEnabled: Bool
    /// Local time of day in minutes after midnight, clamped to 0..<1440.
    public var minuteOfDay: Int {
        didSet { minuteOfDay = Self.clamped(minuteOfDay) }
    }

    public init(isEnabled: Bool, minuteOfDay: Int = defaultMinuteOfDay) {
        self.isEnabled = isEnabled
        self.minuteOfDay = Self.clamped(minuteOfDay)
    }

    public init(isEnabled: Bool, hour: Int, minute: Int) {
        self.init(isEnabled: isEnabled, minuteOfDay: hour * 60 + minute)
    }

    public var hour: Int { minuteOfDay / 60 }
    public var minute: Int { minuteOfDay % 60 }

    /// Reads leniently: a missing or out-of-range time keeps the default
    /// or is clamped, so a damaged value never turns the reminder on.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? false
        let minute = (try? container.decode(Int.self, forKey: .minuteOfDay)) ?? Self.defaultMinuteOfDay
        self.init(isEnabled: isEnabled, minuteOfDay: minute)
    }

    private static func clamped(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}

/// When the daily study reminder fires and what it says.
///
/// Rules:
/// - It fires only when turned on, at the chosen local time.
/// - It skips a day once the user has studied (enough focus to count for
///   the streak) or met the day's goal, so it never nags someone who
///   already showed up.
/// - It fires at most once a day: after it was delivered, the next one is
///   tomorrow's, even if the user moves the time later the same day.
/// - Tomorrow's reminder is always planned, because tomorrow has no study
///   yet; the app plans again whenever study, the day or the settings change.
public enum StudyReminder {
    /// The notification's text.
    public struct Message: Hashable, Sendable {
        public var title: String
        public var body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// A short, guilt-free nudge in the pet's voice: "Mochi misses you" and
    /// "10 minutes?", with a word about the streak when one is running.
    public static func message(petName: String?, streakLength: Int) -> Message {
        let name = petName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = "\(name.isEmpty ? "Tabbi" : name) misses you"
        let body = if streakLength > 0 {
            "10 minutes? That keeps your \(streakLength)-day streak going."
        } else {
            "10 minutes?"
        }
        return Message(title: title, body: body)
    }

    /// The moment the reminder should fire next, or nil when it is off.
    ///
    /// - Parameters:
    ///   - studiedToday: today already counts as a study day.
    ///   - goalMetToday: the day's study goal is met.
    ///   - lastDelivered: when a reminder last fired, so a day never gets two.
    public static func nextFireDate(settings: StudyReminderSettings, now: Date,
                                    studiedToday: Bool, goalMetToday: Bool,
                                    lastDelivered: Date?, calendar: Calendar = .current) -> Date? {
        guard settings.isEnabled else { return nil }
        let today = PlannerDayKey(date: now, calendar: calendar)
        let deliveredToday = lastDelivered.map { PlannerDayKey(date: $0, calendar: calendar) == today } ?? false
        if !studiedToday, !goalMetToday, !deliveredToday,
           let fire = fireDate(on: today, settings: settings, calendar: calendar), fire > now {
            return fire
        }
        return fireDate(on: today.adding(days: 1, calendar: calendar), settings: settings, calendar: calendar)
    }

    /// The chosen time on `day`. A time that a daylight saving change skips
    /// (2:30 on the spring-forward night) moves to the next valid moment.
    public static func fireDate(on day: PlannerDayKey, settings: StudyReminderSettings,
                                calendar: Calendar = .current) -> Date? {
        let start = day.startDate(calendar: calendar)
        if settings.minuteOfDay == 0 { return start }
        return calendar.nextDate(after: start,
                                 matching: DateComponents(hour: settings.hour, minute: settings.minute),
                                 matchingPolicy: .nextTime)
    }
}
