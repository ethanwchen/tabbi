import Foundation

/// Walking art: a side-on torso with the usual front-facing head in front of
/// it, the chibi style that keeps the face (and every hat) readable at notch
/// size. Pets walk toward the left; mirror the frame to walk right. Legs are
/// generated so every body family steps with the same gait. See
/// docs/study/pets.md.
enum WalkArt {
    /// Cat torso, 22x7, stamped at `torsoOrigin`. The front half hides behind
    /// the head; stripes run over the back and the rump stays round. Zones `a` and `b` are
    /// the calico's orange and black patches.
    static let catTorso = SpriteGrid(art: """
        ...BBBBBBBBBBBsbbsBB..
        ..BBBBBBBBBBBBBsbbsBB.
        .BBBBBBBBBBBBaaBBBBsBB
        .BBBBBBBBBBBaaaaBBBBBB
        .cBBBBBBBBBBBaaBBBBBBB
        .cccBBBBBBBBBBBBBBBBBS
        ..ccSSSSSSSSSSSSSSSSS.
        """)

    /// Dog torso, the same size as the cat's. Zone `a` is the beagle saddle.
    static let dogTorso = SpriteGrid(art: """
        ...BBBBBBBBBBaaaaaBB..
        ..BBBBBBBBBBaaaaaaaBB.
        .BBBBBBBBBBBaaaaaaaBBB
        .BBBBBBBBBBBBaaaaaBBBB
        .cBBBBBBBBBBBBBBBBBBBB
        .cccBBBBBBBBBBBBBBBBBS
        ..ccSSSSSSSSSSSSSSSSS.
        """)

    /// Dachshund torso, 23x6: longer and lower, on short legs.
    static let longTorso = SpriteGrid(art: """
        ...BBBBBBBBBBBBBBBBBB..
        ..BBBBBBBBBBBBBBBBBBBB.
        .ccBBBBBBBBBBBBBBBBBBBB
        .cccBBBBBBBBBBBBBBBBBBB
        .ccccBBBBBBBBBBBBBBBBBS
        ..SSSSSSSSSSSSSSSSSSSS.
        """)

    /// The cat's tail held high, swaying a pixel between steps.
    static let catTail = [
        SpriteGrid(art: """
            .tt
            .tt
            .BB
            BB.
            BB.
            BB.
            """),
        SpriteGrid(art: """
            ..tt
            .tt.
            .BB.
            BB..
            BB..
            BB..
            """),
    ]

    /// British Shorthair torso: the cat torso with a silver, faintly ticked
    /// back over pale sides.
    static let roundCatTorso = SpriteGrid(art: """
        ...SSSSSsSSSSSSsSSSS..
        ..SSSSsSSSSSsSSSSSsSS.
        .BBBBBBBBBBBBBBBBBBSSS
        .BBBBBBBBBBBBBBBBBBBBS
        .cBBBBBBBBBBBBBBBBBBBS
        .cccBBBBBBBBBBBBBBBBBS
        ..ccSSSSSSSSSSSSSSSSS.
        """)

    /// The British Shorthair's thick tail, with subtle pale taupe rings.
    static let roundCatTail = [
        SpriteGrid(art: """
            .tt
            .SS
            .tt
            SS.
            tt.
            SS.
            """),
        SpriteGrid(art: """
            ..tt
            .SS.
            .tt.
            SS..
            tt..
            SS..
            """),
    ]

    /// Sphynx torso: lean, with wrinkle lines over the shoulders and a
    /// slim belly line.
    static let sphynxTorso = SpriteGrid(art: """
        ...BBBBBBBBBBBBBBBBB..
        ..BBBSBBSBBBBBBBBBBBB.
        .BBBSBBSBBBBBBBBBBBBBB
        .BBBBBBBBBBBBBBBBBBBBB
        .cBBBBBBBBBBBBBBBBBBBS
        .cccBBBBBBBBBBBBBBBBSS
        ..ccSSSSSSSSSSSSSSSS..
        """)

    /// The Sphynx's thin whip tail, held high with a curled tip.
    static let sphynxTail = [
        SpriteGrid(art: """
            .tt
            ..t
            .B.
            .B.
            B..
            B..
            """),
        SpriteGrid(art: """
            .tt.
            .t..
            .B..
            .B..
            B...
            B...
            """),
    ]

    /// The Scottish Fold's thick plush tail, held high with a shaded tip.
    static let foldCatTail = [
        SpriteGrid(art: """
            .tt
            .BB
            .BB
            BB.
            BB.
            BB.
            """),
        SpriteGrid(art: """
            ..tt
            .BB.
            .BB.
            BB..
            BB..
            BB..
            """),
    ]

    /// Poodle torso: the dog torso covered in curls, with a fluffy chest.
    static let poodleTorso = SpriteGrid(art: """
        ...BBSBBBSBBBBSBBBSB..
        ..BSBBBABBBSBBBABBBSB.
        .ABBBSBBBSBBBSBBBSBBBB
        .cABBBBSBBBBBBSBBBBSBB
        .ccBSBBBBBSBBBBBBSBBBB
        .cccBBBSBBBBBSBBBBBBBS
        ..ccSSSSSSSSSSSSSSSSS.
        """)

    /// The poodle's pom tail, held high and bobbing between steps.
    static let poodleTail = [
        SpriteGrid(art: """
            .tt.
            tAtt
            tttt
            .tt.
            .B..
            BB..
            """),
        SpriteGrid(art: """
            ..tt
            .tAt
            .ttt
            ..tt
            .B..
            BB..
            """),
    ]

    /// Shih Tzu torso: a long coat that hangs in strands, with a fringe that
    /// leaves the legs half hidden.
    static let shihTzuTorso = SpriteGrid(art: """
        ...BBBBBBBBBBBBBBBBB..
        ..BBBBBBBBBBBBBBBBBBB.
        .cBBBBBBBBBBBBBBBBBBBB
        .ccBBSBBBBSBBBBSBBBBSB
        .ccBSBBBSBBBBSBBBBSBBB
        .cBSBBBSBBBBSBBBBSBBSB
        ..SB.SB.SBSB.SBS.BSBS.
        """)

    /// The Shih Tzu's plume, curled over the back and swaying between steps.
    static let shihTzuTail = [
        SpriteGrid(art: """
            .ttt.
            tttA.
            tAt..
            .B...
            BB...
            """),
        SpriteGrid(art: """
            ..ttt
            .tttA
            .tAt.
            .B...
            BB...
            """),
    ]

    static let dogTail = [
        SpriteGrid(art: """
            ..t
            .tt
            .B.
            BB.
            """),
        SpriteGrid(art: """
            ...t
            ..tt
            .BB.
            BB..
            """),
    ]

    static let longTail = [
        SpriteGrid(art: """
            ..t
            .t.
            B..
            """),
        SpriteGrid(art: """
            ...
            .tt
            B..
            """),
    ]

    /// Where a leg's paw lands relative to its hip.
    enum Lean {
        case under
        /// Reaching ahead (left, the walking direction).
        case forward
        /// Pushing off behind.
        case back
    }

    /// One leg, `height` rows tall and 3 wide, paw on the bottom row. Far
    /// legs are shaded so the near and far leg of a pair stay apart without
    /// an outline between them.
    static func leg(height: Int, lean: Lean, far: Bool) -> SpriteGrid {
        var grid = SpriteGrid(width: 3, height: height)
        let fur: SpriteCell = far ? .role(.furShade) : .role(.furBase)
        for y in 0..<height {
            // The hip stays put; the lower half swings to the lean.
            let lower = y >= height / 2
            let left = switch lean {
            case .under: 0
            case .forward: lower ? 0 : 1
            case .back: lower ? 1 : 0
            }
            let cell: SpriteCell = y == height - 1 ? .zone(.paws) : fur
            grid[left, y] = cell
            grid[left + 1, y] = cell
        }
        return grid
    }

    /// A front leg reaching forward along the ground for the stretch: the
    /// hip column drops `height` rows and the forearm lies flat for `reach`
    /// more pixels toward the left, paw first. With no reach it is a plain
    /// standing leg.
    static func reachingLeg(height: Int, reach: Int, far: Bool) -> SpriteGrid {
        var grid = SpriteGrid(width: reach + 2, height: height)
        let fur: SpriteCell = far ? .role(.furShade) : .role(.furBase)
        for y in 0..<height {
            // The bottom two rows are the forearm resting on the ground.
            let lying = reach > 0 && y >= height - 2
            for x in (lying ? 0 : reach)..<(reach + 2) {
                grid[x, y] = fur
            }
        }
        // The paw is the leading tip of the bottom row.
        grid[0, height - 1] = .zone(.paws)
        grid[1, height - 1] = .zone(.paws)
        return grid
    }

    /// One step of the gait: the lean of the near front, far front, near
    /// back, and far back leg. Diagonal pairs move together, like a real trot.
    struct Step {
        let nearFront: Lean
        let farFront: Lean
        let nearBack: Lean
        let farBack: Lean
        /// Contact steps sit a pixel lower than passing steps.
        let isContact: Bool
    }

    static let cycle: [Step] = [
        Step(nearFront: .forward, farFront: .back, nearBack: .back, farBack: .forward, isContact: true),
        Step(nearFront: .under, farFront: .under, nearBack: .under, farBack: .under, isContact: false),
        Step(nearFront: .back, farFront: .forward, nearBack: .forward, farBack: .back, isContact: true),
        Step(nearFront: .under, farFront: .under, nearBack: .under, farBack: .under, isContact: false),
    ]
}
