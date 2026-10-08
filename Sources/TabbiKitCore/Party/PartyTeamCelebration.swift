import Foundation

/// The short "Great job, team!" moment after a shared session runs to its
/// end: what it says and how long it stays at the top of the Party panel.
public struct PartyTeamCelebration: Hashable, Sendable {
    /// How long the message stays before the panel goes back to normal.
    public static let displayDuration: TimeInterval = 8

    public var completion: PartySessionCompletion
    /// Pet points the user earned for the session; 0 when the stay was too
    /// short to pay.
    public var points: Int
    /// The user's pet name, for "+20 points for Miso".
    public var petName: String?
    /// When the celebration started.
    public var date: Date

    public init(completion: PartySessionCompletion, points: Int, petName: String? = nil, date: Date) {
        self.completion = completion
        self.points = max(points, 0)
        let name = petName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.petName = name.isEmpty ? nil : name
        self.date = date
    }

    /// "Great job, team!", or "Great job!" when nobody else studied along.
    public var title: String {
        completion.friendCount > 0 ? "Great job, team!" : "Great job!"
    }

    /// What was earned and how: "+20 points for Miso · 25 min with 2 friends".
    public var detail: String {
        var parts: [String] = []
        if points > 0 {
            let unit = points == 1 ? "point" : "points"
            parts.append(petName.map { "+\(points) \(unit) for \($0)" } ?? "+\(points) \(unit)")
        }
        let company = switch completion.friendCount {
        case 0: "on your own"
        case 1: "with 1 friend"
        default: "with \(completion.friendCount) friends"
        }
        parts.append("\(completion.minutes) min \(company)")
        return parts.joined(separator: " · ")
    }

    /// Whether the message is still up at `now`.
    public func isShowing(at now: Date) -> Bool {
        now >= date && now.timeIntervalSince(date) < Self.displayDuration
    }

    /// When the message goes away.
    public var endsAt: Date { date.addingTimeInterval(Self.displayDuration) }
}
