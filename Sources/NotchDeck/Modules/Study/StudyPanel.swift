import SwiftUI
import NotchKitCore
import NotchKit

/// The Study tab: a countdown dial on the left (the panel's primary
/// element), and on the right the method in use and the timer controls.
/// Tapping the method swaps the panel for an in-notch method picker,
/// since a system menu would pop outside the notch.
struct StudyPanel: View {
    @ObservedObject var store: StudyStore
    @State private var isPicking = false

    var body: some View {
        Group {
            if isPicking {
                StudyMethodPicker(current: store.session.method.kind) { kind in
                    withAnimation(Theme.Motion.snappy) {
                        if let kind { store.choose(kind) }
                        isPicking = false
                    }
                }
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    StudyDial(store: store)
                        .frame(width: 176)
                    VStack(spacing: Theme.Spacing.s) {
                        StudyMethodCard(session: store.session) {
                            withAnimation(Theme.Motion.snappy) { isPicking = true }
                        }
                        StudyControls(store: store)
                    }
                }
            }
        }
        .transition(.opacity)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }
}

private var accent: Color { Theme.Palette.accent(for: .study) }

/// The time (or cards) inside a progress ring, with the phase underneath.
private struct StudyDial: View {
    @ObservedObject var store: StudyStore

    var body: some View {
        let readout = store.readout
        let session = store.session
        Card(padding: 0) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: store.progress ?? 0)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: Theme.Spacing.xxs) {
                    Text(readout.value)
                        .font(.system(size: readout.value.count > 5 ? 26 : 30,
                                      weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(session.isRunning ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                        .contentTransition(.numericText(countsDown: readout.countsDown))
                    Text(readout.caption)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(session.phase.isBreak ? accent : Theme.Palette.tertiaryText)
                }
            }
            .frame(width: 128, height: 128)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .help("\(readout.caption): \(readout.value)")
        .animation(Theme.Motion.content, value: store.progress)
        .animation(Theme.Motion.snappy, value: session.phase)
    }

    /// Open-ended Flowtime has no finish line, so its ring stays a quiet track.
    private var ringColor: Color {
        store.progress == nil ? Theme.Palette.tertiaryText : accent
    }
}

/// The method in use, its rhythm and round, as a button that opens the picker.
private struct StudyMethodCard: View {
    let session: StudySession
    let choose: () -> Void
    @State private var hovering = false

    var body: some View {
        let info = session.method.info
        Button(action: choose) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("Method")
                        Spacer(minLength: Theme.Spacing.s)
                        if let round = StudyTimerFormat.roundLabel(session) {
                            Text(round).monospacedDigit()
                        }
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(info.name)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text(session.method.rhythmLabel)
                            .foregroundStyle(accent)
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                        Spacer(minLength: 0)
                    }
                    .font(Theme.Typography.title)
                    Text(info.tagline)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                    .stroke(Theme.Palette.stroke.opacity(hovering ? 2 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Change the study method")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

/// Every method as a tile; picking one starts a fresh session with it.
private struct StudyMethodPicker: View {
    let current: StudyMethodKind
    /// Called with the chosen kind, or nil to close without changing.
    let done: (StudyMethodKind?) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Choose a method")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer()
                IconButton(symbol: "xmark", help: "Keep the current method") { done(nil) }
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                ForEach(StudyMethod.presets) { method in
                    StudyMethodTile(method: method, isCurrent: method.kind == current) {
                        done(method.kind)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One method in the picker: name and rhythm.
private struct StudyMethodTile: View {
    let method: StudyMethod
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(method.info.name)
                    .foregroundStyle(isCurrent ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                if !nameIsRhythm {
                    Text(method.rhythmLabel)
                        .foregroundStyle(isCurrent ? accent : Theme.Palette.tertiaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .font(Theme.Typography.bodyEmphasis)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .fill(hovering || isCurrent ? Theme.Palette.surfaceHover : Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                    .stroke(accent.opacity(isCurrent ? 0.6 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrent ? "\(method.info.name) is in use" : "Switch to \(method.info.name): \(method.info.tagline)")
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }

    /// "52 / 17" already says its rhythm, so it shouldn't repeat it.
    private var nameIsRhythm: Bool {
        method.info.name.replacingOccurrences(of: " ", with: "") == method.rhythmLabel
    }
}

/// The primary action, then pause (Flowtime only), skip and reset.
private struct StudyControls: View {
    @ObservedObject var store: StudyStore

    var body: some View {
        let session = store.session
        // A fresh focus phase has nothing to skip or reset.
        let isFresh = session.runState == .idle && session.phase == .focus
        let isFlowing = session.isRunning && session.phase == .focus && session.method.focus == .openEnded
        HStack(spacing: Theme.Spacing.xs) {
            StudyPrimaryButton(title: StudyTimerFormat.primaryAction(session), symbol: primarySymbol,
                               help: primaryHelp) {
                withAnimation(Theme.Motion.snappy) { store.primaryAction() }
            }
            Spacer(minLength: 0)
            if isFlowing {
                IconButton(symbol: "pause.fill", help: "Pause without ending the stretch") {
                    withAnimation(Theme.Motion.snappy) { store.pause() }
                }
            }
            Group {
                IconButton(symbol: "forward.end.fill", help: skipHelp) {
                    withAnimation(Theme.Motion.snappy) { store.skip() }
                }
                IconButton(symbol: "arrow.counterclockwise", help: "Reset to a fresh session") {
                    withAnimation(Theme.Motion.snappy) { store.reset() }
                }
            }
            .disabled(isFresh)
            .opacity(isFresh ? 0.4 : 1)
        }
        .animation(Theme.Motion.snappy, value: isFresh)
    }

    private var primarySymbol: String {
        let session = store.session
        guard session.isRunning else { return "play.fill" }
        return session.phase == .focus && session.method.focus == .openEnded ? "cup.and.saucer.fill" : "pause.fill"
    }

    private var primaryHelp: String {
        let session = store.session
        switch session.runState {
        case .running:
            return primarySymbol == "pause.fill" ? "Pause the timer" : "End this stretch and take a sized break"
        case .paused: return "Resume the timer"
        case .idle: return session.phase.isBreak ? "Start the break" : "Start studying"
        }
    }

    private var skipHelp: String {
        switch store.session.phase {
        case .focus: "Skip to the break"
        case .review: "Skip the review"
        case .shortBreak, .longBreak: "Skip the break"
        }
    }
}

/// A filled accent capsule for the panel's one primary action.
private struct StudyPrimaryButton: View {
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
