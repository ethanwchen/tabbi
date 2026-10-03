import Foundation

/// A short line a module wants beside the closed notch, such as "5h 86%"
/// from Claude Usage or "1 problem left" from a practice module. The
/// `HighlightSource` role of a module: the ticker shows it with the module's
/// symbol and accent and opens that module on click, with no ticker code
/// knowing the module.
///
/// The ticker shows at most one highlight per module at a time: the one with
/// the highest `priority` that has not expired. Modules with highlights take
/// turns in the rotation, the highest priority first, ties in tab order.
public struct TickerHighlight: Identifiable, Hashable, Sendable {
    /// How the text is colored.
    public enum Tone: String, Hashable, Sendable {
        /// The module's accent, for a live number.
        case accent
        /// Plain primary text, for a calm status.
        case primary
        /// Secondary text, for something paused or waiting.
        case secondary
        /// The danger color, for a limit that has been hit.
        case danger
    }

    /// Stable within its source module.
    public var id: String
    /// The module that provided it; set by `ProviderSnapshot` when merging.
    public var source: ModuleID
    /// SF Symbol beside the notch; nil uses the source module's symbol.
    public var symbol: String?
    /// A few words, e.g. "5h 86%". The wing has room for about 20 characters.
    public var text: String
    /// The full sentence for the tooltip, e.g. "Claude usage 5h 86%".
    public var summary: String
    public var tone: Tone
    /// Higher wins, both within its module and in the rotation order.
    public var priority: Int
    /// Holds the notch instead of rotating away, like an imminent meeting.
    /// Use it only for something the user must not miss.
    public var isPinned: Bool
    /// When the highlight stops being true (say, a usage window resets).
    /// The ticker hides it from then on and wakes up at that moment, so the
    /// module doesn't have to publish again just to take it down.
    public var expiresAt: Date?

    public init(id: String, source: ModuleID, symbol: String? = nil, text: String, summary: String? = nil,
                tone: Tone = .accent, priority: Int = 0, isPinned: Bool = false, expiresAt: Date? = nil) {
        self.id = id
        self.source = source
        self.symbol = symbol
        self.text = text
        self.summary = summary ?? text
        self.tone = tone
        self.priority = priority
        self.isPinned = isPinned
        self.expiresAt = expiresAt
    }

    /// Whether the highlight still holds at `now`.
    public func isLive(at now: Date) -> Bool {
        expiresAt.map { $0 > now } ?? true
    }
}
