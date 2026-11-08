import Foundation

/// The pet's Pet Cam poses, composed from the shared pet art by
/// `PetComposer`, so every breed, fur tint and outfit works with no art of
/// its own: the stare, the sneak, the swipe, the strike, the lens stare and
/// the innocent lie-down. The new pieces (eye overlays that glance one way,
/// stare into the lens or go wild) are grids in `PetCamData/pet.json`, in
/// the pets.v1 sprite format and palette roles.
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

    private static func eyes(_ left: SpriteGrid, _ right: SpriteGrid) -> PetComposer.Extras.EyeOverlays {
        PetComposer.Extras.EyeOverlays(left: left, right: right)
    }

    /// The pet in `pose`, facing left, or mirrored to face right.
    public static func canvas(_ pose: PetCamPose, profile: PetProfile, facingRight: Bool = false) -> PetCanvas {
        let (pet, stance, extras) = parts(pose)
        let composed = PetComposer.compose(profile.breed, pose: pet, outfit: profile.outfit,
                                           accessories: profile.accessories, bond: profile.bondLook,
                                           stance: stance, extras: extras).picture
        return facingRight ? composed.mirroredHorizontally() : composed
    }

    /// How many mugshot expressions there are (`mugshot(_:profile:)`).
    public static let mugshotLooks = 5

    /// The front view for a mugshot, its expression one of
    /// `mugshotLooks` by `look` (the wall uses the case number, so two
    /// cases side by side never pull the same face): the deadpan stare into
    /// the lens, smug, side-eye, unbothered, and mid-yawn.
    public static func mugshot(_ look: Int, profile: PetProfile) -> PetCanvas {
        let (pose, extras): (PetPose, PetComposer.Extras) = switch ((look % mugshotLooks) + mugshotLooks) % mugshotLooks {
        case 0: (PetPose(headDrop: -1), PetComposer.Extras(eyes: lens))
        case 1: (PetPose(eyes: .happy), PetComposer.Extras())
        case 2: (PetPose(), PetComposer.Extras(eyes: lookLeft))
        case 3: (PetPose(eyes: .sleepy, headDrop: 1), PetComposer.Extras())
        default: (PetPose(eyes: .squeezed, mouth: .wide, headDrop: -1), PetComposer.Extras())
        }
        return PetComposer.compose(profile.breed, pose: pose, outfit: profile.outfit, accessories: profile.accessories,
                                   bond: profile.bondLook, extras: extras).picture
    }

    /// The side view for a mugshot: standing side-on, facing left.
    public static func mugshotProfile(_ profile: PetProfile) -> PetCanvas {
        canvas(.stroll(step: 1), profile: profile)
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
            // Low in the front, rump up, eyes fixed on it: about to pounce.
            return (PetPose(), .stretching(depth: 1, wag: 0), PetComposer.Extras(eyes: lookLeft))
        case .sneak(let step):
            return (PetPose(), .sneaking(step: step), PetComposer.Extras(eyes: lookLeft))
        case .swipe:
            // The paw cocked by the cheek, eyes on the target.
            return (PetPose(gesture: .wave(swing: 1)), .sitting, PetComposer.Extras(eyes: lookLeft))
        case .midAct:
            // The swat: paw flung out, a little hop, mouth open, wild eyes.
            return (PetPose(mouth: .open, gesture: .wave(swing: 0), lift: 1), .sitting, PetComposer.Extras(eyes: wild))
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
