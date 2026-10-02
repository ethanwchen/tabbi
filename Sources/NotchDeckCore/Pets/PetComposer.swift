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
        let layout = SitLayout(breed.bodyShape)
        let pattern = breed.pattern
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        // Layer order: body (pattern applied while stamping), head, face,
        // outfit, accessories. Later layers paint over earlier ones.
        canvas.stamp(layout.body, x: layout.bodyX, y: layout.bodyY, pattern: pattern)
        if breed.hasTail, let tail = layout.tail {
            canvas.stamp(tail.grid, x: tail.x, y: tail.y, pattern: pattern)
        }
        canvas.stamp(layout.head, x: layout.headX, y: layout.headY, pattern: pattern)
        canvas.stamp(layout.face, x: layout.headX, y: layout.headY + layout.faceRow, pattern: pattern)

        if let item = outfitArt(outfit) {
            canvas.stamp(layout.pick(item), x: layout.bodyX, y: layout.bodyY)
        }
        for accessory in PetAccessory.wearable(accessories) {
            switch accessoryArt(accessory) {
            case .body(let item):
                canvas.stamp(layout.pick(item), x: layout.bodyX, y: layout.bodyY)
            case .glasses:
                let glasses = layout.family == .cat ? CostumeArt.glassesCat : CostumeArt.glassesDog
                canvas.stamp(glasses, x: layout.headX, y: layout.headY + layout.eyeRow - 1)
            case .head(let item):
                canvas.stamp(item.grid, x: layout.headX, y: layout.headY + layout.skullTop - item.sitRow)
            }
        }
        return canvas.outlined()
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
