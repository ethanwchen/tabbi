# The Tabbi widget

Tabbi has a widget for the desktop and Notification Center, in small and medium sizes.
It shows the pet in its outfit, today's streak and focus minutes, and the time left while a timer runs.
This page says how it is built, signed and shipped, since Tabbi is a SwiftPM app with no Xcode project.

## How it is built

The widget is the `TabbiWidget` executable target in `Package.swift` (sources in `Sources/TabbiWidget`), so `swift build` builds it with the app and it shares `TabbiKitCore`, including the pet renderer.
`scripts/assemble.sh` wraps the binary in `Tabbi.app/Contents/PlugIns/TabbiWidget.appex` for every edition.

What makes a plain SwiftPM binary a working widget extension:

- The linker entry point is `_NSExtensionMain` (`-Xlinker -e -Xlinker _NSExtensionMain`), the same as Xcode's App Extension product type.
  Foundation's extension main sets up the connection to `chronod` and then runs the `@main` `WidgetBundle`.
  With the default Swift entry point the extension launches, logs `main [WidgetBundle]` and exits at once, and the gallery never lists it.
- The target compiles and links with `-application-extension`, so it can only call API that extensions may use.
- The extension's `Info.plist` (written by `assemble.sh`) has `CFBundlePackageType` `XPC!`, `NSExtension` with `NSExtensionPointIdentifier` `com.apple.widgetkit-extension`, the bundle id `<app id>.Widget`, and the app's version and build numbers, which macOS and App Store Connect expect to match the app's.
- The extension runs in the App Sandbox (macOS runs no widget outside it), so it loads the pet art from its own copy of `Tabbi_TabbiKitCore.bundle` in `TabbiWidget.appex/Contents/Resources`.

The views live in the `TabbiWidgetUI` library target, apart from the extension, so `Tests/TabbiWidgetUITests` can render them.
The extension itself only reads the shared state and builds the timeline.

An Xcode project driven from the scripts would work too, but it would duplicate the package's targets and settings in a second build system.
The SwiftPM target keeps one build, one set of compiler settings and the existing scripts.

## What it shows and when it updates

The app writes a `WidgetState` (`TabbiKitCore/Widget/WidgetState.swift`) as versioned JSON into the App Group container, `WidgetState.appGroup`.
It holds the pet as dressed in the Closet, today's focus minutes, the streak and the running clock.
Before the app has written one, the widget shows the starter cat with no focus yet, and the gallery shows sample data.

- Small: the pet, a streak badge, and the running clock or today's minutes.
- Medium: the pet and its name on a tile, the clock or today's minutes, and chips for the streak and (while a timer runs) today's minutes.
- A running clock is WidgetKit's live date text (`Text(timerInterval:)`), so it counts every second with no reloads.
  A paused clock shows its frozen time.
- Colors are the site's warm palette: a cream card in light mode and a cocoa one in dark mode.
- A click opens Tabbi.

The timeline has an entry now, one when a countdown ends and one at the next midnight, with the `.atEnd` policy.
Each entry works its values out from the state at its own date (`minutes(at:)`, `streak(at:)`, `timer(at:)`), so minutes reset at midnight and a finished countdown goes away even while the app is not running.
Everything else reloads only when the app writes a change; `WidgetStateFile.write` reports whether anything changed.

`swift test --filter TabbiWidgetUITests` renders every state at the real widget sizes in light and dark mode.
Set `TABBI_WIDGET_SNAPSHOTS=<folder>` to also write the PNGs there and look at them.

## Signing

The extension is signed on its own, before the app, with `packaging/TabbiWidget.entitlements`:

- `com.apple.security.app-sandbox`: required for a widget extension.
- `com.apple.security.application-groups` with `B9VRALHV8S.dev.tabbi.Tabbi`: the shared container the app writes the widget's state into.

| Build | Script | Extension signature |
| --- | --- | --- |
| Local | `scripts/bundle.sh` | ad-hoc, with the widget entitlements |
| Direct download | `scripts/release.sh` | Developer ID, Hardened Runtime, the widget entitlements |
| Direct, `--adhoc` | `scripts/release.sh --adhoc` | ad-hoc, with the widget entitlements |
| Mac App Store | `scripts/release-appstore.sh` | Apple Distribution, the widget entitlements |

An ad-hoc signed extension loads and renders in the widget gallery; WidgetKit does not require a Developer ID or a provisioning profile.

## Seeing it locally

1. `scripts/bundle.sh` builds `build/Tabbi.app` with the extension inside.
2. Open the app once from where it will stay (macOS registers an app's extensions when it launches or is registered with LaunchServices).
3. Right-click the desktop, choose Edit Widgets and search for Tabbi.

`pluginkit -m -v -p com.apple.widgetkit-extension | grep -i tabbi` shows whether macOS registered the extension.
`log show --last 5m --predicate 'process == "chronod"' | grep -i tabbi` shows what `chronod` asked the extension for and any error.
Two copies of the app with the same bundle id (an installed release and a local build) compete for the same extension id, so test a local build with the installed copy quit, or give the copy its own ids.

## Still to do

- The App Store edition: App Store Connect expects the extension to embed its own provisioning profile for the App ID `dev.tabbi.Tabbi.Widget` with the app group, and `release-appstore.sh` does not embed one yet.
- The app side: a writer that fills `WidgetState` from the focus clock, the Closet pet and the activity log, and calls `WidgetCenter.reloadTimelines` when `write` reports a change.
  The app's own entitlements need the same app group.
