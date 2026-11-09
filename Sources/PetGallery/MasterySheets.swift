import CoreGraphics
import Foundation
import TabbiKitCore

/// Review sheets for the mastery outfits (`PetCloset.masteryShelf`):
/// `swift run PetGallery out/ mastery`.
///
/// - `mastery-<item>.png`: the item on a spread of breeds that covers every
///   body shape and the dark coats (black cat, tuxedo, Shih Tzu, dachshund,
///   chocolate longhair), sitting, in a celebration hop, walking,
///   stretching and napping, at 4x.
/// - `mastery-all-<breed>.png`: every mastery item on one breed, at 4x and
///   at the closed notch's 2x.
/// - `mastery-loop-<item>.png`: each tick of an animated item's loop.
enum MasterySheets {
    static let breeds: [PetBreed] = [
        .britishShorthair, .blackCat, .tuxedo, .orangeTabby, .sphynx, .scottishFold, .britishLonghair,
        .goldenRetriever, .labrador, .frenchBulldog, .corgi, .dachshund, .poodle, .shihTzu,
    ]

    static func write(to directory: URL) throws {
        for item in PetCloset.masteryShelf {
            let look = PetCloset.wearing(item, on: PetProfile(name: "", breed: .orangeTabby))
            var cells: [Cell] = []
            for breed in breeds {
                for (animation, frameIndex) in [(PetAnimation.idle, 0), (.celebrate, 2), (.walk, 0), (.stretch, 3), (.nap, 0)] {
                    let clip = PetComposer.clip(animation, for: breed, outfit: look.outfit,
                                                accessories: look.accessories)
                    let frame = clip.frames[min(frameIndex, clip.frames.count - 1)]
                    cells.append(Cell(label: "\(breed.displayName) \(animation.rawValue)",
                                      canvas: frame.itemFrames.first ?? frame.canvas, palette: breed.palette))
                }
            }
            try writeSheet(cells, columns: 10, title: "\(item.displayName) on every body shape",
                           to: directory.appendingPathComponent("mastery-\(fileSlug(item.displayName)).png"))

            let loop = PetComposer.clip(.idle, for: .britishShorthair, outfit: look.outfit,
                                        accessories: look.accessories).frames[0]
            if loop.itemFrames.count > 1 {
                let ticks = loop.itemFrames.enumerated().map { index, canvas in
                    Cell(label: "tick \(index)", canvas: canvas, palette: PetBreed.britishShorthair.palette)
                }
                try writeSheet(ticks, columns: 8, title: "\(item.displayName) loop",
                               to: directory.appendingPathComponent("mastery-loop-\(fileSlug(item.displayName)).png"))
            }
        }
        for breed in [PetBreed.britishShorthair, .blackCat, .goldenRetriever, .dachshund, .shihTzu] {
            let cells = PetCloset.masteryShelf.map { item in
                let look = PetCloset.wearing(item, on: PetProfile(name: "", breed: breed))
                return Cell(label: item.displayName, canvas: PetComposer.sitting(breed, outfit: look.outfit,
                                                                                accessories: look.accessories),
                            palette: breed.palette)
            }
            try writeSheet(cells, columns: 8, title: "Mastery outfits on \(breed.displayName)",
                           to: directory.appendingPathComponent("mastery-all-\(breed.rawValue).png"))
            try writeSheet(cells.map { Cell(label: "", canvas: $0.canvas, palette: $0.palette) }, columns: 8, title: "",
                           scale: 2, to: directory.appendingPathComponent("mastery-all-\(breed.rawValue)-2x.png"))
        }
        // Full sets, worn with the shop items they were drawn to go with.
        let sets: [(String, PetOutfit, [PetAccessory])] = [
            ("Astronaut", .astronautSuit, [.astronautHelmet]),
            ("Sleepover", .cozyPajamas, [.nightcap]),
            ("Graduate", .scholarsRobe, [.graduationCap, .owlSpectacles]),
            ("Sage", .sagesRobe, [.wizardHat]),
            ("Stargazer", .starryCloak, [.tinyLantern]),
            ("Baker", .bakersApron, [.chefHat]),
            ("Explorer", .apprenticeRobe, [.explorersHat, .friendshipBandana]),
            ("Gardener", .none, [.blossomSprout, .scarf]),
            ("Busy bee", .none, [.beeAntennae, .roundGlasses]),
            ("Workout", .none, [.sportySweatband, .bowTie]),
        ]
        for breed in [PetBreed.britishShorthair, .tuxedo, .corgi] {
            let cells = sets.map { name, outfit, accessories in
                Cell(label: name, canvas: PetComposer.sitting(breed, outfit: outfit, accessories: accessories),
                     palette: breed.palette)
            }
            try writeSheet(cells, columns: 5, title: "Sets on \(breed.displayName)",
                           to: directory.appendingPathComponent("mastery-sets-\(breed.rawValue).png"))
        }
    }
}
