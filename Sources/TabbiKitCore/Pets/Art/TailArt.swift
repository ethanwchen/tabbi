import Foundation

/// The sitting tail bending out to the side for the tail swish. Every breed
/// keeps its own tail art (a whip, a ringed tail, a pom, a plume): the tail
/// is bent from its base, so no breed needs swish frames of its own.
/// The grids are drawn in `Pets/PetArt/tail.json`.
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
    static let nub = PetArt.tail.grid("nub")

    /// A tail wrapped round a curled-up pet, `length` wide: it comes from
    /// under the rump on the right and runs along the floor in front of the
    /// body, its tip curling up on the left. It has no outline of its own;
    /// the composer outlines it on its own layer so it stands apart from
    /// fur of the same color behind it.
    static func wrapped(length: Int) -> SpriteGrid {
        let length = max(length, 8)
        var grid = SpriteGrid(width: length, height: 3)
        for x in 0..<length {
            // Faint rings every few pixels; plain fur on unstriped breeds.
            let fur: SpriteCell = x > 3 && x % 4 == 1 ? .zone(.stripes) : .role(.furBase)
            if x >= 3, x < length - 2 { grid[x, 1] = fur }
            if x >= 2 { grid[x, 2] = x < 3 ? .zone(.tailTip) : fur }
        }
        // The tip curls up in front of the chin.
        for (x, y) in [(1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (1, 2)] { grid[x, y] = .zone(.tailTip) }
        return grid
    }
}
