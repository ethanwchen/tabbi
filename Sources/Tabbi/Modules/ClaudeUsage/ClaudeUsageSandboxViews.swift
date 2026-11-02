import SwiftUI
import TabbiKitCore
import TabbiKit

/// The sandboxed build's first view of AI Usage: what it reads and where,
/// before the open panel asks for the folder. Continue opens the panel; the
/// footer's menu shows the other tool instead. Nothing is read until a
/// folder is picked.
struct UsageFolderCard: View {
    @ObservedObject var store: ClaudeUsageStore

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                Image(systemName: ClaudeUsageModule.descriptor.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(store.pickedWrongFolder ? wrongFolder : explanation)
                        .font(Theme.Typography.body)
                        .foregroundStyle(store.pickedWrongFolder ? Theme.Palette.warning : Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    UsagePillButton(title: String(localized: "Continue", bundle: .tabbi), isProminent: true,
                                    help: String(localized: "Choose the \(folder) folder next", bundle: .tabbi)) {
                        store.pickFolder()
                    }
                    .padding(.top, Theme.Spacing.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var accent: Color { ClaudeUsageModule.descriptor.accentColor }
    private var folder: String { AIUsageFolder.toolFolderName(for: store.source) }

    private var title: String {
        String(localized: "See your \(store.source.toolName) usage", bundle: .tabbi)
    }

    private var explanation: String {
        switch store.source {
        case .claudeCode:
            String(localized: "Tabbi can count your tokens from the logs Claude Code keeps in the \(folder) folder. Choose it next. Nothing leaves your Mac.", bundle: .tabbi)
        case .codex:
            String(localized: "Tabbi can show your limits and tokens from the logs Codex keeps in the \(folder) folder. Choose it next. Nothing leaves your Mac.", bundle: .tabbi)
        }
    }

    private var wrongFolder: String {
        String(localized: "That folder has no \(store.source.toolName) logs. Choose the \(folder) folder in your home folder.", bundle: .tabbi)
    }
}

/// In place of the live limits, which only the claude CLI can report: the
/// week's tokens as one bar per day, today in the module's accent.
struct DailyTokensCard: View {
    let stats: ClaudeLocalStats?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Tokens per day", bundle: .tabbi)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(1)
                HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        bar(day, isToday: index == days.count - 1)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 228)
        .motion(Theme.Motion.content, value: stats?.daily)
    }

    private struct Day {
        let tokens: Int
        let date: Date
    }

    /// Seven days ending today, with zeros while the scan runs.
    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let values = stats?.daily.count == 7 ? stats?.daily ?? [] : Array(repeating: 0, count: 7)
        return values.enumerated().map { index, tokens in
            Day(tokens: tokens, date: calendar.date(byAdding: .day, value: index - 6, to: today) ?? today)
        }
    }

    private var peak: Int { max(days.map(\.tokens).max() ?? 0, 1) }

    private func bar(_ day: Day, isToday: Bool) -> some View {
        let accent = ClaudeUsageModule.descriptor.accentColor
        let label = day.date.formatted(.dateTime.weekday(.narrow))
        let tokens = ClaudeUsageFormat.compactTokens(day.tokens)
        return VStack(spacing: Theme.Spacing.xs) {
            GeometryReader { geometry in
                let height = max(geometry.size.height * CGFloat(day.tokens) / CGFloat(peak), day.tokens > 0 ? 4 : 2)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isToday ? accent : accent.opacity(day.tokens > 0 ? 0.45 : 0.2))
                    .frame(height: height)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(isToday ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .help(String(localized: "\(day.date.formatted(.dateTime.weekday(.wide))): \(tokens) tokens", bundle: .tabbi))
    }
}

/// The sandboxed build's tool picker in the footer: which logs the panel
/// shows, as no command line AI can be the chosen one there.
struct UsageSourceMenu: View {
    @ObservedObject var store: ClaudeUsageStore
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach([AIUsageSource.claudeCode, .codex], id: \.self) { source in
                Button {
                    store.setSource(source)
                } label: {
                    if source == store.source {
                        Label(source.toolName, systemImage: "checkmark")
                    } else {
                        Text(source.toolName)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(store.source.toolName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 22)
            .background(Capsule().fill(hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: "Pick whose usage to show", bundle: .tabbi))
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// A small capsule button in the module's accent, prominent for the one
/// next step.
struct UsagePillButton: View {
    let title: String
    var isProminent = false
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = ClaudeUsageModule.descriptor.accentColor
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(isProminent ? Theme.Palette.onAccent : accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xxs)
                .frame(height: 24)
                .background(Capsule().fill(isProminent ? accent.opacity(hovering ? 1 : 0.9)
                                           : accent.opacity(hovering ? 0.28 : 0.16)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
