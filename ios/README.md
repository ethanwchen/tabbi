# Tabbi for iPhone

This folder holds the iPhone app: the study timer, the pet, points, the Live Activity and phase-end notifications, all driven by the Mac app's own `TabbiKitCore`, and on top of them the Pet Cam prototype, the game the app is built around (see [Pet Cam](#pet-cam)).
The foundation is concept independent, so the game layer sits on top of it without changing how sessions run or how points are paid.

## What is here

- `project.yml` is the XcodeGen definition of the project, and the generated `TabbiPhone.xcodeproj` is not checked in.
- `App/` is the app target (`dev.tabbi.ios`): the `StudyEngine`, its store and persistence, the phase-end notifications, the Live Activity controller, the study controls, and in `App/PetCam/` the Pet Cam's store and screens.
- `LiveActivityExtension/` is the widget extension (`dev.tabbi.ios.LiveActivity`) that draws the Lock Screen Live Activity and the Dynamic Island.
- `Shared/` is compiled into both: the activity's attributes, the whole-pixel pet view, the tone colors and the CCTV look.
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
TABBI_E2E_TEST=PetCamFlowTests ios/e2e.sh ~/Developer/Tabbi/runs/iphone-app/screens/pet-cam
```

The script runs `FoundationFlowTests` on the iPhone 17 Pro simulator: it picks the Timer, sets it to one minute and starts it, locks the phone, looks at the Lock Screen Live Activity, unlocks to see the Dynamic Island compact and expanded, then locks again until the minute runs out.
At each step it takes a screenshot with `xcrun simctl io <device> screenshot --mask=black`, since the default mask leaves the inside of the Dynamic Island transparent.
Uninstall the app first (`xcrun simctl uninstall booted dev.tabbi.ios`) to see the notification and Live Activity permission prompts of a first run.

`PetCamFlowTests` plays the Pet Cam with one-minute blocks: a catch (through the Lock Screen, the Dynamic Island and the end notification), a miss, an early stop, two more catches until a callback caption shows, a video export and the share sheet, the mugshot wall and a replay from it, and the breed picker.
A checkpoint named `video-start-<name>` starts `xcrun simctl io <device> recordVideo` into `<name>.mp4` and `video-stop` ends it, so every tape is also recorded as it plays.

## Pet Cam

The prototype of the concept in `runs/iphone-app/PROTOTYPE-SPEC.md`: your pet is home alone with a security camera on it.
Before a block you can say what you are avoiding, then make one sealed tap on where the pet will strike, or just press Start and the camera follows the pet's stare.
Nothing about the room shows while the block runs; at its planned end a CCTV tape of four to six stills shows what the pet really did.

### The engine (TabbiKitCore/PetCam)

The game is pure Swift in `Sources/TabbiKitCore/PetCam`, so the Mac can share it, with its tests in `Tests/TabbiKitCoreTests/PetCam*Tests.swift`.

- `PetCamRoom` holds one object on each of three spots (counter, shelf, side table) out of six kinds (mug, plant, fishbowl, vase, tissue box, donut), and the wrecks on the floor; a strike leaves a wreck and a new object of another kind, so the room drifts.
- `PetCamTuning` is the read as data: a weight for the stared spot and for the others, and one visible exception (a wobbling object by default, or the breed's appetite) that adds weight to its spot. The defaults give 60% on the stare with nothing wobbling, 50% on a wobble elsewhere and 75% on a wobble at the stare.
- `PetCamSetup` is the frozen frame: a seed, the stare and the exception, all drawn from the seed and saved, so reopening the app shows the same frame and a stopped block never rerolls it.
- `PetCamGame` arms the camera at Start (blocks of 10 minutes or more, or 5 for the very first), resolves a block that ran to its end into a catch or a miss, turns one cut short into the frozen still (or nothing before the 5-minute commit point), and prepares the next frame from the seed chain, so a whole run replays from its first seed.
- `PetCamLog` is the sync-ready history: versioned, additive (unknown fields and records are skipped, never the file), and credited once per block id, with a commutative union as its merge.
- `PetCamCaptions` fills the grammar in `PetCamData/captions.json` from the room and the log: the object's age ("MUG, LEFT OUT 3 DAYS AGO"), repeats ("2ND PLANT TODAY"), old wrecks ("RIGHT NEXT TO THE MUG SHARDS FROM 21:05") and the same spot again; a catch's charge is the dodge line, or what the pet did.
- `PetCamTape` turns a record into its stills, and `PetCamScene` draws each one.

Scripted players through the real game loop under the default tuning (`PetCamReadTests`, 3000 blocks each): always following the stare catches 55.8%, a random spot 31.6%, and reading the wobble too 59.0%.

### The art

Everything is pets.v1 grids in the pet palette roles: `PetCamData/room.json` holds the room seen from a high corner camera (two walls meeting at the back corner, a 2:1 floor), its day and night windows, every object intact and wrecked, the effects, the room's palette and the layout (light pools, anchors, crops and where the pet stands).
The room is dark at night but for three warm pools on the spots and a moonbeam on the rug, with an ordered dither at each edge, and a spot camera is a 2x crop of the same room.
The six new poses (stare, sneak, swipe, mid-act, lens stare, innocent lie-down) are composed by `PetComposer` from the shared art for every breed and outfit, with eye overlays in `PetCamData/pet.json` and a crouched sneak stance; the composer's extras are internal and change no shipped frame.
`swift run PetGallery <dir> petcam` writes the review sheets: every breed in every pose at 1x and 4x, in the demo look and bare, and the frozen frames and every still of a catch and a miss on each spot.

### The app

- `PetCamStore` follows the `StudyStore` through `StudyObserver`: Start arms the camera at the very moment the session starts, and the focus record that begins at that moment resolves it, in the app or on the next launch, at its real end time.
- `HomeScreen` is the frozen frame with its burn-in, grain and scanlines, the three spots as buttons with a viewfinder on the camera's spot, the dodge line and the "Just 5 minutes" dare; `RecordingScreen` is the monitor during a block, with REC and the countdown only.
- `TapePlayer` plays the stills with cuts of static and ends by itself; `TapeExporter` makes the muted 1080 by 1920 video with the burn-in, captions and a small Tabbi mark, without the dodge line unless the player opts in.
- `MugshotWall` shows every catch with its case number, date and charge, and replays its tape; `PetPicker` is the breed picker.
- The Live Activity and the Dynamic Island are a static CCTV frame (REC, the countdown from `Text(timerInterval:)`, scanlines), and a filmed block's end notification says only "Block done. The tape is ready."

Debug builds take `-PetCamQuickBlocks` (one-minute blocks arm the camera and a stop counts after 10 seconds), `-PetCamSeed <hex>` (a fresh game's first seed), `-PetCamTestHooks` (exposes the next strike to UI tests) and `-TabbiDemoPet` (Mochi in the Cozy Hoodie and Beanie), and a long press on the camera's burn-in opens the tuning panel: the weights, the exception and its chance, live strike chances, scripted players, one-minute blocks, the demo pet, a replay and a new room.

### Strings for translation

The Pet Cam's strings are English only for now and are written inline (`Text(verbatim:)`) so they are easy to find; they need adding to the String Catalog before a release.
On screen: "What are you avoiding?", "Just 5 minutes", "Camera follows the stare. Tap a lit spot to hide it there.", "Camera hidden at the {spot}. Tap it again to follow the stare.", "Blocks under {n} minutes are not filmed.", "Recording. The tape plays when the block is done.", "Just 5 minutes. After that you can stop any time.", "The camera only films blocks of {n} minutes or more.", "Share", "Share video", "Share with what I was avoiding", "The video could not be made.", "Mugshots", "No mugshots yet", "Hide the camera where your pet strikes and catch it in the act. Every catch gets a mugshot here.", "Your pet", "STOPPED", "TABBI CAM", "Tape ready", "Block done", "The tape is ready."
For VoiceOver: "Live camera", "Camera 1, the living room.", the frozen frame's description ("{pet} is staring at the {object} on the {spot}." and "... is wobbling." or "... smells too good."), "Hide the camera at the {spot}", "Mugshot wall, {n}", "Still {n} of {m}", "Plays the tape again", "Makes a muted video of this tape", "Optional. Only the tape and the mugshot show it.", "Starts now. You can stop after five minutes.", "Choose your pet", and each still's description in `TapeStillView.describe`.
The tape captions are the grammar in `TabbiKitCore/PetCam/PetCamData/captions.json`; a translation is a grammar file per language, and the burn-in (timestamps, "CAM 2", "REC", "LIVE") stays as cameras write it.
The debug tuning panel's strings are not shipped.

## Design

The screen follows the ADA SwiftUI doctrine and Apple's HIG (both read as references only): one hero per screen, which is the countdown in a large rounded monospaced numeral, with the pet's spot on the desk as the scene behind it.
Color is information: amber is focus (the Study tab's accent on the Mac), teal is a break, and a quiet neutral is idle, always paired with the phase's name.
The HUD and the controls float on Liquid Glass, the system's own `glassEffect` and glass button styles, over a tinted paper or near-black canvas that follows light and dark mode.
Haptics follow events, not taps: start, stop, a phase that runs out, and a change of method.
Every foundation string on screen comes from TabbiKitCore's String Catalog, so it shows in all 12 languages with no new translations, and the layout wraps rather than truncates up to the largest accessibility text size.

The Pet Cam's screens borrow a security monitor instead: a near-black screen, pale burn-in text in a monospaced face, a red REC dot, scanlines and grain, with the room as the one hero and the controls on Liquid Glass below it.
The feed is drawn at whole device pixels per sprite pixel and never resized, and it steps down a whole pixel at a time when larger text needs room, so the art stays crisp and nothing truncates.

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
