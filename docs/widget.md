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
Before the app has written one, or when the widget cannot read it, the widget shows the starter cat and "Open Tabbi to start" instead of numbers, and the gallery shows sample data.

- Small: the pet, a streak badge, and the running clock or today's minutes.
- Medium: the pet and its name on a tile, the clock or today's minutes, and chips for the streak and (while a timer runs) today's minutes.
- A running clock is WidgetKit's live date text (`Text(timerInterval:)`), so it counts every second with no reloads.
  A paused clock shows its frozen time.
- Colors are the site's warm palette: a cream card in light mode and a cocoa one in dark mode.
  They are plain sRGB values picked from the view's color scheme, not dynamic `NSColor`s, whose appearance closure does not survive the archive WidgetKit hands to the process that draws the widget.
- In the tinted (accented) and vibrant rendering modes the system removes the background and draws the content in one color or as vibrancy, so the views switch to the hierarchical styles (`.primary`, `.secondary`, `.quaternary`) and faint tiles there, and the pet is drawn desaturated.
  With the full-color palette, the opaque cream tiles would turn into solid blocks over the pet and its name, and dark text would vanish.
- A click opens Tabbi.

### Where the state comes from

`WidgetStateWriter` (`Sources/Tabbi/Widget`) keeps the file in step with the app, created once by `AppServices`:

- The pet is the Closet's (`context.studyPet`), so a new outfit or name reaches the widget.
- The clock is the shared focus clock (`ProviderSnapshot.focus`), whichever module runs it.
- Today's minutes and the streak come from the activity log: every `focus.completed` record counts, stopped stretches included, as in Wrap Up.
  The streak walks back one day file at a time and stops at the first day without focus (`WidgetState.focusDays`).

It writes when the clock starts, pauses or ends, the pet's look changes, or focus is logged, coalescing what one event changes into one write.
When `WidgetStateFile.write` reports a change it calls `WidgetCenter.reloadTimelines(ofKind:)`, and once more on the first write of every launch even when nothing changed, so a widget that WidgetKit left stale or blank after an update or a move is redrawn when the user opens Tabbi.
Demo and snapshot runs write nothing, so the real widget never shows sample data.

The timeline has an entry now, one when a countdown ends and one at the next midnight, with the `.atEnd` policy.
Each entry works its values out from the state at its own date (`minutes(at:)`, `streak(at:)`, `timer(at:)`), so minutes reset at midnight and a finished countdown goes away even while the app is not running.
Everything else reloads only when the app writes a change; `WidgetStateFile.write` reports whether anything changed.

The widget reads the file leniently (`WidgetState.init(from:)`): a field it cannot read, such as a breed or timer phase from a newer build of the other edition, falls back on its own, and a newer `schemaVersion` reads as it is.
A missing, empty or corrupt file shows "Open Tabbi to start", and the app rewrites it on its next launch.

`swift test --filter TabbiWidgetUITests` renders every state at the real widget sizes in light and dark mode and in the full-color, tinted and vibrant modes.
Set `TABBI_WIDGET_SNAPSHOTS=<folder>` to also write the PNGs there and look at them.

## Signing

The extension is signed on its own, before the app, with `packaging/TabbiWidget.entitlements`:

- `com.apple.security.app-sandbox`: required for a widget extension.
- `com.apple.security.application-groups` with `B9VRALHV8S.dev.tabbi.Tabbi`: the shared container the app writes the widget's state into.

| Build | Script | Extension signature |
| --- | --- | --- |
| Local | `scripts/bundle.sh` | ad-hoc (or `SIGN_IDENTITY`), with the widget entitlements |
| Direct download | `scripts/release.sh` | Developer ID, Hardened Runtime, the widget entitlements |
| Direct, `--adhoc` | `scripts/release.sh --adhoc` | ad-hoc, with the widget entitlements |
| Mac App Store | `scripts/release-appstore.sh` | Apple Distribution, the widget entitlements, its own embedded profile |

The app is signed with the same app group in both of its entitlements files (`Tabbi.entitlements` and `Tabbi-AppStore.entitlements`), and `bundle.sh` signs the local build with `Tabbi.entitlements` too.
Without it, macOS 15 and later may ask the user before an app may write to another app's group container.

An ad-hoc signed extension loads and renders in the widget gallery; WidgetKit does not require a Developer ID or a provisioning profile.
An ad-hoc signed app with the entitlement writes the shared file with no prompt.
An ad-hoc signed widget cannot read it, though.
For a sandboxed process, macOS 15 and later only open a team-prefixed group container when the signature proves the team (the "team ID prefix" check), and an ad-hoc signature has no team.
Any other process would get the "access data from other apps" prompt, but macOS never shows it for a widget, so the read is denied and the widget shows its empty state ("0 min, No focus yet") and the starter pet.
The log says so:

```
tccd: Preventing prompt from Avocado widget ... for service kTCCServiceSystemPolicyAppData
kernel: (Sandbox) System Policy: TabbiWidget(...) deny(1) file-read-data .../Group Containers/B9VRALHV8S.dev.tabbi.Tabbi/WidgetState.json
```

So the widget shows real data only in builds signed by team `B9VRALHV8S`: `release.sh` (Developer ID), `release-appstore.sh` (Apple Distribution), or a local build made with `SIGN_IDENTITY="Developer ID Application" scripts/bundle.sh`.
A widget signed by team `B9VRALHV8S` passes that check (`containermanagerd: Signature passed strict scrutiny; test = team ID prefix`) and reads the file with no denial.
`release.sh --adhoc` and a plain `bundle.sh` are fine for checking the layout in the gallery, which always shows the sample.

## Seeing it locally

1. `scripts/bundle.sh` builds `build/Tabbi.app` with the extension inside.
   Add `SIGN_IDENTITY="Developer ID Application"` to see the app's real data on the desktop and not only the gallery sample (see Signing).
2. Open the app once from where it will stay (macOS registers an app's extensions when it launches or is registered with LaunchServices).
3. Right-click the desktop, choose Edit Widgets and search for Tabbi.

`pluginkit -m -v -p com.apple.widgetkit-extension | grep -i tabbi` shows whether macOS registered the extension.
`log show --last 5m --predicate 'process == "chronod"' | grep -i tabbi` shows what `chronod` asked the extension for and any error.
Two copies of the app with the same bundle id (an installed release and a local build) compete for the same extension id, so test a local build with the installed copy quit, or give the copy its own ids.

## The App Store edition

App Store Connect expects every executable bundle to embed its own provisioning profile, so the extension has one next to the app's.
`scripts/release-appstore.sh` checks both before building and embeds the widget's as `TabbiWidget.appex/Contents/embedded.provisionprofile`:

1. In the Apple Developer portal, register the App ID `dev.tabbi.Tabbi.Widget` (explicit, macOS).
   It needs no capabilities: the team-prefixed app group is granted by the team id, not by the profile.
2. Create a **Mac App Store Connect** profile for it with the Apple Distribution certificate.
3. Save it as `packaging/TabbiWidget-AppStore.provisionprofile` (gitignored), or point `WIDGET_PROFILE` at it.

The script signs the extension with `packaging/TabbiWidget.entitlements` plus the application and team identifiers from that profile, as it does for the app.
It refuses a profile for another bundle id, a development or Developer ID profile, and an expired one.
The direct download needs no profile for the extension.

## Troubleshooting a blank or white widget

WidgetKit draws a blank (or white, in light mode) widget when the extension crashes, when it cannot reach the extension, or when the content draws nothing it can show.
These are the causes found so far and what guards against each.

| Cause | When | Guard |
| --- | --- | --- |
| A calendar other than Gregorian | `PlannerDayKey.startDate` trapped on days that are not a Gregorian month and day (Heshvan 29 is `5787-02-29`; also Persian, Islamic, Buddhist and Japanese calendars on some days), which crashed `getTimeline` for that day only | `startDate` never traps; `changeDates` works from the date, not the day key (`PlannerDayKeyCalendarTests`) |
| Tinted or vibrant rendering | The desktop while an app is in front (macOS 14 and later), or the monochrome and tinted widget styles of macOS 26 and later: opaque tiles became solid blocks and dark text vanished | Hierarchical styles and faint fills outside full color (`testTintedAndVibrantModesNeverFlattenIntoSolidBlocks`) |
| Two copies installed | The direct download and the App Store edition share the extension id `dev.tabbi.Tabbi.Widget`, macOS registers only one, and each switch between them makes `chronod` drop the widget's cached description until it reloads it (often only at the next login) | The app reloads the widget on every launch and tells the user once about another copy in an Applications folder (`DuplicateCopyCheck`) |
| A missing, corrupt or newer state file | First run, a write cut short, or the other edition at another version | Lenient decoding and the "Open Tabbi to start" state, never an error |
| Missing pet art | A damaged install: loading missing art stops the process | The widget checks `WidgetState.canDrawPet` and draws a paw print instead; `KitResources` also looks in the containing app |
| An ad-hoc signed local build | The sandbox denies the team-prefixed group container (see Signing) | "Open Tabbi to start", and the log says why |

Things checked and ruled out: the container background is set on every view (`.containerBackground`), the extension's memory stays far under its limit (a few small sprites; the art is 80 KB), and the countdown uses live date text, so it needs no reloads.

To look into a report on a Mac:

1. `pluginkit -m -v -p com.apple.widgetkit-extension | grep -i tabbi` lists the registered extension; more than one line, or a path such as `/Applications/Tabbi 2.app`, means two copies.
2. `log show --last 1d --predicate 'subsystem == "dev.tabbi.widget"'` shows what the widget read: "No shared state yet", "Could not read the shared state: ..." or "No App Group container".
3. `log show --last 1d --predicate 'process == "chronod"' | grep -i tabbi` shows extension switches ("Updated extension ... now with pluginUUID"), purged descriptors and launch errors.
4. `ls ~/Library/Logs/DiagnosticReports | grep -i TabbiWidget` lists extension crashes.
5. The calendar in System Settings > General > Language & Region, and whether the widget looks blank only while an app is in front (vibrant mode) or all the time.

Removing the widget and adding it again, or logging out and in, makes `chronod` load the extension afresh, which is why a restart seems to fix it.
