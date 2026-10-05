import Foundation

/// Which streak lengths earn a milestone celebration (docs/design/motion.md,
/// Celebrations). Only round, meaningful lengths count, so a daily habit
/// sparkles a handful of times a year rather than every day.
public enum StreakMilestone {
    /// The milestone lengths up to a year, in days.
    public static let days = [7, 14, 30, 50, 100, 200, 365]

    /// Whether a streak of `length` days is a milestone: one of `days`, or
    /// past a year every further 100 days and every whole year.
    public static func isMilestone(_ length: Int) -> Bool {
        guard length > 0 else { return false }
        if days.contains(length) { return true }
        return length > 365 && (length % 100 == 0 || length % 365 == 0)
    }

    /// The milestone a streak reached by growing from `old` to `new`, or nil.
    ///
    /// `old` is the last length seen; nil means there is no baseline yet
    /// (the first fetch after launch), so nothing that happened while the
    /// app wasn't looking is celebrated. A streak that only held or broke
    /// reaches nothing. When it grew by more than a day between two looks,
    /// the largest milestone passed on the way counts, once.
    public static func reached(from old: Int?, to new: Int) -> Int? {
        guard let old, new > old else { return nil }
        return (max(old + 1, 1)...new).last(where: isMilestone)
    }
}
