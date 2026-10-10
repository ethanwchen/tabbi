// swift-tools-version: 6.0
import Foundation
import PackageDescription

// The Mac App Store build (scripts/release-appstore.sh, docs/appstore.md):
// `TABBI_APPSTORE=1 swift build` compiles the app with the APPSTORE flag and
// leaves out what App Review refuses in a sandboxed app: Sparkle (not even
// linked), install hygiene (it moves the app and reads a private API) and
// the modules that run the claude CLI. Everything else is the same code.
// Pass `--only-use-versions-from-resolved-file` too: without Sparkle the
// manifest has no dependencies, and SwiftPM would delete Package.resolved.
let appStore = ProcessInfo.processInfo.environment["TABBI_APPSTORE"] == "1"

// The pure core and its tests use Swift 6, so data races there are errors.
// The AppKit/SwiftUI targets keep Swift 5 mode, whose runtime does not trap
// when an AppKit, audio or notification callback runs a closure off the main
// actor, but they get Swift 6's complete concurrency checking as warnings,
// and the build stays warning-free.
let coreSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("StrictConcurrency"),
] + (appStore ? [.define("APPSTORE")] : [])

/// Sources the App Store build leaves out, relative to Sources/Tabbi. Their
/// few call sites sit behind `#if !APPSTORE`, and `ModuleList` drops the
/// modules' lines.
let appStoreExcludedSources = [
    "Updates",
    "InstallHygiene",
    "Modules/ClaudeUsage",
]

let package = Package(
    name: "Tabbi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tabbi", targets: ["Tabbi"]),
    ],
    // The one third-party dependency: secure in-place app updates (EdDSA
    // signed archives, an installer that swaps the bundle and relaunches).
    // Why it is worth it: docs/research/installer.md, section 3. The App
    // Store updates the app itself, so that build has none.
    dependencies: appStore ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Pure, testable logic: parsers, models, stores. No AppKit/SwiftUI.
        .target(
            name: "TabbiKitCore",
            // Kit manifests, edition files, pet art, themes and seasonal
            // events ship as human-editable JSON (see docs/kits.md,
            // Edition.swift, PetArt.swift, ThemeCatalog.swift and
            // SeasonalEventCatalog.swift).
            resources: [
                .copy("Kits/Bundled"), .copy("Editions/BundledEditions"), .copy("Pets/PetArt"),
                .copy("Themes/themes.json"), .copy("StudyMethods/study-methods.json"),
                .copy("Events/events.json"),
            ],
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
            dependencies: ["TabbiKitCore", "TabbiKit"]
                + (appStore ? [] : [.product(name: "Sparkle", package: "Sparkle")]),
            exclude: appStore ? appStoreExcludedSources : [],
            swiftSettings: swiftSettings,
            // scripts/assemble.sh puts Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // The desktop and Notification Center widget (docs/widget.md).
        // scripts/assemble.sh wraps this binary in
        // Tabbi.app/Contents/PlugIns/TabbiWidget.appex. An app extension
        // starts in Foundation's NSExtensionMain, which hands control to the
        // @main WidgetBundle; Xcode links every extension this way, and
        // without it the process exits before WidgetKit asks for widgets.
        .executableTarget(
            name: "TabbiWidget",
            dependencies: ["TabbiKitCore", "TabbiWidgetUI"],
            swiftSettings: swiftSettings + [.unsafeFlags(["-application-extension"])],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"]),
            ]
        ),
        // The widget's views, apart from the extension so tests can render
        // them. Extension-safe API only, like the extension itself.
        .target(
            name: "TabbiWidgetUI",
            dependencies: ["TabbiKitCore"],
            swiftSettings: swiftSettings + [.unsafeFlags(["-application-extension"])]
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
        .testTarget(
            name: "TabbiWidgetUITests",
            dependencies: ["TabbiWidgetUI", "TabbiKitCore"],
            swiftSettings: swiftSettings
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
