import Foundation

/// Usage of one model within a period.
public struct ClaudeModelUsage: Equatable, Sendable, Codable {
    public var model: String
    public var tokens: ClaudeTokenUsage
    public var messages: Int

    public init(model: String, tokens: ClaudeTokenUsage, messages: Int) {
        self.model = model
        self.tokens = tokens
        self.messages = messages
    }
}

/// Totals for one period, broken down by model.
public struct ClaudeUsagePeriod: Equatable, Sendable, Codable {
    /// Sorted by total tokens, largest first.
    public var models: [ClaudeModelUsage]

    public init(models: [ClaudeModelUsage]) {
        self.models = models
    }

    public static let empty = ClaudeUsagePeriod(models: [])

    public var tokens: ClaudeTokenUsage { models.reduce(.zero) { $0 + $1.tokens } }
    public var messages: Int { models.reduce(0) { $0 + $1.messages } }
    /// The model that processed the most tokens.
    public var topModel: String? { models.first?.model }
}

/// Local Claude Code usage computed from session transcripts.
public struct ClaudeLocalStats: Equatable, Sendable, Codable {
    /// Since local midnight.
    public var today: ClaudeUsagePeriod
    /// Today plus the six calendar days before it.
    public var lastSevenDays: ClaudeUsagePeriod
    /// Total tokens on each of those seven days, oldest first and today
    /// last, for the week's bar chart. Empty when unknown (older callers).
    public var daily: [Int]

    public init(today: ClaudeUsagePeriod, lastSevenDays: ClaudeUsagePeriod, daily: [Int] = []) {
        self.today = today
        self.lastSevenDays = lastSevenDays
        self.daily = daily
    }

    public static let empty = ClaudeLocalStats(today: .empty, lastSevenDays: .empty,
                                               daily: Array(repeating: 0, count: 7))

    private enum CodingKeys: String, CodingKey {
        case today, lastSevenDays, daily
    }

    /// `daily` came later; a value saved without it decodes with none.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decode(ClaudeUsagePeriod.self, forKey: .today)
        lastSevenDays = try container.decode(ClaudeUsagePeriod.self, forKey: .lastSevenDays)
        daily = try container.decodeIfPresent([Int].self, forKey: .daily) ?? []
    }

    /// Start of the seven-day window: midnight six days before `now`.
    public static func windowStart(now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today
    }

    /// Aggregates records into today / last-seven-days totals. Records are
    /// expected to be unique by message id; records after `now` are ignored.
    public static func aggregate(
        _ records: some Sequence<ClaudeUsageRecord>,
        now: Date,
        calendar: Calendar = .current
    ) -> ClaudeLocalStats {
        let todayStart = calendar.startOfDay(for: now)
        let weekStart = windowStart(now: now, calendar: calendar)
        var today: [String: ClaudeModelUsage] = [:]
        var week: [String: ClaudeModelUsage] = [:]
        var daily = [Int](repeating: 0, count: 7)

        func add(_ record: ClaudeUsageRecord, to bucket: inout [String: ClaudeModelUsage]) {
            bucket[record.model, default: ClaudeModelUsage(model: record.model, tokens: .zero, messages: 0)]
                .tokens += record.usage
            bucket[record.model]!.messages += 1
        }

        for record in records where record.timestamp >= weekStart && record.timestamp <= now {
            add(record, to: &week)
            if record.timestamp >= todayStart { add(record, to: &today) }
            // Calendar days, so a day that lost an hour to daylight saving
            // still counts as one.
            let day = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: record.timestamp)).day ?? 0
            daily[min(max(day, 0), 6)] += record.usage.total
        }

        func period(_ bucket: [String: ClaudeModelUsage]) -> ClaudeUsagePeriod {
            ClaudeUsagePeriod(models: bucket.values.sorted {
                ($0.tokens.total, $1.model) > ($1.tokens.total, $0.model)
            })
        }
        return ClaudeLocalStats(today: period(today), lastSevenDays: period(week), daily: daily)
    }
}
