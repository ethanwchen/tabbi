// swift-tools-version: 6.0
import PackageDescription

// The pure core and its tests use Swift 6, so data races there are errors.
// The AppKit/SwiftUI targets keep Swift 5 mode, whose runtime does not trap
// when an AppKit, audio or notification callback runs a closure off the main
// actor, but they get Swift 6's complete concurrency checking as warnings,
// and the build stays warning-free.
let coreSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("StrictConcurrency"),
]

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
            // Kit manifests and edition files ship as human-editable JSON
            // (see docs/kits.md and Edition.swift).
            resources: [.copy("Kits/Bundled"), .copy("Editions/BundledEditions")],
            swiftSettings: coreSettings
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
            swiftSettings: coreSettings
        ),
        // App-level wiring (registry, provider hub) tested through
        // `@testable import NotchDeck`.
        .testTarget(
            name: "NotchDeckTests",
            dependencies: ["NotchDeck", "NotchKitCore", "NotchKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
