import Foundation

/// Hand-drawn dog art. Dogs need more silhouettes than cats to stay
/// recognizable at notch size, so each ear/snout family has its own head;
/// most share the sitting body and face. See docs/study/pets.md for the
/// symbol legend. Outer outlines are added automatically.
/// The grids are drawn in `Pets/PetArt/dog.json`.
enum DogArt {
    /// Labrador and Beagle: soft ears hanging beside a rounded skull. The
    /// blank pixel between ear and cheek becomes an outline, separating them.
    static let headFloppy = PetArt.dog.grid("headFloppy")

    /// Golden Retriever: long feathered ears framing a narrower face.
    static let headFluffy = PetArt.dog.grid("headFluffy")

    /// French Bulldog: big rounded bat ears on a broad, flat face. Zone `b`
    /// is the cheek patch of a pied coat; it stays clear of the eye so the
    /// eye never disappears into a dark patch.
    static let headBatEared = PetArt.dog.grid("headBatEared")

    /// Corgi: tall pointed ears and a fox-like face with a center blaze.
    static let headPointyEared = PetArt.dog.grid("headPointyEared")

    /// Dachshund: long ears and a long snout. Zone `a` marks the brow dots
    /// of a black-and-tan coat.
    static let headLong = PetArt.dog.grid("headLong")

    /// Eyes, nose, and a panting tongue. The mouth uses the nose color
    /// rather than the outline, which turns into a light rim on dark breeds, stamped with the eyes on the head's
    /// eye row (`DogHead.eyeRow`).
    static let faceOpen = PetArt.dog.grid("faceOpen")

    /// The same face with a longer gap to the nose, for the long snout.
    static let faceLongSnout = PetArt.dog.grid("faceLongSnout")

    /// Sitting, facing the viewer. Zone `a` is the beagle's saddle.
    static let bodySit = PetArt.dog.grid("bodySit")

    /// Raised tail beside the sitting body; stubby-tailed breeds skip it.
    static let tailUp = PetArt.dog.grid("tailUp")

    /// Dachshund sitting: the long body stretches out behind the head on
    /// short legs, which is what makes the breed readable from the front.
    static let bodyLong = PetArt.dog.grid("bodyLong")

    /// Poodle: a round curly topknot over a teddy face, with long curly ears
    /// that end in round poms. Shade dots (`S`) and highlights (`A`) are the
    /// curls; the smooth muzzle stays plain so the face reads at notch size.
    static let headPoodle = PetArt.dog.grid("headPoodle")

    /// Poodle sitting: a curly coat with a fluffy chest and pom bracelets
    /// at the paws.
    static let bodyPoodle = PetArt.dog.grid("bodyPoodle")

    /// The poodle's tail: a short stem curving up from the rump to a round
    /// pom that stands clear of the haunch.
    static let tailPom = PetArt.dog.grid("tailPom")

    /// Shih Tzu: a gold topknot tied with a dark band above a white blaze, a
    /// gold mask around big round eyes, a flat face, and a long white beard
    /// framed by ears that hang past the chin, set apart by an outline. The
    /// band is outline, not nose, so a cap that hides it leaves the face intact.
    static let headShihTzu = PetArt.dog.grid("headShihTzu")

    /// The Shih Tzu's flat face: big round eyes and a button nose right
    /// between them, with a small smiling mouth and tongue under it in the
    /// beard, like the other dogs' faces.
    static let faceShihTzu = PetArt.dog.grid("faceShihTzu")

    /// Shih Tzu sitting: a long flowing coat that falls to the floor in
    /// strands, with only the tips of the paws peeking out.
    static let bodyShihTzu = PetArt.dog.grid("bodyShihTzu")

    /// The Shih Tzu's plumed tail, curled up over the back.
    static let tailPlume = PetArt.dog.grid("tailPlume")
}
