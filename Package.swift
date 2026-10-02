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
        .target(name: "NotchKitCore", swiftSettings: swiftSettings),
        // The app: notch window, SwiftUI views, system integrations.
        .executableTarget(
            name: "NotchDeck",
            dependencies: ["NotchKitCore"],
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
    ]
)
