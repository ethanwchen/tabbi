import Foundation

/// When to send the next request after a reply or a failure, following the
/// server's polling guidance: the server's `heartbeatSeconds` after a
/// success, `Retry-After` on `429`, and exponential backoff (5 s, 10 s,
/// 20 s, ... capped at 5 minutes) on outages and network errors.
///
/// The free-tier request budget is shared by every user, so this never
/// retries faster than the guidance, and stops after an `offline` reply.
public struct PartyHeartbeatSchedule: Hashable, Sendable {
    public static let initialBackoff: TimeInterval = 5
    public static let maxBackoff: TimeInterval = 300
    /// Used when a reply carries no interval but is not `offline`.
    public static let fallbackInterval: TimeInterval = 120

    /// Consecutive transient failures since the last success.
    public private(set) var failures = 0

    public init() {}

    /// After a heartbeat reply: the server's interval, or `nil` to stop
    /// (the reply to an `offline` heartbeat).
    public mutating func delayAfterSuccess(_ reply: PartyHeartbeatReply) -> TimeInterval? {
        failures = 0
        guard reply.presence.status != .offline else { return nil }
        return max(1, reply.nextHeartbeat ?? Self.fallbackInterval)
    }

    /// After a failed request: how long to wait before retrying, or `nil`
    /// when retrying the same request cannot help (e.g. `unauthorized`,
    /// which needs a fresh registration first).
    public mutating func delayAfterFailure(_ error: PartyError) -> TimeInterval? {
        guard error.isTransient else { return nil }
        if case .rateLimited(let retryAfter) = error {
            return retryAfter
        }
        let delay = min(Self.maxBackoff, Self.initialBackoff * pow(2, Double(failures)))
        failures += 1
        return delay
    }

    /// Forgets past failures, e.g. after the network comes back.
    public mutating func reset() {
        failures = 0
    }
}
