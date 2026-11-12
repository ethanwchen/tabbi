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

/// The running study session on the Lock Screen and in the Dynamic Island:
/// the pet, the phase and its countdown. The countdown and the bar are
/// drawn by the system from the phase's dates (`Text(timerInterval:)`,
/// `ProgressView(timerInterval:)`), so they keep moving while the app is
/// suspended. Once the phase's end passes, the activity goes stale and says
/// the phase is done until the app moves it on.
struct StudySessionActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            LockScreenView(pet: context.attributes.pet, state: context.state, isStale: context.isStale || context.state.isDone)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale || context.state.isDone
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PetBadge(pet: context.attributes.pet, pixelSize: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ClockText(state: state, isStale: stale)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandTone(state: state, isStale: stale).color)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(PhaseText.title(state, isStale: stale))
                            .font(.headline)
                        PhaseBar(state: state, isStale: stale)
                            .tint(IslandTone(state: state, isStale: stale).color)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                PetBadge(pet: context.attributes.pet, pixelSize: 1)
            } compactTrailing: {
                ClockText(state: state, isStale: stale)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandTone(state: state, isStale: stale).color)
                    .frame(width: ClockText.compactWidth(for: state))
            } minimal: {
                ClockText(state: state, isStale: stale, minutesOnly: true)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandTone(state: state, isStale: stale).color)
            }
            .keylineTint(IslandTone(state: state, isStale: stale).color)
        }
    }
}

// MARK: Lock Screen

private struct LockScreenView: View {
    let pet: PetProfile
    let state: StudyActivityAttributes.ContentState
    let isStale: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = StudyTone(isBreak: state.isBreak, isIdle: isStale)
        HStack(alignment: .center, spacing: 14) {
            PetBadge(pet: pet, pixelSize: 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(PhaseText.title(state, isStale: isStale))
                        .font(.headline)
                        .foregroundStyle(tone.hue(scheme))
                    Spacer(minLength: 4)
                    ClockText(state: state, isStale: isStale)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                PhaseBar(state: state, isStale: isStale)
                    .tint(tone.hue(scheme))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: Pieces

/// The pet's sitting frame cut to its pixels, drawn by the shared renderer
/// at whole device pixels: `pixelSize` 1 is a 3 pixel square per sprite
/// pixel on a 3x screen.
private struct PetBadge: View {
    let pet: PetProfile
    let pixelSize: CGFloat

    var body: some View {
        PixelPet(canvas: pet.sittingCanvas().trimmed(margin: 1), palette: pet.palette, pixelSize: pixelSize)
            .accessibilityLabel(Text(verbatim: pet.name))
    }
}

/// The phase's clock: counting down to the end, counting up for an open
/// stretch, frozen while paused, and the done line once it went stale.
private struct ClockText: View {
    let state: StudyActivityAttributes.ContentState
    let isStale: Bool
    /// Whole minutes left only, for the tiny minimal presentation.
    var minutesOnly = false

    var body: some View {
        Group {
            if isStale {
                Image(systemName: "checkmark")
            } else {
                switch state.clock {
                case .countdown(let start, let end):
                    if minutesOnly {
                        Text(timerInterval: start...end, countsDown: true, showsHours: false)
                    } else {
                        Text(timerInterval: start...end, countsDown: true)
                    }
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

/// The phase's progress as a bar, filled by the system while it runs.
private struct PhaseBar: View {
    let state: StudyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            switch state.clock {
            case .countdown(let start, let end) where !isStale:
                ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            case .paused(let shown):
                let length = max(state.phaseLength ?? 0, 1)
                ProgressView(value: state.phaseLength == nil ? 0 : min(max(1 - shown / length, 0), 1))
            case .countUp:
                ProgressView(value: 0).opacity(0)
            default:
                ProgressView(value: 1)
            }
        }
        .progressViewStyle(.linear)
        .labelsHidden()
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

/// The Dynamic Island is always black, so it uses the dark-mode hues.
private struct IslandTone {
    let state: StudyActivityAttributes.ContentState
    let isStale: Bool

    var color: Color { StudyTone(isBreak: state.isBreak, isIdle: isStale).hue(.dark) }
}
