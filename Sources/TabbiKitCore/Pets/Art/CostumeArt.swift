import Foundation

/// Hand-drawn costume art. Body items (outfits, neck items) have one grid per
/// body family, the same size as and stamped at the same origin as that
/// family's body. Head items are 20 wide like every head and are placed by
/// the composer on each head's skull top. See docs/study/pets.md.
/// The grids are drawn in `Pets/PetArt/costume.json`.
enum CostumeArt {
    /// A grid drawn for each body family.
    struct BodyItem {
        let cat: SpriteGrid
        let dog: SpriteGrid
        let longDog: SpriteGrid
        /// Over the cat and dog walking torso (`WalkArt.catTorso`).
        let walk: SpriteGrid
        /// Over the dachshund walking torso (`WalkArt.longTorso`).
        let walkLong: SpriteGrid
        /// Rows every grid reaches above its body's top row, for parts that
        /// stick up out of the silhouette, such as spikes along the back.
        var rise = 0
        /// The rest of an animated item's loop: these grids are the still
        /// frame, shown under Reduce Motion, and the loop's first.
        var moreFrames: [BodyItem] = []

        /// Frames in the item's loop; 1 for an item that stays still.
        var frameCount: Int { 1 + moreFrames.count }

        /// The item as drawn on frame `phase` of the item clock.
        func frame(_ phase: Int) -> BodyItem {
            let index = phase % frameCount
            return index == 0 ? self : moreFrames[index - 1]
        }
    }

    /// A face item, one grid for cat faces and one for dog faces, and the
    /// grid row that lands on the head's eye row.
    struct FaceItem {
        let cat: SpriteGrid
        let dog: SpriteGrid
        let eyeRow: Int
        /// The rest of an animated item's loop: these grids are the still
        /// frame, shown under Reduce Motion, and the loop's first.
        var moreFrames: [FaceItem] = []

        /// Frames in the item's loop; 1 for an item that stays still.
        var frameCount: Int { 1 + moreFrames.count }

        /// The item as drawn on frame `phase` of the item clock.
        func frame(_ phase: Int) -> FaceItem {
            let index = phase % frameCount
            return index == 0 ? self : moreFrames[index - 1]
        }
    }

    /// A hat-like item and the grid row that lands on the head's skull top.
    struct HeadItem {
        /// The still frame, shown under Reduce Motion, and the loop's first.
        let grid: SpriteGrid
        let sitRow: Int
        /// The rest of an animated item's loop, each the size of `grid`.
        var moreFrames: [SpriteGrid] = []

        /// Frames in the item's loop; 1 for an item that stays still.
        var frameCount: Int { 1 + moreFrames.count }

        /// The grid drawn on frame `phase` of the item clock.
        func grid(_ phase: Int) -> SpriteGrid {
            let index = phase % frameCount
            return index == 0 ? grid : moreFrames[index - 1]
        }
    }

    /// An item worn behind the pet, such as wings: drawn and outlined on a
    /// layer of its own under the outlined pet, so the pet's outline keeps
    /// it apart from the fur and it may reach out past the body.
    struct BackItem {
        /// Where the item goes for one body family: its loop of grids, the
        /// first the still, and the offset of their top-left corner from
        /// the family's body origin (the walking torso's when walking).
        struct Placement {
            let x: Int
            let y: Int
            let frames: [SpriteGrid]
        }

        let cat: Placement
        let dog: Placement
        let longDog: Placement
        /// Behind the cat and dog walking torso (`WalkArt.catTorso`).
        let walk: Placement
        /// Behind the dachshund walking torso (`WalkArt.longTorso`).
        let walkLong: Placement

        /// Frames in the item's loop, the same for every body family.
        var frameCount: Int { cat.frames.count }
    }

    /// An item that floats in the air around the pet, such as falling
    /// petals: loose particles drawn in front of the pet without an
    /// outline. A particle that would touch the pet or an effect is left
    /// out of that frame, so nothing ever covers the pet or looks cut.
    struct AuraItem {
        /// Around a pet facing the viewer, offset from the frame's corner.
        let front: BackItem.Placement
        /// Around a pet seen from the side (walking, stretching, curled up).
        let side: BackItem.Placement
        /// Around the dachshund sitting side-on, its head where other pets
        /// leave air; the front loop unless the item needs its own.
        let longDog: BackItem.Placement

        /// Frames in the item's loop, the same for both views.
        var frameCount: Int { front.frames.count }
    }

    // MARK: Outfits

    static let scrubs = PetArt.costume.bodyItem("scrubs")

    static let whiteCoat = PetArt.costume.bodyItem("whiteCoat")

    // MARK: Neck

    static let stethoscope = PetArt.costume.bodyItem("stethoscope")

    static let scarf = PetArt.costume.bodyItem("scarf")

    // MARK: Face

    /// Round glasses ringing the eyes. Dark frames read on every fur color
    /// except the darkest, where the warm rim still frames the face. The dog
    /// lenses are wider than the closer-set eyes so the frames never touch
    /// the pupils and blur into them.
    static let roundGlasses = PetArt.costume.faceItem("roundGlasses")

    // MARK: Head

    static let surgicalCap = PetArt.costume.headItem("surgicalCap")

    static let beanie = PetArt.costume.headItem("beanie")

    static let graduationCap = PetArt.costume.headItem("graduationCap")

    static let headMirror = PetArt.costume.headItem("headMirror")
}

// MARK: - Fun head items

extension CostumeArt {
    /// A small gold crown on a navy band, so the gold never melts into
    /// orange or golden fur.
    static let tinyCrown = PetArt.costume.headItem("tinyCrown")

    /// A polka-dot party cone with a red pom-pom and a gold trim that
    /// sits one row into the forehead, which gives the cone its height.
    static let partyHat = PetArt.costume.headItem("partyHat")

    /// A puffy chef's toque, wider at the top, on a band.
    static let chefHat = PetArt.costume.headItem("chefHat")

    /// A starry wizard cone whose tip flops to the side, on a wide brim
    /// pulled one row down over the brow.
    static let wizardHat = PetArt.costume.headItem("wizardHat")

    /// Tall white bunny ears with pink insides on a knit headband.
    static let bunnyEars = PetArt.costume.headItem("bunnyEars")
}

// MARK: - Fun head items, second set

extension CostumeArt {
    /// A pointed witch hat with a crooked tip, a red band with a gold
    /// buckle, and a flat brim. Straighter and plainer than the wizard hat,
    /// so the two read apart.
    static let witchHat = PetArt.costume.headItem("witchHat")

    /// A leather cowboy hat: a dented crown on a navy band and a wide brim
    /// that curls up at both ends.
    static let cowboyHat = PetArt.costume.headItem("cowboyHat")

    /// Three little flowers on a leafy vine laid across the crown.
    static let flowerCrown = PetArt.costume.headItem("flowerCrown")

    /// A green frog hood with two bulging eyes on top and a wide smile
    /// across the forehead.
    static let frogHat = PetArt.costume.headItem("frogHat")

    /// A navy headband with a metal plate, tied at the side so the two
    /// tails hang past the ear.
    static let ninjaHeadband = PetArt.costume.headItem("ninjaHeadband")
}

// MARK: - Fun face and mask items

extension CostumeArt {
    /// Wide dark shades with a white glint on each lens. The lenses cover
    /// the eyes completely, which is the whole joke.
    static let coolSunglasses = PetArt.costume.faceItem("coolSunglasses")

    /// A navy tricorn with upturned sides, a white skull badge, and gold
    /// trim along the brim.
    static let pirateHat = PetArt.costume.headItem("pirateHat")

    /// An eyepatch over the right eye, its strap running up under the hat.
    static let eyepatch = PetArt.costume.faceItem("eyepatch")

    /// Spiky white hair standing straight up, shaded on one side of each
    /// spike, with a fringe that falls onto the blindfold.
    static let spikyHair = PetArt.costume.headItem("spikyHair")

    /// A dark blindfold tied over both eyes, open under the nose bridge.
    static let blindfold = PetArt.costume.faceItem("blindfold")
}

// MARK: - Fun head and neck items, third set

extension CostumeArt {
    /// A white space helmet with its dark visor flipped up over the brow
    /// (a glint shows it is glass), an antenna with a red light, a metal
    /// collar ring, and side pods over the ears, so it reads as a helmet
    /// rather than a cap. A gold visor read as a hard hat.
    static let astronautHelmet = PetArt.costume.headItem("astronautHelmet")

    /// Chunky over-ear headphones: a red band over the crown and big
    /// red cups with metal grilles over the ears. The band matches the
    /// cups so it stays readable on dark fur, where navy disappeared.
    static let chunkyHeadphones = PetArt.costume.headItem("chunkyHeadphones")

    /// A red bow tie under the chin with a darker knot.
    static let bowTie = PetArt.costume.bodyItem("bowTie")
}

// MARK: - Fun outfits

extension CostumeArt {
    /// A zip-up hoodie in the knit color with the hood bunched at the collar,
    /// a metal zipper, a kangaroo pocket, and the hood lying on the back when
    /// seen from the side. White drawstrings read as a face from the front.
    static let cozyHoodie = PetArt.costume.bodyItem("cozyHoodie")

    /// A red cape fastened with a gold clasp at the collar. From the front it
    /// drapes over the shoulders and falls past both sides of the body, its
    /// crimson lining showing. Walking, it streams up and back from the
    /// collar over the tail like a cape in the wind, since a cloth lying on
    /// the short visible back reads as a saddle or a tuft at notch size.
    static let superheroCape = PetArt.costume.bodyItem("superheroCape")

    /// A green dinosaur suit with a gold belly and gold spikes down the back.
    /// Its hood is `dinosaurHood`.
    static let dinosaurHoodie = PetArt.costume.bodyItem("dinosaurHoodie")

    /// A starry navy robe to match the wizard hat, with gold trim down the
    /// front and a gold hem that flares a little above the paws.
    static let wizardRobe = PetArt.costume.bodyItem("wizardRobe")

    /// The dinosaur hood: gold spikes along the crown, little white teeth
    /// along the brim, and sides that frame the face, so it reads as a hood.
    static let dinosaurHood = PetArt.costume.headItem("dinosaurHood")
}

// MARK: - Limited edition items

extension CostumeArt {
    /// A crimson baseball cap turned backwards: the strap opening shows
    /// over the brow with a metal snap, and the brim hides behind the head.
    static let backwardsCap = PetArt.costume.headItem("backwardsCap")

    /// A crimson headband with a small gold and red flame over the brow.
    static let flameHeadband = PetArt.costume.headItem("flameHeadband")

    /// A wreath of gold leaves with a few green ones, resting on the brow.
    static let goldenLaurel = PetArt.costume.headItem("goldenLaurel")
    /// A thin gold arc floating above the head that bobs up and down a
    /// pixel, with a glint crossing its top on the way up. It is two rows
    /// tall because a dog's hop leaves only three rows above the head.
    static let halo = PetArt.costume.headItem("halo")

    /// A gold medal with a glint, hung from a crimson ribbon around the neck.
    static let teamMedal = PetArt.costume.bodyItem("teamMedal")
}

// MARK: - Seasonal event items

extension CostumeArt {
    /// A navy witch hat whose tip leans over, a gold crescent moon on the
    /// crown, a pumpkin-orange band and a wide flat brim.
    static let moonlitWitchHat = PetArt.costume.headItem("moonlitWitchHat")

    /// A small jack-o'-lantern sitting on the head: leather ribs, a stem
    /// with a leaf, and a dark carved face. Gold on orange read as a box,
    /// so the face stays dark and the candle inside flickers now and then,
    /// lighting the eyes or the grin gold for a tick.
    static let pumpkinHat = PetArt.costume.headItem("pumpkinHat")

    /// Branching brown antlers that rise above the ears from a crimson
    /// headband.
    static let reindeerAntlers = PetArt.costume.headItem("reindeerAntlers")

    /// A red lion dance head: a gold horn, white brows over gold-ringed
    /// eyes and a gold fringe. Now and then the mirror on its forehead
    /// catches the light.
    static let lionDanceHat = PetArt.costume.headItem("lionDanceHat")

    /// A brown cherry branch over one ear with three pink blossoms and a
    /// green bud. Now and then a petal comes loose and drifts away.
    static let sakuraSprig = PetArt.costume.headItem("sakuraSprig")

    /// A crimson scarf with a white trim along its lower edge, a white
    /// stripe across the tail and a white fringe. Now and then a speck of
    /// snow glints on the band, then a snowflake twinkles on the tail.
    static let snowScarf = PetArt.costume.bodyItem("snowScarf")

    /// Pink heart lenses in a crimson frame. Now and then a light glints
    /// on one lens, then the other.
    static let heartGlasses = PetArt.costume.faceItem("heartGlasses")

    /// Navy-rimmed aviators with sunset lenses, pink over orange. Now and
    /// then the sun glints down one lens, then the other.
    static let summerShades = PetArt.costume.faceItem("summerShades")
}

// MARK: - Back items

extension CostumeArt {
    /// White feathered wings that rise from behind the shoulders and flap:
    /// spread, raised, spread, lowered. From the front both show beside the
    /// body; walking, the near wing stands up off the back.
    static let angelWings = PetArt.costume.backItem("angelWings")
    /// A crimson cape with an ermine collar and a gold trim a glint runs
    /// down. From the front it falls to the floor beside the body; walking
    /// and on the side-on dachshund it streams back over the shoulders and
    /// ripples.
    static let kingsCape = PetArt.costume.backItem("kingsCape")
}

// MARK: - Aura items

extension CostumeArt {
    /// Pink cherry blossom petals that drift down and sway on both sides of
    /// the pet, and over its back when seen from the side.
    static let cherryPetals = PetArt.costume.auraItem("cherryPetals")
    /// Gold sparkles that each glint for four ticks (a dot, a star with a
    /// white heart, then a white dot), a new one every tick, so four show
    /// at a time. From the front they twinkle in place beside and above the
    /// pet; walking they are born at its back and drift away behind it, a
    /// trail.
    static let sparkleTrail = PetArt.costume.auraItem("sparkleTrail")
    /// A small white cloud with two puffs and a grey underside that hangs
    /// beside the head (over the back on a walk and on the side-on
    /// dachshund) and drizzles: its drops fall a row a tick, and each one
    /// goes away before it would land on the pet.
    static let rainCloud = PetArt.costume.auraItem("rainCloud")
}
