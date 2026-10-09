import Foundation
import TabbiKitCore
import SwiftUI

/// State for the Usage panel: live subscription limits from the user's
/// `claude` CLI plus local token stats from session transcripts, or, while
/// the Codex CLI is the chosen AI (`source`), both read from Codex's own
/// session logs.
///
/// Each live Claude probe spends a sliver of the user's own usage, so probes only
/// run on the refresh button or when the panel opens with a snapshot older
/// than `ClaudeLimitsRecord.staleAfter`; never on a timer. The last snapshot
/// is persisted so the panel is instant on launch. Codex logs its limits
/// itself, so for Codex a refresh only re-reads the logs.
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
    /// Whose logs the panel shows; follows the chosen AI.
    @Published private(set) var source: AIUsageSource

    private static let defaultsKey = "claudeUsage.limitsRecord"

    private let isDemo: Bool
    private let defaults = UserDefaults.standard
    private let scanner: ClaudeUsageLogScanner
    private var statusTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var codexTask: Task<Void, Never>?
    private let codexRoot: URL
    /// Where Codex's sessions are read from, as the panel shows it
    /// (`~/.codex/sessions`, or the folder under `CODEX_HOME`).
    var codexFolder: String { (codexRoot.path as NSString).abbreviatingWithTildeInPath }
    /// The Claude probe's last snapshot, kept while Codex is shown so
    /// switching back is instant.
    private var claudeLimits: ClaudeLimitsRecord?
    /// A scan was requested while one was running; run another when it ends.
    private var rescanPending = false

    /// `codexRoot` is where Codex keeps its sessions; tests point it at a
    /// temporary folder.
    init(storage: EditionStorage, runMode: RunMode, source: AIUsageSource = .claudeCode,
         codexRoot: URL = CodexUsageLog.defaultRoot(),
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        isDemo = runMode.isDemo
        self.source = source
        self.codexRoot = codexRoot
        scanner = ClaudeUsageLogScanner(indexURL: ClaudeUsageLogScanner.indexURL(in: storage))
        if isDemo {
            // TABBI_USAGE_PREVIEW=codex renders the Codex panel.
            if environment["TABBI_USAGE_PREVIEW"] == "codex" { self.source = .codex }
            loadDemoData()
            return
        }
        claudeLimits = ClaudeLimitsRecord(encoded: defaults.data(forKey: Self.defaultsKey))
        load()
    }

    /// Called when the chosen AI changes, so the panel shows its logs.
    func setSource(_ newSource: AIUsageSource) {
        guard !isDemo, newSource != source else { return }
        source = newSource
        probeError = nil
        stats = nil
        isFetching = (newSource == .codex ? codexTask : probeTask) != nil
        load()
    }

    /// Shows what is already known for `source` and starts reading the rest.
    private func load() {
        switch source {
        case .claudeCode:
            limits = claudeLimits
            updateCLIStatus()
            // Warm the stats so the first open is instant; later scans are incremental.
            scanLocalStats()
        case .codex:
            limits = nil
            updateCLIStatus()
            readCodexLogs()
        }
    }

    /// Called when the panel becomes visible.
    func panelDidAppear() {
        guard !isDemo else { return }
        switch source {
        case .claudeCode:
            scanLocalStats()
            if ClaudeLimitsRecord.shouldRefreshOnOpen(limits, now: Date()) { refresh() }
        case .codex:
            readCodexLogs()
        }
    }

    /// Probes the CLI for live limits, or re-reads the Codex logs. No-op
    /// while a probe is running.
    func refresh() {
        guard !isDemo else { return }
        guard source.probesLimits else {
            readCodexLogs()
            return
        }
        guard probeTask == nil else { return }
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
        guard !isDemo, source == .claudeCode else { return }
        updateCLIStatus()
    }

    /// Cancels the previous lookup so a slow one for an old path (or the
    /// other source) can't win.
    private func updateCLIStatus() {
        statusTask?.cancel()
        cliStatus = .locating
        let source = source
        statusTask = Task { [weak self] in
            let url = await Self.locateCLI(for: source)
            guard !Task.isCancelled else { return }
            self?.cliStatus = url == nil ? .missing : .available
        }
    }

    /// Off the main thread: a cache miss may consult the login shell.
    private static func locateCLI(for source: AIUsageSource = .claudeCode) async -> URL? {
        await Task.detached(priority: .utility) {
            switch source {
            case .claudeCode: ClaudeExecutableResolver.shared.resolve()
            case .codex: AIProviderFactory.defaultLocate(.codexCLI)
            }
        }.value
    }

    /// Reads Codex's session logs off the main thread. Reading is free, so
    /// it runs whenever the panel opens; a read already running is reused.
    private func readCodexLogs() {
        guard codexTask == nil else { return }
        isFetching = true
        codexTask = Task { [weak self, codexRoot] in
            let usage = await Task.detached(priority: .utility) { CodexUsageLog.read(root: codexRoot) }.value
            guard let self else { return }
            codexTask = nil
            // The user may have switched back to Claude Code meanwhile, and
            // its probe may still be running.
            guard source == .codex else { return }
            isFetching = false
            limits = usage.limits
            stats = usage.stats
        }
    }

    private func finishProbe(_ outcome: Result<ClaudeRateLimitSnapshot, Error>, cliFound: Bool) {
        probeTask = nil
        if case .success(let snapshot) = outcome {
            let record = ClaudeLimitsRecord(snapshot: snapshot, fetchedAt: Date())
            claudeLimits = record
            defaults.set(record.encoded(), forKey: Self.defaultsKey)
        }
        // The user may have switched to Codex while the probe ran.
        guard source == .claudeCode else { return }
        isFetching = false
        cliStatus = cliFound ? .available : .missing
        switch outcome {
        case .success:
            limits = claudeLimits
            probeError = nil
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
            if source == .claudeCode { stats = result }
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

    /// Realistic sample data for screenshots (`TABBI_DEMO=1`).
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
        if source == .codex {
            loadCodexDemoStats()
            return
        }
        let today = ClaudeUsagePeriod(models: [
            ClaudeModelUsage(
                model: "claude-opus-5-5",
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
                model: "claude-opus-5-5",
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

    /// Codex turns: cached input is counted as cache reads, as in its logs.
    private func loadCodexDemoStats() {
        let today = ClaudeUsagePeriod(models: [
            ClaudeModelUsage(
                model: "gpt-5-codex",
                tokens: ClaudeTokenUsage(input: 214_000, output: 38_600, cacheRead: 1_186_000, cacheCreation: 0),
                messages: 96
            ),
        ])
        let week = ClaudeUsagePeriod(models: [
            ClaudeModelUsage(
                model: "gpt-5-codex",
                tokens: ClaudeTokenUsage(input: 1_320_000, output: 241_000, cacheRead: 7_480_000, cacheCreation: 0),
                messages: 612
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
