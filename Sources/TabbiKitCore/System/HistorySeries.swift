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

    /// One cubic Bezier piece of `monotoneCurve`, in plot units (x a slot,
    /// y a fraction).
    public struct CurveSegment: Equatable, Sendable {
        public struct Point: Equatable, Sendable {
            public var x: Double
            public var y: Double
        }

        public var control1: Point
        public var control2: Point
        public var end: Point
    }

    /// A smooth curve through every point that never overshoots them
    /// (monotone cubic interpolation, as d3's `curveMonotoneX`), so a
    /// sparkline stays inside `0...1` and shows no bump the data lacks.
    /// Starts at the first point; empty when there are fewer than two.
    ///
    /// The System panel draws it with a plain `Shape`: Swift Charts kept
    /// about 250 MB of graphics memory alive for three small sparklines.
    public var monotoneCurve: [CurveSegment] {
        guard points.count >= 2 else { return [] }
        let xs = points.map { Double($0.x) }
        let ys = points.map(\.y)
        let count = points.count
        var slopes = [Double](repeating: 0, count: count - 1)
        for i in 0..<(count - 1) {
            let width = xs[i + 1] - xs[i]
            slopes[i] = width == 0 ? 0 : (ys[i + 1] - ys[i]) / width
        }
        var tangents = [Double](repeating: 0, count: count)
        for i in 1..<(count - 1) {
            let before = xs[i] - xs[i - 1], after = xs[i + 1] - xs[i]
            let (s0, s1) = (slopes[i - 1], slopes[i])
            let blended = (s0 * after + s1 * before) / (before + after)
            let sameDirection = (s0 > 0 && s1 > 0) || (s0 < 0 && s1 < 0)
            tangents[i] = sameDirection
                ? (s0 > 0 ? 1 : -1) * min(abs(s0), abs(s1), 0.5 * abs(blended)) * 2
                : 0
        }
        // The ends follow the neighbouring tangent toward the end slope.
        tangents[0] = count == 2 ? slopes[0] : (3 * slopes[0] - tangents[1]) / 2
        tangents[count - 1] = count == 2 ? slopes[count - 2] : (3 * slopes[count - 2] - tangents[count - 2]) / 2
        return (0..<(count - 1)).map { i in
            let third = (xs[i + 1] - xs[i]) / 3
            return CurveSegment(
                control1: .init(x: xs[i] + third, y: ys[i] + third * tangents[i]),
                control2: .init(x: xs[i + 1] - third, y: ys[i + 1] - third * tangents[i + 1]),
                end: .init(x: xs[i + 1], y: ys[i + 1])
            )
        }
    }
}
