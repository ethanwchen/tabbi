import Foundation

/// The last live limits probe and when it happened. Persisted so the panel
/// shows numbers instantly on launch without spending a probe.
public struct ClaudeLimitsRecord: Equatable, Sendable {
    public var snapshot: ClaudeRateLimitSnapshot
    public var fetchedAt: Date

    public init(snapshot: ClaudeRateLimitSnapshot, fetchedAt: Date) {
        self.snapshot = snapshot
        self.fetchedAt = fetchedAt
    }

    /// Each probe runs a tiny `claude -p` request that counts against the
    /// user's own limits, so opening the panel only re-probes after this long.
    public static let staleAfter: TimeInterval = 10 * 60

    /// Whether opening the panel should trigger a probe. Never before the
    /// first manual refresh: spending the user's usage is opt-in. Manual
    /// refresh always probes regardless.
    public static func shouldRefreshOnOpen(_ record: ClaudeLimitsRecord?, now: Date) -> Bool {
        guard let record else { return false }
        return now.timeIntervalSince(record.fetchedAt) >= staleAfter
    }

    // MARK: Persistence

    private struct Stored: Codable {
        struct Window: Codable {
            var utilization: Double
            var resetsAt: Date?
        }
        var status: String?
        var fiveHour: Window?
        var sevenDay: Window?
        var fetchedAt: Date
    }

    /// JSON encoding for UserDefaults. A private schema so the shared
    /// `ClaudeRateLimitSnapshot` type doesn't need to be Codable.
    public func encoded() -> Data? {
        func window(_ value: ClaudeUsageWindow?) -> Stored.Window? {
            value.map { Stored.Window(utilization: $0.utilization, resetsAt: $0.resetsAt) }
        }
        let stored = Stored(
            status: snapshot.status,
            fiveHour: window(snapshot.fiveHour),
            sevenDay: window(snapshot.sevenDay),
            fetchedAt: fetchedAt
        )
        return try? JSONEncoder().encode(stored)
    }

    /// Decodes `encoded()` output; nil for missing or corrupt data.
    public init?(encoded data: Data?) {
        guard let data, let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        func window(_ value: Stored.Window?) -> ClaudeUsageWindow? {
            value.map { ClaudeUsageWindow(utilization: $0.utilization, resetsAt: $0.resetsAt) }
        }
        self.init(
            snapshot: ClaudeRateLimitSnapshot(
                status: stored.status,
                fiveHour: window(stored.fiveHour),
                sevenDay: window(stored.sevenDay)
            ),
            fetchedAt: stored.fetchedAt
        )
    }
}
