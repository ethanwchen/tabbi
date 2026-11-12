// The four questions (ada-swiftui-design, Step 0):
// - Question: how long is left in this block? The countdown is the hero.
// - Metaphor: a kitchen timer on a study desk, with the pet studying along.
// - Temperature: warm and calm, the cozy Tabbi voice.
// - Stage: the pet's spot on the desk. The whole screen is that room, lit
//   by the session's tone; the HUD and the controls float on glass above it.
// The game layer comes later, so the scene stays a quiet room for now.

import SwiftUI
import TabbiKitCore

/// The one screen: the pet, the countdown and the controls.
struct TimerScreen: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsMethods = false

    private var session: StudySession { store.session }
    private var tone: StudyTone { StudyTone(isBreak: session.phase.isBreak, isIdle: session.runState == .idle) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    hero
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .padding(.horizontal, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .top, spacing: 0) { hud }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .background { Room(tone: tone).ignoresSafeArea() }
        .animation(.spring(duration: 0.45), value: tone)
        .animation(.spring(duration: 0.4), value: store.award)
        .sheet(isPresented: $showsMethods) {
            MethodSheet().presentationDetents([.medium, .large])
        }
        .sensoryFeedback(trigger: session.runState) { old, new in
            switch (old, new) {
            case (_, .running): .start
            case (.running, _): .stop
            default: nil
            }
        }
        .sensoryFeedback(.success, trigger: store.completions)
        .sensoryFeedback(.selection, trigger: session.method)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(tone.hue(scheme).opacity(scheme == .dark ? 0.22 : 0.16))
                    .frame(width: petPixel * 26, height: petPixel * 4)
                    .blur(radius: 6)
                    .offset(y: petPixel)
                    .accessibilityHidden(true)
                PetStage(profile: store.pet, activity: PetAnimator.Activity(session),
                         celebrations: store.completions, pixelSize: petPixel)
            }
            .padding(.bottom, 6)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                clock(at: context.date)
            }

            if let award = store.award {
                AwardLine(award: award, tone: tone)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if session.method.kind == .timer, session.runState == .idle {
                TimerLengthPicker(length: store.engine.timer) { store.setTimer($0) }
            }
        }
    }

    /// Points per sprite pixel: 6 (a 192 point pet), smaller at the
    /// accessibility text sizes so the countdown keeps the room it needs.
    private var petPixel: CGFloat { typeSize.isAccessibilitySize ? 4 : 6 }

    private func clock(at date: Date) -> some View {
        let readout = StudyTimerFormat.readout(session, at: date)
        let label = readout.caption.isEmpty ? StudyTimerFormat.phaseName(session.phase, method: session.method)
            : readout.caption
        return VStack(spacing: 2) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(tone.hue(scheme))
                .multilineTextAlignment(.center)
            Text(readout.value)
                .font(.system(size: 96, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: readout.countsDown))
                .animation(.spring(duration: 0.3), value: readout.value)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(.primary)
            if let round = StudyTimerFormat.roundLabel(session) {
                Text(round)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: HUD and controls

    /// The method and the points, side by side, or stacked when the text
    /// is too large for one row, so no word is ever broken.
    private var hud: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                methodButton
                Spacer(minLength: 0)
                pointsPill
            }
            VStack(alignment: .leading, spacing: 8) {
                methodButton
                pointsPill
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var methodButton: some View {
        Button { showsMethods = true } label: {
            HStack(spacing: 6) {
                Text(StudyMethodInfo.info(for: session.method.kind).displayName)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityHint(Text("Choose a method", bundle: .tabbi))
    }

    private var pointsPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(StudyTone.focus.hue(scheme))
                .accessibilityHidden(true)
            Text("\(store.balance) pts", bundle: .tabbi)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if session.runState != .idle {
                Button { store.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Stop", bundle: .tabbi))
                .accessibilityHint(Text("Stop and keep the time studied so far", bundle: .tabbi))
                .transition(.scale.combined(with: .opacity))
            }
            Button { store.primaryAction() } label: {
                Text(StudyTimerFormat.primaryAction(session))
                    .font(.title3.weight(.semibold))
                    // The dark-mode hues are light, so they carry dark text.
                    .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : Color.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(tone == .rest ? StudyTone.rest.hue(scheme) : StudyTone.focus.hue(scheme))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.35), value: session.runState)
    }
}

/// The room the pet sits in, lit by the session's tone: a tinted neutral
/// canvas with a soft glow rising from the desk. Decorative; the state is
/// written out on screen.
private struct Room: View {
    let tone: StudyTone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hue = tone.hue(scheme)
        ZStack {
            StudyTone.canvas(scheme)
            RadialGradient(colors: [hue.opacity(scheme == .dark ? 0.30 : 0.20), .clear],
                           center: UnitPoint(x: 0.5, y: 0.62), startRadius: 10, endRadius: 420)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The points a session just earned: the pill and the Mac's headline.
private struct AwardLine: View {
    let award: PetStudyAward
    let tone: StudyTone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 6) {
            Text(award.pointsText)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(StudyTone.focus.hue(scheme).opacity(0.18), in: .capsule)
                .foregroundStyle(StudyTone.focus.hue(scheme))
            Text(award.headline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let unlock = award.unlockLine {
                Text(unlock)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The Timer's length, a minute at a time, as the Mac's stepper steps it.
private struct TimerLengthPicker: View {
    let length: StudyTimerLength
    let change: (StudyTimerLength) -> Void

    var body: some View {
        HStack(spacing: 4) {
            step(up: false, symbol: "minus", label: Text("A shorter timer", bundle: .tabbi))
            Text(DurationFormat.minutes(length.minutes))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 72)
                .multilineTextAlignment(.center)
            step(up: true, symbol: "plus", label: Text("A longer timer", bundle: .tabbi))
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }

    private func step(up: Bool, symbol: String, label: Text) -> some View {
        Button { change(length.stepped(up: up)) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .disabled(!length.canStep(up: up))
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: length)
    }
}
