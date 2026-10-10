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

extension StudyReminder {
    /// Who the reminder speaks for: the pet's name, or "Your cat" while a
    /// cat still goes by its breed ("British Shorthair misses you" reads
    /// like a stranger).
    public static func speaker(for pet: PetProfile) -> String {
        pet.name == pet.breed.displayName ? "Your \(pet.breed.species.displayName.lowercased())" : pet.name
    }

    /// Whether the day's study goal (the Study timer's focus time goal,
    /// `StudyDailyGoal.progressID`) is met in the shared progress.
    /// False when no module shares that goal.
    public static func goalMet(in progress: [ProgressItem]) -> Bool {
        progress.contains { $0.id == StudyDailyGoal.progressID && $0.target > 0 && $0.isComplete }
    }
}

/// The reminder's saved state: the user's settings plus what was planned
/// and delivered, so a relaunch never sends a second reminder the same day.
/// One versioned JSON document next to the pet's save.
public struct StudyReminderSave: Codable, Hashable, Sendable {
    /// Version 1 is the first format.
    public static let schema = VersionedJSON(current: 1)

    public var settings: StudyReminderSettings
    /// The moment the pending reminder is set for, if one is.
    public var scheduledFor: Date?
    /// When a reminder last fired.
    public var lastDelivered: Date?

    public init(settings: StudyReminderSettings = .off, scheduledFor: Date? = nil, lastDelivered: Date? = nil) {
        self.settings = settings
        self.scheduledFor = scheduledFor
        self.lastDelivered = lastDelivered
    }

    /// Counts a planned reminder whose moment has passed as delivered. The
    /// system shows a pending reminder on time even while Tabbi is closed,
    /// and Tabbi withdraws it whenever its day stops needing one, so a past
    /// plan means it fired.
    public mutating func settle(now: Date) {
        guard let scheduledFor, scheduledFor <= now else { return }
        lastDelivered = max(lastDelivered ?? scheduledFor, scheduledFor)
        self.scheduledFor = nil
    }

    /// Settles the past and plans the next reminder, returning its moment
    /// (nil when the reminder is off).
    public mutating func plan(now: Date, studiedToday: Bool, goalMetToday: Bool,
                              calendar: Calendar = .current) -> Date? {
        settle(now: now)
        scheduledFor = StudyReminder.nextFireDate(settings: settings, now: now, studiedToday: studiedToday,
                                                  goalMetToday: goalMetToday, lastDelivered: lastDelivered,
                                                  calendar: calendar)
        return scheduledFor
    }

    private enum CodingKeys: String, CodingKey { case settings, scheduledFor, lastDelivered }

    /// Reads leniently: a damaged field falls back to its default, so a bad
    /// value never turns the reminder on or loses the delivery record.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = (try? container.decode(StudyReminderSettings.self, forKey: .settings)) ?? .off
        scheduledFor = try? container.decode(Date.self, forKey: .scheduledFor)
        lastDelivered = try? container.decode(Date.self, forKey: .lastDelivered)
    }

    /// The saved state, or nil when there is no file. Throws when the file
    /// exists but isn't a reminder save.
    public static func load(from url: URL) throws -> StudyReminderSave? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try schema.decode(StudyReminderSave.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.schema.encode(self).write(to: url, options: .atomic)
    }
}
