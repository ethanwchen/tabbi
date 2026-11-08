import ActivityKit
import SwiftUI
import TabbiKitCore
import WidgetKit

@main
struct TabbiLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        StudySessionActivity()
    }
}

/// The running study session on the Lock Screen and in the Dynamic Island,
/// as a dark, static CCTV frame: scanlines, the REC dot, the hidden
/// camera's number, the countdown and the pet lying still. It never shows
/// the room or a caption, and nothing in it moves or changes during the
/// block, so a glance gives nothing to think about. The countdown is drawn by the system from the phase's dates
/// (`Text(timerInterval:)`), so it keeps moving while the app is suspended;
/// once the phase's end passes, the activity goes stale and says the tape is
/// ready (or the phase is done) until the app moves it on.
struct StudySessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            LockScreenView(state: context.state, pet: context.attributes.pet,
                           isStale: context.isStale || context.state.isDone)
                .activityBackgroundTint(CCTV.screen)
                .activitySystemActionForegroundColor(CCTV.burnIn)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale || context.state.isDone
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 10) {
                        RestingPet(pet: context.attributes.pet, pixelSize: 1.5)
                        VStack(alignment: .leading, spacing: 4) {
                            CameraLabel(state: state, isStale: stale)
                            CameraNumber(state: state)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockText(state: state, isStale: stale)
                        .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        .foregroundStyle(CCTV.burnIn)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 6)
                }
            } compactLeading: {
                Circle()
                    .fill(state.filming && !stale ? CCTV.rec : CCTV.standby)
                    .frame(width: 9, height: 9)
                    .padding(.leading, 2)
                    .accessibilityLabel(Text(verbatim: state.filming ? "Recording" : PhaseText.title(state, isStale: stale)))
            } compactTrailing: {
                ClockText(state: state, isStale: stale)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CCTV.burnIn)
                    .frame(width: ClockText.compactWidth(for: state))
            } minimal: {
                Circle()
                    .fill(state.filming && !stale ? CCTV.rec : CCTV.standby)
                    .frame(width: 10, height: 10)
            }
            .keylineTint(state.filming && !stale ? CCTV.rec : CCTV.standby)
        }
    }
}

// MARK: Lock Screen

private struct LockScreenView: View {
    let state: StudyActivityAttributes.ContentState
    let pet: PetProfile
    let isStale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RestingPet(pet: pet, pixelSize: 2)
            VStack(alignment: .leading, spacing: 6) {
                CameraLabel(state: state, isStale: isStale)
                HStack(spacing: 8) {
                    CameraNumber(state: state)
                    Text(verbatim: "TABBI CAM")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .kerning(1.4)
                        .foregroundStyle(CCTV.burnIn.opacity(0.55))
                }
            }
            Spacer(minLength: 8)
            ClockText(state: state, isStale: isStale)
                .font(.system(size: 40, weight: .semibold, design: .monospaced))
                .foregroundStyle(CCTV.burnIn)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background { Scanlines(opacity: 0.35) }
    }
}

/// The dot and its word: REC while the camera films a block, the phase's
/// name while it waits (a break, a block too short to film), and the done
/// line once the phase has run out.
private struct CameraLabel: View {
    let state: StudyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let recording = state.filming && !isStale
        RecLabel(text: recording ? "REC" : PhaseText.title(state, isStale: isStale).uppercased(), isRecording: recording)
    }
}

// MARK: Pieces

/// The pet lying on the floor, wide awake, the way it waits on the tape: a
/// still picture that never changes during the block.
private struct RestingPet: View {
    let pet: PetProfile
    let pixelSize: CGFloat

    var body: some View {
        PixelPet(canvas: PetCamPetArt.canvas(.lieDown, profile: pet).trimmed(margin: 1), palette: pet.palette,
                 pixelSize: pixelSize)
            .accessibilityHidden(true)
    }
}

/// "CAM 3", the hidden camera filming the block; nothing when none is.
private struct CameraNumber: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        if let camera = state.camera {
            Text(verbatim: "CAM \(camera)")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(CCTV.burnIn)
        }
    }
}

/// The phase's clock: counting down to the end, counting up for an open
/// stretch, frozen while paused, and the done line once it went stale.
private struct ClockText: View {
    let state: StudyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if isStale {
                Image(systemName: state.filming ? "play.fill" : "checkmark")
                    .imageScale(.small)
                    .accessibilityLabel(Text(verbatim: state.doneLine))
            } else {
                switch state.clock {
                case .countdown(let start, let end):
                    Text(timerInterval: start...end, countsDown: true)
                case .countUp(let since):
                    Text(timerInterval: since...Date.distantFuture, countsDown: false)
                case .paused(let shown):
                    Text(verbatim: StudyTimerFormat.clock(shown))
                }
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// A fixed width for the compact clock, sized to its longest reading,
    /// since a timer text otherwise claims all the room it can.
    static func compactWidth(for state: StudyActivityAttributes.ContentState) -> CGFloat {
        let seconds: TimeInterval = switch state.clock {
        case .countdown(let start, let end): end.timeIntervalSince(start)
        case .countUp: 3600
        case .paused(let shown): shown
        }
        return seconds >= 3600 ? 62 : 44
    }
}

/// The words for the phase: its name, "Paused" beside it, or the done
/// line the app wrote once the phase has run out.
private enum PhaseText {
    static func title(_ state: StudyActivityAttributes.ContentState, isStale: Bool) -> String {
        if isStale { return state.doneLine }
        if case .paused = state.clock {
            return String(localized: "\(state.phaseName) · Paused", bundle: .tabbi)
        }
        return state.phaseName
    }
}

