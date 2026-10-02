import Foundation

/// Builds a full pet frame from the shared art of its body shape.
///
/// Every frame is a fixed `frameSize`×`frameSize` canvas with the pet's paws
/// on the same baseline, so frames can be swapped in place without jitter.
public enum PetComposer {
    public static let frameSize = 32

    /// The pet sitting, facing the viewer, optionally dressed. Accessories
    /// are filtered through `PetAccessory.wearable`, so any list is safe.
    public static func sitting(
        _ breed: PetBreed, outfit: PetOutfit = .none, accessories: [PetAccessory] = []
    ) -> PetCanvas {
        compose(breed, pose: PetPose(), outfit: outfit, accessories: accessories).canvas
    }

    /// The sitting pet in `pose`: an eye state, a head nod, and a hop, all
    /// relative to the plain sitting frame so costumes stay anchored.
    public static func sitting(
        _ breed: PetBreed, pose: PetPose, outfit: PetOutfit = .none, accessories: [PetAccessory] = []
    ) -> PetCanvas {
        compose(breed, pose: pose, outfit: outfit, accessories: accessories).canvas
    }

    /// A composed, outlined frame plus where the head ended up, so effects
    /// and the speech-bubble anchor can be placed relative to it.
    struct Composed {
        var canvas: PetCanvas
        /// Top-right corner of the head's skull, in frame pixels.
        var headTopRight: PetPoint
    }

    /// `hanging` swaps the body for two front legs reaching straight up to
    /// the top edge, for the pet dangling from the notch in the peek animation.
    static func compose(
        _ breed: PetBreed, pose: PetPose, outfit: PetOutfit, accessories: [PetAccessory], hanging: Bool = false
    ) -> Composed {
        let layout = SitLayout(breed.bodyShape)
        let pattern = breed.pattern
        // A hanging pet's chin always rests on the same row, whatever the head.
        let headY = hanging ? hangingChinRow + 1 - layout.head.height : layout.headY + pose.headDrop
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        // Layer order: body (pattern applied while stamping), head, face,
        // outfit, accessories. Later layers paint over earlier ones.
        if !hanging {
            canvas.stamp(layout.body, x: layout.bodyX, y: layout.bodyY, pattern: pattern)
        }
        if !hanging, breed.hasTail, let tail = layout.tail {
            canvas.stamp(tail.grid, x: tail.x, y: tail.y, pattern: pattern)
        }
        if hanging {
            let leg = EffectArt.hangingLeg(length: headY + 3)
            canvas.stamp(leg, x: layout.headX + 4, y: 0, pattern: pattern)
            canvas.stamp(leg, x: layout.headX + layout.head.width - 4 - leg.width, y: 0, pattern: pattern)
        }
        canvas.stamp(layout.head, x: layout.headX, y: headY, pattern: pattern)
        let face = EffectArt.face(layout.face, eyeRow: layout.eyeRow - layout.faceRow, eyes: pose.eyes)
        canvas.stamp(face, x: layout.headX, y: headY + layout.faceRow, pattern: pattern)

        if !hanging, let item = outfitArt(outfit) {
            canvas.stamp(layout.pick(item), x: layout.bodyX, y: layout.bodyY)
        }
        for accessory in PetAccessory.wearable(accessories) {
            switch accessoryArt(accessory) {
            case .body(let item):
                guard !hanging else { continue }
                canvas.stamp(layout.pick(item), x: layout.bodyX, y: layout.bodyY)
            case .glasses:
                let glasses = layout.family == .cat ? CostumeArt.glassesCat : CostumeArt.glassesDog
                canvas.stamp(glasses, x: layout.headX, y: headY + layout.eyeRow - 1)
            case .head(let item):
                canvas.stamp(item.grid, x: layout.headX, y: headY + layout.skullTop - item.sitRow)
            }
        }
        let anchor = PetPoint(x: layout.headX + layout.head.width - 1, y: headY + layout.skullTop - pose.lift)
        return Composed(canvas: canvas.outlined().shifted(x: 0, y: -pose.lift), headTopRight: anchor)
    }

    private static func outfitArt(_ outfit: PetOutfit) -> CostumeArt.BodyItem? {
        switch outfit {
        case .none: nil
        case .scrubs: CostumeArt.scrubs
        case .whiteCoat: CostumeArt.whiteCoat
        }
    }

    private enum AccessoryArt {
        case body(CostumeArt.BodyItem)
        case glasses
        case head(CostumeArt.HeadItem)
    }

    private static func accessoryArt(_ accessory: PetAccessory) -> AccessoryArt {
        switch accessory {
        case .stethoscope: .body(CostumeArt.stethoscope)
        case .scarf: .body(CostumeArt.scarf)
        case .roundGlasses: .glasses
        case .surgicalCap: .head(CostumeArt.surgicalCap)
        case .headMirror: .head(CostumeArt.headMirror)
        case .graduationCap: .head(CostumeArt.graduationCap)
        case .beanie: .head(CostumeArt.beanie)
        }
    }

    /// Where every part of a sitting pet goes for one body shape. Costumes
    /// anchor to these numbers instead of hard-coding positions per breed.
    private struct SitLayout {
        enum Family { case cat, dog, longDog }

        let family: Family
        let body: SpriteGrid
        let bodyX: Int
        let bodyY: Int
        let tail: (grid: SpriteGrid, x: Int, y: Int)?
        let head: SpriteGrid
        let headX: Int
        let headY: Int
        let face: SpriteGrid
        /// Head row the face grid's top row is stamped on.
        let faceRow: Int
        /// Head row of the top of the eyes.
        let eyeRow: Int
        /// Head row where a hat's band sits: just below the top of the skull,
        /// so hats rest on the head instead of floating above it.
        let skullTop: Int

        init(_ shape: PetBodyShape) {
            switch shape {
            case .cat, .roundCat:
                family = .cat
                (body, bodyX, bodyY, tail) = (CatArt.bodySit, 6, 20, nil)
                head = shape == .roundCat ? CatArt.headRound : CatArt.head
                (headX, headY, face, faceRow, eyeRow, skullTop) = (6, 7, CatArt.faceOpen, 0, 7, 3)
            case .longDog:
                family = .longDog
                (body, bodyX, bodyY, tail) = (DogArt.bodyLong, 6, 21, nil)
                (head, headX, headY, face) = (DogArt.headLong, 2, 8, DogArt.faceLongSnout)
                (faceRow, eyeRow, skullTop) = (4, 4, 1)
            case .floppyDog, .fluffyDog, .batEaredDog, .pointyEaredDog:
                family = .dog
                (body, bodyX, bodyY) = (DogArt.bodySit, 6, 20)
                tail = (DogArt.tailUp, 23, 24)
                let (grid, eyes, skull): (SpriteGrid, Int, Int) = switch shape {
                case .fluffyDog: (DogArt.headFluffy, 4, 1)
                case .batEaredDog: (DogArt.headBatEared, 8, 5)
                case .pointyEaredDog: (DogArt.headPointyEared, 8, 5)
                default: (DogArt.headFloppy, 4, 1)
                }
                // Dog heads differ in height; all rest their chin on the neck.
                (head, headX, headY, face) = (grid, 6, 21 - grid.height, DogArt.faceOpen)
                (faceRow, eyeRow, skullTop) = (eyes, eyes, skull)
            }
        }

        func pick(_ item: CostumeArt.BodyItem) -> SpriteGrid {
            switch family {
            case .cat: item.cat
            case .dog: item.dog
            case .longDog: item.longDog
            }
        }
    }
}
