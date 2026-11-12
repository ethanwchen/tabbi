import Foundation

extension PetComposer {
    /// One step of a clip with its Radiant effects: the step's normal
    /// frames (one per tick of the items' own loop) drawn over the Radiant
    /// loop. `without(item, phase)` is the same step without that item (nil:
    /// without any item), finished like the normal frames, so each effect
    /// knows its item's pixels and where the bare pet is.
    static func radiantFrames(
        _ layout: RadiantLayout, normal: [PetCanvas], animation: PetAnimation, ceiling: Int?,
        report: inout RadiantRenderReport, without: (PetItem?, Int) -> PetCanvas
    ) -> [PetCanvas] {
        let art = RadiantArt.shared
        let normalLoop = max(1, normal.count)
        let total = lcm(normalLoop, layout.loop)
        let bare = without(nil, 0)
        var withoutItem: [PetItem: [PetCanvas]] = [:]
        for entry in layout.entries where withoutItem[entry.item] == nil {
            withoutItem[entry.item] = (0..<normalLoop).map { without(entry.item, $0) }
        }
        // Each item's pixels per phase of the items' own loop, measured once.
        let scenes = layout.entries.map { entry in
            (0..<normalLoop).map { RadiantItemScene(with: normal[$0], without: withoutItem[entry.item]![$0]) }
        }
        let geometry = RadiantGeometry(bare: bare)
        let placements = layout.entries.map { art.item($0.item)!.effect($0.intensity)!.placements[$0.placement] }
        let hanging = animation == .peekIn || animation == .peekOut
        var frames: [PetCanvas] = []
        frames.reserveCapacity(total)
        for t in 0..<total {
            let phase = t % normalLoop
            let dressed = normal[phase]
            let ticks = layout.ticks(at: t, loop: art.loop)
            let jobs = layout.entries.indices.map { n in
                RadiantRenderer.Job(placement: placements[n], tick: ticks[n], item: scenes[n][phase])
            }
            // Each frame starts with no pixel claimed; the report adds up collisions.
            var frameReport = RadiantRenderReport()
            frames.append(RadiantRenderer.render(jobs, dressed: dressed, bare: bare, geometry: geometry, hanging: hanging,
                                                 ceiling: ceiling, report: &frameReport))
            report.collisions += frameReport.collisions
        }
        return frames
    }

    private static func lcm(_ a: Int, _ b: Int) -> Int {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        return a / gcd(a, b) * b
    }
}
