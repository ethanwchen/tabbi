import Foundation

/// The `TABBI_DEMO=1` season. A demo should show an event going on, with
/// progress toward its first item, whatever the real date is, so it pins
/// the Closet's seasonal clock to a moment in the featured run (the one
/// going on, or else the next) and logs two focus sessions in that run.
public struct SeasonalEventDemo: Sendable {
    /// Noon on the third day of the featured run.
    public let moment: Date
    /// An hour of focus logged on the run's second and third mornings.
    public let tally: SeasonalEventTally

    public init?(today: Date, catalog: SeasonalEventCatalog = .bundled, calendar: Calendar = .current) {
        guard let run = catalog.featured(at: today, calendar: calendar)?.occurrence,
              let moment = calendar.date(byAdding: DateComponents(day: 2, hour: 12), to: run.start),
              run.contains(moment) else { return nil }
        func session(day: Int, minutes: Double) -> ActivityRecord? {
            guard let end = calendar.date(byAdding: DateComponents(day: day, hour: 10), to: run.start) else { return nil }
            return ActivityRecord(source: "focus", kind: .focusCompleted, start: end.addingTimeInterval(-minutes * 60),
                                  end: end, quantity: minutes, unit: .minutes)
        }
        self.moment = moment
        tally = SeasonalEventTally(catalog: catalog, calendar: calendar,
                                   records: [session(day: 1, minutes: 35), session(day: 2, minutes: 25)].compactMap { $0 })
    }
}
