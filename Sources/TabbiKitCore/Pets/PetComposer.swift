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
        compose(breed, pose: PetPose(), outfit: outfit, accessories: accessories).picture
    }

    /// The sitting pet in `pose`: an eye state, a head nod, and a hop, all
    /// relative to the plain sitting frame so costumes stay anchored.
    public static func sitting(
        _ breed: PetBreed, pose: PetPose, outfit: PetOutfit = .none, accessories: [PetAccessory] = []
    ) -> PetCanvas {
        compose(breed, pose: pose, outfit: outfit, accessories: accessories).picture
    }

    /// A composed, outlined frame plus where the head ended up, so effects
    /// and the speech-bubble anchor can be placed relative to it.
    struct Composed {
        /// The pet, without what it wears behind it.
        var canvas: PetCanvas
        /// The outlined layer of back items (wings), or nil when none is
        /// worn. Kept apart so effects can float in front of it.
        var back: PetCanvas?
        /// The particles of aura items (petals) in the air, not outlined
        /// and not moved by a hop, or nil when none is worn or the pet is
        /// out of view. Added in front of the pet after its effects.
        var aura: PetCanvas?
        /// Top-right corner of the head's skull, in frame pixels.
        var headTopRight: PetPoint
        /// Top-left corner of a held mug, where its steam rises from.
        var mugTop: PetPoint?

        /// The pet with its aura, over its back layer.
        var picture: PetCanvas {
            let pet = aura.map { canvas.scattering($0) } ?? canvas
            return back.map { pet.over($0) } ?? pet
        }
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
        /// Curled up asleep on the floor: the walking torso lying down with
        /// no legs, the head resting at its front and the tail wrapped round
        /// under the chin. `breath` 1 raises the back a pixel.
        case curled(breath: Int)
    }

    /// `phase` is the tick of the item clock (`itemLoopLength`): animated
    /// costume items draw that frame of their loop, and 0 is their still.
    static func compose(
        _ breed: PetBreed, pose: PetPose, outfit: PetOutfit, accessories: [PetAccessory], stance: Stance = .sitting,
        phase: Int = 0
    ) -> Composed {
        let layout = SitLayout(breed.bodyShape)
        let pattern = breed.pattern
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        var headX = layout.headX
        var headY = layout.headY + pose.headDrop
        // Layer order: body (pattern applied while stamping), head, face,
        // outfit, accessories. Later layers paint over earlier ones.
        var bodyItem: (CostumeArt.BodyItem) -> (SpriteGrid, Int, Int)? = { item in
            (layout.pick(item.frame(phase)), layout.bodyX, layout.bodyY - item.rise)
        }
        // Back items (wings) go on a layer of their own under the pet,
        // placed from the body origin and moved with the body.
        let behind = backItems(accessories)
        var back = PetCanvas(width: frameSize, height: frameSize)
        switch stance {
        case .sitting:
            for item in behind {
                let placement = layout.pick(item)
                back.stamp(placement.frames[phase % item.frameCount], x: layout.bodyX + placement.x,
                           y: layout.bodyY + placement.y)
            }
            // A gesturing pet lifts its left front paw off the floor.
            var body = pose.liftsLeftPaw ? PawArt.liftingLeftPaw(layout.body) : layout.body
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
            canvas.lay(walkingTorso(breed, walk, outfit: outfit, accessories: accessories, wag: index / 2, phase: phase)) { _ in sink }
            back.lay(walkingBack(behind, walk, phase: phase)) { _ in sink }
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
            let torso = walkingTorso(breed, walk, outfit: outfit, accessories: accessories, wag: wag, phase: phase)
            let pivot = walk.torsoX + walk.torso.width * 2 / 3
            let bow = { (x: Int) in
                x >= pivot ? 0 : min(depth, Int((Double(depth * (pivot - x)) / Double(pivot - walk.torsoX)).rounded()))
            }
            canvas.lay(torso, drop: bow)
            back.lay(walkingBack(behind, walk, phase: phase), drop: bow)
            // The forearms lie in front of the lowered chest.
            for (x, far) in [(walk.frontHip + 3, true), (walk.frontHip, false)] {
                canvas.stamp(WalkArt.reachingLeg(height: height, reach: reach, far: far),
                             x: x - reach, y: legY + walk.legHeight - height, pattern: pattern)
            }
            bodyItem = { _ in nil }
            headX = walk.headX
            headY = walk.chinRow + 1 - layout.head.height + depth + pose.headDrop
        case .curled(let breath):
            let walk = WalkLayout(breed.bodyShape, layout.family)
            // The torso drops onto the floor where the legs were; on a
            // breath the middle of the back swells up a pixel.
            let torso = walkingTorso(breed, walk, outfit: outfit, accessories: accessories, wag: nil, phase: phase)
            let floor = walk.legHeight
            canvas.lay(torso) { _ in floor }
            back.lay(walkingBack(behind, walk, phase: phase)) { _ in floor }
            if breath > 0 {
                let back = (walk.torsoX + 4)...(walk.torsoX + walk.torso.width - 4)
                canvas.lay(torso) { x in back.contains(x) ? floor - 1 : floor }
            }
            bodyItem = { _ in nil }
            headX = walk.headX
            headY = curledChinRow + 1 - layout.head.height + pose.headDrop
        }
        canvas.stamp(layout.head, x: headX, y: headY, pattern: pattern)
        let face = EffectArt.face(layout.face, eyeRow: layout.eyeRow - layout.faceRow, eyes: pose.eyes)
        canvas.stamp(face, x: headX, y: headY + layout.faceRow, pattern: pattern)
        if let (grid, origin) = EffectArt.mouth(pose.mouth, in: layout.face) {
            canvas.stamp(grid, x: headX + origin.x, y: headY + layout.faceRow + origin.y, pattern: pattern)
        }
        if case .curled = stance, breed.hasTail {
            // The tail comes round from the rump and runs along the floor
            // in front, under the chin, tip curling up by the cheek.
            let walk = WalkLayout(breed.bodyShape, layout.family)
            let left = headX + 2
            let tail = TailArt.wrapped(length: walk.torsoX + walk.torso.width - left)
            var layer = PetCanvas(width: frameSize, height: frameSize)
            layer.stamp(tail, x: left, y: frameSize - 1 - tail.height, pattern: pattern)
            canvas.lay(layer.outlined()) { _ in 0 }
        }

        func stampFace(_ item: CostumeArt.FaceItem) {
            canvas.stamp(layout.family == .cat ? item.cat : item.dog, x: headX, y: headY + layout.eyeRow - item.eyeRow)
        }
        func stampHead(_ item: CostumeArt.HeadItem) {
            canvas.stamp(item.grid(phase), x: headX, y: headY + layout.skullTop - item.sitRow)
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
            case .back, .aura:
                continue
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
        // Aura items float in the air, so they are placed in the frame and
        // follow the view (front or side), not the body.
        var aura: PetCanvas?
        let floating = auraItems(accessories)
        if !floating.isEmpty, stance != .hanging {
            var layer = PetCanvas(width: frameSize, height: frameSize)
            for item in floating {
                let placement = stance == .sitting ? item.front : item.side
                layer.stamp(placement.frames[phase % item.frameCount], x: placement.x, y: placement.y)
            }
            aura = layer
        }
        let anchor = PetPoint(x: headX + layout.head.width - 1, y: headY + layout.skullTop - pose.lift)
        // The back layer is outlined on its own and goes under the outlined
        // pet, whose outline keeps wings apart from fur of any color.
        return Composed(canvas: canvas.outlined().shifted(x: 0, y: -pose.lift),
                        back: behind.isEmpty ? nil : back.outlined().shifted(x: 0, y: -pose.lift),
                        aura: aura, headTopRight: anchor, mugTop: mugTop)
    }

    /// Draws a held prop in front of the sitting pet, centered under the
    /// head so it lines up on every body shape. The laptop stands on the
    /// floor; the mug rises from the chest to the mouth, found from the
    /// face art like an open mouth; a toy rolls away to the left along the
    /// floor. Returns the mug's top-left corner.
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
        case .toy(let roll, let bounce, let bat):
            // Cats play with yarn, dogs with a ball. Each pixel rolled turns
            // the winding or the band, so the toy reads as rolling. Only a
            // ball bounces; yarn stays on the floor.
            let yarn = layout.family == .cat
            let art = yarn ? PropArt.yarn : PropArt.ball
            let toy = art[(roll / 2) % art.count]
            let x = toyX(roll: roll, center: center)
            let y = frameSize - toy.height - (yarn ? 0 : max(bounce, 0))
            canvas.stamp(toy, x: x, y: y)
            if bat {
                // The lifted left paw, outlined all round, presses on the
                // toy's top; the leg it hangs from is hidden behind the toy.
                canvas.stamp(PropArt.paw, x: x - 1, y: y - 1, pattern: pattern)
            }
            return nil
        }
    }

    /// Left edge of the toy `roll` pixels after it starts rolling away from
    /// its spot on the floor, centered under the head; it stops at the edge.
    private static func toyX(roll: Int, center: Int) -> Int {
        max(0, center - PropArt.ball[0].width / 2 - max(roll, 0))
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
        _ breed: PetBreed, _ walk: WalkLayout, outfit: PetOutfit, accessories: [PetAccessory], wag: Int?, phase: Int
    ) -> PetCanvas {
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        canvas.stamp(walk.torso, x: walk.torsoX, y: walk.torsoY, pattern: breed.pattern)
        if breed.hasTail, let wag {
            let tail = walk.tails[wag % walk.tails.count]
            canvas.stamp(tail, x: walk.tailX, y: walk.torsoY - tail.height, pattern: breed.pattern)
        }
        for item in bodyItems(outfit: outfit, accessories: accessories) {
            canvas.stamp(walk.pick(item.frame(phase)), x: walk.torsoX, y: walk.torsoY - item.rise)
        }
        return canvas
    }

    /// The back items worn, on their own frame canvas placed from the
    /// walking torso, so a stance can move them with it.
    private static func walkingBack(_ items: [CostumeArt.BackItem], _ walk: WalkLayout, phase: Int) -> PetCanvas {
        var canvas = PetCanvas(width: frameSize, height: frameSize)
        for item in items {
            let placement = walk.pick(item)
            canvas.stamp(placement.frames[phase % item.frameCount], x: walk.torsoX + placement.x,
                         y: walk.torsoY + placement.y)
        }
        return canvas
    }

    private static func backItems(_ accessories: [PetAccessory]) -> [CostumeArt.BackItem] {
        PetAccessory.wearable(accessories).compactMap { accessory in
            if case .back(let item) = accessoryArt(accessory) { item } else { nil }
        }
    }

    /// The aura items worn (petals), in drawing order.
    private static func auraItems(_ accessories: [PetAccessory]) -> [CostumeArt.AuraItem] {
        PetAccessory.wearable(accessories).compactMap { accessory in
            if case .aura(let item) = accessoryArt(accessory) { item } else { nil }
        }
    }

    /// The outfit and neck items worn, in drawing order.
    private static func bodyItems(outfit: PetOutfit, accessories: [PetAccessory]) -> [CostumeArt.BodyItem] {
        let neck = PetAccessory.wearable(accessories).compactMap { accessory -> CostumeArt.BodyItem? in
            if case .body(let item) = accessoryArt(accessory) { item } else { nil }
        }
        return (outfitArt(outfit).map { [$0] } ?? []) + neck
    }

    /// Ticks of the item clock before every animated item worn is back on
    /// its first frame together: 1 when nothing worn animates.
    static func itemLoopLength(outfit: PetOutfit, accessories: [PetAccessory]) -> Int {
        var counts = [outfitArt(outfit)?.frameCount, outfitHood(outfit)?.frameCount]
        for accessory in PetAccessory.wearable(accessories) {
            switch accessoryArt(accessory) {
            case .body(let item): counts.append(item.frameCount)
            case .head(let item), .mask(let item, _): counts.append(item.frameCount)
            case .back(let item): counts.append(item.frameCount)
            case .aura(let item): counts.append(item.frameCount)
            case .face: break
            }
        }
        return counts.compactMap { $0 }.reduce(1) { length, count in length / gcd(length, count) * count }
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

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
        /// Drawn on the layer behind the pet.
        case back(CostumeArt.BackItem)
        /// In the air around the pet.
        case aura(CostumeArt.AuraItem)
    }

    private static func accessoryArt(_ accessory: PetAccessory) -> AccessoryArt {
        switch accessory {
        case .stethoscope: .body(CostumeArt.stethoscope)
        case .scarf: .body(CostumeArt.scarf)
        case .bowTie: .body(CostumeArt.bowTie)
        case .teamMedal: .body(CostumeArt.teamMedal)
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
        case .backwardsCap: .head(CostumeArt.backwardsCap)
        case .flameHeadband: .head(CostumeArt.flameHeadband)
        case .goldenLaurel: .head(CostumeArt.goldenLaurel)
        case .angelWings: .back(CostumeArt.angelWings)
        case .kingsCape: .back(CostumeArt.kingsCape)
        case .halo: .head(CostumeArt.halo)
        case .cherryPetals: .aura(CostumeArt.cherryPetals)
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
            case .cat, .roundCat, .sphynxCat, .foldCat:
                family = .cat
                // The British Shorthair's and Scottish Fold's plump bodies are a
                // column wider, so their tails start one later.
                let plump = shape == .roundCat || shape == .foldCat
                (bodyX, bodyY, tail, tailColumn) = (6, 20, nil, plump ? 18 : 17)
                (body, head, face) = switch shape {
                case .roundCat: (CatArt.bodyRound, CatArt.headRound, CatArt.faceRound)
                case .sphynxCat: (CatArt.bodySphynx, CatArt.headSphynx, CatArt.faceSphynx)
                case .foldCat: (CatArt.bodyFold, CatArt.headFold, CatArt.faceOpen)
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

        func pick(_ item: CostumeArt.BackItem) -> CostumeArt.BackItem.Placement {
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
                case .foldCat: (WalkArt.catTorso, WalkArt.foldCatTail)
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

        func pick(_ item: CostumeArt.BackItem) -> CostumeArt.BackItem.Placement {
            family == .longDog ? item.walkLong : item.walk
        }
    }
}

extension PetPose {
    /// Whether the left front paw is up (a gesture, or batting a toy), so
    /// the sitting body must not also show it on the floor.
    fileprivate var liftsLeftPaw: Bool {
        if gesture != nil { return true }
        if case .toy(_, _, true) = prop { return true }
        return false
    }
}

extension PetCanvas {
    /// A copy whose transparent pixels show `layer` from behind.
    func over(_ layer: PetCanvas) -> PetCanvas {
        var copy = self
        for y in 0..<height {
            for x in 0..<width where copy[x, y] == nil { copy[x, y] = layer[x, y] }
        }
        return copy
    }

    /// A copy with the particles of `layer` (each group of pixels touching
    /// side by side or corner to corner) in the free air: a particle that
    /// would cover or touch an opaque pixel is left out whole, so petals
    /// float in front of the pet without ever hiding or brushing it.
    func scattering(_ layer: PetCanvas) -> PetCanvas {
        var copy = self
        var seen = Set<Int>()
        for start in layer.pixels.indices where layer.pixels[start] != nil && !seen.contains(start) {
            var particle: [Int] = []
            var queue = [start]
            seen.insert(start)
            while let index = queue.popLast() {
                particle.append(index)
                let (x, y) = (index % width, index / width)
                for dy in -1...1 {
                    for dx in -1...1 where layer[x + dx, y + dy] != nil {
                        let neighbor = (y + dy) * width + x + dx
                        if seen.insert(neighbor).inserted { queue.append(neighbor) }
                    }
                }
            }
            let clear = particle.allSatisfy { index in
                let (x, y) = (index % width, index / width)
                return [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)].allSatisfy { self[x + $0.0, y + $0.1] == nil }
            }
            guard clear else { continue }
            for index in particle { copy[index % width, index / width] = layer.pixels[index] }
        }
        return copy
    }

    /// Paints the opaque pixels of `layer` over this canvas, moving each
    /// column down by `drop(x)` pixels: a plain offset, or a bend.
    fileprivate mutating func lay(_ layer: PetCanvas, drop: (Int) -> Int) {
        for x in 0..<layer.width {
            let dy = drop(x)
            for y in 0..<layer.height { if let role = layer[x, y] { self[x, y + dy] = role } }
        }
    }
}

extension PetItem {
    /// Ticks of the item's own animation loop (a flame flickering, a glint
    /// crossing gold), each `PetFrame.itemFrameDuration` long: 1 for an item
    /// that stays still.
    public var loopFrameCount: Int {
        switch self {
        case .outfit(let outfit): PetComposer.itemLoopLength(outfit: outfit, accessories: [])
        case .accessory(let accessory): PetComposer.itemLoopLength(outfit: .none, accessories: [accessory])
        }
    }
}
