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
    /// Points per sprite pixel for party pets: a 24 pt pet fits the notch's height.
    public static let partyPetPixelSize: CGFloat = 0.75
    /// Party pets overlap a little, since each sprite has empty room around it.
    public static let partyPetStep: CGFloat = 18
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
        case .focus(let focus):
            // Measure a fixed-width sample so the wing doesn't breathe as digits change.
            content = textWidth(String(TickerFormat.focusClock(focus.time).map { $0.isNumber ? "0" : $0 }))
        case .tasks(let remaining):
            content = textWidth(TickerFormat.tasksLeft(remaining))
        case .progress(let progress):
            content = textWidth(TickerFormat.progressLeft(progress))
        case .highlight(let highlight):
            content = textWidth(highlight.text)
        case .pet(let pet):
            // Measured asleep too, so the wing doesn't jump when the pet dozes off.
            content = max(textWidth(pet.profile.name) + Theme.Spacing.xs + textWidth(TickerFormat.petSleeping),
                          NotchPetWing.side)
        case .party(let party):
            content = max(partyPetsWidth(count: party.pets.count), textWidth(TickerFormat.partySize(party.memberCount)))
        }
        let wing = (content + outerInset + innerGap).rounded(.up)
        return min(max(wing, iconSize + outerInset + innerGap), maxWingWidth)
    }

    /// The icon beside the closed notch; a module's progress, and its
    /// highlight unless it names a symbol, use that module's symbol from
    /// `catalog`.
    public static func symbol(for item: TickerItem, catalog: ModuleCatalog) -> String {
        switch item {
        case .meeting(let meeting): meeting.canJoin ? "video.fill" : "calendar"
        case .nowPlaying: "music.note"
        case .focus(let focus): focus.phase == .focus ? "timer" : "cup.and.saucer.fill"
        case .tasks: "checklist"
        case .progress(let progress): catalog.descriptor(for: progress.source).symbol
        case .highlight(let highlight): highlight.symbol ?? catalog.descriptor(for: highlight.source).symbol
        case .pet: "pawprint.fill"
        case .party: "person.3.fill"
        }
    }

    /// The full sentence for the tooltip, e.g. "Standup in 4 min".
    public static func summary(for item: TickerItem) -> String {
        switch item {
        case .meeting(let meeting): TickerFormat.meetingSummary(meeting)
        case .nowPlaying: "Now playing"
        case .focus(let focus): TickerFormat.focusSummary(focus)
        case .tasks(let remaining): TickerFormat.tasksLeft(remaining)
        case .progress(let progress): "\(progress.title): \(TickerFormat.progressLeft(progress))"
        case .highlight(let highlight): highlight.summary
        case .pet(let pet): TickerFormat.petSummary(pet)
        case .party(let party):
            "Studying with " + ListFormatter.localizedString(byJoining: party.pets.dropFirst().map(\.name)
                + (party.memberCount > party.pets.count ? ["\(party.memberCount - party.pets.count) more"] : []))
        }
    }

    /// Width of `count` overlapping party pets.
    public static func partyPetsWidth(count: Int) -> CGFloat {
        let side = CGFloat(PetComposer.frameSize) * partyPetPixelSize
        return count > 0 ? side + CGFloat(count - 1) * partyPetStep : 0
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
