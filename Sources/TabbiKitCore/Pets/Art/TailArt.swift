import Foundation

/// The sitting tail bending out to the side for the tail swish. Every breed
/// keeps its own tail art (a whip, a ringed tail, a pom, a plume): the tail
/// is bent from its base, so no breed needs swish frames of its own.
enum TailArt {
    /// `body` cut in two at `column`: the body without the tail, and the tail
    /// alone on a grid of the same size, for tails drawn into the sitting
    /// body (cats, the dachshund).
    static func split(_ body: SpriteGrid, at column: Int) -> (body: SpriteGrid, tail: SpriteGrid) {
        var rest = body
        var tail = SpriteGrid(width: body.width, height: body.height)
        for y in 0..<body.height {
            for x in column..<body.width {
                tail[x, y] = body[x, y]
                rest[x, y] = .empty
            }
        }
        return (rest, tail)
    }

    /// `tail` bent `swing` pixels out to the right at its tip. The base row
    /// stays put and each row above leans a little further, never more than
    /// a pixel past the row below, so the tail stays one connected stroke.
    /// The grid grows by `swing` columns to make room. The swing is cut down
    /// so the tail stays within `room` columns of the grid's left edge (the
    /// dachshund's tail already sits near the edge of the frame).
    static func swung(_ tail: SpriteGrid, by swing: Int, room: Int) -> SpriteGrid {
        let rows = (0..<tail.height).filter { y in (0..<tail.width).contains { tail[$0, y] != .empty } }
        let right = (0..<tail.width).last { x in (0..<tail.height).contains { tail[x, $0] != .empty } } ?? 0
        let swing = min(swing, room - 1 - right)
        guard swing > 0, let top = rows.first, let base = rows.last, base > top else { return tail }
        var bent = SpriteGrid(width: tail.width + swing, height: tail.height)
        for y in 0..<tail.height {
            let lean = Double(swing * (base - y)) / Double(base - top)
            let shift = min(max(Int(lean.rounded()), 0), base - y)
            for x in 0..<tail.width where tail[x, y] != .empty { bent[x + shift, y] = tail[x, y] }
        }
        return bent
    }

    /// A stub tail peeking out by the haunch for breeds without a tail (a
    /// corgi, a French bulldog), which wiggle it instead of swishing.
    static let nub = SpriteGrid(art: """
        tt
        BB
        """)
}
