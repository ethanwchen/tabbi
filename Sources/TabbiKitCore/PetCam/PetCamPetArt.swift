import Foundation

/// The pet's Pet Cam poses, composed from the shared pet art by
/// `PetComposer`, so every breed, fur tint and outfit works with no art of
/// its own: the stare, the sneak, the swipe, the strike each object calls
/// for, the freeze mid-act, the lens stare and the innocent lie-down. The
/// new pieces (eye overlays that glance one way, stare into the lens or go
/// wild, a held donut, the marks a mugshot wears) are grids in
/// `PetCamData/pet.json`, in the pets.v1 sprite format and palette roles.
///
/// Every pose is drawn facing left, the walk's direction, and mirrored to
/// face right; the composed frame is the usual 32x32 with the paws on the
/// bottom row, so poses swap in place.
public enum PetCamPetArt {
    static let art = PetCamData.load("pet")

    /// Both eyes glancing left under a lowered lid: the stalking look.
    static let lookLeft = eyes(art.grid("eyesLookLeft"), art.grid("eyesLookLeft"))
    /// Both eyes up, for the bookcase behind and above the pet.
    static let lookUp = eyes(art.grid("eyesLookUp"), art.grid("eyesLookUp"))
    /// Wide, dark, unblinking: staring into the lens.
    static let lens = eyes(art.grid("eyesLensLeft"), art.grid("eyesLensRight"))
    /// Small pupils in wide eyes, for the moment of the strike.
    static let wild = eyes(art.grid("eyesWild"), art.grid("eyesWild").mirrored())
    /// A donut with a bite out of it, held up to the mouth.
    static let heldDonut = art.grid("heldDonut")

    /// The evidence a pet wears in its mugshot, by what it went for.
    static func guiltyMarks(_ kind: PetCamObjectKind) -> [PetComposer.Extras.Mark] {
        func mark(_ name: String, _ anchor: PetComposer.Extras.Mark.Anchor) -> PetComposer.Extras.Mark {
            PetComposer.Extras.Mark(grid: art.grid(name), anchor: anchor)
        }
        return switch kind {
        case .fishbowl: [mark("markFish", .crown)]
        case .donut: [mark("markFrosting", .mouth)]
        case .tissues: [mark("markTissue", .leftEar)]
        case .plant: [mark("markSoil", .nose)]
        case .mug: [mark("markCoffee", .mouth)]
        case .vase: [mark("markPetal", .crown)]
        }
    }

    private static func eyes(_ left: SpriteGrid, _ right: SpriteGrid) -> PetComposer.Extras.EyeOverlays {
        PetComposer.Extras.EyeOverlays(left: left, right: right)
    }

    /// The pet in `pose`, facing left, or mirrored to face right.
    public static func canvas(_ pose: PetCamPose, profile: PetProfile, facingRight: Bool = false) -> PetCanvas {
        var (pet, stance, extras) = parts(pose)
        func compose(_ pet: PetPose) -> PetCanvas {
            PetComposer.compose(profile.breed, pose: pet, outfit: profile.outfit, accessories: profile.accessories,
                                bond: profile.bondLook, stance: stance, extras: extras).picture
        }
        if pet.lift > 0 {
            // A hop or a leap as high as this pet's ears and hat allow, with
            // the top row kept clear.
            var grounded = pet
            grounded.lift = 0
            let top = compose(grounded).opaqueBounds?.minY ?? 0
            pet.lift = max(min(pet.lift, top - 1), 1)
        }
        let composed = compose(pet)
        return facingRight ? composed.mirroredHorizontally() : composed
    }

    /// How many mugshot expressions there are (`mugshot(_:profile:)`).
    public static let mugshotLooks = 5

    /// The front view for a mugshot, its expression one of
    /// `mugshotLooks` by `look` (the wall uses the case number, so two
    /// cases side by side never pull the same face): the deadpan stare into
    /// the lens, smug, side-eye, unbothered, and mid-yawn. With `evidence`,
    /// the pet wears what it went for: a fish on its head and wet fur, frosting
    /// on its mouth, a tissue over one ear, soil on its nose, a coffee drip
    /// or a petal.
    public static func mugshot(_ look: Int, profile: PetProfile, evidence: PetCamObjectKind? = nil) -> PetCanvas {
        var (pose, extras): (PetPose, PetComposer.Extras) = switch ((look % mugshotLooks) + mugshotLooks) % mugshotLooks {
        case 0: (PetPose(headDrop: -1), PetComposer.Extras(eyes: lens))
        case 1: (PetPose(eyes: .happy), PetComposer.Extras())
        case 2: (PetPose(), PetComposer.Extras(eyes: lookLeft))
        case 3: (PetPose(eyes: .sleepy, headDrop: 1), PetComposer.Extras())
        default: (PetPose(eyes: .squeezed, mouth: .wide, headDrop: -1), PetComposer.Extras())
        }
        if let evidence {
            extras.marks = guiltyMarks(evidence)
            // A frosted or coffee-stained mouth stays shut so the mark reads.
            if evidence == .donut || evidence == .mug { pose.mouth = .closed }
        }
        return PetComposer.compose(profile.breed, pose: pose, outfit: profile.outfit, accessories: profile.accessories,
                                   bond: profile.bondLook, extras: extras).picture
    }

    /// The side view for a mugshot: standing side-on, facing left.
    public static func mugshotProfile(_ profile: PetProfile) -> PetCanvas {
        canvas(.stroll(step: 1), profile: profile)
    }

    /// The strike as each object calls for it.
    static func act(_ kind: PetCamObjectKind) -> (PetPose, PetComposer.Stance, PetComposer.Extras) {
        switch kind {
        case .mug:
            // The swat: paw flung out, a little hop, mouth open, wild eyes.
            (PetPose(mouth: .open, gesture: .wave(swing: 0), lift: 1), .sitting, PetComposer.Extras(eyes: wild))
        case .fishbowl:
            // A paw in the water and a splash in the face: eyes squeezed shut,
            // mouth open.
            (PetPose(eyes: .squeezed, mouth: .open, gesture: .wave(swing: 0)), .sitting, PetComposer.Extras())
        case .donut:
            // Mouth full: the donut up in both paws, eyes squeezed in bliss.
            (PetPose(eyes: .squeezed), .sitting, PetComposer.Extras(held: heldDonut))
        case .tissues:
            // Shredding: paw up and pulling, eyes delighted.
            (PetPose(eyes: .happy, mouth: .open, gesture: .wave(swing: 1)), .sitting, PetComposer.Extras())
        case .plant:
            // Digging: down low at the pot, eyes squeezed against the soil.
            (PetPose(eyes: .squeezed), .sneaking(step: 2), PetComposer.Extras())
        case .vase:
            // A head-shove: head down and turned into it, eyes shut.
            (PetPose(eyes: .closed, headDrop: 1), .stretching(depth: 1, wag: 1), PetComposer.Extras(faceShift: -1))
        }
    }

    /// Which way the pet faces when it stares at `spot` from the middle
    /// of the floor: the counter is to its left, the side table to its
    /// right, and the bookcase behind it (it sits facing the camera).
    public static func facesRight(staringAt spot: PetCamSpot) -> Bool { spot == .table }

    static func parts(_ pose: PetCamPose) -> (PetPose, PetComposer.Stance, PetComposer.Extras) {
        switch pose {
        case .stare(let spot):
            if spot == .shelf {
                // Sitting tall, head tipped back, eyes up at the bookcase.
                return (PetPose(headDrop: -1), .sitting, PetComposer.Extras(eyes: lookUp))
            }
            // Low in the front, rump up, the head turned toward it and the
            // eyes fixed on it: about to pounce.
            return (PetPose(), .stretching(depth: 1, wag: 0), PetComposer.Extras(eyes: lookLeft, faceShift: -2))
        case .sneak(let step):
            return (PetPose(), .sneaking(step: step), PetComposer.Extras(eyes: lookLeft, faceShift: -1))
        case .swipe:
            // The paw cocked by the cheek, eyes on the target.
            return (PetPose(gesture: .wave(swing: 1)), .sitting, PetComposer.Extras(eyes: lookLeft, faceShift: -1))
        case .act(let kind):
            return act(kind)
        case .caughtMidAct(let kind):
            if kind.isEaten {
                // Mouth full, the donut up in both paws, eyes on the lens.
                return (PetPose(), .sitting, PetComposer.Extras(eyes: lens, held: heldDonut))
            }
            // Off the spot and in the air, paw flung out, eyes on the lens.
            return (PetPose(mouth: .open, gesture: .wave(swing: 0), lift: 4), .sitting, PetComposer.Extras(eyes: lens))
        case .lensStare:
            return (PetPose(headDrop: -1), .sitting, PetComposer.Extras(eyes: lens))
        case .lieDown:
            return (PetPose(), .curled(breath: 0), PetComposer.Extras(eyes: lens))
        case .stroll(let step):
            return (PetPose(), .walking(step: step), PetComposer.Extras())
        }
    }
}

extension PetCanvas {
    /// A left-right mirror image, for a pet facing right.
    func mirroredHorizontally() -> PetCanvas {
        var result = PetCanvas(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width { result[width - 1 - x, y] = self[x, y] }
        }
        return result
    }
}

extension PetCamData {
    /// Reads one pets.v1 file from `PetCamData`. It ships inside the app,
    /// so a missing or broken file stops with the reason, like the pet art.
    static func load(_ name: String) -> PetArtFile {
        guard let url = KitResources.bundle?.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            preconditionFailure("Missing \(subdirectory)/\(name).json")
        }
        do {
            return try PetArtFile.decode(Data(contentsOf: url))
        } catch {
            preconditionFailure("Invalid \(subdirectory)/\(name).json: \(error)")
        }
    }
}
