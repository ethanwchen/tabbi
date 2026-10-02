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
        .target(name: "NotchDeckCore", swiftSettings: swiftSettings),
        // The app: notch window, SwiftUI views, system integrations.
        .executableTarget(
            name: "NotchDeck",
            dependencies: ["NotchDeckCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "NotchDeckCoreTests",
            dependencies: ["NotchDeckCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
