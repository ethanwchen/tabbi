import CoreGraphics
import Foundation

/// Turns composed pet frames into crisp `CGImage`s.
///
/// Scaling is done here by writing each sprite pixel as an exact
/// `scale`×`scale` block, so the result is pixel-perfect nearest-neighbor no
/// matter how the image is drawn later. Results are cached because the same
/// few frames repeat forever in an idle animation.
public final class PetRenderer: @unchecked Sendable {
    private struct Key: Hashable {
        let canvas: PetCanvas
        let palette: PetPalette
        let scale: Int
    }

    private let lock = NSLock()
    private var cache: [Key: CGImage] = [:]
    private var order: [Key] = []
    private let capacity: Int

    /// `capacity` bounds memory: a plain pet uses roughly 40 distinct
    /// frames. An animated costume item multiplies that by its loop length
    /// (a 24-tick aura over a long clip can pass 256), and then the oldest
    /// frames simply render again, which a 32x32 sprite makes cheap. A
    /// bigger cache would hold many full-scale bitmaps for little gain.
    public init(capacity: Int = 256) {
        self.capacity = capacity
    }

    public static let shared = PetRenderer()

    /// Number of images currently cached (exposed for tests).
    public var cachedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cache.count
    }

    /// Renders `canvas` with `palette`, scaled up by an integer factor.
    public func image(for canvas: PetCanvas, palette: PetPalette, scale: Int = 1) -> CGImage? {
        let key = Key(canvas: canvas, palette: palette, scale: max(1, scale))
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let image = Self.render(canvas, palette: palette, scale: key.scale) else { return nil }

        lock.lock(); defer { lock.unlock() }
        if cache[key] == nil {
            cache[key] = image
            order.append(key)
            if order.count > capacity { cache[order.removeFirst()] = nil }
        }
        return cache[key]
    }

    /// Uncached rendering into premultiplied RGBA.
    public static func render(_ canvas: PetCanvas, palette: PetPalette, scale: Int = 1) -> CGImage? {
        let scale = max(1, scale)
        let width = canvas.width * scale, height = canvas.height * scale
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colors = canvas.colors(using: palette)
        for sy in 0..<canvas.height {
            for sx in 0..<canvas.width {
                guard let color = colors[sy * canvas.width + sx] else { continue }
                let a = UInt16(color.alpha)
                let premultiplied = [color.red, color.green, color.blue].map { UInt8(UInt16($0) * a / 255) }
                for dy in 0..<scale {
                    var offset = ((sy * scale + dy) * width + sx * scale) * 4
                    for _ in 0..<scale {
                        bytes[offset] = premultiplied[0]
                        bytes[offset + 1] = premultiplied[1]
                        bytes[offset + 2] = premultiplied[2]
                        bytes[offset + 3] = color.alpha
                        offset += 4
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
