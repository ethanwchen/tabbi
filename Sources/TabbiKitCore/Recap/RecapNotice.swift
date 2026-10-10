import Foundation

/// The words of the macOS notification that says a weekly recap is ready.
/// Warm like the card: the week's line, the time focused when there was
/// any, and where to find the card, never a count of what was missed.
public struct RecapNotice: Hashable, Sendable {
    public let title: String
    public let body: String

    public init(recap: WeeklyRecap, cheer: RecapCheer) {
        title = "Your week with Tabbi is ready"
        let focus = recap.focusMinutes > 0 ? " \(DurationFormat.minutes(recap.focusMinutes)) of focus." : ""
        body = "\(cheer.line)\(focus) Open the notch to see your recap."
    }
}
