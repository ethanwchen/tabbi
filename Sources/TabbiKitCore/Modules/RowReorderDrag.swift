import Foundation

/// A row being dragged through a list of equally tall rows, as the Settings
/// tab list draws it: the lifted row follows the pointer without leaving the
/// list, the rows it passes slide one slot toward the gap it left, and the
/// slot it would land in on release is the drop target.
///
/// Pure geometry, so the reordering rules are tested without a view.
public struct RowReorderDrag: Equatable, Sendable {
    /// The slot the row was picked up from.
    public let from: Int
    /// How many rows the list has.
    public let count: Int
    /// The height of one row, separators included.
    public let rowHeight: Double
    /// How far the pointer has moved since the drag began, positive downward,
    /// before clamping to the list.
    public var translation: Double

    public init(from: Int, count: Int, rowHeight: Double, translation: Double = 0) {
        self.from = from
        self.count = count
        self.rowHeight = rowHeight
        self.translation = translation
    }

    /// How far the lifted row is drawn from its slot: the pointer's travel,
    /// held inside the list so the row never slides past the first or last slot.
    public var liftedOffset: Double {
        let up = -Double(from) * rowHeight
        let down = Double(max(count - 1 - from, 0)) * rowHeight
        return min(max(translation, up), down)
    }

    /// The slot the row lands in on release: the one its center is over.
    public var target: Int {
        guard count > 0, rowHeight > 0 else { return from }
        return min(max(from + Int((liftedOffset / rowHeight).rounded()), 0), count - 1)
    }

    /// Whether releasing now changes the order.
    public var movesRow: Bool { target != from }

    /// How far the row in slot `index` is drawn from its slot: the lifted row
    /// follows the pointer, and the rows between its old and new slot shift
    /// one slot toward the gap.
    public func offset(at index: Int) -> Double {
        if index == from { return liftedOffset }
        if from < index, index <= target { return -rowHeight }
        if target <= index, index < from { return rowHeight }
        return 0
    }
}
