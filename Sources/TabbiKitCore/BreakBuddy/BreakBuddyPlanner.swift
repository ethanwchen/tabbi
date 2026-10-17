import Foundation

/// Picks the one move the pet models at the start of a break. Pure and
/// deterministic: the same break, preferences and time always give the
/// same moment, so the Windows port can replay it from the golden fixture.
///
/// The rules, in order:
/// - Nothing when the buddy is off, every move is turned off, the break was
///   already planned (`BreakBuddyPreferences.lastBreakKey`), or less than
///   `minimumBreak` of it is left.
/// - A long break (`longBreak` or more) suggests standing up.
/// - Every `sipEvery`th planned break suggests a sip.
/// - Otherwise the pet rotates through `rotation` (stretch, eyes, breath),
///   picking the move after the last one it rotated to.
/// - When none of the rotation is turned on, the first other move that is.
///
/// The moment lasts the move's `length`, but never more than half the
/// break that is left, so the user always keeps most of the break to
/// themselves.
public enum BreakBuddyPlanner {
    /// Shorter breaks get no moment: half of them would be too short to do anything.
    public static let minimumBreak: TimeInterval = 40
    /// A break this long or longer (a Pomodoro's long break) suggests standing up.
    public static let longBreak: TimeInterval = 10 * 60
    /// A sip comes round on every this many planned breaks.
    public static let sipEvery = 3
    /// The moves short breaks take turns with.
    public static let rotation: [BreakMove] = [.stretch, .eyeRest, .breathe]

    /// A break under way, as the planner sees it.
    public struct Break: Hashable, Sendable {
        /// The module running the break's clock.
        public var source: ModuleID
        /// When the break began.
        public var startedAt: Date
        /// The break's full length in seconds.
        public var length: TimeInterval

        public init(source: ModuleID, startedAt: Date, length: TimeInterval) {
            self.source = source
            self.startedAt = startedAt
            self.length = length
        }

        /// When the break runs out.
        public var endsAt: Date { startedAt.addingTimeInterval(length) }

        /// A countdown break on the shared focus clock, or nil for focus,
        /// a clock counting up (no length to size a moment by), or one
        /// stopped or paused.
        public init?(_ focus: ProvidedFocus) {
            guard focus.phase == .rest, case .countdown(let endsAt) = focus.clock,
                  let length = focus.phaseLength, length > 0 else { return nil }
            self.init(source: focus.source, startedAt: endsAt.addingTimeInterval(-length), length: length)
        }
    }

    /// A planned moment and the preferences with the planner's history
    /// moved on, which the caller saves.
    public struct Plan: Equatable, Sendable {
        public var moment: BreakMoment
        public var preferences: BreakBuddyPreferences
    }

    /// The id the history keeps for a break: its clock and the second it began.
    public static func breakKey(_ rest: Break) -> String {
        "\(rest.source.rawValue)@\(Int(rest.startedAt.timeIntervalSince1970.rounded()))"
    }

    /// The moment for `rest` starting at `now`, or nil when it gets none.
    public static func plan(for rest: Break, preferences: BreakBuddyPreferences, at now: Date) -> Plan? {
        let key = breakKey(rest)
        let left = rest.endsAt.timeIntervalSince(max(now, rest.startedAt))
        guard preferences.isOn, !preferences.enabledMoves.isEmpty, preferences.lastBreakKey != key,
              left >= minimumBreak else { return nil }
        let (move, rotated) = pick(for: rest, preferences: preferences)
        var next = preferences
        if rotated { next.lastMove = move }
        next.breaksSinceSip = move == .sip ? 0 : preferences.breaksSinceSip + 1
        next.lastBreakKey = key
        let length = min(move.length, (left / 2).rounded(.down))
        let moment = BreakMoment(move: move, source: rest.source, breakStartedAt: rest.startedAt, startedAt: now,
                                 endsAt: now.addingTimeInterval(length))
        return Plan(moment: moment, preferences: next)
    }

    /// The move for `rest`, and whether the rotation picked it (so the next
    /// break rotates on from it).
    private static func pick(for rest: Break, preferences: BreakBuddyPreferences) -> (BreakMove, rotated: Bool) {
        if rest.length >= longBreak, preferences.isEnabled(.standUp) { return (.standUp, false) }
        if preferences.breaksSinceSip + 1 >= sipEvery, preferences.isEnabled(.sip) { return (.sip, false) }
        let turns = rotation.filter(preferences.isEnabled)
        guard !turns.isEmpty else {
            // Only moves outside the rotation are on; `plan` checked one is.
            return (preferences.enabledMoves.first ?? .stretch, false)
        }
        let after = preferences.lastMove.flatMap { rotation.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        for step in 0..<rotation.count {
            let move = rotation[(after + step) % rotation.count]
            if preferences.isEnabled(move) { return (move, true) }
        }
        return (turns[0], true)
    }
}
