import SwiftUI
import TabbiKitCore

// The study session's own controls, shared by the Pet Cam screens: the
// method picker, the points, the Timer's length, the countdown and the
// session buttons. They run the foundation's `StudyStore` unchanged and use
// only strings TabbiKitCore already translates.

/// The current method; opens the method sheet.
struct MethodButton: View {
    @Environment(StudyStore.self) private var store
    @Binding var showsMethods: Bool

    var body: some View {
        Button { showsMethods = true } label: {
            HStack(spacing: 6) {
                Text(StudyMethodInfo.info(for: store.session.method.kind).displayName)
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
}

/// The pet's points; opens the pet picker.
struct PointsButton: View {
    @Environment(StudyStore.self) private var store
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .foregroundStyle(StudyTone.focus.hue(.dark))
                    .accessibilityHidden(true)
                Text("\(store.balance) pts", bundle: .tabbi)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    // A number and its unit stay together on one line.
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(verbatim: "Choose your pet"))
    }
}

/// The Timer's length, a minute at a time, as the Mac's stepper steps it.
struct TimerLengthPicker: View {
    let length: StudyTimerLength
    let change: (StudyTimerLength) -> Void
    /// The step buttons grow a little with the text (up to 60 points) and
    /// keep a gap from the length, so the glyphs never crowd it and the
    /// length never wraps at the largest sizes.
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 44
    @ScaledMetric(relativeTo: .headline) private var gap: CGFloat = 8
    private var side: CGFloat { min(scaledSide, 60) }

    var body: some View {
        HStack(spacing: gap) {
            step(up: false, symbol: "minus", label: Text("A shorter timer", bundle: .tabbi))
            Text(DurationFormat.minutes(length.minutes))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .fixedSize()
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
                .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .disabled(!length.canStep(up: up))
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: length)
    }
}

/// The session's countdown, as the foundation's hero showed it: the phase
/// (or the readout's caption) over a large monospaced clock.
struct StudyClock: View {
    let session: StudySession
    var size: CGFloat = 88
    var tint: Color = CCTV.burnIn

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let readout = StudyTimerFormat.readout(session, at: context.date)
            let label = readout.caption.isEmpty ? StudyTimerFormat.phaseName(session.phase, method: session.method)
                : readout.caption
            VStack(spacing: 2) {
                Text(label)
                    .font(CCTV.font(.subheadline))
                    .kerning(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(tint.opacity(0.75))
                    .multilineTextAlignment(.center)
                Text(readout.value)
                    .font(.system(size: size, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: readout.countsDown))
                    .animation(.spring(duration: 0.3), value: readout.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(tint)
                if let round = StudyTimerFormat.roundLabel(session) {
                    Text(round)
                        .font(.footnote)
                        .foregroundStyle(tint.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Stop and the primary action (pause, resume, or end a Flowtime stretch)
/// for a session under way.
struct SessionButtons: View {
    @Environment(StudyStore.self) private var store
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Button { store.stop() } label: {
                Image(systemName: "stop.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Stop", bundle: .tabbi))
            .accessibilityHint(Text("Stop and keep the time studied so far", bundle: .tabbi))
            Button { store.primaryAction() } label: {
                Text(StudyTimerFormat.primaryAction(store.session))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.black.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .tint(tint)
        }
    }
}

/// The points a session just earned: the pill and the Mac's headline.
struct AwardLine: View {
    let award: PetStudyAward

    var body: some View {
        VStack(spacing: 4) {
            Text(award.pointsText)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(StudyTone.focus.hue(.dark).opacity(0.18), in: .capsule)
                .foregroundStyle(StudyTone.focus.hue(.dark))
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
