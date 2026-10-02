import Foundation

/// Builds a full pet frame from the shared art of its body shape.
///
/// Every frame is a fixed `frameSize`×`frameSize` canvas with the pet's paws
/// on the same baseline, so frames can be swapped in place without jitter.
public enum PetComposer {
    public static let frameSize = 32

    /// The pet sitting, facing the viewer.
    public static func sitting(_ breed: PetBreed) -> PetCanvas {
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        let pattern = breed.pattern
        // Body first, then the head overlapping the neck, then the face.
        switch breed.bodyShape {
        case .cat, .roundCat:
            canvas.stamp(CatArt.bodySit, x: 6, y: 20, pattern: pattern)
            canvas.stamp(breed.bodyShape == .roundCat ? CatArt.headRound : CatArt.head, x: 6, y: 7, pattern: pattern)
            canvas.stamp(CatArt.faceOpen, x: 6, y: 7, pattern: pattern)
        case .longDog:
            canvas.stamp(DogArt.bodyLong, x: 6, y: 21, pattern: pattern)
            canvas.stamp(DogArt.headLong, x: 2, y: 8, pattern: pattern)
            canvas.stamp(DogArt.faceLongSnout, x: 2, y: 12, pattern: pattern)
        case .floppyDog, .fluffyDog, .batEaredDog, .pointyEaredDog:
            let head = dogHead(for: breed.bodyShape)
            canvas.stamp(DogArt.bodySit, x: 6, y: 20, pattern: pattern)
            if breed.hasTail { canvas.stamp(DogArt.tailUp, x: 23, y: 24, pattern: pattern) }
            canvas.stamp(head.grid, x: 6, y: 21 - head.grid.height, pattern: pattern)
            canvas.stamp(DogArt.faceOpen, x: 6, y: 21 - head.grid.height + head.eyeRow, pattern: pattern)
        }
        return canvas.outlined()
    }

    /// A dog head and the row its eyes sit on, so the shared face lines up.
    private struct DogHead {
        let grid: SpriteGrid
        let eyeRow: Int
    }

    private static func dogHead(for shape: PetBodyShape) -> DogHead {
        switch shape {
        case .fluffyDog: DogHead(grid: DogArt.headFluffy, eyeRow: 4)
        case .batEaredDog: DogHead(grid: DogArt.headBatEared, eyeRow: 8)
        case .pointyEaredDog: DogHead(grid: DogArt.headPointyEared, eyeRow: 8)
        default: DogHead(grid: DogArt.headFloppy, eyeRow: 4)
        }
    }
}
