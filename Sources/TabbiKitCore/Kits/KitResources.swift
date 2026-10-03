import Foundation

/// Finds TabbiKitCore's resource bundle without `Bundle.module`.
///
/// SwiftPM's generated accessor only looks beside the executable and in the
/// build folder, then calls `fatalError`; inside a packaged .app the bundle
/// lives in Contents/Resources (the bundle root can't hold extra files once
/// signed). This checks every place the bundle is copied to and returns
/// `nil` instead of crashing.
enum KitResources {
    static let bundleName = "Tabbi_TabbiKitCore.bundle"

    static let bundle: Bundle? = {
        // NotchDeck.app/Contents/Resources, then beside the executable
        // (`swift run`), then beside the test bundle (`swift test`).
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent(),
        ]
        return candidates.lazy
            .compactMap { $0.flatMap { Bundle(url: $0.appendingPathComponent(bundleName)) } }
            .first
    }()

    private final class BundleToken {}
}
