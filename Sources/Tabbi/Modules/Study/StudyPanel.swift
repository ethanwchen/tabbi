import SwiftUI
import TabbiKitCore
import TabbiKit

/// The Study tab: a countdown dial on the left (the panel's primary
/// element), and on the right the method in use and the timer controls.
/// Tapping the method swaps the panel for an in-notch method picker, and
/// each method's (i) for its info popover, since system menus and popovers
/// would pop outside the notch.
struct StudyPanel: View {
    @ObservedObject var store: StudyStore
    /// Focus mode, whose sound and Do Not Disturb deep focus blocks use.
    let focusMode: FocusController
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
                StudyMethodInfoView(method: .preset(kind, custom: store.custom, timer: store.timer), isCurrent: kind == store.session.method.kind,
                                    use: { store.choose(kind); show(nil) },
                                    close: { show(back) })
            case .sounds:
                StudySoundMixer(focus: focusMode) { show(nil) }
            case .custom:
                StudyCustomEditor(store: store) { show(nil) }
            case nil:
                if let party = store.partySession {
                    StudyPartySessionView(store: store, session: party)
                        .transition(.opacity)
                } else {
                    timer
                }
            }
        }
        .transition(.opacity)
        .motion(Theme.Motion.snappy, value: store.partySession == nil)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }

    /// The user's own timer: the dial, then the method and its controls.
    private var timer: some View {
        HStack(spacing: Theme.Spacing.s) {
            StudyDial(store: store)
                .frame(width: 176)
            VStack(spacing: Theme.Spacing.s) {
                StudyMethodCard(store: store, focusMode: focusMode, choose: { show(.picker) },
                                info: { show(.info(store.session.method.kind, from: nil)) },
                                sounds: { show(.sounds) }, edit: { show(.custom) })
                StudyControls(store: store)
            }
        }
    }

    private func show(_ next: StudyPanelOverlay?) {
        withMotion(Theme.Motion.snappy) { overlay = next }
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
            ProgressRing(progress: store.progress, tint: ringColor, lineWidth: 6) {
                VStack(spacing: Theme.Spacing.xxs) {
                    Text(readout.value)
                        .font(.system(size: readout.value.count > 5 ? 26 : 30,
                                      weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(session.isRunning ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                        .contentTransition(.numericText(countsDown: readout.countsDown))
                    if !readout.caption.isEmpty {
                        Text(readout.caption)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(session.phase.isBreak ? accent : Theme.Palette.tertiaryText)
                    }
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
        .help(readout.caption.isEmpty ? "Timer: \(readout.value)" : "\(readout.caption): \(readout.value)")
        .overlay(alignment: .bottomTrailing) {
            PetView(player: store.pet)
                .padding(Theme.Spacing.xs)
                .help(petHelp)
        }
        // A sprint's card count rolls; a clock's once-a-second tick is set
        // without a spring, since animating it kept the notch redrawing.
        .motion(Theme.Motion.content, value: session.cardsDone)
        .motion(Theme.Motion.snappy, value: session.phase)
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

/// A party's shared session in place of the user's own timer: time left
/// in the ring, then the method, who started it and who is in it. Stepping
/// out or ending it stays in the Party tab, which owns the party, so the
/// own timer comes back here once the session ends or the user steps out.
private struct StudyPartySessionView: View {
    @ObservedObject var store: StudyStore
    let session: ProvidedPartySession

    var body: some View {
        let remaining = session.remaining(at: store.now)
        HStack(spacing: Theme.Spacing.s) {
            Card(padding: 0) {
                ProgressRing(progress: progress(remaining), tint: accent, lineWidth: 6) {
                    VStack(spacing: Theme.Spacing.xxs) {
                        Text(StudyTimerFormat.clock(remaining))
                            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Theme.Palette.primaryText)
                            .contentTransition(.numericText(countsDown: true))
                        Text("Focus")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                }
                .frame(width: 128, height: 128)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .help("Shared focus: \(StudyTimerFormat.clock(remaining)) left")
            .overlay(alignment: .bottomTrailing) {
                PetView(player: store.pet)
                    .padding(Theme.Spacing.xs)
                    .help("\(store.pet.profile.name) is studying with the party")
            }
            .frame(width: 176)
            VStack(spacing: Theme.Spacing.s) {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("Party session")
                            Spacer(minLength: Theme.Spacing.s)
                            Label(session.companyLine, systemImage: "person.2.fill")
                                .labelStyle(StudyTodayLabelStyle())
                                .help(session.friendCount == 0 ? "Everyone else has stepped out" : "Friends in this session now")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        Text(session.methodName)
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .lineLimit(1)
                        Text(startedBy)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .lineLimit(1)
                        Text("Ends at \(session.endsAt.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.xs)
                        StudyTodayRow(today: store.today, goal: store.goal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(session.isHost ? "End it for everyone in the Party tab" : "Step out in the Party tab anytime")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 28)
                .help(session.isHost ? "The session runs for the whole party until it ends or you end it"
                                     : "Stepping out keeps the session going for the others; your own timer comes back here")
            }
        }
    }

    /// How far the shared phase has run, so the ring fills as it does.
    private func progress(_ remaining: TimeInterval) -> Double {
        session.length > 0 ? 1 - remaining / session.length : 0
    }

    private var startedBy: String {
        if let host = session.hostName { return "\(host) started it for the party" }
        return "You started it for the party"
    }
}

/// The method in use, its rhythm and round, the deep focus switch with
/// the sound button, and today's tally at the bottom. The name opens the
/// picker, the (i) the method's info popover, and the sound button the mixer.
private struct StudyMethodCard: View {
    @ObservedObject var store: StudyStore
    let focusMode: FocusController
    let choose: () -> Void
    let info: () -> Void
    let sounds: () -> Void
    /// Opens the Custom method's lengths.
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        Card {
            // A short panel (Compact) drops the "Method" caption and moves
            // its round and buttons up beside the name, so the card keeps
            // its edges instead of being clipped.
            ViewThatFits(in: .vertical) {
                content(showsCaption: true)
                content(showsCaption: false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(Theme.Palette.stroke.opacity(hovering ? 2 : 0), lineWidth: 1)
        )
        .motion(Theme.Motion.snappy, value: hovering)
    }

    private func content(showsCaption: Bool) -> some View {
        let session = store.session
        let methodInfo = session.method.info
        // The Timer's length row leaves Regular a hair short of the full
        // gaps, which the spacers absorb there, so only the caption is
        // what a shorter panel drops.
        let gap = session.method.kind == .timer ? Theme.Spacing.xxs : Theme.Spacing.xs
        return VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if showsCaption {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Method")
                    Spacer(minLength: Theme.Spacing.s)
                    accessories
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Button(action: choose) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(methodInfo.name)
                                .foregroundStyle(Theme.Palette.primaryText)
                            // The Timer's length row already shows its length.
                            if !session.method.nameIsRhythm, session.method.kind != .timer {
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
                        if session.method.kind != .timer {
                            Text(methodInfo.tagline)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Change the timer method")
                .onHover { hovering = $0 }
                if !showsCaption {
                    accessories
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            if session.method.kind == .timer {
                StudyTimerLengthRow(length: store.timer, isCounting: session.runState != .idle,
                                    set: store.setTimer, start: store.startTimer)
            }
            Spacer(minLength: gap)
            StudyDeepFocusRow(store: store, focus: focusMode, openMixer: sounds)
            Spacer(minLength: gap)
            StudyTodayRow(today: store.today, goal: store.goal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The round, the Custom method's edit button and the (i), which sit in
    /// the caption row or, without it, beside the method's name.
    @ViewBuilder private var accessories: some View {
        let session = store.session
        if let round = StudyTimerFormat.roundLabel(session) {
            Text(round).monospacedDigit()
        }
        if session.method.kind == .custom {
            StudyEditButton(action: edit)
        }
        StudyInfoButton(method: session.method.kind, action: info)
            .padding(.trailing, -Theme.Spacing.xs)
    }
}

/// The Timer's lengths: one click starts a common one, and a stepper sets
/// any other, so a custom length needs no extra screen.
private struct StudyTimerLengthRow: View {
    let length: StudyTimerLength
    let isCounting: Bool
    let set: (StudyTimerLength) -> Void
    let start: (StudyTimerLength) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(StudyTimerLength.presets, id: \.self) { minutes in
                StudyTimerChip(title: "\(minutes) min", isOn: length.minutes == minutes,
                               help: isCounting ? "Change the countdown to \(minutes) minutes, or to a minute from now if that time has passed"
                                                 : "Start a \(minutes) minute countdown") {
                    start(StudyTimerLength(minutes: minutes))
                }
            }
            Spacer(minLength: 0)
            IconButton(symbol: "minus", help: "A shorter timer") { set(length.stepped(up: false)) }
                .disabled(!length.canStep(up: false))
            IconButton(symbol: "plus", help: "A longer timer") { set(length.stepped(up: true)) }
                .disabled(!length.canStep(up: true))
        }
        .padding(.top, Theme.Spacing.xxs)
    }
}

/// One of the Timer's one-click lengths, filled with the accent when picked.
private struct StudyTimerChip: View {
    let title: String
    let isOn: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isOn ? Theme.Palette.background : Theme.Palette.secondaryText)
                .padding(.horizontal, Theme.Spacing.s)
                .frame(height: 22)
                .background(Capsule().fill(isOn ? accent : (hovering ? Theme.Palette.surfaceHover : Theme.Palette.surface)))
                .contentShape(Capsule())
        }
        .buttonStyle(.tactile(.pill))
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
        .motion(Theme.Motion.snappy, value: isOn)
    }
}

/// The deep focus switch, and the focus sound study blocks play with it.
private struct StudyDeepFocusRow: View {
    @ObservedObject var store: StudyStore
    @ObservedObject var focus: FocusController
    let openMixer: () -> Void

    var body: some View {
        // A narrow panel (Compact) shortens the switch's name instead of
        // truncating it; the tooltip still says what it does.
        ViewThatFits(in: .horizontal) {
            row(title: "Deep focus")
            row(title: "Deep")
        }
    }

    private func row(title: String) -> some View {
        let isOn = store.deepFocus
        return HStack(spacing: Theme.Spacing.s) {
            StudyCapsuleToggle(title: title, symbol: "moon", isOn: isOn, help: help) {
                store.setDeepFocus(!isOn)
            }
            .fixedSize()
            Spacer(minLength: 0)
            StudySoundButton(focus: focus, isActive: isOn, openMixer: openMixer)
                .layoutPriority(-1)
        }
    }

    private var help: String {
        store.deepFocus ? "Deep focus is on: focus blocks bring \(summary). Click to turn it off"
             : "Turn on deep focus: focus blocks bring \(summary)"
    }

    /// The focus mode effects that study blocks apply, e.g. "Rain + Fireplace, a playlist and Do Not Disturb".
    private var summary: String {
        let settings = focus.settings
        var parts: [String] = []
        if !settings.mix.isOff { parts.append(settings.mix.summary.lowercased()) }
        if settings.playlist != nil { parts.append("your playlist") }
        if focus.doNotDisturb { parts.append("Do Not Disturb") }
        switch parts.count {
        case 0: return "nothing yet; pick a sound"
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }
}

/// Today's focus minutes, finished blocks and the points they earned
/// for the pet.
private struct StudyTodayRow: View {
    let today: StudyDayTally
    let goal: StudyDailyGoal

    var body: some View {
        // A narrow panel drops the "Today" label, then the goal, so every
        // number stays whole.
        ViewThatFits(in: .horizontal) {
            row(showsTitle: true, showsGoal: true)
            row(showsTitle: false, showsGoal: true)
            row(showsTitle: false, showsGoal: false)
        }
        .labelStyle(StudyTodayLabelStyle())
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.secondaryText)
        .monospacedDigit()
        .lineLimit(1)
        .contentTransition(.numericText())
        .motion(Theme.Motion.content, value: today)
    }

    private func row(showsTitle: Bool, showsGoal: Bool) -> some View {
        let metGoal = today.minutes >= goal.minutes
        let studied = StudyTimerFormat.studied(minutes: today.minutes)
        return HStack(spacing: Theme.Spacing.s) {
            if showsTitle {
                Text("Today")
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .fixedSize()
            }
            Label(showsGoal ? StudyTimerFormat.studied(minutes: today.minutes, of: goal.minutes) : studied,
                  systemImage: metGoal ? "checkmark.seal.fill" : "clock")
                .foregroundStyle(metGoal ? accent : Theme.Palette.secondaryText)
                .fixedSize()
                .help(metGoal ? "Daily focus goal met" : "Focus time today, out of your daily goal")
            Label("\(today.sessions) done", systemImage: "checkmark.circle")
                .fixedSize()
                .help("Focus blocks finished today")
            Spacer(minLength: 0)
            Label(StudyTimerFormat.points(today.points), systemImage: "star.fill")
                .foregroundStyle(today.points > 0 ? accent : Theme.Palette.tertiaryText)
                .fixedSize()
                .help("Points earned today; spend them on your pet's wardrobe")
        }
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

/// One method in the picker: name and rhythm, with its (i) when `info`
/// is set. Onboarding's method step shows the info beside the tiles instead.
struct StudyMethodTile: View {
    let method: StudyMethod
    let isCurrent: Bool
    let info: (() -> Void)?
    let action: () -> Void
    /// Whether the tile shows the rhythm after the name; onboarding's
    /// narrower tiles leave it to the summary beside them.
    var showsRhythm = true
    /// Reports hover changes, so onboarding can preview the hovered method.
    var hovered: (Bool) -> Void = { _ in }
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            tile
            if let info {
                StudyInfoButton(method: method.kind, action: info)
            }
        }
    }

    private var tile: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(method.info.name)
                    .foregroundStyle(isCurrent ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.xs)
                if showsRhythm, !method.nameIsRhythm {
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
        .buttonStyle(.tactile(.pill))
        .help(isCurrent ? "\(method.info.name) is in use" : "Switch to \(method.info.name): \(method.info.tagline)")
        .onHover { hovering = $0; hovered($0) }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}

/// The primary action, then pause (Flowtime only), skip (not for the
/// Timer, which has no breaks) and stop.
private struct StudyControls: View {
    @ObservedObject var store: StudyStore

    var body: some View {
        let session = store.session
        // A fresh focus phase has nothing to skip or stop.
        let isFresh = session.runState == .idle && session.phase == .focus
        let isFlowing = session.isRunning && session.phase == .focus && session.method.focus == .openEnded
        HStack(spacing: Theme.Spacing.xs) {
            StudyPrimaryButton(title: StudyTimerFormat.primaryAction(session), symbol: primarySymbol,
                               help: primaryHelp) {
                withMotion(Theme.Motion.snappy) { store.primaryAction() }
            }
            Spacer(minLength: 0)
            if isFlowing {
                IconButton(symbol: "pause.fill", help: "Pause without ending the stretch") {
                    withMotion(Theme.Motion.snappy) { store.pause() }
                }
            }
            Group {
                // The Timer has nothing to skip to; Stop ends it.
                if session.method.hasBreaks {
                    IconButton(symbol: "forward.end.fill", help: skipHelp) {
                        withMotion(Theme.Motion.snappy) { store.skip() }
                    }
                }
                IconButton(symbol: "stop.fill", help: "Stop and keep the time studied so far") {
                    withMotion(Theme.Motion.snappy) { store.stop() }
                }
            }
            .disabled(isFresh)
            .opacity(isFresh ? 0.4 : 1)
        }
        .motion(Theme.Motion.snappy, value: isFresh)
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
        case .idle:
            if session.method.kind == .timer { return "Start the countdown" }
            return session.phase.isBreak ? "Start the break" : "Start studying"
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
        .buttonStyle(.tactile(.pill))
        .help(help)
        .onHover { hovering = $0 }
        .motion(Theme.Motion.snappy, value: hovering)
    }
}
