import SwiftUI
import NotchKitCore
import NotchKit

/// The Study tab: a countdown dial on the left (the panel's primary
/// element), and on the right the method in use and the timer controls.
/// Tapping the method swaps the panel for an in-notch method picker, and
/// each method's (i) for its info popover, since system menus and popovers
/// would pop outside the notch.
struct StudyPanel: View {
    @ObservedObject var store: StudyStore
    @State private var overlay: StudyPanelOverlay? = StudyPanelOverlay(snapshot: StudySnapshotState.current)

    var body: some View {
        Group {
            switch overlay {
            case .picker:
                StudyMethodPicker(methods: store.methods, current: store.session.method.kind, info: { show(.info($0, from: .picker)) }) { kind in
                    if let kind { store.choose(kind) }
                    // Custom opens its lengths right away, so picking it is never a guess.
                    show(kind == .custom ? .custom : nil)
                }
            case .info(let kind, let back):
                StudyMethodInfoView(method: .preset(kind, custom: store.custom), isCurrent: kind == store.session.method.kind,
                                    use: { store.choose(kind); show(nil) },
                                    close: { show(back) })
            case .sounds:
                StudySoundMixer { show(nil) }
            case .custom:
                StudyCustomEditor(store: store) { show(nil) }
            case nil:
                HStack(spacing: Theme.Spacing.s) {
                    StudyDial(store: store)
                        .frame(width: 176)
                    VStack(spacing: Theme.Spacing.s) {
                        StudyMethodCard(store: store, choose: { show(.picker) },
                                        info: { show(.info(store.session.method.kind, from: nil)) },
                                        sounds: { show(.sounds) }, edit: { show(.custom) })
                        StudyControls(store: store)
                    }
                }
            }
        }
        .transition(.opacity)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }

    private func show(_ next: StudyPanelOverlay?) {
        withAnimation(Theme.Motion.snappy) { overlay = next }
    }
}

/// What covers the timer: the method picker, a method's info popover
/// that returns to wherever it was opened from, the sound mixer, or the
/// Custom method's lengths.
private indirect enum StudyPanelOverlay: Equatable {
    case picker
    case info(StudyMethodKind, from: StudyPanelOverlay?)
    case sounds
    case custom

    init?(snapshot: StudySnapshotState?) {
        switch snapshot {
        case .picker: self = .picker
        case .info(let kind): self = .info(kind, from: nil)
        case .sounds: self = .sounds
        case .custom: self = .custom
        case .method, .paused, nil: return nil
        }
    }
}

private var accent: Color { studyAccent }

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
                    if waitsForCards {
                        Text("Waiting for Anki")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(accent.opacity(0.8))
                            .help("Turn on the Anki tab with Anki open so the sprint can count your cards")
                    }
                }
            }
            .frame(width: 128, height: 128)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .help("\(readout.caption): \(readout.value)")
        .overlay(alignment: .bottomTrailing) {
            PetView(player: store.pet)
                .padding(Theme.Spacing.xs)
                .help(petHelp)
        }
        .animation(Theme.Motion.content, value: store.progress)
        .animation(Theme.Motion.snappy, value: session.phase)
    }

    /// A sprint whose cards nothing is counting: say so instead of a stuck 0.
    private var waitsForCards: Bool {
        store.session.phase == .focus && store.session.method.cardGoal != nil && !store.canCountCards
    }

    /// What the corner pet is up to, in the pet's own name.
    private var petHelp: String {
        let name = store.pet.profile.name
        let session = store.session
        if !session.isRunning { return "\(name) naps until the timer runs" }
        return session.phase.isBreak ? "\(name) is taking the break with you" : "\(name) is studying with you"
    }

    /// Open-ended Flowtime has no finish line, so its ring stays a quiet track.
    private var ringColor: Color {
        store.progress == nil ? Theme.Palette.tertiaryText : accent
    }
}

/// The method in use, its rhythm and round, the deep focus switch with
/// the sound chips, and today's tally at the bottom. The name opens the
/// picker, the (i) the method's info popover, and Mix or Playlist the mixer.
private struct StudyMethodCard: View {
    @ObservedObject var store: StudyStore
    let choose: () -> Void
    let info: () -> Void
    let sounds: () -> Void
    /// Opens the Custom method's lengths.
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        let session = store.session
        let methodInfo = session.method.info
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Method")
                    Spacer(minLength: Theme.Spacing.s)
                    if let round = StudyTimerFormat.roundLabel(session) {
                        Text(round).monospacedDigit()
                    }
                    if session.method.kind == .custom {
                        StudyEditButton(action: edit)
                    }
                    StudyInfoButton(method: session.method.kind, action: info)
                        .padding(.trailing, -Theme.Spacing.xs)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                Button(action: choose) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(methodInfo.name)
                                .foregroundStyle(Theme.Palette.primaryText)
                            if !session.method.nameIsRhythm {
                                Text(session.method.rhythmLabel)
                                    .foregroundStyle(accent)
                                    .monospacedDigit()
                            }
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(hovering ? Theme.Palette.secondaryText : Theme.Palette.tertiaryText)
                            Spacer(minLength: 0)
                        }
                        .font(Theme.Typography.title)
                        Text(methodInfo.tagline)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change the study method")
                .onHover { hovering = $0 }
                Spacer(minLength: Theme.Spacing.xs)
                StudyDeepFocusRow(store: store, openMixer: sounds)
                Spacer(minLength: Theme.Spacing.xs)
                StudyTodayRow(today: store.today, goal: store.goal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(Theme.Palette.stroke.opacity(hovering ? 2 : 0), lineWidth: 1)
        )
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

/// The deep focus switch, and the focus sound study blocks play with it.
private struct StudyDeepFocusRow: View {
    @ObservedObject var store: StudyStore
    @ObservedObject private var focus = FocusController.shared
    let openMixer: () -> Void

    var body: some View {
        let isOn = store.deepFocus
        HStack(spacing: Theme.Spacing.s) {
            StudyCapsuleToggle(title: "Deep focus", symbol: "moon", isOn: isOn, help: help) {
                store.setDeepFocus(!isOn)
            }
            Spacer(minLength: 0)
            StudySoundRow(isActive: isOn, openMixer: openMixer)
        }
    }

    private var help: String {
        store.deepFocus ? "Deep focus is on: study blocks bring \(summary). Click to turn it off"
             : "Turn on deep focus: study blocks bring \(summary)"
    }

    /// The focus mode effects that study blocks apply, e.g. "Rain + Fireplace, a playlist and Do Not Disturb".
    private var summary: String {
        let settings = focus.settings
        var parts: [String] = []
        if !settings.mix.isOff { parts.append(settings.mix.summary.lowercased()) }
        if settings.playlist != nil { parts.append("your playlist") }
        if settings.doNotDisturb { parts.append("Do Not Disturb") }
        switch parts.count {
        case 0: return "nothing yet; pick a sound"
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }
}

/// Today's study minutes, finished stretches and the points they earned
/// for the pet.
private struct StudyTodayRow: View {
    let today: StudyDaySummary
    let goal: StudyDailyGoal

    var body: some View {
        let metGoal = today.minutes >= goal.minutes
        HStack(spacing: Theme.Spacing.s) {
            Text("Today")
                .foregroundStyle(Theme.Palette.tertiaryText)
            Label("\(StudyTimerFormat.studied(minutes: today.minutes)) of \(StudyTimerFormat.studied(minutes: goal.minutes))",
                  systemImage: metGoal ? "checkmark.seal.fill" : "clock")
                .foregroundStyle(metGoal ? accent : Theme.Palette.secondaryText)
                .help(metGoal ? "Daily study goal met" : "Time studied today, out of your daily goal")
            Label("\(today.completedSessions) done", systemImage: "checkmark.circle")
                .help("Study stretches finished today")
            Spacer(minLength: 0)
            Label(StudyTimerFormat.points(today.points), systemImage: "star.fill")
                .foregroundStyle(today.points > 0 ? accent : Theme.Palette.tertiaryText)
                .help("Study points earned today; spend them on your pet's wardrobe")
        }
        .labelStyle(StudyTodayLabelStyle())
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.secondaryText)
        .monospacedDigit()
        .lineLimit(1)
        .contentTransition(.numericText())
        .animation(Theme.Motion.content, value: today)
    }
}

/// A small icon tucked close to its count.
private struct StudyTodayLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            configuration.icon.font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}

/// Every method the kit offers as a tile; picking one starts a fresh session with it.
private struct StudyMethodPicker: View {
    /// The kit's methods, in its order.
    let methods: [StudyMethod]
    let current: StudyMethodKind
    /// Opens a method's info popover.
    let info: (StudyMethodKind) -> Void
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
                ForEach(methods) { method in
                    StudyMethodTile(method: method, isCurrent: method.kind == current,
                                    info: { info(method.kind) }) {
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
    let info: () -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            tile
            StudyInfoButton(method: method.kind, action: info)
        }
    }

    private var tile: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(method.info.name)
                    .foregroundStyle(isCurrent ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                if !method.nameIsRhythm {
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
