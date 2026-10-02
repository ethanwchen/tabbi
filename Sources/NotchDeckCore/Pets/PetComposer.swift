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
        canvas.stamp(CatArt.bodySit, x: 6, y: 20, pattern: pattern)
        canvas.stamp(breed.bodyShape == .roundCat ? CatArt.headRound : CatArt.head, x: 6, y: 7, pattern: pattern)
        canvas.stamp(CatArt.faceOpen, x: 6, y: 7, pattern: pattern)
        return canvas.outlined()
    }
}
