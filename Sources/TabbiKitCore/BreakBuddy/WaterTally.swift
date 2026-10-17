import Foundation

/// Glasses of water and finished break moves, kept in the shared activity
/// log so they stay on the Mac with everything else the user did.
///
/// Both kinds are the break buddy's own and nothing scores them: points,
/// streaks, Wrap Up and the widget read only focus records, so a glass of
/// water or a stretch never earns or costs anything. A skipped move is not
/// logged at all.
public enum WaterTally {
    /// A glass of water the user logged from the break card.
    public static let waterKind: ActivityKind = "water.logged"
    /// A break move the user did with the pet; `subject` is the move.
    public static let moveKind: ActivityKind = "break.move"
    /// The unit a glass of water is logged in.
    public static let glass: ActivityUnit = "glass"
    /// The break buddy belongs to the pet, whose module logs for it.
    public static let source: ModuleID = .closet

    /// The record for one glass of water at `date`.
    public static func water(at date: Date) -> ActivityRecord {
        ActivityRecord(source: source, kind: waterKind, start: date, quantity: 1, unit: glass)
    }

    /// The record for `move`, done with the pet at `date`.
    public static func move(_ move: BreakMove, at date: Date) -> ActivityRecord {
        ActivityRecord(source: source, kind: moveKind, start: date, subject: move.rawValue)
    }

    /// Glasses of water logged on `day` among `records`.
    public static func glasses(in records: some Sequence<ActivityRecord>, on day: PlannerDayKey,
                               calendar: Calendar = .current) -> Int {
        Int(records.filter { $0.kind == waterKind && $0.source == source && $0.day(calendar: calendar) == day }
            .reduce(0) { $0 + max($1.quantity ?? 1, 0) })
    }

    /// Moves done on `day` among `records`, one per record, oldest first.
    public static func moves(in records: some Sequence<ActivityRecord>, on day: PlannerDayKey,
                             calendar: Calendar = .current) -> [BreakMove] {
        records.filter { $0.kind == moveKind && $0.source == source && $0.day(calendar: calendar) == day }
            .compactMap { $0.subject.flatMap(BreakMove.init(rawValue:)) }
    }
}
