import Foundation

/// The server data the Party panel shows and refreshes on a timer.
public enum PartyFeed: String, CaseIterable, Hashable, Sendable {
    case friends
    case party
}

/// When to fetch friends and the party, following the backend's polling
/// guidance: the friends list when the panel opens and every 60 s while it
/// stays open, the party every 30 s while I'm in one and the panel shows,
/// and once per opening otherwise. While the panel is hidden the party is
/// still fetched once after connecting (via `invalidate`) and once whenever
/// the notch opens on any tab, so the closed notch's party pets stay
/// current. The free plan's daily request budget is shared by every user,
/// so this never polls faster.
///
/// The store calls `didFetch` after every attempt, failed or not, so a down
/// server is retried at the normal interval instead of in a tight loop.
public struct PartyRefreshPlan: Hashable, Sendable {
    public static let friendsInterval: TimeInterval = 60
    public static let partyInterval: TimeInterval = 30

    public private(set) var isVisible = false
    /// Whether I'm in a party; only then does the party refresh on a timer.
    public var inParty = false
    private var lastFetch: [PartyFeed: Date] = [:]
    /// Whether the party is owed one fetch even while the panel is hidden.
    private var partyOwed = false

    public init() {}

    /// Shows or hides the panel. Opening it makes every feed due at once;
    /// hiding it stops all refreshes.
    public mutating func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        if visible { lastFetch = [:] }
    }

    /// The notch opened, on any tab: the party is due once more.
    public mutating func notchDidOpen() {
        partyOwed = true
    }

    /// Records a fetch attempt, successful or not.
    public mutating func didFetch(_ feed: PartyFeed, at now: Date) {
        lastFetch[feed] = now
        if feed == .party { partyOwed = false }
    }

    /// Makes a feed due right away, e.g. the party after joining or leaving,
    /// or friends after adding one.
    public mutating func invalidate(_ feed: PartyFeed) {
        lastFetch[feed] = nil
        if feed == .party { partyOwed = true }
    }

    /// The feeds to fetch now, in display order.
    public func due(at now: Date) -> [PartyFeed] {
        PartyFeed.allCases.filter { feed in
            guard let next = nextFetch(of: feed) else { return false }
            return next <= now
        }
    }

    /// When the next feed falls due, or nil when nothing will until the
    /// panel or notch opens again or something is invalidated.
    public func nextDue() -> Date? {
        PartyFeed.allCases.compactMap(nextFetch(of:)).min()
    }

    private func nextFetch(of feed: PartyFeed) -> Date? {
        guard isVisible else { return feed == .party && partyOwed ? .distantPast : nil }
        guard let last = lastFetch[feed] else { return .distantPast }
        switch feed {
        case .friends: return last.addingTimeInterval(Self.friendsInterval)
        case .party: return inParty ? last.addingTimeInterval(Self.partyInterval) : nil
        }
    }
}
