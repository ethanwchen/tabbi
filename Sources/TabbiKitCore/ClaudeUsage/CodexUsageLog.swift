import Foundation

/// What the OpenAI Codex CLI's own session logs say about usage: its latest
/// 5-hour and weekly limits and the tokens it used today and this week.
///
/// Codex writes one rollout file per session
/// (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`). After each model turn
/// it logs a `token_count` event with the session's running token totals
/// and, on ChatGPT plans, the plan's rate limits. Reading those files costs
/// the user nothing, unlike a live Claude probe, so the Usage tab can show
/// Codex limits without spending any of them.
public struct CodexUsage: Equatable, Sendable {
    /// The newest limits any session logged, stamped with when it logged
    /// them; nil when no session reported limits (API-key sign-in).
    public var limits: ClaudeLimitsRecord?
    public var stats: ClaudeLocalStats

    public init(limits: ClaudeLimitsRecord?, stats: ClaudeLocalStats) {
        self.limits = limits
        self.stats = stats
    }

    public static let empty = CodexUsage(limits: nil, stats: .empty)
}

/// Parses Codex rollout logs into `CodexUsage`. Strictly read-only.
public enum CodexUsageLog {
    /// `$CODEX_HOME/sessions`, or `~/.codex/sessions` when CODEX_HOME is unset.
    public static func defaultRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return home.appendingPathComponent("sessions", isDirectory: true)
    }

    /// Reads every session file touched in the last seven days. Files are
    /// memory-mapped and only `token_count` and `turn_context` lines are
    /// decoded, so tool output in the logs is never parsed.
    public static func read(
        root: URL = defaultRoot(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CodexUsage {
        let windowStart = ClaudeLocalStats.windowStart(now: now, calendar: calendar)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return .empty }
        var sessions: [Data] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true,
                  (values?.contentModificationDate ?? .distantPast) >= windowStart,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe)
            else { continue }
            sessions.append(data)
        }
        return summarize(sessions: sessions, now: now, calendar: calendar)
    }

    /// Aggregates the given session files (each one rollout's bytes).
    public static func summarize(
        sessions: [Data],
        now: Date,
        calendar: Calendar = .current
    ) -> CodexUsage {
        var records: [ClaudeUsageRecord] = []
        var latest: ClaudeLimitsRecord?
        for session in sessions {
            var model = defaultModel
            var previous = ClaudeTokenUsage.zero
            for line in lines(of: session) {
                switch line {
                case .model(let name):
                    model = name
                case .tokens(let timestamp, let total, let limits):
                    // Totals are cumulative per session; each increase is one
                    // model turn. A drop means the counter restarted.
                    let delta = total.total < previous.total ? total : difference(total, previous)
                    previous = total
                    if delta.total > 0 {
                        records.append(ClaudeUsageRecord(messageID: "", model: model, timestamp: timestamp, usage: delta))
                    }
                    if let limits, timestamp <= now, timestamp > (latest?.fetchedAt ?? .distantPast) {
                        latest = ClaudeLimitsRecord(snapshot: limits, fetchedAt: timestamp)
                    }
                }
            }
        }
        if let fetchedAt = latest?.fetchedAt, let snapshot = latest?.snapshot {
            // Codex only logs limits when it runs, so a window that has reset
            // since the last session is empty now.
            latest?.snapshot = ClaudeRateLimitSnapshot(
                status: snapshot.status,
                fiveHour: current(snapshot.fiveHour, length: 5 * 3600, fetchedAt: fetchedAt, now: now),
                sevenDay: current(snapshot.sevenDay, length: 7 * 86400, fetchedAt: fetchedAt, now: now))
        }
        return CodexUsage(limits: latest, stats: ClaudeLocalStats.aggregate(records, now: now, calendar: calendar))
    }

    /// `window` as of `now`: empty once its reset time has passed, or, for
    /// old logs with no reset time, once a whole window has gone by.
    private static func current(_ window: ClaudeUsageWindow?, length: TimeInterval,
                                fetchedAt: Date, now: Date) -> ClaudeUsageWindow? {
        guard let window else { return nil }
        let hasReset = window.resetsAt.map { $0 <= now } ?? (now.timeIntervalSince(fetchedAt) >= length)
        return hasReset ? ClaudeUsageWindow(utilization: 0, resetsAt: nil) : window
    }

    private static func difference(_ lhs: ClaudeTokenUsage, _ rhs: ClaudeTokenUsage) -> ClaudeTokenUsage {
        ClaudeTokenUsage(input: max(lhs.input - rhs.input, 0), output: max(lhs.output - rhs.output, 0),
                         cacheRead: max(lhs.cacheRead - rhs.cacheRead, 0))
    }

    /// Shown when a session never named its model (very old Codex versions).
    public static let defaultModel = "codex"

    // MARK: Lines

    enum Line {
        case model(String)
        case tokens(Date, total: ClaudeTokenUsage, limits: ClaudeRateLimitSnapshot?)
    }

    static func lines(of data: Data) -> [Line] {
        data.withUnsafeBytes { buffer -> [Line] in
            guard let base = buffer.baseAddress else { return [] }
            var result: [Line] = []
            var start = 0
            while start < buffer.count {
                let end = memchr(base + start, 0x0A, buffer.count - start)
                    .map { UnsafeRawPointer($0) - base } ?? buffer.count
                if let line = parse(UnsafeRawBufferPointer(start: base + start, count: end - start)) {
                    result.append(line)
                }
                start = end + 1
            }
            return result
        }
    }

    /// Parses one rollout line given as UTF-8 bytes; nil for anything else.
    static func parse(_ bytes: UnsafeRawBufferPointer) -> Line? {
        let isTokens = contains(bytes, tokenCountMarker)
        guard isTokens || contains(bytes, turnContextMarker), let base = bytes.baseAddress else { return nil }
        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: bytes.count, deallocator: .none)
        guard let line = try? decoder.decode(Entry.self, from: data), let payload = line.payload else { return nil }

        if line.type == "turn_context" {
            return payload.model.flatMap { $0.isEmpty ? nil : .model($0) }
        }
        guard line.type == "event_msg", payload.type == "token_count",
              let timestamp = line.timestamp.flatMap(parseTimestamp)
        else { return nil }
        let usage = payload.info?.totalTokenUsage
        let total = usage.map { usage in
            // Codex counts cached input inside input_tokens, and reasoning
            // inside output_tokens.
            let cached = usage.cachedInput ?? 0
            return ClaudeTokenUsage(input: max((usage.input ?? 0) - cached, 0), output: usage.output ?? 0, cacheRead: cached)
        }
        let limits = payload.rateLimits.flatMap { $0.snapshot(at: timestamp) }
        guard total != nil || limits != nil else { return nil }
        return .tokens(timestamp, total: total ?? .zero, limits: limits)
    }

    private struct Entry: Decodable {
        var timestamp: String?
        var type: String?
        var payload: Payload?
    }

    private struct Payload: Decodable {
        var type: String?
        var model: String?
        var info: Info?
        var rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type, model, info
            case rateLimits = "rate_limits"
        }
    }

    private struct Info: Decodable {
        var totalTokenUsage: Usage?

        enum CodingKeys: String, CodingKey {
            case totalTokenUsage = "total_token_usage"
        }
    }

    private struct Usage: Decodable {
        var input: Int?
        var cachedInput: Int?
        var output: Int?

        enum CodingKeys: String, CodingKey {
            case input = "input_tokens"
            case cachedInput = "cached_input_tokens"
            case output = "output_tokens"
        }
    }

    /// Codex has logged limits in two shapes: nested `primary`/`secondary`
    /// windows (with `resets_at` epoch seconds, or `resets_in_seconds`
    /// in versions before that), and before those, flat
    /// `primary_used_percent` fields with no reset time.
    private struct RateLimits: Decodable {
        struct Window: Decodable {
            var usedPercent: Double?
            var resetsAt: Double?
            var resetsInSeconds: Double?

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case resetsAt = "resets_at"
                case resetsInSeconds = "resets_in_seconds"
            }

            func window(at timestamp: Date) -> ClaudeUsageWindow? {
                guard let usedPercent else { return nil }
                let reset = resetsAt.map { Date(timeIntervalSince1970: $0) }
                    ?? resetsInSeconds.map { timestamp + $0 }
                return ClaudeUsageWindow(utilization: usedPercent / 100, resetsAt: reset)
            }
        }
        var primary: Window?
        var secondary: Window?
        var primaryUsedPercent: Double?
        var secondaryUsedPercent: Double?

        enum CodingKeys: String, CodingKey {
            case primary, secondary
            case primaryUsedPercent = "primary_used_percent"
            case secondaryUsedPercent = "secondary_used_percent"
        }

        /// Codex's primary window is the 5-hour one and its secondary the weekly one.
        func snapshot(at timestamp: Date) -> ClaudeRateLimitSnapshot? {
            let fiveHour = primary?.window(at: timestamp)
                ?? primaryUsedPercent.map { ClaudeUsageWindow(utilization: $0 / 100, resetsAt: nil) }
            let weekly = secondary?.window(at: timestamp)
                ?? secondaryUsedPercent.map { ClaudeUsageWindow(utilization: $0 / 100, resetsAt: nil) }
            guard fiveHour != nil || weekly != nil else { return nil }
            return ClaudeRateLimitSnapshot(status: nil, fiveHour: fiveHour, sevenDay: weekly)
        }
    }

    private static let decoder = JSONDecoder()
    private static let tokenCountMarker = Array("\"token_count\"".utf8)
    private static let turnContextMarker = Array("\"turn_context\"".utf8)

    private static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { pattern in
            guard let base = haystack.baseAddress, let pat = pattern.baseAddress else { return false }
            return memmem(base, haystack.count, pat, pattern.count) != nil
        }
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}
