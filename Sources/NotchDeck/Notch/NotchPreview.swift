import AppKit
import SwiftUI
import NotchKitCore

/// The live preview in the two wings beside the closed notch: an icon or
/// artwork on the leading side, short text or the equalizer on the trailing
/// side, crossfading as the ticker rotates.
struct NotchPreview: View {
    let item: TickerItem
    let notchWidth: CGFloat
    @EnvironmentObject private var services: AppServices

    var body: some View {
        let wing = NotchPreviewLayout.wingWidth(for: item)
        // Music keeps the centered artwork + equalizer pair it always had;
        // everything else hugs the outer edges like a Dynamic Island.
        let inset = item == .nowPlaying ? 0 : NotchPreviewLayout.outerInset
        let edge: (leading: Alignment, trailing: Alignment) =
            item == .nowPlaying ? (.center, .center) : (.leading, .trailing)
        HStack(spacing: 0) {
            leading
                .padding(.leading, inset)
                .frame(width: wing, alignment: edge.leading)
            Color.clear.frame(width: notchWidth)
            trailing
                .padding(.trailing, inset)
                .frame(width: wing, alignment: edge.trailing)
        }
        .id(item.kind)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.combined(with: .offset(y: -6))
        ))
        .help(NotchPreviewLayout.summary(for: item))
    }

    private var accent: Color { Theme.Palette.accent(for: item.kind.module) }

    @ViewBuilder private var leading: some View {
        switch item {
        case .nowPlaying:
            ModuleViews.compactLeading(services: services)
        default:
            Image(systemName: NotchPreviewLayout.symbol(for: item))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: NotchPreviewLayout.iconSize, height: NotchPreviewLayout.iconSize)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch item {
        case .nowPlaying:
            ModuleViews.compactTrailing(services: services)
        case .meeting(let meeting):
            HStack(spacing: Theme.Spacing.xs) {
                Text(meeting.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .truncationMode(.tail)
                Text(TickerFormat.meetingCountdown(meeting.timing))
                    .foregroundStyle(accent)
                    .fixedSize()
            }
            .previewText()
        case .focus(_, let remaining, let isRunning):
            Text(TickerFormat.focusClock(remaining))
                .foregroundStyle(isRunning ? accent : Theme.Palette.secondaryText)
                .previewText()
        case .tasks(let remaining):
            Text(TickerFormat.tasksLeft(remaining))
                .foregroundStyle(Theme.Palette.primaryText)
                .previewText()
        case .claudeUsage(let window, let utilization):
            Text(TickerFormat.usage(window: window, utilization: utilization))
                .foregroundStyle(utilization >= 1 ? Theme.Palette.danger : accent)
                .previewText()
        }
    }
}

private extension View {
    func previewText() -> some View {
        font(Theme.Typography.caption)
            .monospacedDigit()
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}

/// Sizes for the closed-notch preview.
///
/// The wing width is computed from the text rather than measured by SwiftUI,
/// so the notch shape, its hit area, and offscreen snapshots all agree on it
/// in the same frame.
@MainActor
enum NotchPreviewLayout {
    static let iconSize: CGFloat = 20
    /// Gap between the wing content and the outer edge of the notch shape.
    static let outerInset: CGFloat = Theme.Spacing.s
    /// Keeps a long meeting title from turning the notch into a menu bar.
    static let maxWingWidth: CGFloat = 132
    /// Gap between the trailing text and the camera housing.
    private static let innerGap: CGFloat = Theme.Spacing.s

    /// Width of each wing; both are equal so the shape stays centered on the camera.
    static func wingWidth(for item: TickerItem) -> CGFloat {
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
        case .claudeUsage(let window, let utilization):
            content = textWidth(TickerFormat.usage(window: window, utilization: utilization))
        }
        let wing = (content + outerInset + innerGap).rounded(.up)
        return min(max(wing, iconSize + outerInset + innerGap), maxWingWidth)
    }

    static func symbol(for item: TickerItem) -> String {
        switch item {
        case .meeting(let meeting): meeting.canJoin ? "video.fill" : "calendar"
        case .nowPlaying: "music.note"
        case .focus(let phase, _, _): phase == .focus ? "timer" : "cup.and.saucer.fill"
        case .tasks: "checklist"
        case .claudeUsage: "gauge.with.dots.needle.67percent"
        }
    }

    /// The full sentence for the tooltip, e.g. "Standup in 4 min".
    static func summary(for item: TickerItem) -> String {
        switch item {
        case .meeting(let meeting): TickerFormat.meetingSummary(meeting)
        case .nowPlaying: "Now playing"
        case .focus(let phase, let remaining, let isRunning):
            "\(phase == .focus ? "Focus" : "Break") \(TickerFormat.focusClock(remaining))\(isRunning ? "" : " (paused)")"
        case .tasks(let remaining): TickerFormat.tasksLeft(remaining)
        case .claudeUsage(let window, let utilization):
            "Claude usage \(TickerFormat.usage(window: window, utilization: utilization))"
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
