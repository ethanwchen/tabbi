import SwiftUI
import NotchKitCore
import NotchKit

/// The Focus tab: a large countdown dial on the left (the panel's primary
/// element), and on the right what this session is for, what focus mode
/// does while it runs, and the timer controls.
struct FocusPanel: View {
    @ObservedObject var store: FocusStore
    @EnvironmentObject private var services: AppServices

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            FocusDial(store: store)
                .frame(width: 176)
            VStack(spacing: Theme.Spacing.s) {
                FocusTaskCard(store: store, providers: services.providers)
                FocusModeCard()
                FocusControls(store: store)
            }
        }
        .onAppear { store.setVisible(true, viewer: .focus) }
        .onDisappear { store.setVisible(false, viewer: .focus) }
    }
}

private var accent: Color { Theme.Palette.accent(for: .focus) }

/// The countdown inside a progress ring, with the phase underneath.
private struct FocusDial: View {
    @ObservedObject var store: FocusStore

    var body: some View {
        let timer = store.timer
        Card(padding: 0) {
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: store.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: Theme.Spacing.xxs) {
                    Text(FocusTimerFormat.clock(store.remaining))
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(timer.isRunning ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                        .contentTransition(.numericText(countsDown: true))
                    Text(phaseLabel)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(timer.phase == .rest ? accent : Theme.Palette.tertiaryText)
                }
            }
            .frame(width: 128, height: 128)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .help("\(FocusTimerFormat.phaseName(timer.phase)): \(FocusTimerFormat.clock(store.remaining)) left")
        .animation(Theme.Motion.content, value: store.progress)
        .animation(Theme.Motion.snappy, value: timer.phase)
    }

    private var phaseLabel: String {
        let phase = FocusTimerFormat.phaseName(store.timer.phase)
        return store.timer.isPaused ? "\(phase) · Paused" : phase
    }
}

/// What this session is for: the task linked from Today, or a hint.
private struct FocusTaskCard: View {
    @ObservedObject var store: FocusStore
    @ObservedObject var providers: ProviderHub

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(heading)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                    Spacer(minLength: Theme.Spacing.s)
                    if store.timer.completedFocusCount > 0 {
                        Text(sessionsDone)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .monospacedDigit()
                    }
                }
                .font(Theme.Typography.caption)
                if let linkedTitle, store.timer.phase == .focus {
                    Label {
                        Text(linkedTitle)
                    } icon: {
                        Image(systemName: "scope").foregroundStyle(accent)
                    }
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("Focusing on: \(linkedTitle)")
                } else {
                    Text(FocusTimerFormat.status(store.timer))
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// The linked item's title, while some module still lists it.
    private var linkedTitle: String? {
        guard let id = store.timer.linkedItemID?.uuidString else { return nil }
        return providers.snapshot.tasks.first { $0.id == id }?.title
    }

    private var heading: String {
        guard store.timer.phase == .focus else { return "Break" }
        return linkedTitle == nil ? "Focus session" : "Focusing on"
    }

    private var sessionsDone: String {
        let count = store.timer.completedFocusCount
        return count == 1 ? "1 session done" : "\(count) sessions done"
    }
}

/// What focus mode does while a focus phase runs, from Settings › Focus.
private struct FocusModeCard: View {
    @ObservedObject private var controller = FocusController.shared

    var body: some View {
        let settings = controller.settings
        Card {
            HStack(spacing: Theme.Spacing.m) {
                FocusModeItem(symbol: "waveform", title: "Sound", value: settings.mix.summary,
                              isOn: !settings.mix.isOff)
                FocusModeItem(symbol: "moon.fill", title: "Do Not Disturb",
                              value: settings.doNotDisturb ? "On" : "Off", isOn: settings.doNotDisturb)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help("Change focus sound and Do Not Disturb in Settings › Focus")
    }
}

/// One focus mode setting: a glyph, its name, and its value.
private struct FocusModeItem: View {
    let symbol: String
    let title: String
    let value: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? accent : Theme.Palette.tertiaryText)
                .frame(width: 16)
            Text(title)
                .foregroundStyle(Theme.Palette.tertiaryText)
            Text(value)
                .foregroundStyle(isOn ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(Theme.Typography.caption)
    }
}

/// Start or pause (the primary action), then skip and reset.
private struct FocusControls: View {
    @ObservedObject var store: FocusStore

    var body: some View {
        let timer = store.timer
        // A fresh focus session has nothing to skip or reset.
        let isFresh = timer.runState == .idle && timer.phase == .focus
        HStack(spacing: Theme.Spacing.xs) {
            FocusPrimaryButton(title: primaryTitle, symbol: timer.isRunning ? "pause.fill" : "play.fill",
                               help: primaryHelp) {
                withAnimation(Theme.Motion.snappy) { store.toggleRunning() }
            }
            Spacer(minLength: 0)
            Group {
                IconButton(symbol: "forward.end.fill", help: timer.phase == .focus ? "Skip to the break" : "Skip the break") {
                    withAnimation(Theme.Motion.snappy) { store.skip() }
                }
                IconButton(symbol: "arrow.counterclockwise", help: "Reset to a fresh focus session") {
                    withAnimation(Theme.Motion.snappy) { store.reset() }
                }
            }
            .disabled(isFresh)
            .opacity(isFresh ? 0.4 : 1)
        }
        .animation(Theme.Motion.snappy, value: isFresh)
    }

    private var primaryTitle: String {
        switch store.timer.runState {
        case .running: "Pause"
        case .paused: "Resume"
        case .idle: store.timer.phase == .focus ? "Start focus" : "Start break"
        }
    }

    private var primaryHelp: String {
        switch store.timer.runState {
        case .running: "Pause the timer"
        case .paused: "Resume the timer"
        case .idle: store.timer.phase == .focus ? "Start a focus session" : "Start the break"
        }
    }
}

/// A filled accent capsule for the panel's one primary action.
private struct FocusPrimaryButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(Theme.Typography.bodyEmphasis)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.Palette.background)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: 28)
            .background(Capsule().fill(accent.opacity(hovering ? 1 : 0.88)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
