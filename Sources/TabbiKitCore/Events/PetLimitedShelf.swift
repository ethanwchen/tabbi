import Foundation

/// One shelf of the Closet's Limited section. Thirteen limited items do not
/// fit one row, so the section groups them: the event going on now (or the
/// next one) first, then the study milestones, then every other event's
/// items in the order their next runs start, so the list reads as the year
/// ahead.
public struct PetLimitedShelf: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The featured event: the run going on now, or the next to start.
        case event(SeasonalEventOccurrence, isActive: Bool)
        /// Limited items that are not seasonal: milestones and the launch week cap.
        case milestones
        /// The other events' items, which come back with their next run.
        case laterEvents
    }

    public var kind: Kind
    public var items: [PetItem]

    public init(kind: Kind, items: [PetItem]) {
        self.kind = kind
        self.items = items
    }
}

public extension SeasonalEventCatalog {
    /// The run the Limited section features at `date`: the one going on (the
    /// soonest to end when two overlap), or else the next to start.
    func featured(at date: Date, calendar: Calendar = .current) -> (occurrence: SeasonalEventOccurrence, isActive: Bool)? {
        if let active = active(at: date, calendar: calendar).first { return (active, true) }
        return next(after: date, calendar: calendar).map { ($0, false) }
    }

    /// The Limited section's shelves at `date`, each holding at least one
    /// item, and together every limited item once (`PetCloset.limitedShelf`).
    func limitedShelves(at date: Date, calendar: Calendar = .current) -> [PetLimitedShelf] {
        let featured = featured(at: date, calendar: calendar)
        let featuredItems = featured?.occurrence.event.rewards.map(\.item) ?? []
        let later = events
            .filter { $0.id != featured?.occurrence.event.id }
            .compactMap { event in
                (event.occurrence(containing: date, calendar: calendar)
                    ?? event.nextOccurrence(after: date, calendar: calendar)).map { (event, $0.start) }
            }
            .sorted { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
            .flatMap { $0.0.rewards.map(\.item) }
        let seasonal = Set(events.flatMap { $0.rewards.map(\.item) })
        let milestones = PetCloset.limitedShelf.filter { !seasonal.contains($0) }
        var shelves: [PetLimitedShelf] = []
        if let featured {
            shelves.append(PetLimitedShelf(kind: .event(featured.occurrence, isActive: featured.isActive),
                                           items: featuredItems))
        }
        shelves.append(PetLimitedShelf(kind: .milestones, items: milestones))
        shelves.append(PetLimitedShelf(kind: .laterEvents, items: later))
        return shelves.filter { !$0.items.isEmpty }
    }
}
