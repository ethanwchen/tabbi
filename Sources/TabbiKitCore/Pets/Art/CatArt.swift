import Foundation

/// Hand-drawn cat art shared by every cat breed. See docs/study/pets.md
/// for the symbol legend. Outer outlines are added automatically.
/// The grids are drawn in `Pets/PetArt/cat.json`.
enum CatArt {
    static let head = PetArt.cat.grid("head")

    /// British Shorthair: small rounded ears set wide, a faint silver crown
    /// with subtle ticking, and full round cheeks around a white muzzle and chin.
    static let headRound = PetArt.cat.grid("headRound")

    /// British Shorthair face: the shared cat eyes (2x3, a highlight in the
    /// top corner) in blue and the shared nose and "w" mouth, with
    /// rosy cheeks.
    static let faceRound = PetArt.cat.grid("faceRound")

    static let faceOpen = PetArt.cat.grid("faceOpen")

    static let bodySit = PetArt.cat.grid("bodySit")

    /// British Shorthair sitting body: the `bodySit` frame (so every costume
    /// fits) widened a column to the right for a plump, round belly that sits
    /// centered under the head, with faint ticking on the flanks, a white
    /// chest and paws, and a thick ringed tail split off at column 18.
    static let bodyRound = PetArt.cat.grid("bodyRound")

    /// Sphynx: big bat-like ears flaring out from a narrow crown, two soft
    /// forehead wrinkles drawn as short shade lines, sharp cheekbones, and a narrow
    /// muzzle. Hairless, so there is no ear tuft or stripe zone.
    static let headSphynx = PetArt.cat.grid("headSphynx")

    /// Sphynx face: big 3x3 lemon eyes with a round, friendly pupil under a
    /// highlight, a small nose over a "w" mouth, and rosy cheeks.
    static let faceSphynx = PetArt.cat.grid("faceSphynx")

    /// Sphynx sitting body, the same 20x11 frame as `bodySit` so every
    /// costume fits: a lean chest with one soft wrinkle at the neck, bony haunches,
    /// and a thin whip tail curling up.
    static let bodySphynx = PetArt.cat.grid("bodySphynx")

    /// Scottish Fold: a round owl-like head with small ears folded forward
    /// and down over the crown (a shade crease under each flap), wide full
    /// cheeks, and a pale muzzle. It wears the shared cat face.
    static let headFold = PetArt.cat.grid("headFold")

    /// Scottish Fold sitting body: as plump as the British Shorthair's (the
    /// same 21-wide frame, centered under the head, so every costume fits)
    /// in a plain plush coat with a pale chest and a thick tail split off
    /// at column 18.
    static let bodyFold = PetArt.cat.grid("bodyFold")
}
