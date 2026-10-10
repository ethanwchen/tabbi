import SwiftUI
import TabbiKitCore
import WidgetKit

/// The widget's two sizes, so the views and their tests need no WidgetKit
/// environment to pick a layout.
public enum PetWidgetSize: Sendable {
    case small
    case medium
}

/// The Tabbi widget: the pet in its outfit, the streak, today's focus
/// minutes and, while a timer runs, its clock.
///
/// Everything shown is read from `state` as of `date` (the timeline entry's
/// date), so minutes reset at midnight and a finished countdown goes away
/// without the app writing again. A running clock uses WidgetKit's live
/// date text, which counts on its own with no timeline reloads.
public struct PetWidgetView: View {
    let state: WidgetState
    let date: Date
    let size: PetWidgetSize

    public init(state: WidgetState, date: Date, size: PetWidgetSize) {
        self.state = state
        self.date = date
        self.size = size
    }

    public var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            }
        }
        .foregroundStyle(WidgetPalette.primaryText)
        .containerBackground(WidgetPalette.background, for: .widget)
        .widgetURL(Self.openURL)
    }

    /// Opens Tabbi when the widget is clicked. A widget opens its own app on
    /// a click anyway; the URL says so explicitly.
    public static let openURL = URL(string: "tabbi://open")

    // MARK: Layouts

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                PetSprite(pet: state.pet, pointsPerPixel: 2)
                Spacer(minLength: 4)
                StreakBadge(days: streak)
            }
            Spacer(minLength: 4)
            headline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                PetSprite(pet: state.pet, pointsPerPixel: 3)
                Text(state.pet.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 112)
            .frame(maxHeight: .infinity)
            .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                headline
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    StatChip(symbol: "flame.fill", value: streakText, caption: "streak",
                             tint: streak > 0 ? WidgetPalette.accent : WidgetPalette.secondaryText,
                             accessibilityText: streak == 0 ? "No streak yet" : "\(streakText) streak")
                    if timer != nil {
                        StatChip(symbol: "clock.fill", value: minutesText, caption: "today",
                                 tint: WidgetPalette.secondaryText,
                                 accessibilityText: "\(minutesText) focused today")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The one primary element: the running clock, or today's minutes.
    @ViewBuilder private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let timer {
                Label(isPaused ? "\(timer.label) paused" : timer.label, systemImage: symbol(for: timer))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(for: timer))
                    .lineLimit(1)
                TimerClock(timer: timer, date: date)
                    .font(.system(size: size == .small ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("Today")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondaryText)
                Text(minutesText)
                    .font(.system(size: size == .small ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(minutes == 0 ? "No focus yet" : "focused")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Values

    private var timer: WidgetState.Timer? { state.timer(at: date) }
    private var minutes: Int { state.minutes(at: date) }
    private var streak: Int { state.streak(at: date) }
    private var minutesText: String { DurationFormat.minutes(minutes) }
    private var streakText: String {
        switch streak {
        case 0: "Start today"
        case 1: "1 day"
        default: "\(streak) days"
        }
    }

    private var isPaused: Bool {
        if case .paused? = timer?.clock { true } else { false }
    }

    private func symbol(for timer: WidgetState.Timer) -> String {
        if isPaused { return "pause.circle.fill" }
        return timer.phase == .focus ? "timer" : "cup.and.saucer.fill"
    }

    private func tint(for timer: WidgetState.Timer) -> Color {
        timer.phase == .focus ? WidgetPalette.accent : WidgetPalette.rest
    }
}

/// A running clock as live date text, or a paused one as a still time.
private struct TimerClock: View {
    let timer: WidgetState.Timer
    let date: Date

    var body: some View {
        switch timer.clock {
        case .countdown(let end):
            Text(timerInterval: date...max(end, date), countsDown: true)
        case .countUp(let start):
            Text(timerInterval: min(start, date)...Date.distantFuture, countsDown: false)
        case .paused(let shown):
            Text(FocusTimerFormat.clock(shown))
                .foregroundStyle(WidgetPalette.secondaryText)
        }
    }
}

/// The pet's sitting frame at a whole number of points per sprite pixel,
/// rendered at the display's pixel density with no smoothing, so its edges
/// stay sharp.
struct PetSprite: View {
    let pet: PetProfile
    let pointsPerPixel: Int

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let canvas = pet.sittingCanvas()
        let scale = pointsPerPixel * max(1, Int(displayScale.rounded()))
        Group {
            if let image = PetRenderer.shared.image(for: canvas, palette: pet.palette, scale: scale) {
                Image(decorative: image, scale: CGFloat(scale) / CGFloat(pointsPerPixel))
                    .interpolation(.none)
            }
        }
        .frame(width: CGFloat(canvas.width * pointsPerPixel), height: CGFloat(canvas.height * pointsPerPixel))
        .accessibilityElement()
        .accessibilityLabel("\(pet.name), \(pet.breed.displayName)")
    }
}

/// The small widget's streak: a flame and the day count.
private struct StreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .foregroundStyle(days > 0 ? WidgetPalette.accent : WidgetPalette.secondaryText)
            Text("\(days)")
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(WidgetPalette.surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "1 day streak" : "\(days) day streak")
    }
}

/// A medium widget stat: a symbol, a value and what it counts. VoiceOver
/// reads it as one phrase instead of the symbol's name and two fragments.
private struct StatChip: View {
    let symbol: String
    let value: String
    let caption: String
    let tint: Color
    let accessibilityText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetPalette.secondaryText)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
