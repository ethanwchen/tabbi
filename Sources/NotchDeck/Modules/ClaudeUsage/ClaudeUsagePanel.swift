import SwiftUI
import NotchDeckCore

/// Live 5-hour and weekly limits as rings, today's local usage in a card,
/// and a footer with freshness and a manual refresh.
struct ClaudeUsagePanel: View {
    @ObservedObject var store: ClaudeUsageStore

    var body: some View {
        // Relative labels ("resets in 2h 14m", "Updated 3m ago") only need
        // minute precision, and the timeline pauses when the panel is hidden.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.l) {
                    limitsArea(now: context.date)
                    TodayCard(stats: store.stats)
                }
                .frame(maxHeight: .infinity)
                UsageFooter(store: store, now: context.date)
            }
        }
        .onAppear { store.panelDidAppear() }
    }

    @ViewBuilder
    private func limitsArea(now: Date) -> some View {
        if store.cliStatus == .missing && store.limits == nil {
            CLIMissingCard()
        } else {
            let snapshot = store.limits?.snapshot
            HStack(spacing: Theme.Spacing.xs) {
                UsageRing(title: "5-hour", window: snapshot?.fiveHour, now: now,
                          help: "Usage of your rolling 5-hour limit")
                UsageRing(title: "Weekly", window: snapshot?.sevenDay, now: now,
                          help: "Usage of your weekly limit")
            }
        }
    }
}

/// One usage window as a ring with the percentage inside.
private struct UsageRing: View {
    let title: String
    let window: ClaudeUsageWindow?
    let now: Date
    let help: String

    private static let diameter: CGFloat = 80
    private static let lineWidth: CGFloat = 7

    var body: some View {
        let utilization = window?.utilization ?? 0
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle()
                    .stroke(Theme.Palette.surface, lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(utilization, 0), 1))
                    .stroke(color(for: utilization),
                            style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let window {
                    Text(ClaudeUsageFormat.percent(window.utilization))
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .padding(.bottom, Theme.Spacing.xxs)
            .animation(Theme.Motion.content, value: utilization)

            Text(title)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text(window.flatMap { ClaudeUsageFormat.resetDescription(resetsAt: $0.resetsAt, now: now) } ?? " ")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
        }
        // Fixed width so the layout doesn't shift as the reset label changes.
        .frame(width: 120)
        .help(help)
    }

    private func color(for utilization: Double) -> Color {
        switch ClaudeUsageLevel(utilization: utilization) {
        case .normal: Theme.Palette.accent(for: .claudeUsage)
        case .warning: Theme.Palette.warning
        case .critical: Theme.Palette.danger
        }
    }
}

/// Today's local usage from Claude Code transcripts.
private struct TodayCard: View {
    let stats: ClaudeLocalStats?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Today")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                if let stats {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(ClaudeUsageFormat.compactTokens(stats.today.tokens.total))
                            .font(Theme.Typography.metric)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .contentTransition(.numericText())
                        Text("tokens")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .help("Input, output, and cache tokens across all Claude Code sessions since midnight")
                    Spacer(minLength: 0)
                    row("Messages", value: "\(stats.today.messages)")
                    row("Top model", value: stats.today.topModel.map(ClaudeUsageFormat.modelName) ?? "None yet")
                    row("Last 7 days", value: ClaudeUsageFormat.compactTokens(stats.lastSevenDays.tokens.total) + " tokens")
                } else {
                    Spacer(minLength: 0)
                    HStack(spacing: Theme.Spacing.s) {
                        LoadingArc()
                        Text("Reading Claude Code sessions…")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(Theme.Motion.content, value: stats)
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.Palette.secondaryText)
            Spacer(minLength: Theme.Spacing.s)
            Text(value)
                .foregroundStyle(Theme.Palette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(Theme.Typography.body)
    }
}

/// Shown in place of the rings when the `claude` CLI can't be found.
private struct CLIMissingCard: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("Claude Code not found", systemImage: "terminal")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Install Claude Code and sign in to see your live 5-hour and weekly limits.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                (Text("Installed elsewhere? Set ")
                    + Text(ClaudeCLI.overrideVariable).font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    + Text(" to its path."))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 228)
    }
}

/// Freshness, probe warnings, and the refresh button.
private struct UsageFooter: View {
    @ObservedObject var store: ClaudeUsageStore
    let now: Date

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if store.probeError != nil && !store.isFetching {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Palette.warning)
            }
            Text(status)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.Spacing.s)
            if store.cliStatus != .missing {
                RefreshButton(isFetching: store.isFetching, action: store.refresh)
            }
        }
        .font(Theme.Typography.caption.monospacedDigit())
        .frame(height: 24)
        .help(store.probeError ?? "")
        .animation(Theme.Motion.snappy, value: store.isFetching)
    }

    private var status: String {
        if store.isFetching { return "Checking limits…" }
        let updated = store.limits.map { ClaudeUsageFormat.updatedDescription(fetchedAt: $0.fetchedAt, now: now) }
        if let error = store.probeError {
            return updated.map { "Refresh failed · \($0)" } ?? error
        }
        if let updated { return updated }
        switch store.cliStatus {
        case .locating: return "Looking for Claude Code…"
        case .missing: return "Showing local stats only"
        case .available: return "Not checked yet · refresh to load your live limits"
        }
    }
}

/// A small spinning arc. Pure SwiftUI (unlike `ProgressView`) so it also
/// renders in snapshots; driven by the clock, so it only ticks while shown.
private struct LoadingArc: View {
    var body: some View {
        TimelineView(.animation) { context in
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(Theme.Palette.accent(for: .claudeUsage),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(spinAngle(at: context.date)))
        }
        .frame(width: 12, height: 12)
    }
}

/// One turn per second, derived from the clock rather than an animation.
private func spinAngle(at date: Date) -> Double {
    date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
}

/// The shared `IconButton`, spinning while a probe runs. Rotating the whole
/// button is invisible on its circular background, so only the glyph turns.
private struct RefreshButton: View {
    let isFetching: Bool
    let action: () -> Void

    var body: some View {
        TimelineView(.animation(paused: !isFetching)) { context in
            IconButton(symbol: "arrow.clockwise", size: 24,
                       help: "Check live limits (sends a tiny request with your claude CLI)",
                       action: action)
                .rotationEffect(.degrees(isFetching ? spinAngle(at: context.date) : 0))
        }
        .disabled(isFetching)
    }
}
