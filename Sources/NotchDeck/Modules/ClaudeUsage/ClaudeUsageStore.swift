import Foundation
import NotchKitCore
import SwiftUI

/// State for the Claude Usage panel: live subscription limits from the
/// user's `claude` CLI plus local token stats from session transcripts.
///
/// Each live probe spends a sliver of the user's own usage, so probes only
/// run on the refresh button or when the panel opens with a snapshot older
/// than `ClaudeLimitsRecord.staleAfter`; never on a timer. The last snapshot
/// is persisted so the panel is instant on launch.
@MainActor
final class ClaudeUsageStore: ObservableObject {
    enum CLIStatus: Equatable {
        case locating
        case available
        case missing
    }

    @Published private(set) var cliStatus: CLIStatus = .locating
    /// The most recent successful probe, possibly from a previous launch.
    @Published private(set) var limits: ClaudeLimitsRecord?
    @Published private(set) var isFetching = false
    /// Set when the latest probe failed; `limits` keeps the previous snapshot.
    @Published private(set) var probeError: String?
    /// nil until the first transcript scan finishes.
    @Published private(set) var stats: ClaudeLocalStats?

    private static let defaultsKey = "claudeUsage.limitsRecord"

    private let isDemo: Bool
    private let defaults = UserDefaults.standard
    private let scanner: ClaudeUsageLogScanner
    private var statusTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    /// A scan was requested while one was running; run another when it ends.
    private var rescanPending = false

    init(storage: EditionStorage, runMode: RunMode) {
        isDemo = runMode.isDemo
        scanner = ClaudeUsageLogScanner(indexURL: ClaudeUsageLogScanner.indexURL(in: storage))
        if isDemo {
            loadDemoData()
            return
        }
        limits = ClaudeLimitsRecord(encoded: defaults.data(forKey: Self.defaultsKey))
        updateCLIStatus()
        // Warm the stats so the first open is instant; later scans are incremental.
        scanLocalStats()
    }

    /// Called when the panel becomes visible.
    func panelDidAppear() {
        guard !isDemo else { return }
        scanLocalStats()
        if ClaudeLimitsRecord.shouldRefreshOnOpen(limits, now: Date()) { refresh() }
    }

    /// Probes the CLI for live limits. No-op while a probe is running.
    func refresh() {
        guard !isDemo, probeTask == nil else { return }
        isFetching = true
        probeTask = Task { [weak self] in
            let executable = await Self.locateCLI()
            let outcome: Result<ClaudeRateLimitSnapshot, Error>
            if let executable {
                do { outcome = .success(try await ClaudeLimitsProbe.run(executable: executable)) }
                catch { outcome = .failure(error) }
            } else {
                outcome = .failure(ClaudeLimitsProbe.Failure.noLimitsReported)
            }
            self?.finishProbe(outcome, cliFound: executable != nil)
        }
    }

    /// Called when the user changes the `claude` path in Settings.
    func claudePathDidChange() {
        guard !isDemo else { return }
        updateCLIStatus()
    }

    /// Cancels the previous lookup so a slow one for an old path can't win.
    private func updateCLIStatus() {
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            let url = await Self.locateCLI()
            guard !Task.isCancelled else { return }
            self?.cliStatus = url == nil ? .missing : .available
        }
    }

    /// Off the main thread: a cache miss may consult the login shell.
    private static func locateCLI() async -> URL? {
        await Task.detached(priority: .utility) { ClaudeExecutableResolver.shared.resolve() }.value
    }

    private func finishProbe(_ outcome: Result<ClaudeRateLimitSnapshot, Error>, cliFound: Bool) {
        probeTask = nil
        isFetching = false
        cliStatus = cliFound ? .available : .missing
        switch outcome {
        case .success(let snapshot):
            let record = ClaudeLimitsRecord(snapshot: snapshot, fetchedAt: Date())
            limits = record
            probeError = nil
            defaults.set(record.encoded(), forKey: Self.defaultsKey)
        case .failure(let error):
            probeError = cliFound ? Self.describe(error) : nil
        }
        // The probe itself wrote a transcript line; pick it up.
        scanLocalStats()
    }

    private func scanLocalStats() {
        guard scanTask == nil else {
            rescanPending = true
            return
        }
        scanTask = Task(priority: .utility) { [weak self, scanner] in
            let result = await scanner.scan()
            guard let self else { return }
            stats = result
            scanTask = nil
            if rescanPending {
                rescanPending = false
                scanLocalStats()
            }
        }
    }

    /// A short, user-facing reason for a failed probe.
    private static func describe(_ error: Error) -> String {
        switch error {
        case ClaudeLimitsProbe.Failure.timedOut:
            return "Claude didn't respond in time"
        case ClaudeLimitsProbe.Failure.noLimitsReported:
            return "Claude didn't report usage limits"
        case ClaudeLimitsProbe.Failure.cliError(let text):
            let message = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return message.isEmpty || message.count > 60 ? "Claude returned an error" : message
        default:
            return "Couldn't reach Claude"
        }
    }

    // MARK: Demo

    /// Realistic sample data for screenshots (`NOTCHDECK_DEMO=1`).
    private func loadDemoData() {
        let now = Date()
        cliStatus = .available
        limits = ClaudeLimitsRecord(
            snapshot: ClaudeRateLimitSnapshot(
                status: "allowed",
                fiveHour: ClaudeUsageWindow(utilization: 0.42, resetsAt: now + 2 * 3600 + 14 * 60 + 30),
                sevenDay: ClaudeUsageWindow(utilization: 0.76, resetsAt: Self.demoWeeklyReset(after: now))
            ),
            fetchedAt: now - 3 * 60
        )
        let today = ClaudeUsagePeriod(models: [
            ClaudeModelUsage(
                model: "claude-opus-4-5-20251101",
                tokens: ClaudeTokenUsage(input: 18_400, output: 96_300, cacheRead: 1_642_000, cacheCreation: 212_500),
                messages: 214
            ),
            ClaudeModelUsage(
                model: "claude-haiku-4-5-20251001",
                tokens: ClaudeTokenUsage(input: 6_100, output: 12_800, cacheRead: 148_000, cacheCreation: 31_000),
                messages: 58
            ),
        ])
        let week = ClaudeUsagePeriod(models: [
            ClaudeModelUsage(
                model: "claude-opus-4-5-20251101",
                tokens: ClaudeTokenUsage(input: 96_000, output: 512_000, cacheRead: 9_870_000, cacheCreation: 1_204_000),
                messages: 1_318
            ),
            ClaudeModelUsage(
                model: "claude-haiku-4-5-20251001",
                tokens: ClaudeTokenUsage(input: 31_000, output: 64_000, cacheRead: 702_000, cacheCreation: 158_000),
                messages: 297
            ),
        ])
        stats = ClaudeLocalStats(today: today, lastSevenDays: week)
    }

    /// Next Thursday 9:00, so the weekly label reads like "resets Thu 9:00 AM".
    private static func demoWeeklyReset(after now: Date) -> Date {
        let calendar = Calendar.current
        let components = DateComponents(hour: 9, minute: 0, weekday: 5)
        let next = calendar.nextDate(after: now + 24 * 3600, matching: components, matchingPolicy: .nextTime)
        return next ?? now + 3 * 24 * 3600
    }
}
