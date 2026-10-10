import Foundation

public extension RecapArchive {
    /// Sample recaps for demo mode: the last few weeks ending at the newest
    /// ready week, which is the best one yet and not seen, so the notch shows
    /// its card once. One light week sits among them so the list shows how a
    /// quieter week reads too.
    static func demo(now: Date, calendar: Calendar = .current) -> RecapArchive {
        let newest = RecapWeek.latestReady(at: now, calendar: calendar)
        // Minutes per day, Monday first, oldest week first.
        let weeks: [(minutes: [Int], cards: Int, tasks: Int)] = [
            ([50, 75, 0, 100, 25, 0, 50], 140, 9),
            ([25, 0, 0, 25, 0, 0, 0], 30, 3),
            ([75, 100, 50, 125, 75, 25, 0], 210, 12),
            ([100, 125, 75, 150, 100, 50, 75], 320, 17),
        ]
        let recaps = weeks.enumerated().map { offset, sample in
            let minutes = sample.minutes
            var streak = 0
            var run = 0
            for value in minutes {
                run = WeeklyRecap.isActive(minutes: value, cards: 0, tasks: 0) ? run + 1 : 0
                streak = max(streak, run)
            }
            let total = minutes.reduce(0, +)
            return WeeklyRecap(
                week: newest.adding(weeks: offset - (weeks.count - 1), calendar: calendar),
                minutesByDay: minutes,
                sessions: total / 25,
                cardsReviewed: sample.cards,
                tasksDone: sample.tasks,
                points: PetPointsRules.points(forMinutes: total, completed: true),
                longestStreak: streak
            )
        }
        return RecapArchive(recaps: recaps, settledWeek: newest,
                            seenWeek: newest.adding(weeks: -1, calendar: calendar))
    }
}
