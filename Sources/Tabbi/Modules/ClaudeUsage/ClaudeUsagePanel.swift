import SwiftUI
import TabbiKitCore
import TabbiKit

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
                    // A shorter panel (Compact) packs the card's lines closer
                    // instead of clipping it.
                    ViewThatFits(in: .vertical) {
                        TodayCard(stats: store.stats, source: store.source, spacing: Theme.Spacing.s)
                        TodayCard(stats: store.stats, source: store.source, spacing: Theme.Spacing.xs)
                    }
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
            CLIMissingCard(source: store.source, codexFolder: store.codexFolder)
        } else {
            let snapshot = store.limits?.snapshot
            HStack(spacing: Theme.Spacing.xs) {
                UsageRing(title: String(localized: "5-hour", bundle: .tabbi), window: snapshot?.fiveHour, now: now,
                          help: String(localized: "Usage of your rolling 5-hour limit", bundle: .tabbi))
                UsageRing(title: String(localized: "Weekly", bundle: .tabbi), window: snapshot?.sevenDay, now: now,
                          help: String(localized: "Usage of your weekly limit", bundle: .tabbi))
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
            ProgressRing(progress: utilization, tint: color(for: utilization),
                         track: Theme.Palette.surface, lineWidth: Self.lineWidth) {
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
            .motion(Theme.Motion.content, value: utilization)

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
        case .normal: ClaudeUsageModule.descriptor.accentColor
        case .warning: Theme.Palette.warning
        case .critical: Theme.Palette.danger
        }
    }
}

/// Today's local usage from Claude Code transcripts or Codex logs.
private struct TodayCard: View {
    let stats: ClaudeLocalStats?
    let source: AIUsageSource
    /// The gap between the card's lines.
    let spacing: CGFloat

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: spacing) {
                Text("Today in \(source.toolName)", bundle: .tabbi)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                if let stats {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(ClaudeUsageFormat.compactTokens(stats.today.tokens.total))
                            .font(Theme.Typography.metric)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .contentTransition(.numericText())
                        Text("tokens", bundle: .tabbi)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .help(String(localized: "Input, output, and cache tokens across all \(source.toolName) sessions since midnight", bundle: .tabbi))
                    Spacer(minLength: 0)
                    row(String(localized: "Messages", bundle: .tabbi), value: stats.today.messages.formatted())
                    row(String(localized: "Top model", bundle: .tabbi), value: stats.today.topModel.map(ClaudeUsageFormat.modelName) ?? String(localized: "None yet", bundle: .tabbi))
                    let week = ClaudeUsageFormat.compactTokens(stats.lastSevenDays.tokens.total)
                    row(String(localized: "Last 7 days", bundle: .tabbi), value: String(localized: "\(week) tokens", bundle: .tabbi), short: week)
                } else {
                    Spacer(minLength: 0)
                    HStack(spacing: Theme.Spacing.s) {
                        Spinner(tint: ClaudeUsageModule.descriptor.accentColor)
                        Text("Reading \(source.toolName) sessions…", bundle: .tabbi)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .motion(Theme.Motion.content, value: stats)
    }

    /// The title stays whole; on the narrow Compact panel the value falls
    /// back to `short` (the figure without its unit) instead of clipping.
    private func row(_ title: String, value: String, short: String? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: Theme.Spacing.s)
            ViewThatFits(in: .horizontal) {
                Text(value)
                if let short { Text(short) }
            }
            .foregroundStyle(Theme.Palette.primaryText)
            .monospacedDigit()
            .lineLimit(1)
        }
        .font(Theme.Typography.body)
    }
}

/// Shown in place of the rings when the source's CLI can't be found.
private struct CLIMissingCard: View {
    let source: AIUsageSource
    let codexFolder: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label(String(localized: "\(source.toolName) not found", bundle: .tabbi), systemImage: "terminal")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(explanation)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                pathNote
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    // A long CODEX_HOME folder shortens in the middle.
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 228)
    }

    /// Where the data comes from, with the folder or variable in monospace.
    private var pathNote: Text {
        let path = Text(source == .codex ? codexFolder : ClaudeCLI.overrideVariable)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
        return source == .codex
            ? Text("Tabbi reads \(path) and sends nothing.", bundle: .tabbi)
            : Text("Installed elsewhere? Set \(path) to its path.", bundle: .tabbi)
    }

    private var explanation: String {
        switch source {
        case .claudeCode: String(localized: "Install Claude Code and sign in to see your live 5-hour and weekly limits.", bundle: .tabbi)
        case .codex: String(localized: "Install Codex and sign in with ChatGPT to see your 5-hour and weekly limits.", bundle: .tabbi)
        }
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
                RefreshButton(isFetching: store.isFetching, source: store.source, action: store.refresh)
            }
        }
        .font(Theme.Typography.caption.monospacedDigit())
        .frame(height: 24)
        .help(store.probeError ?? "")
        .motion(Theme.Motion.snappy, value: store.isFetching)
    }

    private var status: String {
        if store.isFetching {
            return store.source == .codex ? String(localized: "Reading Codex logs…", bundle: .tabbi) : String(localized: "Checking limits…", bundle: .tabbi)
        }
        let updated = store.limits.map { ClaudeUsageFormat.updatedDescription(fetchedAt: $0.fetchedAt, now: now) }
        if let error = store.probeError {
            return updated.map { String(localized: "Refresh failed · \($0)", bundle: .tabbi) } ?? error
        }
        if let updated { return updated }
        switch store.cliStatus {
        case .locating: return String(localized: "Looking for \(store.source.toolName)…", bundle: .tabbi)
        case .missing: return String(localized: "Showing local stats only", bundle: .tabbi)
        case .available where store.source == .codex: return String(localized: "No limits in your Codex logs yet", bundle: .tabbi)
        case .available: return String(localized: "Not checked yet · refresh to load your live limits", bundle: .tabbi)
        }
    }
}

/// The shared `IconButton`, spinning while a probe runs. Rotating the whole
/// button is invisible on its circular background, so only the glyph turns.
private struct RefreshButton: View {
    let isFetching: Bool
    let source: AIUsageSource
    let action: () -> Void

    var body: some View {
        IconButton(symbol: "arrow.clockwise", size: 24,
                   help: source.probesLimits
                       ? String(localized: "Check live limits (sends a tiny request with your claude CLI)", bundle: .tabbi)
                       : String(localized: "Read the latest Codex logs (sends nothing)", bundle: .tabbi),
                   action: action)
            .spinning(isFetching)
        .disabled(isFetching)
    }
}
