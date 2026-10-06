import Foundation

/// Small props a sitting pet holds for the study moments: a tiny laptop
/// (focusing) and a coffee mug (breaks), plus its toys (yarn and a ball). Props are drawn in front of the
/// pet with their own outline, so they read against fur of any color, and
/// the paws holding them are drawn with the prop, so every body shape uses
/// the same art.
enum PropArt {
    /// The back of a laptop lid, seen from the front: the pet types behind
    /// it. A heart sticker makes it read as a laptop and not a box.
    static let laptop = SpriteGrid(art: """
        .OOOOOOOOOOOO.
        OMMMMMMMMMMMMO
        OMMMMMMMMMMMMO
        OMMMMMHHMMMMMO
        OMMMMMMMMMMMMO
        OVVVVVVVVVVVVO
        OOOOOOOOOOOOOO
        """)

    /// A front paw resting over the laptop's top edge (or lifted to tap),
    /// outlined all round so it reads against the lid and the chest.
    static let paw = SpriteGrid(art: """
        .OOOO.
        OppppO
        OppppO
        .OOOO.
        """)

    /// A mug with its handle on the right; the paws on each side hold it.
    static let mug = SpriteGrid(art: """
        OOOOO..
        OGGGOOO
        OGGGO.O
        OGGGOOO
        OJJJO..
        .OOO...
        """)

    /// A paw wrapped around the side of the mug.
    static let mugPaw = SpriteGrid(art: """
        .OO.
        OppO
        OppO
        .OO.
        """)

    /// Two wisps of steam that take turns rising from the coffee. They
    /// curl over the chest, so they are drawn as line art in the mouth
    /// role, which turns dark on light fur and light on dark fur.
    static let steam = [
        SpriteGrid(art: """
            .R.
            R..
            .R.
            """),
        SpriteGrid(art: """
            R..
            .R.
            ..R
            """),
    ]

    /// A ball of yarn in the cozy knit color, wound in curved strands. The
    /// two grids mirror the winding, so alternating them as it moves makes
    /// it read as rolling.
    static let yarn = [
        SpriteGrid(art: """
            ..OOO..
            .OGJGO.
            OGJGGJO
            OJGGJGO
            OGGJGGO
            .OJGGO.
            ..OOO..
            """),
        SpriteGrid(art: """
            ..OOO..
            .OGJGO.
            OJGGJGO
            OGJGGJO
            OGGJGGO
            .OGGJO.
            ..OOO..
            """),
    ]

    /// A red rubber ball with a gold band and a shine on the upper left (the
    /// light stays put while the band turns as it rolls).
    static let ball = [
        SpriteGrid(art: """
            ..OOO..
            .OZHHO.
            OZHHHHO
            OYYYYYO
            OHHHHHO
            .OHHHO.
            ..OOO..
            """),
        SpriteGrid(art: """
            ..OOO..
            .OZYHO.
            OZHYHHO
            OHHYHHO
            OHHYHHO
            .OHYHO.
            ..OOO..
            """),
    ]
}
