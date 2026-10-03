import AppKit
import NotchKitCore

/// Sizes for the closed-notch preview.
///
/// The wing width is computed from the text rather than measured by SwiftUI,
/// so the notch shape, its hit area, and offscreen snapshots all agree on it
/// in the same frame.
@MainActor
public enum NotchPreviewLayout {
    public static let iconSize: CGFloat = 20
    /// Gap between the wing content and the outer edge of the notch shape.
    public static let outerInset: CGFloat = Theme.Spacing.s
    /// Keeps a long meeting title from turning the notch into a menu bar.
    public static let maxWingWidth: CGFloat = 132
    /// Gap between the trailing text and the camera housing.
    private static let innerGap: CGFloat = Theme.Spacing.s

    /// Width of each wing; both are equal so the shape stays centered on the camera.
    public static func wingWidth(for item: TickerItem) -> CGFloat {
        let content: CGFloat
        switch item {
        case .nowPlaying:
            return Theme.Layout.compactWingWidth
        case .meeting(let meeting):
            content = textWidth(meeting.title) + Theme.Spacing.xs
                + textWidth(TickerFormat.meetingCountdown(meeting.timing))
        case .focus(_, let remaining, _):
            // Measure a fixed-width sample so the wing doesn't breathe as digits change.
            content = textWidth(String(TickerFormat.focusClock(remaining).map { $0.isNumber ? "0" : $0 }))
        case .tasks(let remaining):
            content = textWidth(TickerFormat.tasksLeft(remaining))
        case .progress(let progress):
            content = textWidth(TickerFormat.progressLeft(progress))
        case .claudeUsage(let window, let utilization):
            content = textWidth(TickerFormat.usage(window: window, utilization: utilization))
        case .pet(let pet):
            // Measured asleep too, so the wing doesn't jump when the pet dozes off.
            content = max(textWidth(pet.profile.name) + Theme.Spacing.xs + textWidth(TickerFormat.petSleeping),
                          NotchPetWing.side)
        }
        let wing = (content + outerInset + innerGap).rounded(.up)
        return min(max(wing, iconSize + outerInset + innerGap), maxWingWidth)
    }

    public static func symbol(for item: TickerItem) -> String {
        switch item {
        case .meeting(let meeting): meeting.canJoin ? "video.fill" : "calendar"
        case .nowPlaying: "music.note"
        case .focus(let phase, _, _): phase == .focus ? "timer" : "cup.and.saucer.fill"
        case .tasks: "checklist"
        case .progress(let progress): progress.source.descriptor.symbol
        case .claudeUsage: "gauge.with.dots.needle.67percent"
        case .pet: "pawprint.fill"
        }
    }

    /// The full sentence for the tooltip, e.g. "Standup in 4 min".
    public static func summary(for item: TickerItem) -> String {
        switch item {
        case .meeting(let meeting): TickerFormat.meetingSummary(meeting)
        case .nowPlaying: "Now playing"
        case .focus(let phase, let remaining, let isRunning):
            "\(phase == .focus ? "Focus" : "Break") \(TickerFormat.focusClock(remaining))\(isRunning ? "" : " (paused)")"
        case .tasks(let remaining): TickerFormat.tasksLeft(remaining)
        case .progress(let progress): "\(progress.title): \(TickerFormat.progressLeft(progress))"
        case .claudeUsage(let window, let utilization):
            "Claude usage \(TickerFormat.usage(window: window, utilization: utilization))"
        case .pet(let pet): TickerFormat.petSummary(pet)
        }
    }

    /// `Theme.Typography.caption` with monospaced digits, as AppKit measures it.
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let monospaced = rounded.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
        ]]])
        return NSFont(descriptor: monospaced, size: 10.5) ?? base
    }()

    private static func textWidth(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }
}
