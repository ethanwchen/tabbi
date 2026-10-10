import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Focus tab: a large countdown dial on the left (the panel's primary
/// element), and on the right one card with what this session is for and
/// what focus mode does while it runs, then the timer controls.
struct FocusPanel: View {
    @ObservedObject var store: FocusStore
    /// Focus mode, whose sound and Do Not Disturb settings the panel shows.
    let focusMode: FocusController
    /// What other modules share, for the task this session is linked to.
    let providers: ProviderHub

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            FocusDial(store: store)
                .frame(width: 176)
            VStack(spacing: Theme.Spacing.s) {
                FocusSessionCard(store: store, focusMode: focusMode, providers: providers)
                FocusControls(store: store)
            }
        }
        .onAppear { store.setVisible(true, viewer: .focus) }
        .onDisappear { store.setVisible(false, viewer: .focus) }
    }
}

private var accent: Color { FocusModule.descriptor.accentColor }

/// The countdown inside a progress ring, with the phase underneath.
private struct FocusDial: View {
    @ObservedObject var store: FocusStore

    var body: some View {
        let timer = store.timer
        Card(padding: 0) {
            ProgressRing(progress: store.progress, tint: accent, lineWidth: 6) {
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
        .motion(Theme.Motion.content, value: store.progress)
        .motion(Theme.Motion.snappy, value: timer.phase)
    }

    private var phaseLabel: String {
        let phase = FocusTimerFormat.phaseName(store.timer.phase)
        return store.timer.isPaused ? "\(phase) · Paused" : phase
    }
}

/// What this session is for (the task linked from Today, or the timer's
/// status) at the top and what focus mode does while it runs at the
/// bottom: one unit, so the column has one card above the controls, as in
/// Study. Pinning the two to the edges keeps the task near the top instead
/// of floating in the middle of a tall card.
private struct FocusSessionCard: View {
    @ObservedObject var store: FocusStore
    let focusMode: FocusController
    @ObservedObject var providers: ProviderHub

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                task
                Spacer(minLength: Theme.Spacing.m)
                FocusModeRow(controller: focusMode)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var task: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(heading)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer(minLength: Theme.Spacing.s)
                if store.sessionsToday > 0 {
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
        let count = store.sessionsToday
        return count == 1 ? "1 session today" : "\(count) sessions today"
    }
}

/// What focus mode does while a focus phase runs, from Settings › Focus.
private struct FocusModeRow: View {
    @ObservedObject var controller: FocusController

    var body: some View {
        // A narrow panel (Compact) stacks the settings so a bare "On" never
        // loses its name, and only drops the names when even that is too wide.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.m) { items(showsTitles: true) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { items(showsTitles: true) }
            HStack(spacing: Theme.Spacing.m) { items(showsTitles: false) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(controller.offersDoNotDisturb ? "Change focus sound and Do Not Disturb in Settings > Tabs > Options"
                                            : "Change focus sound in Settings > Tabs > Options")
    }

    @ViewBuilder
    private func items(showsTitles: Bool) -> some View {
        let settings = controller.settings
        FocusModeItem(symbol: "waveform", name: "Sound", showsName: showsTitles,
                      value: settings.mix.summary, isOn: !settings.mix.isOff)
        if controller.offersDoNotDisturb {
            FocusModeItem(symbol: "moon.fill", name: "Do Not Disturb", showsName: showsTitles,
                          value: settings.doNotDisturb ? "On" : "Off", isOn: settings.doNotDisturb)
                .fixedSize()
        }
    }
}

/// One focus mode setting: a glyph, its name (left out when space is short), and its value.
private struct FocusModeItem: View {
    let symbol: String
    let name: String
    let showsName: Bool
    let value: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? accent : Theme.Palette.tertiaryText)
                .frame(width: 16)
            if showsName {
                Text(name)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize()
            }
            Text(value)
                .foregroundStyle(isOn ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(Theme.Typography.caption)
        // VoiceOver reads the name even where the panel hides it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(value)")
    }
}

/// Start or pause (the primary action), then skip and stop.
private struct FocusControls: View {
    @ObservedObject var store: FocusStore

    var body: some View {
        let timer = store.timer
        // A fresh focus session has nothing to skip or stop.
        let isFresh = timer.runState == .idle && timer.phase == .focus
        HStack(spacing: Theme.Spacing.xs) {
            FocusPrimaryButton(title: primaryTitle, symbol: timer.isRunning ? "pause.fill" : "play.fill",
                               help: primaryHelp) {
                withMotion(Theme.Motion.snappy) { store.toggleRunning() }
            }
            Spacer(minLength: 0)
            Group {
                IconButton(symbol: "forward.end.fill", help: timer.phase == .focus ? "Skip to the break" : "Skip the break") {
                    withMotion(Theme.Motion.snappy) { store.skip() }
                }
                IconButton(symbol: "stop.fill", help: "Stop and keep the time focused so far") {
                    withMotion(Theme.Motion.snappy) { store.stop() }
                }
            }
            .disabled(isFresh)
            .opacity(isFresh ? 0.4 : 1)
        }
        .motion(Theme.Motion.snappy, value: isFresh)
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
        .buttonStyle(.tactile(.pill))
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
