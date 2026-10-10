import Foundation

/// Decides which ticker item the closed notch shows.
///
/// A pinned item (an imminent or current meeting) always wins. Otherwise the
/// available items take turns, each held for `interval` seconds. The user
/// can also move on by hand (`advance`), which holds the chosen item for a
/// full turn, even over a pin, so a peek at the song during a meeting
/// countdown isn't snatched away at once. The state
/// is just "which kind, since when", and callers pass `now` explicitly, so
/// the rotation is deterministic and survives items appearing and vanishing
/// between ticks.
public struct TickerRotation: Equatable, Sendable {
    public var interval: TimeInterval
    /// Kind on screen after the last `update`, `nil` when the notch is plain.
    public private(set) var currentKind: TickerKind?
    /// When `currentKind` came on screen.
    public private(set) var shownSince: Date?
    /// The kinds of the last `update`'s items, in order, so that when the
    /// kind on screen vanishes its successor still takes over.
    private var order: [TickerKind] = []
    /// Until when an item the user cycled to holds the notch over a pin.
    private var heldUntil: Date?

    public init(interval: TimeInterval) {
        self.interval = max(interval, 1)
    }

    /// Advances the rotation to `now` and returns the item to show.
    ///
    /// The returned item carries fresh data (e.g. a countdown) even when the
    /// kind on screen hasn't changed.
    public mutating func update(items: [TickerItem], at now: Date) -> TickerItem? {
        let previousOrder = order
        order = items.map(\.kind)
        guard !items.isEmpty else {
            currentKind = nil
            shownSince = nil
            heldUntil = nil
            return nil
        }
        if let heldUntil, now < heldUntil, let currentKind,
           let held = items.first(where: { $0.kind == currentKind }) {
            return held
        }
        heldUntil = nil
        if let pinned = items.first(where: \.isPinned) {
            // Keep the original start so that once the pin lifts the
            // rotation moves on at once rather than holding a stale item.
            if currentKind != pinned.kind { show(pinned.kind, at: now) }
            return pinned
        }
        if let currentKind, let shownSince,
           let current = items.first(where: { $0.kind == currentKind }),
           now.timeIntervalSince(shownSince) < interval {
            return current
        }
        let next = nextItem(after: currentKind, in: items, previousOrder: previousOrder)
        show(next.kind, at: now)
        return next
    }

    /// Moves on to the item after the one on screen right away, as when the
    /// user swipes down or middle-clicks the closed notch, and returns it.
    ///
    /// The chosen item holds for a full `interval`, pinned or not, then the
    /// rotation (or a pin) carries on. With one item or none there is
    /// nothing to cycle to, and the item on screen stays.
    public mutating func advance(items: [TickerItem], at now: Date) -> TickerItem? {
        guard items.count > 1 else { return update(items: items, at: now) }
        let previousOrder = order
        order = items.map(\.kind)
        let next = nextItem(after: currentKind, in: items, previousOrder: previousOrder)
        show(next.kind, at: now)
        heldUntil = now.addingTimeInterval(interval)
        return next
    }

    private mutating func show(_ kind: TickerKind, at now: Date) {
        currentKind = kind
        shownSince = now
    }

    /// The first item whose kind comes after `kind` in rotation order,
    /// wrapping around. If `kind` itself vanished, the first kind that
    /// followed it last time and is still there takes over, so the order the
    /// user sees stays stable.
    private func nextItem(after kind: TickerKind?, in items: [TickerItem],
                          previousOrder: [TickerKind]) -> TickerItem {
        guard let kind else { return items[0] }
        if let position = items.firstIndex(where: { $0.kind == kind }) {
            return items[(position + 1) % items.count]
        }
        guard let position = previousOrder.firstIndex(of: kind) else { return items[0] }
        for candidate in previousOrder[(position + 1)...] {
            if let item = items.first(where: { $0.kind == candidate }) { return item }
        }
        return items[0]
    }
}
