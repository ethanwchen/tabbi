import Foundation

/// How close the pet is to the next shop item, before and after the points
/// a session just earned: what the end-of-session bar fills toward
/// ("1 more session to Ninja Headband") and what the closed notch hints at
/// when an unlock is near (the goal-gradient effect).
///
/// The goal is the cheapest shop item not owned that the points before the
/// session could not buy yet, so a session that makes an item affordable
/// fills the bar to the end instead of jumping to the next goal.
public struct UnlockProgress: Hashable, Sendable {
    /// Sessions left at or under which an unlock counts as near.
    public static let nearSessions = 2

    public var item: PetItem
    /// Spendable points before the session.
    public var balanceBefore: Int
    /// Spendable points now.
    public var balance: Int
    /// Points one more session like this one earns, for `sessionsLeft`.
    public var pointsPerSession: Int

    /// - Parameters:
    ///   - balance: spendable points now.
    ///   - earned: points the session just earned (0 for a plain look).
    ///   - ledger: what the pet owns.
    ///   - pointsPerSession: what a session like the one just done earns;
    ///     a typical focus block when nil or not positive.
    /// Nil when every shop item is owned.
    public init?(balance: Int, earned: Int = 0, ledger: PetPointsLedger, pointsPerSession: Int? = nil) {
        let before = max(0, balance - earned)
        let goals = PetItem.shopItems.filter { !ledger.owns($0) && $0.cost > before }
        guard let item = goals.min(by: { $0.cost < $1.cost }) else { return nil }
        self.item = item
        balanceBefore = before
        self.balance = balance
        let perSession = pointsPerSession ?? 0
        self.pointsPerSession = perSession > 0 ? perSession : PetEconomy.pointsPerTypicalBlock
    }

    /// The progress right after `award` was credited to `closet`, paced by
    /// the award's own sessions.
    public init?(after award: PetStudyAward, closet: PetCloset) {
        let pace = award.completedSessions > 0 ? award.points / award.completedSessions : nil
        self.init(balance: closet.balance, earned: award.points, ledger: closet.save.ledger, pointsPerSession: pace)
    }

    /// The pet's progress for its closet now, with no session just earned.
    public init?(closet: PetCloset) {
        self.init(balance: closet.balance, ledger: closet.save.ledger)
    }

    public var cost: Int { item.cost }
    /// Points still missing; 0 once the item is affordable.
    public var missing: Int { max(0, cost - balance) }
    public var isReady: Bool { missing == 0 }

    /// How full the bar was before the session, from 0 to 1.
    public var fractionBefore: Double { Self.fraction(balanceBefore, of: cost) }
    /// How full the bar is now, from 0 to 1.
    public var fraction: Double { Self.fraction(balance, of: cost) }

    /// Sessions like the last one still needed; 0 once ready.
    public var sessionsLeft: Int {
        missing == 0 ? 0 : (missing + pointsPerSession - 1) / pointsPerSession
    }

    /// Whether the unlock is close enough for the closed notch to hint at it.
    public var isNear: Bool { sessionsLeft <= Self.nearSessions }

    /// The line under the bar, e.g. "1 more session to Ninja Headband".
    public var line: String {
        switch sessionsLeft {
        case 0: "Enough for the \(item.displayName) now"
        case 1: "1 more session to \(item.displayName)"
        default: "\(sessionsLeft) more sessions to \(item.displayName)"
        }
    }

    private static func fraction(_ points: Int, of cost: Int) -> Double {
        guard cost > 0 else { return 1 }
        return min(1, max(0, Double(points) / Double(cost)))
    }
}
