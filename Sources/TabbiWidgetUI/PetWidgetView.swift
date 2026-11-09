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
///
/// When the widget has no state of the app's to show (`isWaitingForApp`:
/// Tabbi has not run yet, or the file could not be read) it shows the pet
/// and "Open Tabbi to start" rather than made-up numbers, so it is never
/// blank and never wrong.
public struct PetWidgetView: View {
    let state: WidgetState
    let date: Date
    let size: PetWidgetSize
    let rendering: PetWidgetRendering
    let isWaitingForApp: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(state: WidgetState, date: Date, size: PetWidgetSize, rendering: PetWidgetRendering = .fullColor,
                isWaitingForApp: Bool = false) {
        self.state = state
        self.date = date
        self.size = size
        self.rendering = rendering
        self.isWaitingForApp = isWaitingForApp
    }

    public var body: some View {
        Group {
            switch (size, isWaitingForApp) {
            case (.small, false): small
            case (.medium, false): medium
            case (.small, true): smallWaiting
            case (.medium, true): mediumWaiting
            }
        }
        .foregroundStyle(palette.primaryText)
        .containerBackground(palette.background, for: .widget)
        .widgetURL(Self.openURL)
    }

    private var palette: WidgetPalette { WidgetPalette(scheme: colorScheme, rendering: rendering) }

    /// Opens Tabbi when the widget is clicked. A widget opens its own app on
    /// a click anyway; the URL says so explicitly.
    public static let openURL = URL(string: "tabbi://open")

    // MARK: Layouts

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                PetSprite(pet: state.pet, pointsPerPixel: 2, rendering: rendering)
                Spacer(minLength: 4)
                StreakBadge(days: streak, palette: palette)
            }
            Spacer(minLength: 4)
            headline
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            petTile

            VStack(alignment: .leading, spacing: 0) {
                headline
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    StatChip(symbol: "flame.fill", value: streakText, caption: String(localized: "streak", bundle: .tabbi),
                             tint: streak > 0 ? palette.accent : palette.secondaryText, palette: palette,
                             accessibilityText: streak == 0 ? String(localized: "No streak yet", bundle: .tabbi)
                                 : String(localized: "\(streak)-day streak", bundle: .tabbi))
                    if timer != nil {
                        StatChip(symbol: "clock.fill", value: minutesText, caption: String(localized: "today", bundle: .tabbi),
                                 tint: palette.secondaryText, palette: palette,
                                 accessibilityText: String(localized: "\(minutesText) focused today", bundle: .tabbi))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The pet and its name on a tile, the medium widget's left side.
    private var petTile: some View {
        VStack(spacing: 4) {
            PetSprite(pet: state.pet, pointsPerPixel: 3, rendering: rendering)
            Text(state.pet.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
        }
        .frame(width: 112)
        .frame(maxHeight: .infinity)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Waiting for the app

    /// Before the app has shared anything: the pet and a gentle nudge.
    private var smallWaiting: some View {
        VStack(alignment: .leading, spacing: 0) {
            PetSprite(pet: state.pet, pointsPerPixel: 2, rendering: rendering)
            Spacer(minLength: 4)
            waitingText
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumWaiting: some View {
        HStack(spacing: 16) {
            petTile
            waitingText
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var waitingText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open Tabbi to start", bundle: .tabbi)
                .font(.system(size: size == .small ? 15 : 17, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your pet, streak and timer show up here.", bundle: .tabbi)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Headline

    /// The one primary element: the running clock, or today's minutes.
    @ViewBuilder private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let timer {
                Label(isPaused ? String(localized: "\(timer.label) (paused)", bundle: .tabbi) : timer.label, systemImage: symbol(for: timer))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(for: timer))
                    .widgetAccentable()
                    .lineLimit(1)
                TimerClock(timer: timer, date: date, palette: palette)
                    .font(.system(size: size == .small ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("Today", bundle: .tabbi)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                Text(minutesText)
                    .font(.system(size: size == .small ? 28 : 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(minutes == 0 ? String(localized: "No focus yet", bundle: .tabbi) : String(localized: "focused", bundle: .tabbi))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
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
        // "%lld days" is taken by a dative phrase in the Closet chart, so
        // the widget's count has a key of its own; its English is "12 days".
        streak == 0 ? String(localized: "Start today", bundle: .tabbi)
            : String(localized: "\(streak) streak days", bundle: .tabbi)
    }

    private var isPaused: Bool {
        if case .paused? = timer?.clock { true } else { false }
    }

    private func symbol(for timer: WidgetState.Timer) -> String {
        if isPaused { return "pause.circle.fill" }
        return timer.phase == .focus ? "timer" : "cup.and.saucer.fill"
    }

    private func tint(for timer: WidgetState.Timer) -> AnyShapeStyle {
        timer.phase == .focus ? palette.accent : palette.rest
    }
}

/// A running clock as live date text, or a paused one as a still time.
private struct TimerClock: View {
    let timer: WidgetState.Timer
    let date: Date
    let palette: WidgetPalette

    var body: some View {
        switch timer.clock {
        case .countdown(let end):
            Text(timerInterval: date...max(end, date), countsDown: true)
        case .countUp(let start):
            Text(timerInterval: min(start, date)...Date.distantFuture, countsDown: false)
        case .paused(let shown):
            Text(FocusTimerFormat.clock(shown))
                .foregroundStyle(palette.secondaryText)
        }
    }
}

/// The pet's sitting frame at a whole number of points per sprite pixel,
/// rendered at the display's pixel density with no smoothing, so its edges
/// stay sharp.
///
/// If the pet art did not ship with the extension (a damaged install), it
/// draws a paw print instead: loading missing art stops the process, and
/// WidgetKit would show a blank widget.
struct PetSprite: View {
    let pet: PetProfile
    let pointsPerPixel: Int
    var rendering: PetWidgetRendering = .fullColor

    @Environment(\.displayScale) private var displayScale

    /// Checked once per process; the art cannot appear while it runs.
    static let canDraw = WidgetState.canDrawPet
    /// The sprite canvas's size in sprite pixels, for the paw print's frame.
    static let fallbackSide = 32

    var body: some View {
        Group {
            if Self.canDraw {
                sprite
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: CGFloat(Self.fallbackSide * pointsPerPixel) * 0.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: CGFloat(Self.fallbackSide * pointsPerPixel),
                           height: CGFloat(Self.fallbackSide * pointsPerPixel))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(pet.name), \(pet.breed.displayName)")
    }

    private var sprite: some View {
        let canvas = pet.sittingCanvas()
        let scale = pointsPerPixel * max(1, Int(displayScale.rounded()))
        return Group {
            if let image = PetRenderer.shared.image(for: canvas, palette: pet.palette, scale: scale) {
                petImage(Image(decorative: image, scale: CGFloat(scale) / CGFloat(pointsPerPixel)).interpolation(.none))
            }
        }
        .frame(width: CGFloat(canvas.width * pointsPerPixel), height: CGFloat(canvas.height * pointsPerPixel))
    }

    /// Outside full color the system would draw the sprite as one flat
    /// tinted silhouette; desaturated keeps the pet's shading, so it still
    /// reads as the pet (macOS 15 and later; macOS 14 has no tinted widgets).
    @ViewBuilder private func petImage(_ image: Image) -> some View {
        if #available(macOS 15, *), rendering == .accented {
            image.widgetAccentedRenderingMode(.desaturated)
        } else {
            image
        }
    }
}

/// The small widget's streak: a flame and the day count.
private struct StreakBadge: View {
    let days: Int
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .foregroundStyle(days > 0 ? palette.accent : palette.secondaryText)
                .widgetAccentable()
            Text("\(days)")
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(days)-day streak", bundle: .tabbi))
    }
}

/// A medium widget stat: a symbol, a value and what it counts. VoiceOver
/// reads it as one phrase instead of the symbol's name and two fragments.
private struct StatChip: View {
    let symbol: String
    let value: String
    let caption: String
    let tint: AnyShapeStyle
    let palette: WidgetPalette
    let accessibilityText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
