// swift-tools-version: 6.0
import PackageDescription

// Swift 5 language mode keeps AppKit/SwiftUI interop free of strict-concurrency
// noise; the core target is still written to be Sendable-friendly.
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "NotchDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchDeck", targets: ["NotchDeck"]),
    ],
    targets: [
        // Pure, testable logic: parsers, models, stores. No AppKit/SwiftUI.
        .target(
            name: "NotchKitCore",
            // Kit manifests ship as human-editable JSON (see docs/kits.md).
            resources: [.copy("Kits/Bundled")],
            swiftSettings: swiftSettings
        ),
        // Shared AppKit/SwiftUI: design system, notch window pieces, shared
        // components and pet views. Modules build their panels from these.
        .target(
            name: "NotchKit",
            dependencies: ["NotchKitCore"],
            swiftSettings: swiftSettings
        ),
        // The app: modules, settings, system integrations, assembly.
        .executableTarget(
            name: "NotchDeck",
            dependencies: ["NotchKitCore", "NotchKit"],
            swiftSettings: swiftSettings
        ),
        // Renders pet sprite contact sheets for art review: `swift run PetGallery out/`.
        .executableTarget(
            name: "PetGallery",
            dependencies: ["NotchKitCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "NotchKitCoreTests",
            dependencies: ["NotchKitCore"],
            swiftSettings: swiftSettings
        ),
        // App-level wiring (registry, provider hub) tested through
        // `@testable import NotchDeck`.
        .testTarget(
            name: "NotchDeckTests",
            dependencies: ["NotchDeck", "NotchKitCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
