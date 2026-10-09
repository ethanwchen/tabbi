import Foundation

/// Expression and effect art used by the animations: eye states stamped
/// over a face, the sleep "z", and the celebration heart. Effects use the
/// `effect` and `heart` roles and are painted after outlining, so they float
/// free of the pet instead of growing a border.
enum EffectArt {
    /// Eye states are 4x3, centered on a 2x3 open eye (one pixel of margin
    /// on each side), so they work for every face. A 3-wide eye keeps one
    /// pixel of margin on its cheek side.
    static let eyesClosed = SpriteGrid(art: """
        ....
        ....
        EEEE
        """)

    /// Content, sleepy curve.
    static let eyesSleepy = SpriteGrid(art: """
        ....
        E..E
        .EE.
        """)

    /// Squeezed shut, as in a yawn: a ">" that points at the nose (mirrored
    /// for the right eye).
    static let eyesSqueezed = SpriteGrid(art: """
        EE..
        ..EE
        EE..
        """)

    /// Happy "^" arches.
    static let eyesHappy = SpriteGrid(art: """
        .EE.
        E..E
        ....
        """)

    static let zSmall = SpriteGrid(art: """
        ZZZ
        ..Z
        .Z.
        ZZZ
        """)

    static let zLarge = SpriteGrid(art: """
        ZZZZ
        ...Z
        ..Z.
        .Z..
        ZZZZ
        """)

    static let heart = SpriteGrid(art: """
        .H.H.
        HHHHH
        HHHHH
        .HHH.
        ..H..
        """)

    static let sparkle = SpriteGrid(art: """
        .Z.
        ZZZ
        .Z.
        """)

    /// Dust kicked up beside the paws when a hop lands.
    static let dustLeft = SpriteGrid(art: """
        Z...
        ..Z.
        .ZZZ
        """)

    static let dustRight = SpriteGrid(art: """
        ...Z
        .Z..
        ZZZ.
        """)

    /// A small "o": the mouth starting (and ending) a yawn. Four wide and
    /// centered under the nose, so it covers any face's own mouth; the
    /// corners are muzzle fur, hiding mouth lines or a tongue drawn there.
    static let mouthOpen = SpriteGrid(art: """
        mRRm
        mPPm
        .mm.
        """)

    /// The yawn at its widest: a dark mouth with the tongue at the bottom.
    static let mouthWide = SpriteGrid(art: """
        mRRm
        ROOR
        RPPR
        mRRm
        """)

    /// The same two mouths for a face whose mouth hangs from the nose: a
    /// row of muzzle hides that line, then a shorter opening ends on the chin.
    static let mouthOpenBelowNose = SpriteGrid(art: """
        mmmm
        mRRm
        mPPm
        """)

    static let mouthWideBelowNose = SpriteGrid(art: """
        mmmm
        mRRm
        RPPR
        mRRm
        """)

    /// Where an open mouth goes on `face`: four pixels wide, centered on
    /// the nose's top row, on the first row below the nose. Found from the
    /// art, so new faces need no numbers. When a face draws its mouth line
    /// in the nose color right under the nose (most dogs), that row is
    /// painted over with muzzle and the mouth opens one row lower, so it
    /// never merges into a dark nose. Nil when closed or without a nose.
    static func mouth(_ mouth: PetPose.Mouth, in face: SpriteGrid) -> (grid: SpriteGrid, origin: PetPoint)? {
        guard mouth != .closed else { return nil }
        let isNose: (Int, Int) -> Bool = { face[$0, $1] == .role(.nose) }
        guard let top = (0..<face.height).first(where: { y in (0..<face.width).contains { isNose($0, y) } })
        else { return nil }
        let columns = (0..<face.width).filter { isNose($0, top) }
        let center = (columns[0] + columns[columns.count - 1] + 1) / 2
        var row = top + 1
        while row < face.height, isNose(center - 1, row) || isNose(center, row) { row += 1 }
        // A mouth line in the nose color right under the nose means the
        // mouth hangs from it: open below a row of muzzle, a little shorter
        // so it still ends on the chin.
        let hangs = row < face.height && (0..<face.width).contains { isNose($0, row) }
        let shape = switch (mouth, hangs) {
        case (.wide, false): mouthWide
        case (.wide, true): mouthWideBelowNose
        case (_, false): mouthOpen
        case (_, true): mouthOpenBelowNose
        }
        return (shape, PetPoint(x: center - 2, y: row))
    }

    /// A front leg reaching up to the top edge, paw first, for hanging out of
    /// the notch. Drawn behind the head, so only the upper part shows.
    static func hangingLeg(length: Int) -> SpriteGrid {
        var leg = SpriteGrid(width: 4, height: max(3, length))
        for y in 0..<leg.height {
            for x in 0..<leg.width {
                let isPaw = y < 2
                // Rounded paw tip: the toe row is one pixel narrower per side.
                if y == 0, x == 0 || x == 3 { continue }
                leg[x, y] = isPaw ? .zone(.paws) : (x == 0 || x == 3 ? .empty : .role(.furBase))
            }
        }
        return leg
    }

    /// `face` with its open eyes replaced by `eyes`. Open eyes are found as
    /// the eye-colored pixels on the face's `eyeRow`, so contributors only
    /// draw the open face. Cleared eye pixels become transparent, letting the
    /// head's fur (and any mask zone) show through.
    ///
    /// Asleep, the mouth closes too: a panting tongue (blush pixels below the
    /// cheek row, `eyeRow + 3`) is cleared, so the muzzle shows through and
    /// the nose-colored mouth corners read as a closed "w".
    static func face(_ face: SpriteGrid, eyeRow: Int, eyes: PetPose.Eyes) -> SpriteGrid {
        let overlay: SpriteGrid
        switch eyes {
        case .open: return face
        case .closed: overlay = eyesClosed
        case .sleepy: overlay = eyesSleepy
        case .happy: overlay = eyesHappy
        case .squeezed: overlay = eyesSqueezed
        }
        var result = face
        if eyes == .sleepy {
            for y in min(face.height, eyeRow + 4)..<face.height {
                for x in 0..<face.width where face[x, y] == .role(.blush) { result[x, y] = .empty }
            }
        }
        // A pupil drawn in the outline color is part of the eye it sits in.
        let isEye: (SpriteCell) -> Bool = {
            $0 == .role(.eye) || $0 == .role(.pupil) || $0 == .role(.eyeLight) || $0 == .role(.outline)
        }
        // Left edges of each eye on the eye row; most eyes are 2 wide, a few 3.
        let lefts = (0..<face.width).filter { x in
            isEye(face[x, eyeRow]) && (x == 0 || !isEye(face[x - 1, eyeRow]))
        }
        for left in lefts {
            let width = max(2, (left..<face.width).prefix { isEye(face[$0, eyeRow]) }.count)
            for y in eyeRow..<min(face.height, eyeRow + 3) {
                for x in left..<min(face.width, left + width) where isEye(face[x, y]) { result[x, y] = .empty }
            }
            // The overlay's spare pixel goes toward the cheek: left of a left
            // eye, right of a right eye.
            let isRightEye = left * 2 + width > face.width
            let start = isRightEye && width > 2 ? left : left - 1
            for y in 0..<overlay.height {
                for x in 0..<overlay.width where overlay[x, y] != .empty {
                    let fx = start + (isRightEye ? overlay.width - 1 - x : x), fy = eyeRow + y
                    if fx >= 0, fx < face.width, fy < face.height { result[fx, fy] = overlay[x, y] }
                }
            }
        }
        return result
    }
}
