import SwiftUI
import NotchKitCore
import NotchKit

/// The Today panel's compact Pomodoro card: a progress ring that doubles as
/// the start/pause button, the countdown with its phase, and the linked task.
/// Skip and reset appear on hover once a session is under way, so the task
/// title gets the full width the rest of the time.
struct FocusCard: View {
    @ObservedObject var store: FocusStore
    /// Today's checklist, to resolve the linked item's title.
    let items: [PlannerItem]
    @State private var hovering = false

    var body: some View {
        let timer = store.timer
        // Slightly tighter vertically so it fits under three Up Next rows.
        Card(padding: 0) {
            HStack(spacing: Theme.Spacing.s) {
                FocusRingButton(progress: store.progress, phase: timer.phase,
                                isRunning: timer.isRunning, help: toggleHelp) {
                    store.toggleRunning()
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(FocusTimerFormat.clock(store.remaining))
                            .font(Theme.Typography.metricSmall)
                            .foregroundStyle(timer.isRunning ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                            .contentTransition(.numericText(countsDown: true))
                        Text(FocusTimerFormat.phaseName(timer.phase))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(timer.phase == .rest ? accent : Theme.Palette.tertiaryText)
                    }
                    detailLine
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hovering, timer.runState != .idle || timer.phase == .rest {
                    HStack(spacing: Theme.Spacing.xxs) {
                        IconButton(symbol: "forward.end.fill", size: 20, help: skipHelp) {
                            withAnimation(Theme.Motion.snappy) { store.skip() }
                        }
                        IconButton(symbol: "arrow.counterclockwise", size: 20, help: "Reset to a fresh focus session") {
                            withAnimation(Theme.Motion.snappy) { store.reset() }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs + Theme.Spacing.xxs)
        }
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: timer.runState)
        .animation(Theme.Motion.snappy, value: timer.phase)
    }

    private var accent: Color { Theme.Palette.accent(for: .planner) }

    /// The linked checklist item, while it's still on today's list.
    private var linkedTitle: String? {
        guard let id = store.timer.linkedItemID else { return nil }
        return items.first { $0.id == id }?.title
    }

    /// The linked task behind a target glyph (the narrow card can't fit a
    /// "Focusing on:" prefix, so that lives in the tooltip), or a status line.
    @ViewBuilder
    private var detailLine: some View {
        if let linkedTitle, store.timer.phase == .focus {
            Label {
                Text(linkedTitle)
            } icon: {
                Image(systemName: "scope").imageScale(.small).foregroundStyle(accent)
            }
            .labelStyle(FocusDetailLabelStyle())
            .help("Focusing on: \(linkedTitle)")
        } else {
            Text(FocusTimerFormat.status(store.timer))
        }
    }

    private var toggleHelp: String {
        switch store.timer.runState {
        case .running: "Pause"
        case .paused: "Resume"
        case .idle: store.timer.phase == .focus ? "Start a focus session" : "Start the break"
        }
    }

    private var skipHelp: String {
        store.timer.phase == .focus ? "Skip to the break" : "Skip the break"
    }
}

/// A thin progress ring in the module accent with a play/pause glyph inside;
/// clicking it starts or pauses the timer.
private struct FocusRingButton: View {
    let progress: Double
    let phase: FocusPhase
    let isRunning: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let accent = Theme.Palette.accent(for: .planner)
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(accent.opacity(hovering ? 0.22 : 0.10))
                    .padding(2.5)
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                    // Optically center the play triangle.
                    .offset(x: isRunning ? 0 : 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.content, value: progress)
    }
}

/// Icon and title on one line with tight spacing, for the card's detail line.
private struct FocusDetailLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}
