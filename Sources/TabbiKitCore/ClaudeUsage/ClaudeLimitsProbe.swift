import Foundation

/// Reads the live usage limits from the user's `claude` CLI.
///
/// The CLI reports a `rate_limit_event` near the start of every request, so a
/// probe sends a trivial prompt to the cheapest model and stops the process as
/// soon as that event arrives, before the answer is generated.
public enum ClaudeLimitsProbe {
    public enum Failure: Error, Equatable, Sendable {
        /// The CLI finished without reporting limits (e.g. API-key login,
        /// which has no subscription windows).
        case noLimitsReported
        /// The CLI reported an error result, e.g. not logged in.
        case cliError(String?)
        /// No limits arrived within the timeout.
        case timedOut
    }

    /// Runs one probe against `executable`.
    public static func run(executable: URL, timeout: Duration = .seconds(45)) async throws -> ClaudeRateLimitSnapshot {
        try await firstSnapshot(
            in: ClaudeCLI.stream(executable: executable, prompt: "ok", extraArguments: ["--model", "haiku"]),
            timeout: timeout
        )
    }

    /// Returns the first rate-limit event that carries a usage window, then
    /// cancels the consumption of `events`, which stops the underlying process.
    ///
    /// Returning from a `for await` loop does not end an `AsyncThrowingStream`
    /// whose producer is still alive; only cancelling a task suspended in it
    /// does. So the consumer hands the snapshot over through `found` and keeps
    /// waiting until the group cancels it.
    public static func firstSnapshot(
        in events: AsyncThrowingStream<ClaudeStreamEvent, Error>,
        timeout: Duration
    ) async throws -> ClaudeRateLimitSnapshot {
        let (found, foundContinuation) = AsyncStream<ClaudeRateLimitSnapshot>.makeStream()
        return try await withThrowingTaskGroup(of: ClaudeRateLimitSnapshot?.self) { group in
            group.addTask {
                defer { foundContinuation.finish() }
                var reported = false
                for try await event in events {
                    switch event {
                    case .rateLimit(let snapshot) where !reported && (snapshot.fiveHour != nil || snapshot.sevenDay != nil):
                        reported = true
                        foundContinuation.yield(snapshot)
                    case .result(let result) where result.isError && !reported:
                        throw Failure.cliError(result.text)
                    default:
                        continue
                    }
                }
                if !reported { throw Failure.noLimitsReported }
                return nil
            }
            group.addTask {
                for await snapshot in found { return snapshot }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw Failure.timedOut
            }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if let snapshot = result { return snapshot }
            }
            throw Failure.noLimitsReported
        }
    }
}
