/// Plot-ready view of a metric history for the System panel's sparklines.
///
/// Points are right-aligned on a fixed `capacity`-wide x axis, so a history
/// that is still filling up grows in from the right edge instead of
/// stretching across the whole chart and then jumping as samples arrive.
public struct HistorySeries: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        /// Slot on the x axis, `0..<capacity`; the newest sample sits at `capacity - 1`.
        public var x: Int
        /// Value clamped to `0...1`.
        public var y: Double
    }

    public let capacity: Int
    public let points: [Point]

    /// Keeps the newest `capacity` finite values; non-finite samples are dropped.
    public init(_ values: [Double], capacity: Int) {
        precondition(capacity > 0, "HistorySeries capacity must be positive")
        self.capacity = capacity
        let finite = values.filter(\.isFinite).suffix(capacity)
        let offset = capacity - finite.count
        points = finite.enumerated().map { index, value in
            Point(x: offset + index, y: min(max(value, 0), 1))
        }
    }

    public var isEmpty: Bool { points.isEmpty }

    /// Highest value in the window, or `nil` when empty.
    public var peak: Double? { points.map(\.y).max() }

    /// Mean value in the window, or `nil` when empty.
    public var average: Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.y } / Double(points.count)
    }
}
