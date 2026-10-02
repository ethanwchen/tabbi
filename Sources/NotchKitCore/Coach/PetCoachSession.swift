import Foundation

extension PetCoachStudyState {
    /// Reads the shared focus timer (`ProviderSnapshot.focus`) the way the
    /// coach sees it: only a running focus phase counts as studying, so the
    /// pet stays quiet on breaks, while paused, and with no timer at all.
    public init(_ timer: FocusTimer?) {
        guard let timer else {
            self = .notStudying
            return
        }
        if timer.isPaused {
            self = .paused
        } else if !timer.isRunning {
            self = .notStudying
        } else {
            self = timer.phase == .focus ? .focusing : .onBreak
        }
    }
}

extension PetCoachInput {
    /// Focus phases at least this long count as deep focus: long reading
    /// stretches are expected there, so idle checks wait longer.
    public static let deepFocusPhaseLength: TimeInterval = 45 * 60

    /// One reading built from the shared focus timer, so the app only has
    /// to supply what the system reports (idle seconds, frontmost app).
    public init(now: Date, idleSeconds: TimeInterval, frontmost: CoachAppCategory, timer: FocusTimer?) {
        self.init(
            now: now,
            idleSeconds: idleSeconds,
            frontmost: frontmost,
            study: PetCoachStudyState(timer),
            deepFocus: (timer?.config.focusDuration ?? 0) >= Self.deepFocusPhaseLength
        )
    }
}

extension PetCoach {
    /// How often the app samples idle time and the frontmost app while a
    /// focus phase runs. The coach's shortest threshold is 30 s, so 5 s is
    /// plenty; outside focus the app does not sample at all.
    public static let sampleInterval: TimeInterval = 5
}

/// The coach's persisted state: its cooldowns and snooze (so a relaunch
/// can't reset the rate limits) and the user's focus/distracting app lists.
/// One versioned JSON document next to the pet's `PetSave`.
public struct PetCoachSave: Hashable, Codable, Sendable {
    /// Bump when the format changes in a way old builds cannot read.
    public static let currentVersion = 1

    public var version: Int
    public var coach: PetCoach
    public var apps: CoachAppList
    /// The user's Settings switch. Off means the app doesn't sample at all,
    /// so the pet never walks out.
    public var nudgesOn: Bool

    public init(coach: PetCoach = PetCoach(), apps: CoachAppList = CoachAppList(), nudgesOn: Bool = true) {
        version = Self.currentVersion
        self.coach = coach
        self.apps = apps
        self.nudgesOn = nudgesOn
    }

    private enum CodingKeys: String, CodingKey { case version, coach, apps, nudgesOn }

    /// Saves written before the switch existed read as nudges on.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        coach = try container.decode(PetCoach.self, forKey: .coach)
        apps = try container.decode(CoachAppList.self, forKey: .apps)
        nudgesOn = try container.decodeIfPresent(Bool.self, forKey: .nudgesOn) ?? true
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PetCoachSave {
        try JSONDecoder().decode(PetCoachSave.self, from: data)
    }

    /// Loads the save at `url`, or returns nil when there is none yet.
    /// A corrupt file throws so the caller can decide not to overwrite it.
    public static func load(from url: URL) throws -> PetCoachSave? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decode(Data(contentsOf: url))
    }

    /// Writes atomically, creating the parent folder if needed.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try encoded().write(to: url, options: .atomic)
    }
}
