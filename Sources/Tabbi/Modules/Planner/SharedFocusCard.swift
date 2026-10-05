import SwiftUI
import TabbiKitCore
import TabbiKit

/// Stands in for the Pomodoro card when another enabled module runs its own
/// focus clock (Study in the Med School kit), so the layout has one timer.
/// It mirrors that clock from the provider snapshot in the owner's accent
/// and opens the owner's tab on click; the controls live there.
struct SharedFocusCard: View {
    let owner: ModuleID
    @ObservedObject var providers: ProviderHub
    @EnvironmentObject private var notch: NotchViewModel
    @Environment(\.moduleCatalog) private var catalog
    @State private var hovering = false

    var body: some View {
        let descriptor = catalog.descriptor(for: owner)
        // The merged clock may come from another engine; only the owner's counts here.
        let focus = providers.snapshot.focus.flatMap { $0.source == owner ? $0 : nil }
        Button {
            notch.selected = owner
        } label: {
            Card(padding: 0) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(focus, descriptor: descriptor, now: context.date)
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.xs + Theme.Spacing.xxs)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.04 : 0))
                    .allowsHitTesting(false)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Open \(descriptor.title) to start, pause or skip")
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: focus)
    }

    private func content(_ focus: ProvidedFocus?, descriptor: ModuleDescriptor, now: Date) -> some View {
        let accent = descriptor.accentColor
        return HStack(spacing: Theme.Spacing.s) {
            SharedFocusRing(progress: progress(focus, at: now), symbol: descriptor.symbol, accent: accent)
            VStack(alignment: .leading, spacing: 0) {
                if let focus {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(StudyTimerFormat.clock(focus.shownTime(at: now)))
                            .font(Theme.Typography.metricSmall)
                            .foregroundStyle(focus.isRunning ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                            .contentTransition(.numericText(countsDown: !focus.countsUp))
                        Text(focus.label)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(focus.phase == .rest ? accent : Theme.Palette.tertiaryText)
                            .lineLimit(1)
                    }
                    Text(focus.isPaused ? "Paused in \(descriptor.title)" : "Running in \(descriptor.title)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                } else {
                    Text("\(descriptor.title) timer")
                        .font(Theme.Typography.metricSmall)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                    Text("Start a session in \(descriptor.title)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Share of the phase done; a phase that counts up shows a full ring.
    private func progress(_ focus: ProvidedFocus?, at now: Date) -> Double {
        guard let focus, focus.isActive else { return 0 }
        guard let length = focus.phaseLength, length > 0 else { return 1 }
        return min(max(focus.elapsed(at: now) / length, 0), 1)
    }
}

/// The Pomodoro card's ring in the owner's accent, with the owner's symbol
/// inside instead of a play button, since the card only opens its tab.
private struct SharedFocusRing: View {
    let progress: Double
    let symbol: String
    let accent: Color

    var body: some View {
        ProgressRing(progress: progress, tint: accent) {
            Circle()
                .fill(accent.opacity(0.10))
                .padding(2.5)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
        }
        .frame(width: 28, height: 28)
    }
}
