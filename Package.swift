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
    name: "Tabbi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tabbi", targets: ["Tabbi"]),
    ],
    dependencies: [
        // The one third-party dependency: secure in-place app updates (EdDSA
        // signed archives, an installer that swaps the bundle and relaunches).
        // Why it is worth it: docs/research/installer.md, section 3.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Pure, testable logic: parsers, models, stores. No AppKit/SwiftUI.
        .target(
            name: "TabbiKitCore",
            // Kit manifests and edition files ship as human-editable JSON
            // (see docs/kits.md and Edition.swift).
            resources: [.copy("Kits/Bundled"), .copy("Editions/BundledEditions")],
            swiftSettings: coreSettings
        ),
        // Shared AppKit/SwiftUI: design system, notch window pieces, shared
        // components and pet views. Modules build their panels from these.
        .target(
            name: "TabbiKit",
            dependencies: ["TabbiKitCore"],
            swiftSettings: swiftSettings
        ),
        // The app: modules, settings, system integrations, assembly.
        .executableTarget(
            name: "Tabbi",
            dependencies: ["TabbiKitCore", "TabbiKit", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: swiftSettings,
            // scripts/assemble.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // Renders pet sprite contact sheets for art review: `swift run PetGallery out/`.
        .executableTarget(
            name: "PetGallery",
            dependencies: ["TabbiKitCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TabbiKitCoreTests",
            dependencies: ["TabbiKitCore"],
            swiftSettings: coreSettings
        ),
        // App-level wiring (registry, provider hub) tested through
        // `@testable import Tabbi`.
        .testTarget(
            name: "TabbiTests",
            dependencies: ["Tabbi", "TabbiKitCore", "TabbiKit"],
            swiftSettings: swiftSettings
        ),
    ]
)
