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
        /// Top-left corner of a held mug, where its steam rises from.
        var mugTop: PetPoint?
    }

    /// How the body under the head is drawn.
    enum Stance: Equatable {
        case sitting
        /// Two front legs reaching straight up to the top edge, for the pet
        /// dangling from the notch in the peek animation.
        case hanging
        /// Side-on torso mid-stride; `step` indexes `WalkArt.cycle`.
        case walking(step: Int)
        /// The walking body bowing into a stretch: the chest sinks `depth`
        /// pixels while the front paws slide forward and the rump stays up.
        /// `wag` picks the tail position.
        case stretching(depth: Int, wag: Int)
    }

    static func compose(
        _ breed: PetBreed, pose: PetPose, outfit: PetOutfit, accessories: [PetAccessory], stance: Stance = .sitting
    ) -> Composed {
        let layout = SitLayout(breed.bodyShape)
        let pattern = breed.pattern
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        var headX = layout.headX
        var headY = layout.headY + pose.headDrop
        // Layer order: body (pattern applied while stamping), head, face,
        // outfit, accessories. Later layers paint over earlier ones.
        var bodyItem: (CostumeArt.BodyItem) -> (SpriteGrid, Int, Int)? = { item in
            (layout.pick(item), layout.bodyX, layout.bodyY - item.rise)
        }
        switch stance {
        case .sitting:
            // A gesturing pet lifts its left front paw off the floor.
            var body = pose.gesture == nil ? layout.body : PawArt.liftingLeftPaw(layout.body)
            let swing = max(pose.tailSwing, 0)
            if swing > 0, let column = layout.tailColumn {
                // A tail drawn into the body is cut out and bent on its own.
                let (rest, tail) = TailArt.split(body, at: column)
                body = rest
                let room = frameSize - 1 - layout.bodyX
                canvas.stamp(TailArt.swung(tail, by: swing, room: room), x: layout.bodyX, y: layout.bodyY, pattern: pattern)
            }
            canvas.stamp(body, x: layout.bodyX, y: layout.bodyY, pattern: pattern)
            if breed.hasTail, let tail = layout.tail {
                let room = frameSize - 1 - tail.x
                canvas.stamp(TailArt.swung(tail.grid, by: swing, room: room), x: tail.x, y: tail.y, pattern: pattern)
            } else if !breed.hasTail, swing > 0 {
                // No tail to swish: a stub pops out past the haunch and bobs.
                let haunch = layout.bodyX + layout.body.width - 1
                canvas.stamp(TailArt.nub, x: haunch, y: layout.bodyY + 7 - swing, pattern: pattern)
            }
        case .hanging:
            // A hanging pet's chin always rests on the same row, whatever the head.
            headY = hangingChinRow + 1 - layout.head.height
            let leg = EffectArt.hangingLeg(length: headY + 3)
            canvas.stamp(leg, x: layout.headX + 4, y: 0, pattern: pattern)
            canvas.stamp(leg, x: layout.headX + layout.head.width - 4 - leg.width, y: 0, pattern: pattern)
            bodyItem = { _ in nil }
        case .walking(let index):
            let walk = WalkLayout(breed.bodyShape, layout.family)
            let step = WalkArt.cycle[index % WalkArt.cycle.count]
            // Contact steps sink a pixel onto bent legs; the head rides along.
            let sink = step.isContact ? 1 : 0
            let legY = walk.torsoY + walk.torso.height
            let legs: [(Int, WalkArt.Lean, Bool)] = [
                (walk.frontHip + 3, step.farFront, true), (walk.backHip + 3, step.farBack, true),
                (walk.frontHip, step.nearFront, false), (walk.backHip, step.nearBack, false),
            ]
            for (x, lean, far) in legs {
                canvas.stamp(WalkArt.leg(height: walk.legHeight, lean: lean, far: far), x: x, y: legY, pattern: pattern)
            }
            // The tail sways once per half cycle, not every step, so it doesn't flicker.
            canvas.lay(walkingTorso(breed, walk, outfit: outfit, accessories: accessories, wag: index / 2)) { _ in sink }
            bodyItem = { _ in nil }
            headX = walk.headX
            headY = walk.chinRow + 1 - layout.head.height + sink + pose.headDrop
        case .stretching(let bow, let wag):
            let walk = WalkLayout(breed.bodyShape, layout.family)
            // Short legs bow less, so the chin never sinks onto the paws.
            let depth = min(bow, walk.legHeight - 1)
            let legY = walk.torsoY + walk.torso.height
            // Back legs stand straight; front legs fold down and reach ahead,
            // ending on the same baseline.
            let height = max(2, walk.legHeight - depth)
            let reach = depth * 2
            for (x, far) in [(walk.backHip + 3, true), (walk.backHip, false)] {
                canvas.stamp(WalkArt.leg(height: walk.legHeight, lean: .under, far: far), x: x, y: legY, pattern: pattern)
            }
            // Bow the torso: columns toward the chest sink, the rump stays put.
            let torso = walkingTorso(breed, walk, outfit: outfit, accessories: accessories, wag: wag)
            let pivot = walk.torsoX + walk.torso.width * 2 / 3
            canvas.lay(torso) { x in
                x >= pivot ? 0 : min(depth, Int((Double(depth * (pivot - x)) / Double(pivot - walk.torsoX)).rounded()))
            }
            // The forearms lie in front of the lowered chest.
            for (x, far) in [(walk.frontHip + 3, true), (walk.frontHip, false)] {
                canvas.stamp(WalkArt.reachingLeg(height: height, reach: reach, far: far),
                             x: x - reach, y: legY + walk.legHeight - height, pattern: pattern)
            }
            bodyItem = { _ in nil }
            headX = walk.headX
            headY = walk.chinRow + 1 - layout.head.height + depth + pose.headDrop
        }
        canvas.stamp(layout.head, x: headX, y: headY, pattern: pattern)
        let face = EffectArt.face(layout.face, eyeRow: layout.eyeRow - layout.faceRow, eyes: pose.eyes)
        canvas.stamp(face, x: headX, y: headY + layout.faceRow, pattern: pattern)
        if let (grid, origin) = EffectArt.mouth(pose.mouth, in: layout.face) {
            canvas.stamp(grid, x: headX + origin.x, y: headY + layout.faceRow + origin.y, pattern: pattern)
        }

        func stampFace(_ item: CostumeArt.FaceItem) {
            canvas.stamp(layout.family == .cat ? item.cat : item.dog, x: headX, y: headY + layout.eyeRow - item.eyeRow)
        }
        func stampHead(_ item: CostumeArt.HeadItem) {
            canvas.stamp(item.grid, x: headX, y: headY + layout.skullTop - item.sitRow)
        }
        if let item = outfitArt(outfit), let (grid, x, y) = bodyItem(item) {
            canvas.stamp(grid, x: x, y: y)
        }
        // An outfit's hood goes under any hat, which is worn over it.
        if let hood = outfitHood(outfit) {
            stampHead(hood)
        }
        for accessory in PetAccessory.wearable(accessories) {
            switch accessoryArt(accessory) {
            case .body(let item):
                guard let (grid, x, y) = bodyItem(item) else { continue }
                canvas.stamp(grid, x: x, y: y)
            case .face(let item):
                stampFace(item)
            case .head(let item):
                stampHead(item)
            case .mask(let head, let face):
                stampFace(face)
                stampHead(head)
            }
        }
        var mugTop: PetPoint?
        if stance == .sitting, let prop = pose.prop {
            mugTop = stampProp(prop, on: &canvas, layout: layout, headX: headX, headY: headY, pattern: pattern)
            mugTop?.y -= pose.lift
        }
        if stance == .sitting, let gesture = pose.gesture {
            stampGesture(gesture, on: &canvas, layout: layout, headX: headX, headY: headY, pattern: pattern)
        }
        let anchor = PetPoint(x: headX + layout.head.width - 1, y: headY + layout.skullTop - pose.lift)
        return Composed(canvas: canvas.outlined().shifted(x: 0, y: -pose.lift), headTopRight: anchor, mugTop: mugTop)
    }

    /// Draws a held prop in front of the sitting pet, centered under the
    /// head so it lines up on every body shape. The laptop stands on the
    /// floor; the mug rises from the chest to the mouth, found from the
    /// face art like an open mouth. Returns the mug's top-left corner.
    private static func stampProp(
        _ prop: PetPose.Prop, on canvas: inout PetCanvas, layout: SitLayout, headX: Int, headY: Int,
        pattern: PetPattern
    ) -> PetPoint? {
        let center = headX + layout.head.width / 2
        switch prop {
        case .laptop(let tap):
            let lidY = frameSize - 1 - PropArt.laptop.height
            canvas.stamp(PropArt.laptop, x: center - PropArt.laptop.width / 2, y: lidY)
            // Resting paws hang over the lid's edge; a tapping paw lifts off it.
            let pawY = lidY - 1
            canvas.stamp(PropArt.paw, x: center - 7, y: pawY - (tap < 0 ? 2 : 0), pattern: pattern)
            canvas.stamp(PropArt.paw, x: center + 1, y: pawY - (tap > 0 ? 2 : 0), pattern: pattern)
            return nil
        case .mug(let raise):
            guard let (_, mouth) = EffectArt.mouth(.open, in: layout.face) else { return nil }
            let mouthX = headX + mouth.x + 2
            let sipY = headY + layout.faceRow + mouth.y - 1
            // Held in the lap, low enough that the steam rises over the chest.
            let lapY = headY + layout.head.height + 3
            let y = lapY + (sipY - lapY) * min(max(raise, 0), 2) / 2
            let x = mouthX - 3
            // Paws first, so the mug's handle shows over the right one.
            canvas.stamp(PropArt.mugPaw, x: x - 3, y: y + 1, pattern: pattern)
            canvas.stamp(PropArt.mugPaw, x: x + 4, y: y + 1, pattern: pattern)
            canvas.stamp(PropArt.mug, x: x, y: y)
            return PetPoint(x: x, y: y)
        }
    }

    /// Draws the lifted front paw in front of the sitting pet. The wave
    /// grows from the left shoulder and holds the paw beside the head; the
    /// grooming paw rises from the chest to the mouth (found from the face
    /// art, like an open mouth) or over the left cheek.
    private static func stampGesture(
        _ gesture: PetPose.Gesture, on canvas: inout PetCanvas, layout: SitLayout, headX: Int, headY: Int,
        pattern: PetPattern
    ) {
        let shoulder = PetPoint(x: layout.bodyX + 3, y: layout.bodyY + 4)
        switch gesture {
        case .wave(let swing):
            let arm = PawArt.wave[min(max(swing, 0), PawArt.wave.count - 1)]
            canvas.stamp(arm, x: shoulder.x - 8, y: shoulder.y - arm.height + 1, pattern: pattern)
        case .groom(let reach):
            guard let (_, mouth) = EffectArt.mouth(.open, in: layout.face) else { return }
            let mouthX = headX + mouth.x + 2
            let mouthY = headY + layout.faceRow + mouth.y
            // Just under the tongue to lick it; lower at rest; up and to the
            // side over the cheek to wash.
            let (x, y) = switch reach {
            case ...0: (mouthX - 4, mouthY + 4)
            case 1: (mouthX - 4, mouthY + 2)
            default: (mouthX - 8, mouthY - 3)
            }
            // The whole front leg is lifted, so it reaches down to just
            // above the floor where the paw stood.
            let knee = layout.bodyY + layout.body.height - 2
            canvas.stamp(PawArt.groom(height: knee - y + 1), x: x, y: y, pattern: pattern)
        }
    }

    /// The walking torso with its tail and torso costumes, on its own frame
    /// canvas so a stance can bend it before laying it over the legs. The
    /// torso is behind the head, so torso costumes go on here, before it.
    private static func walkingTorso(
        _ breed: PetBreed, _ walk: WalkLayout, outfit: PetOutfit, accessories: [PetAccessory], wag: Int
    ) -> PetCanvas {
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        canvas.stamp(walk.torso, x: walk.torsoX, y: walk.torsoY, pattern: breed.pattern)
        if breed.hasTail {
            let tail = walk.tails[wag % walk.tails.count]
            canvas.stamp(tail, x: walk.tailX, y: walk.torsoY - tail.height, pattern: breed.pattern)
        }
        for item in bodyItems(outfit: outfit, accessories: accessories) {
            canvas.stamp(walk.pick(item), x: walk.torsoX, y: walk.torsoY - item.rise)
        }
        return canvas
    }

    /// The outfit and neck items worn, in drawing order.
    private static func bodyItems(outfit: PetOutfit, accessories: [PetAccessory]) -> [CostumeArt.BodyItem] {
        let neck = PetAccessory.wearable(accessories).compactMap { accessory -> CostumeArt.BodyItem? in
            if case .body(let item) = accessoryArt(accessory) { item } else { nil }
        }
        return (outfitArt(outfit).map { [$0] } ?? []) + neck
    }

    private static func outfitArt(_ outfit: PetOutfit) -> CostumeArt.BodyItem? {
        switch outfit {
        case .none: nil
        case .scrubs: CostumeArt.scrubs
        case .whiteCoat: CostumeArt.whiteCoat
        case .cozyHoodie: CostumeArt.cozyHoodie
        case .superheroCape: CostumeArt.superheroCape
        case .dinosaurHoodie: CostumeArt.dinosaurHoodie
        case .wizardRobe: CostumeArt.wizardRobe
        }
    }

    /// The head part of an outfit, drawn like a hat that moves with the head.
    private static func outfitHood(_ outfit: PetOutfit) -> CostumeArt.HeadItem? {
        outfit == .dinosaurHoodie ? CostumeArt.dinosaurHood : nil
    }

    private enum AccessoryArt {
        case body(CostumeArt.BodyItem)
        case face(CostumeArt.FaceItem)
        case head(CostumeArt.HeadItem)
        /// A head item worn with a face piece, such as a hat and an eyepatch.
        case mask(CostumeArt.HeadItem, CostumeArt.FaceItem)
    }

    private static func accessoryArt(_ accessory: PetAccessory) -> AccessoryArt {
        switch accessory {
        case .stethoscope: .body(CostumeArt.stethoscope)
        case .scarf: .body(CostumeArt.scarf)
        case .bowTie: .body(CostumeArt.bowTie)
        case .roundGlasses: .face(CostumeArt.roundGlasses)
        case .coolSunglasses: .face(CostumeArt.coolSunglasses)
        case .surgicalCap: .head(CostumeArt.surgicalCap)
        case .headMirror: .head(CostumeArt.headMirror)
        case .graduationCap: .head(CostumeArt.graduationCap)
        case .beanie: .head(CostumeArt.beanie)
        case .tinyCrown: .head(CostumeArt.tinyCrown)
        case .partyHat: .head(CostumeArt.partyHat)
        case .chefHat: .head(CostumeArt.chefHat)
        case .wizardHat: .head(CostumeArt.wizardHat)
        case .bunnyEars: .head(CostumeArt.bunnyEars)
        case .witchHat: .head(CostumeArt.witchHat)
        case .cowboyHat: .head(CostumeArt.cowboyHat)
        case .flowerCrown: .head(CostumeArt.flowerCrown)
        case .frogHat: .head(CostumeArt.frogHat)
        case .ninjaHeadband: .head(CostumeArt.ninjaHeadband)
        case .pirateHat: .mask(CostumeArt.pirateHat, CostumeArt.eyepatch)
        case .blindfoldedSorcerer: .mask(CostumeArt.spikyHair, CostumeArt.blindfold)
        case .astronautHelmet: .head(CostumeArt.astronautHelmet)
        case .chunkyHeadphones: .head(CostumeArt.chunkyHeadphones)
        }
    }

    /// Where every part of a sitting pet goes for one body shape. Costumes
    /// anchor to these numbers instead of hard-coding positions per breed.
    private enum Family { case cat, dog, longDog }

    private struct SitLayout {

        let family: Family
        let body: SpriteGrid
        let bodyX: Int
        let bodyY: Int
        let tail: (grid: SpriteGrid, x: Int, y: Int)?
        /// First body column of a tail drawn into the sitting body, so the
        /// tail swish can bend it on its own.
        let tailColumn: Int?
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
            case .cat, .roundCat, .sphynxCat:
                family = .cat
                (bodyX, bodyY, tail, tailColumn) = (6, 20, nil, 17)
                (body, head, face) = switch shape {
                case .roundCat: (CatArt.bodyRound, CatArt.headRound, CatArt.faceRound)
                case .sphynxCat: (CatArt.bodySphynx, CatArt.headSphynx, CatArt.faceSphynx)
                default: (CatArt.bodySit, CatArt.head, CatArt.faceOpen)
                }
                (headX, headY, faceRow, eyeRow, skullTop) = (6, 7, 0, 7, 3)
            case .longDog:
                family = .longDog
                (body, bodyX, bodyY, tail, tailColumn) = (DogArt.bodyLong, 6, 21, nil, 23)
                (head, headX, headY, face) = (DogArt.headLong, 2, 8, DogArt.faceLongSnout)
                (faceRow, eyeRow, skullTop) = (4, 4, 1)
            case .floppyDog, .fluffyDog, .batEaredDog, .pointyEaredDog, .poodleDog, .shihTzuDog:
                family = .dog
                tailColumn = nil
                (body, bodyX, bodyY) = switch shape {
                case .poodleDog: (DogArt.bodyPoodle, 6, 20)
                case .shihTzuDog: (DogArt.bodyShihTzu, 6, 20)
                default: (DogArt.bodySit, 6, 20)
                }
                tail = switch shape {
                case .poodleDog: (DogArt.tailPom, 24, 21)
                case .shihTzuDog: (DogArt.tailPlume, 24, 21)
                default: (DogArt.tailUp, 23, 24)
                }
                let (grid, eyes, skull): (SpriteGrid, Int, Int) = switch shape {
                case .fluffyDog: (DogArt.headFluffy, 4, 1)
                case .batEaredDog: (DogArt.headBatEared, 8, 5)
                case .pointyEaredDog: (DogArt.headPointyEared, 8, 5)
                case .poodleDog: (DogArt.headPoodle, 8, 4)
                case .shihTzuDog: (DogArt.headShihTzu, 7, 5)
                default: (DogArt.headFloppy, 4, 1)
                }
                // Dog heads differ in height; all rest their chin on the neck.
                let dogFace = shape == .shihTzuDog ? DogArt.faceShihTzu : DogArt.faceOpen
                (head, headX, headY, face) = (grid, 6, 21 - grid.height, dogFace)
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

    /// Where every part of a walking pet goes for one body family. The head
    /// is the sitting head, so faces, glasses, and hats need no walking art.
    private struct WalkLayout {
        let family: Family
        let torso: SpriteGrid
        let torsoX = 7
        let torsoY: Int
        let tails: [SpriteGrid]
        let tailX: Int
        let legHeight: Int
        /// Left edge of the near front and near back leg; far legs stand 3
        /// pixels further back.
        let frontHip = 9
        let backHip: Int
        let headX = 1
        /// Frame row of the head's last pixel on a passing step.
        let chinRow: Int

        init(_ shape: PetBodyShape, _ family: Family) {
            self.family = family
            switch family {
            case .cat:
                (torso, tails) = switch shape {
                case .roundCat: (WalkArt.roundCatTorso, WalkArt.roundCatTail)
                case .sphynxCat: (WalkArt.sphynxTorso, WalkArt.sphynxTail)
                default: (WalkArt.catTorso, WalkArt.catTail)
                }
                (torsoY, tailX) = (20, 26)
                (legHeight, backHip, chinRow) = (4, 22, 24)
            case .dog:
                (torso, tails) = switch shape {
                case .poodleDog: (WalkArt.poodleTorso, WalkArt.poodleTail)
                case .shihTzuDog: (WalkArt.shihTzuTorso, WalkArt.shihTzuTail)
                default: (WalkArt.dogTorso, WalkArt.dogTail)
                }
                (torsoY, tailX) = (20, 26)
                (legHeight, backHip, chinRow) = (4, 22, 24)
            case .longDog:
                (torso, torsoY, tails, tailX) = (WalkArt.longTorso, 22, WalkArt.longTail, 27)
                (legHeight, backHip, chinRow) = (3, 23, 26)
            }
        }

        func pick(_ item: CostumeArt.BodyItem) -> SpriteGrid {
            family == .longDog ? item.walkLong : item.walk
        }
    }
}

extension PetCanvas {
    /// Paints the opaque pixels of `layer` over this canvas, moving each
    /// column down by `drop(x)` pixels: a plain offset, or a bend.
    fileprivate mutating func lay(_ layer: PetCanvas, drop: (Int) -> Int) {
        for x in 0..<layer.width {
            let dy = drop(x)
            for y in 0..<layer.height { if let role = layer[x, y] { self[x, y + dy] = role } }
        }
    }
}
