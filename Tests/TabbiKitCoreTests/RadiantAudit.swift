import Foundation
@testable import TabbiKitCore

/// Shared measuring for the Radiant tests: renders looks with a given
/// layout and reports, per frame and tick, what the effects changed.
enum RadiantAudit {
    /// The outfit and accessories wearing `items`.
    static func wearing(_ items: [PetItem]) -> (PetOutfit, [PetAccessory]) {
        var outfit = PetOutfit.none
        var accessories: [PetAccessory] = []
        for item in items {
            switch item {
            case .outfit(let o): outfit = o
            case .accessory(let a): accessories.append(a)
            }
        }
        return (outfit, accessories)
    }

    static func slot(_ item: PetItem) -> String {
        switch item {
        case .outfit: "outfit"
        case .accessory(let a): String(describing: a.slot)
        }
    }

    /// Every pair and triple of Radiant items that can be worn together.
    static var combinations: [[PetItem]] {
        let items = PetRadiant.eligibleItems
        var sets: [[PetItem]] = []
        for (i, a) in items.enumerated() {
            for b in items[(i + 1)...] where slot(a) != slot(b) { sets.append([a, b]) }
        }
        for (i, a) in items.enumerated() {
            for (j, b) in items.enumerated() where j > i && slot(a) != slot(b) {
                for c in items[(j + 1)...] where slot(c) != slot(a) && slot(c) != slot(b) { sets.append([a, b, c]) }
            }
        }
        return sets
    }

    struct Result {
        var maxChange = Array(repeating: 0, count: 0)
        var collisions = 0
        var eyeHits = 0
        var faceHits = 0
        var marginHits = 0
        var ceilingHits = 0
        var notes: [String] = []
    }

    /// Renders every animation of `items` on `breed` with `layout`, full size
    /// and under the notch ceiling, and checks every frame and tick.
    /// `maxChange[t]` is the most effect pixels that change from tick t-1 to
    /// t (pixels where the Radiant frame or the one before differs from the
    /// normal frame), over every frame.
    static func audit(_ items: [PetItem], layout: RadiantLayout, breed: PetBreed,
                      animations: [PetAnimation] = PetAnimation.allCases, ceilings: [Int?] = [nil, 2]) -> Result {
        let (outfit, accessories) = wearing(items)
        var result = Result(maxChange: Array(repeating: 0, count: layout.loop))
        for animation in animations {
            for ceiling in ceilings {
                var report = RadiantRenderReport()
                let radiant = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories,
                                               bond: .none, layout: layout, ceiling: ceiling, report: &report)
                var unused = RadiantRenderReport()
                let normal = PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories,
                                              bond: .none, layout: nil, ceiling: ceiling, report: &unused)
                // The bare pet as the effects saw it: under the ceiling the
                // frame moves down as far as the dressed pet needs, so the
                // full-size bare frame is moved by the same amount.
                let bare = PetComposer.clip(animation, for: breed)
                let fullNormal = ceiling == nil ? normal
                    : PetComposer.clip(animation, for: breed, outfit: outfit, accessories: accessories, bond: .none,
                                       layout: nil, ceiling: nil, report: &unused)
                result.collisions += report.collisions
                for (i, frame) in radiant.frames.enumerated() {
                    let ticks = frame.itemFrames.isEmpty ? [frame.canvas] : frame.itemFrames
                    let plainFrame = normal.frames[i]
                    let plain = plainFrame.itemFrames.isEmpty ? [plainFrame.canvas] : plainFrame.itemFrames
                    let drop = ceiling == nil ? 0 : shift(from: fullNormal.frames[i].canvas, to: plainFrame.canvas)
                    let bareCanvas = bare.frames[i].canvas.shifted(x: 0, y: drop)
                    let geometry = RadiantGeometry(bare: bareCanvas)
                    let face = geometry.faceGuard
                    let barePixels = bareCanvas.pixels
                    for (t, canvas) in ticks.enumerated() {
                        let r = canvas.pixels, n = plain[t % plain.count].pixels
                        let p = ticks[(t + ticks.count - 1) % ticks.count].pixels
                        let pn = plain[(t + ticks.count - 1) % ticks.count % plain.count].pixels
                        let width = canvas.width, height = canvas.height
                        var change = 0
                        for i in 0..<r.count {
                            if r[i] != p[i], r[i] != n[i] || p[i] != pn[i] { change += 1 }
                            guard r[i] != n[i] else { continue }
                            let x = i % width, y = i / width
                            if let under = n[i] {
                                if RadiantGeometry.eyeRoles.contains(under) { result.eyeHits += 1 }
                                if RadiantGeometry.faceRoles.contains(under) { result.faceHits += 1 }
                                if under == barePixels[i], face?.contains(x, y) == true { result.faceHits += 1 }
                            } else {
                                if x < 1 || x > width - 2 || y < 1 || y > height - 2 { result.marginHits += 1 }
                                if let ceiling, y < ceiling, r[i] != nil { result.ceilingHits += 1 }
                            }
                        }
                        let slot = t % layout.loop
                        if ticks.count > 1, change > result.maxChange[slot] { result.maxChange[slot] = change }
                    }
                }
            }
        }
        return result
    }

    /// How far a frame moved down under the notch ceiling.
    static func shift(from full: PetCanvas, to shown: PetCanvas) -> Int {
        let pet = full.pixels.indices.filter { full.pixels[$0].map { !RadiantGeometry.effectRoles.contains($0) } ?? false }
        func score(_ d: Int) -> Int {
            pet.filter { i in
                let j = i + d * full.width
                return j < shown.pixels.count && shown.pixels[j] == full.pixels[i]
            }.count
        }
        return (0...12).max { score($0) < score($1) } ?? 0
    }

    static func single(_ item: PetItem, _ intensity: PetRadiantIntensity, placement: Int) -> RadiantLayout {
        RadiantLayout(entries: [.init(item: item, intensity: intensity, placement: placement, turn: nil)], cycles: 1)
    }
}
