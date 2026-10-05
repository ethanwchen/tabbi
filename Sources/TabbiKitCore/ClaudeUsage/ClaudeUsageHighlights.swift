import Foundation

/// What Claude Usage shows beside the closed notch: a rate-limit window that
/// is above `threshold`, e.g. "5h 86%".
///
/// One highlight per window above the threshold, each expiring when its
/// window resets (the snapshot is only refreshed on demand, so after that
/// its number no longer holds). The ticker shows the one with the highest
/// priority, which is the fuller window; ties favor the 5-hour window
/// because it resets sooner and is the one the user can act on.
public enum ClaudeUsageHighlights {
    /// Usage only surfaces once a window is above this fraction.
    public static let threshold: Double = 0.8

    /// Which rate-limit window a highlight reports.
    public enum Window: String, Sendable {
        case fiveHour
        case weekly

        /// Short label for the notch, e.g. "5h".
        public var label: String { self == .fiveHour ? "5h" : "Week" }
    }

    /// The highlights for `snapshot` at `now`; empty when no window is above
    /// the threshold or every such window has reset.
    public static func highlights(for snapshot: ClaudeRateLimitSnapshot?, at now: Date,
                                  source: ModuleID = .claudeUsage) -> [TickerHighlight] {
        let windows: [(Window, ClaudeUsageWindow?)] = [(.fiveHour, snapshot?.fiveHour), (.weekly, snapshot?.sevenDay)]
        return windows.compactMap { window, usage in
            guard let usage, usage.utilization > threshold,
                  usage.resetsAt.map({ $0 > now }) ?? true else { return nil }
            return highlight(window: window, utilization: usage.utilization, resetsAt: usage.resetsAt, source: source)
        }
    }

    /// The highlight for one window at `utilization`.
    public static func highlight(window: Window, utilization: Double, resetsAt: Date? = nil,
                                 source: ModuleID = .claudeUsage) -> TickerHighlight {
        let text = "\(window.label) \(ClaudeUsageFormat.percent(utilization))"
        return TickerHighlight(
            id: window.rawValue, source: source, text: text, summary: "Claude usage \(text)",
            tone: utilization >= 1 ? .danger : .accent,
            // Per mille, doubled so the 5-hour window wins a tie.
            priority: Int((utilization * 1000).rounded()) * 2 + (window == .fiveHour ? 1 : 0),
            expiresAt: resetsAt
        )
    }
}
