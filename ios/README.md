# Tabbi for iPhone

This folder holds the iPhone app's foundation: the study timer, the pet, points, the Live Activity and phase-end notifications, all driven by the Mac app's own `TabbiKitCore`.
It is deliberately concept independent, so the game layer the iPhone app will be built around can land on top of it without changing how sessions run or how points are paid.

## What is here

- `project.yml` is the XcodeGen definition of the project, and the generated `TabbiPhone.xcodeproj` is not checked in.
- `App/` is the app target (`dev.tabbi.ios`): the `StudyEngine`, its store and persistence, the phase-end notifications, the Live Activity controller, the animated pet and the one screen.
- `LiveActivityExtension/` is the widget extension (`dev.tabbi.ios.LiveActivity`) that draws the Lock Screen Live Activity and the Dynamic Island.
- `Shared/` is compiled into both: the activity's attributes, the whole-pixel pet view and the tone colors.
- `Tests/` is the unit test target (`dev.tabbi.ios.Tests`), which replays the golden fixtures in `shared/fixtures` on the iPhone.
- `UITests/` drives the app like a person for the end-to-end check, and `e2e.sh` runs it and takes the screenshots.

The bundle ids sit under the Mac app's team (`B9VRALHV8S`) and its `dev.tabbi` prefix.

## How it uses TabbiKitCore

The root `Package.swift` lists iOS 26 as a platform and offers `TabbiKitCore` as a library product, which is the only target ever built for iOS.
The few places in the core that start a subprocess (`StreamingProcess`, `AIExecutableLocator`, `ClaudePathCheck`, `FocusShortcutRunner`) keep their Mac code unchanged behind `#if os(macOS)` and report "unavailable" on iOS, and the Mac-only window-level rule in `NotchVisibility` is compiled for the Mac alone.

- The timer is `StudySession`, the Study tab's wall-clock state machine, with the methods from `study-methods.json` (all of them except the Anki sprint, which counts cards from AnkiConnect on the Mac).
- Points are `PetCloset`'s: finished blocks through `credit(from:to:at:)` against the saved `creditedFocusCount`, and focus cut short through `credit(_:)` from the phase's activity record, exactly as the Mac pays the Study tab.
- The one difference is timing, not amount: the Mac hides an idle session from the crediting clock, so a block that ends into an idle phase (a Timer, or a focus and break that both ran out while the app slept) is paid at the next start, while the iPhone observes the idle session too and pays it at once (see the `StudyEngine` doc comment).
- The pet is drawn by `PetRenderer` at whole device pixels and animated by `PetAnimator`, so it types through a focus block, sips coffee on a break and hops when a block is done.
- The session, the pet's `PetSave` and the `StudyLog` are three versioned JSON files in Application Support/Tabbi, and a file that cannot be read is never overwritten.

Because time comes from stored dates, a session keeps running while the app is suspended or killed.
On the next launch or return to the foreground, the engine applies every phase end that passed, each at its real end time, and pays for it once.
While the app is away, the Live Activity counts down by itself with `Text(timerInterval:)` and goes stale at the phase end, and a local notification says the phase is done.

## Generate, build, test and run

Install XcodeGen once with `brew install xcodegen`, then generate the project from the repo root:

```sh
xcodegen generate --spec ios/project.yml
```

Build for a simulator (Xcode 27 with the iOS 26.5 or 27 simulator runtime):

```sh
xcodebuild build -project ios/TabbiPhone.xcodeproj -scheme TabbiPhone \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Run the unit tests the same way with `test` instead of `build`.
The first build fetches Sparkle, because Xcode resolves the whole root package, even though no iOS target links it.

To run the app, boot a simulator, install the built app and launch it:

```sh
xcrun simctl boot 'iPhone 17 Pro'
xcrun simctl install booted <DerivedData>/Build/Products/Debug-iphonesimulator/TabbiPhone.app
xcrun simctl launch booted dev.tabbi.ios
```

Passing `-TabbiResetState` at launch starts from a fresh install's state, and `-AppleLanguages '(de)'` shows another of the 12 languages.

## End-to-end check

```sh
ios/e2e.sh ~/Developer/Tabbi/runs/iphone-app/screens/foundation
```

The script runs `FoundationFlowTests` on the iPhone 17 Pro simulator: it picks the Timer, sets it to one minute and starts it, locks the phone, looks at the Lock Screen Live Activity, unlocks to see the Dynamic Island compact and expanded, then locks again until the minute runs out.
At each step it takes a screenshot with `xcrun simctl io <device> screenshot --mask=black`, since the default mask leaves the inside of the Dynamic Island transparent.
Uninstall the app first (`xcrun simctl uninstall booted dev.tabbi.ios`) to see the notification and Live Activity permission prompts of a first run.

## Design

The screen follows the ADA SwiftUI doctrine and Apple's HIG (both read as references only): one hero per screen, which is the countdown in a large rounded monospaced numeral, with the pet's spot on the desk as the scene behind it.
Color is information: amber is focus (the Study tab's accent on the Mac), teal is a break, and a quiet neutral is idle, always paired with the phase's name.
The HUD and the controls float on Liquid Glass, the system's own `glassEffect` and glass button styles, over a tinted paper or near-black canvas that follows light and dark mode.
Haptics follow events, not taps: start, stop, a phase that runs out, and a change of method.
Every string on screen comes from TabbiKitCore's String Catalog, so it shows in all 12 languages with no new translations, and the layout wraps rather than truncates up to the largest accessibility text size.

## Planned Mac connection

Nothing in this PR touches the backend or the wire protocol; this note records what an iPhone already gets and what will need additive changes later.

### What exists today

- `SyncDocument` is one JSON document per Apple account, whose merge is a join: `pet` is last writer wins, `tallies` is keyed by device id and merged by max, `unlocks` and `studyDays` are unions and `longestStreak` is a max.
- An iPhone is just another device id in `tallies`, so it can earn and spend points locally and merge them with the Mac's with no change to the document or the server, which stores the document as sent.
- The pet's look and points already live in the same `PetSave` the Mac writes, so the iPhone can hand them to `SyncDocument` as they are.
- The Party protocol has no Mac-only fields, and the Windows app already speaks it, so an iPhone can register, keep friends, send presence (`status`, `method`, `phaseEndsAt`) and join a party's shared session as another client.
- The web Sign in with Apple flow (the `dev.tabbi.Tabbi.signin` Services ID, ending in a `tabbi://auth/apple` link) needs no backend change, only the iPhone app registering the `tabbi` URL scheme.

### Additive backend changes needed later

1. Native Sign in with Apple: `backend/src/apple.ts` accepts only `APPLE_CLIENT_ID` (`dev.tabbi.Tabbi`) as the identity token's audience, so a token from `dev.tabbi.ios` is refused as "wrong audience".
   The fix is a list of accepted app audiences that adds the iOS bundle id (with a backend test), or grouping the iOS App ID with the Mac's under the same primary App ID for Sign in with Apple.
2. Minutes in sync: the document carries study days but not minutes or the activity log, so seasonal event progress, the 50 hour milestone and weekly recaps would not count iPhone study on the Mac.
   An additive, per-device minutes tally (merged by max like `tallies`) would carry it, with older Macs ignoring the unknown field, plus a schema, fixture and compatibility test per `docs/party-compatibility.md`.
3. Live timer mirroring: presence is one row per user, so a Mac and an iPhone would overwrite each other's `phaseEndsAt`, and sync is read on launch and wake, not live.
   A small additive route (for example `GET` and `PUT /v1/timer` with the device id, method, phase, start and end, and an `If-Match` revision like sync) would let each device count down the other's session from dates, behind a new `Tabbi-Protocol` version.
   It also needs a rule that only the device that ran a block pays its points (the crediting baseline is per clock source today), so a mirrored block is never paid twice.
   A locked iPhone would only see the Mac's timer through a push-to-start or push-updated Live Activity, which needs an APNs key and a send path the Worker does not have yet.
