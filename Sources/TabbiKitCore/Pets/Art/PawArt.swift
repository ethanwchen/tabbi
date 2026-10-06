import Foundation

/// A front leg lifted off the floor for the paw gestures (a wave, grooming).
/// Drawn in front of the sitting pet with its own outline, so it reads over
/// the head and chest of any breed, and anchored to the shoulder, so every
/// body shape uses the same art. The forearm is plain fur and the paw is
/// the paw zone, so white mittens and dark points follow the breed.
enum PawArt {
    /// The waving arm: index 0 leans out from the head, 1 swings back in
    /// beside the cheek. Column 8 of the bottom row is the shoulder; the
    /// forearm stays open there so it grows out of the body instead of
    /// being cut off by an outline.
    static let wave = [
        SpriteGrid(art: """
            .OOOO......
            OppppO.....
            OppppO.....
            OppppO.....
            .OBBBO.....
            ..OBBBO....
            ..OBBBO....
            ...OBBBO...
            ...OBBBO...
            ....OBBBO..
            ....OBBBO..
            .....OBBBO.
            ......OBBB.
            """),
        SpriteGrid(art: """
            ....OOOO...
            ...OppppO..
            ...OppppO..
            ...OppppO..
            ....OBBBO..
            ....OBBBO..
            ....OBBBO..
            .....OBBBO.
            .....OBBBO.
            .....OBBBO.
            .....OBBBO.
            ......OBBBO
            ......OBBB.
            """),
    ]

    /// The arm folded up in front of the chest with the paw at the top, for
    /// licking it and washing the face, `height` rows tall so it reaches
    /// down to the chest from wherever the paw is. The forearm ends open at
    /// the bottom, where it meets the chest.
    static func groom(height: Int) -> SpriteGrid {
        let paw = SpriteGrid(art: """
            .OOOO.
            OppppO
            OppppO
            """)
        var arm = SpriteGrid(width: paw.width, height: max(paw.height + 1, height))
        for y in 0..<arm.height {
            for x in 0..<arm.width {
                arm[x, y] = y < paw.height ? paw[x, y] : [.empty, .role(.outline), .role(.furBase)][min(x, 5 - x)]
            }
        }
        return arm
    }
}

extension PawArt {
    /// `body` with its left front paw lifted, so the pet doesn't show three
    /// front paws. The paw is the paw-zone shape touching the floor furthest
    /// left. On the floor row its whole run of pixels goes (with any cuff
    /// around it); above that, paw pixels tucked against fur become a fold
    /// of shaded fur and a leg standing free (a dachshund's) goes entirely.
    static func liftingLeftPaw(_ body: SpriteGrid) -> SpriteGrid {
        let bottom = body.height - 1
        let isPaw: (Int, Int) -> Bool = { body[$0, $1] == .zone(.paws) }
        guard let start = (0..<body.width / 2).first(where: { isPaw($0, bottom) }) else { return body }
        // Flood the paw shape from the floor.
        var paw: Set<[Int]> = [[start, bottom]]
        var queue = [[start, bottom]]
        while let cell = queue.popLast() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let x = cell[0] + dx, y = cell[1] + dy
                guard x >= 0, x < body.width, y >= 0, y < body.height, isPaw(x, y), !paw.contains([x, y]) else { continue }
                paw.insert([x, y])
                queue.append([x, y])
            }
        }
        var result = body
        let isFur: (Int, Int) -> Bool = { x, y in
            x >= 0 && x < body.width && body[x, y] != .empty && !paw.contains([x, y])
        }
        for cell in paw {
            let (x, y) = (cell[0], cell[1])
            result[x, y] = y < bottom && (isFur(x - 1, y) || isFur(x + 1, y)) ? .role(.furShade) : .empty
        }
        // The floor row loses the paw's whole run, cuffs included.
        var x = start
        while x > 0, body[x - 1, bottom] != .empty { x -= 1 }
        while x < body.width, body[x, bottom] != .empty {
            result[x, bottom] = .empty
            x += 1
        }
        return result
    }
}
