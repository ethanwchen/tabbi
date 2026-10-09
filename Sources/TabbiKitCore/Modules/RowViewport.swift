import Foundation

/// How tall to draw a clipped list of equally tall rows, so it ends on a
/// whole row instead of showing a sliver of the next one. Today's checklist
/// uses it: the fade at its bottom edge then always lands on a full row,
/// which reads as "more below" rather than as a broken, half-cut row.
public enum RowViewport {
    /// The tallest height up to `available` that holds a whole number of
    /// rows. A space shorter than one row is returned unchanged, so a
    /// squeezed list still shows what it can instead of nothing.
    public static func height(fitting available: Double, rowHeight: Double) -> Double {
        guard rowHeight > 0, available >= rowHeight else { return max(available, 0) }
        return (available / rowHeight).rounded(.down) * rowHeight
    }
}
