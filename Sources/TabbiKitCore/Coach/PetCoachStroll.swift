import Foundation

/// The coach overlay's little play: the pet trots out from under the notch
/// along the top of the screen, stops to say its line, then trots back.
///
/// A pure value of timestamps, so the overlay view only asks "where is the
/// pet at `date`?" and every frame (and every snapshot) is deterministic.
/// Offsets are in points from the notch edge, growing away from the notch.
public struct PetCoachStroll: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case walkingOut
        /// Standing still with the speech bubble up.
        case talking
        case walkingBack
        /// Back under the notch; the overlay can close.
        case finished
    }

    /// Which way the pet faces. The walk clip faces left, so `.awayFromNotch`
    /// draws it mirrored when the overlay sits right of the notch.
    public enum Heading: Hashable, Sendable {
        case awayFromNotch
        case towardNotch
    }

    public let startedAt: Date
    /// How far from the notch edge the pet stops to talk, in points.
    public let distance: Double
    /// Walking speed in points per second.
    public let speed: Double
    /// How long the bubble stays up when nobody answers it.
    public let talkDuration: TimeInterval
    /// When the user answered (or dismissed) the bubble, if they did.
    public private(set) var dismissedAt: Date?
    /// When the pointer came to rest on the bubble, while it is still there.
    /// Holding stops the talking clock, so a line being read stays up.
    public private(set) var heldSince: Date?
    /// Talk time added by earlier holds.
    public private(set) var heldFor: TimeInterval = 0

    /// After a hold ends the bubble stays at least this long, so moving the
    /// pointer away never snaps it shut mid-sentence.
    public static let lingerAfterHold: TimeInterval = 1.5

    /// A calm trot: 96 pt at 64 pt/s takes 1.5 s each way, quick enough to
    /// not be in the way and slow enough to read as a walk, not a dart.
    public init(
        startedAt: Date,
        distance: Double = 96,
        speed: Double = 64,
        talkDuration: TimeInterval = 12
    ) {
        self.startedAt = startedAt
        self.distance = max(distance, 0)
        self.speed = max(speed, 1)
        self.talkDuration = max(talkDuration, 0)
    }

    /// Seconds for the full walk one way.
    public var walkDuration: TimeInterval { distance / speed }

    /// The pet arrives at its spot and the bubble appears.
    public var arrivesAt: Date { startedAt.addingTimeInterval(walkDuration) }

    /// When the pet turns to walk home: on time, or early once dismissed.
    /// Dismissing mid-walk turns it around where it stands.
    public var turnsBackAt: Date {
        let unanswered = heldSince == nil ? arrivesAt.addingTimeInterval(talkDuration + heldFor) : .distantFuture
        guard let dismissedAt else { return unanswered }
        return min(max(dismissedAt, startedAt), unanswered)
    }

    /// Back under the notch.
    public var endsAt: Date {
        turnsBackAt.addingTimeInterval(offset(walkingOutAt: turnsBackAt) / speed)
    }

    /// Ends the bubble early: the pet turns around now. Only the first
    /// dismissal counts, so a double click can't restart the walk.
    public mutating func dismiss(at date: Date) {
        guard dismissedAt == nil else { return }
        dismissedAt = date
    }

    /// Keeps the bubble up while the pointer rests on it. Only while talking
    /// and not dismissed; a second hold before a release changes nothing.
    public mutating func hold(at date: Date) {
        guard heldSince == nil, dismissedAt == nil, phase(at: date) == .talking else { return }
        heldSince = date
    }

    /// The pointer left the bubble: the talking clock runs again, with at
    /// least `lingerAfterHold` left.
    public mutating func release(at date: Date) {
        guard let heldSince else { return }
        self.heldSince = nil
        heldFor += max(date.timeIntervalSince(heldSince), 0)
        let left = arrivesAt.addingTimeInterval(talkDuration + heldFor).timeIntervalSince(date)
        if left < Self.lingerAfterHold { heldFor += Self.lingerAfterHold - left }
    }

    /// Seconds the bubble has been talking at `date`, not counting holds:
    /// what decides when a two-part line moves on to its second part.
    public func talkElapsed(at date: Date) -> TimeInterval {
        let clock = min(date, heldSince ?? date)
        return max(clock.timeIntervalSince(arrivesAt) - heldFor, 0)
    }

    /// When the bubble will have talked for `seconds`, or nil while held
    /// (the clock is stopped, so that moment is not known yet).
    public func date(afterTalking seconds: TimeInterval) -> Date? {
        guard heldSince == nil else { return nil }
        return arrivesAt.addingTimeInterval(seconds + heldFor)
    }

    public func phase(at date: Date) -> Phase {
        if date >= endsAt { return .finished }
        if date >= turnsBackAt { return .walkingBack }
        if date >= arrivesAt { return .talking }
        return .walkingOut
    }

    /// Distance from the notch edge at `date`, 0 before the start and after
    /// the end.
    public func offset(at date: Date) -> Double {
        switch phase(at: date) {
        case .walkingOut, .talking:
            return offset(walkingOutAt: date)
        case .walkingBack:
            let back = date.timeIntervalSince(turnsBackAt) * speed
            return max(offset(walkingOutAt: turnsBackAt) - back, 0)
        case .finished:
            return 0
        }
    }

    public func heading(at date: Date) -> Heading {
        switch phase(at: date) {
        case .walkingOut, .talking: .awayFromNotch
        case .walkingBack, .finished: .towardNotch
        }
    }

    /// Whether the speech bubble shows at `date`.
    public func showsBubble(at date: Date) -> Bool { phase(at: date) == .talking }

    private func offset(walkingOutAt date: Date) -> Double {
        let walked = max(date.timeIntervalSince(startedAt), 0) * speed
        return min(walked, distance)
    }
}
