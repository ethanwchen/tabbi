import SwiftUI
import TabbiKitCore

/// One camera picture: a `PetCamShot` drawn by `PetCamScene` at whole
/// device pixels per sprite pixel, never resized, so nothing is
/// interpolated (as `PixelPet` draws the pet). The wide shot is as large as
/// the width allows in whole pixels, and a spot camera (half the room
/// across) or a close-up (a quarter) draws at exactly two or four times its
/// scale, so every framing fills the same frame with the same square pixels.
/// The monitor's scanlines run along the wide shot's pixel rows, the same
/// on every pixel, so they never beat against the art.
struct FeedView: View {
    let shot: PetCamShot
    let pet: PetProfile
    let daylight: Bool
    /// Points available across; the picture snaps down to whole pixels.
    let width: CGFloat
    var tick = 0
    var scanlines = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let size = PetCamScene.size(of: shot.framing)
        let scale = Self.devicePixels(spriteWidth: size.width, width: width, displayScale: displayScale)
        let points = CGFloat(scale) / max(displayScale, 1)
        Group {
            if let image = FeedCache.shared.image(shot: shot, pet: pet, daylight: daylight, tick: tick, scale: scale) {
                Image(decorative: image, scale: max(displayScale, 1))
                    .interpolation(.none)
            } else {
                CCTV.screen
            }
        }
        .frame(width: CGFloat(size.width) * points, height: CGFloat(size.height) * points)
        .overlay {
            if scanlines {
                PixelScanlines(rowDevicePixels: Self.wideDevicePixels(width: width, displayScale: displayScale))
            }
        }
    }

    /// Whole device pixels per sprite pixel of the wide shot at `width` points.
    static func wideDevicePixels(width: CGFloat, displayScale: CGFloat) -> Int {
        let wide = CGFloat(PetCamScene.size(of: .wide).width)
        return max(1, Int((width * max(displayScale, 1) / wide).rounded(.down)))
    }

    /// Whole device pixels per sprite pixel for a picture `spriteWidth`
    /// pixels wide in `width` points: the wide shot's scale times how much
    /// narrower the crop is (two for a spot camera, four for a close-up).
    static func devicePixels(spriteWidth: Int, width: CGFloat, displayScale: CGFloat) -> Int {
        let zoom = max(1, PetCamScene.size(of: .wide).width / max(spriteWidth, 1))
        return wideDevicePixels(width: width, displayScale: displayScale) * zoom
    }

    /// The picture's size in points for `framing` at `width`.
    static func pictureSize(_ framing: PetCamShot.Framing, width: CGFloat, displayScale: CGFloat) -> CGSize {
        let size = PetCamScene.size(of: framing)
        let points = CGFloat(devicePixels(spriteWidth: size.width, width: width, displayScale: displayScale))
            / max(displayScale, 1)
        return CGSize(width: CGFloat(size.width) * points, height: CGFloat(size.height) * points)
    }
}

/// The last few camera pictures, so a still that stays on screen (or a
/// wobble that rocks back) is drawn once. Full-size pictures are a few
/// megabytes each, so only a handful are kept.
@MainActor
final class FeedCache {
    static let shared = FeedCache()

    private struct Key: Hashable {
        let shot: PetCamShot
        let pet: PetProfile
        let daylight: Bool
        let tick: Int
        let scale: Int
    }

    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let capacity = 8

    func image(shot: PetCamShot, pet: PetProfile, daylight: Bool, tick: Int, scale: Int) -> CGImage? {
        let key = Key(shot: shot, pet: pet, daylight: daylight, tick: tick, scale: scale)
        if let hit = images[key] { return hit }
        guard let image = PetCamScene.frame(shot, pet: pet, daylight: daylight, tick: tick).image(scale: scale) else {
            return nil
        }
        images[key] = image
        order.append(key)
        if order.count > capacity { images[order.removeFirst()] = nil }
        return image
    }

    func removeAll() {
        images.removeAll()
        order.removeAll()
    }

    /// Draws `shots` off the main actor and keeps them, so a tape's next
    /// still is ready before its cut instead of rendering during it.
    func prefetch(_ shots: [(shot: PetCamShot, daylight: Bool)], pet: PetProfile, scale: Int) {
        let missing = shots.filter { images[Key(shot: $0.shot, pet: pet, daylight: $0.daylight, tick: 0, scale: scale)] == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            for job in missing {
                guard let image = PetCamScene.frame(job.shot, pet: pet, daylight: job.daylight).image(scale: scale) else {
                    continue
                }
                await MainActor.run {
                    let key = Key(shot: job.shot, pet: pet, daylight: job.daylight, tick: 0, scale: scale)
                    guard FeedCache.shared.images[key] == nil else { return }
                    FeedCache.shared.images[key] = image
                    FeedCache.shared.order.append(key)
                    if FeedCache.shared.order.count > FeedCache.shared.capacity {
                        FeedCache.shared.images[FeedCache.shared.order.removeFirst()] = nil
                    }
                }
            }
        }
    }
}

/// A monitor's scanlines on the picture's pixel grid: one device pixel of
/// shade at the foot of every wide-shot pixel row, so every sprite pixel of
/// every framing carries the same lines and stays crisp.
struct PixelScanlines: View {
    let rowDevicePixels: Int
    var opacity = 0.22
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let scale = max(displayScale, 1)
            let line = 1 / scale
            let period = CGFloat(max(rowDevicePixels, 2)) / scale
            var y = period - line
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: line)), with: .color(.black))
                y += period
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fine film grain over the picture: specks of two device pixels, placed on
/// whole device pixels so none is smeared, that change a few times a
/// second. Still under Reduce Motion.
struct Grain: View {
    var amount = 0.10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let frame = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.12)
            Canvas { canvas, size in
                var roll = PetCamRandom(seed: UInt64(truncatingIfNeeded: frame), stream: "grain")
                let scale = max(displayScale, 1)
                let dot = 2 / scale
                let count = Int(size.width * size.height / 260)
                for _ in 0..<count {
                    let x = (roll.unit() * size.width * scale).rounded(.down) / scale
                    let y = (roll.unit() * size.height * scale).rounded(.down) / scale
                    let light = roll.unit() > 0.5
                    canvas.fill(Path(CGRect(x: x, y: y, width: dot, height: dot)),
                                with: .color(light ? .white.opacity(amount) : .black.opacity(amount * 1.6)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
