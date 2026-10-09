import Foundation

/// Small props a sitting pet holds for the study moments: a tiny laptop
/// (focusing) and a coffee mug (breaks), plus its toys (yarn and a ball). Props are drawn in front of the
/// pet with their own outline, so they read against fur of any color, and
/// the paws holding them are drawn with the prop, so every body shape uses
/// the same art.
/// The grids are drawn in `Pets/PetArt/prop.json`.
enum PropArt {
    /// The back of a laptop lid, seen from the front: the pet types behind
    /// it. A heart sticker makes it read as a laptop and not a box.
    static let laptop = PetArt.prop.grid("laptop")

    /// A front paw resting over the laptop's top edge (or lifted to tap),
    /// outlined all round so it reads against the lid and the chest.
    static let paw = PetArt.prop.grid("paw")

    /// A mug with its handle on the right; the paws on each side hold it.
    static let mug = PetArt.prop.grid("mug")

    /// A paw wrapped around the side of the mug.
    static let mugPaw = PetArt.prop.grid("mugPaw")

    /// Two wisps of steam that take turns rising from the coffee. They
    /// curl over the chest, so they are drawn as line art in the mouth
    /// role, which turns dark on light fur and light on dark fur.
    static let steam = PetArt.prop.sequence("steam")

    /// A ball of yarn in the cozy knit color, wound in curved strands. The
    /// two grids mirror the winding, so alternating them as it moves makes
    /// it read as rolling.
    static let yarn = PetArt.prop.sequence("yarn")

    /// A red rubber ball with a gold band and a shine on the upper left (the
    /// light stays put while the band turns as it rolls).
    static let ball = PetArt.prop.sequence("ball")
}
