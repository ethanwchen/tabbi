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

`PetCamFlowTests` plays the Pet Cam like a person in five-minute blocks, so the points visibly move: a catch through the Lock Screen, the Dynamic Island and the end notification, a miss, an early stop, a dare stopped after its floor that still plays its tape, and two more catches and two more misses, so every tape shape plays once, then a video export and the share sheet, the case file and a replay from it, and the breed picker; it checks that every tape draws its picture at one size.
A checkpoint named `video-start-<name>` starts `xcrun simctl io <device> recordVideo` into `<name>.mp4` and `video-stop` ends it, so every tape is also recorded as it plays.

## Pet Cam

The prototype of the concept in `runs/iphone-app/PROTOTYPE-SPEC.md`: your pet is home alone with a security camera on it.
Before a block you can say what you are avoiding, then make one sealed tap on where the pet will strike, or just press Start and the camera follows the pet's stare.
Any block of five minutes or more is filmed, and a "Just 5 minutes" dare stopped after its five minutes still plays its tape.
Nothing about the room shows while the block runs; at its planned end a CCTV tape of five to seven stills shows what the pet really did.

### The engine (TabbiKitCore/PetCam)

The game is pure Swift in `Sources/TabbiKitCore/PetCam`, so the Mac can share it, with its tests in `Tests/TabbiKitCoreTests/PetCam*Tests.swift`.

- `PetCamRoom` holds one object on each of three spots (counter, shelf, side table) out of six kinds (mug, plant, fishbowl, vase, tissue box, donut), and the wrecks on the floor; a strike leaves a wreck and a new object of another kind, never one whose wreck is still on the floor (when every free kind has one, the oldest mess is cleared away first) and preferring the kinds caught least, so the room drifts, never contradicts itself, and the case file fills evenly.
- `PetCamTuning` is the read as data, one tell and one exception: with nothing else showing the pet strikes where it stares 62% of the time; in about one block in three a visible exception shows on a spot it is not staring at (a wobbling object by default, or the breed's appetite), and then it decides the strike 75% of the time, a strong lean rather than a sure thing.
- `PetCamSetup` is the frozen frame: a seed, the stare and the exception, all drawn from the seed and saved, so reopening the app shows the same frame and a stopped block never rerolls it. From the second block on, a block with nothing wobbling also names the WANTED object, whichever of the two objects the pet is not eyeing it has gone longer without being caught with (ties to the seed), and a block with a wobble names none; it never changes where the pet strikes, it is the stake that makes every block one choice.
- `PetCamGame` arms the camera at Start (any block of five minutes or more), resolves a block that ran to its end into a catch or a miss (and a dare stopped after its five minutes the same way), turns any other block cut short into the frozen still (or nothing before the 5-minute commit point), keeps each catch's case number and its object's rap sheet, and prepares the next frame from the seed chain, so a whole run replays from its first seed.
- `PetCamLog` is the sync-ready history: versioned, additive (unknown fields and records are skipped, never the file), and credited once per block id, with a commutative union as its merge.
- `PetCamCaptions` fills the grammar in `PetCamData/captions.json` from the room and the log. Every beat has at least five lines and no line repeats in its beat across three tapes. The object's age reads from another day as "MUG, LEFT OUT 3 DAYS AGO" and the same day from the pet's side ("THE VASE LASTED 2 MINUTES."); repeats ("2ND PLANT TODAY"), the same spot again and where the pet was last caught come first, and an old wreck ("RIGHT NEXT TO THE MUG SHARDS FROM 21:05") only when the camera can see it. A catch's charge is "OBSTRUCTION OF" the dodge line, or what the pet did; the line under it is the object's rap sheet (FIRST OFFENSE, 2ND OFFENSE, 3RD OFFENSE, REPEAT OFFENDER), the stamp escalates (CAUGHT, CAUGHT AGAIN, HABITUAL), and a catch with the WANTED object says how long it was wanted.
- `PetCamTape` turns a record into its stills, and `PetCamScene` draws each one. The act is the object's own: a swat at the mug, a paw reached into the fishbowl with a splash ring, a chomp of the donut, a two-paw shred of the tissues, a dig in the plant, a head-shove at the vase, each with what it throws up, and the mug, vase, fishbowl and plant are caught on their way down. The eye contact wears the evidence and the freeze is the face the case file shows. `PetCamTape.clip` is the share cut (see the app). Each outcome has three shapes, picked by the seed and never one of the last two: a catch plays straight to the eye contact, opens cold on a close-up of the wreck with no pet in frame and rewinds, or freezes on the act itself (mid-air, or with its mouth full); a miss hears the crash as debris skids into the wrong camera's frame and the pet walks in at second three, adds a double take into the lens, or opens cold on the alibi. Every miss ends on CAM 1 pushed in on the wreck ("MEANWHILE, BY THE COUNTER: MUG SHARDS.", and "IT WAS ALREADY WOBBLING." when the exception decided it). Every tape runs 10 to 15 seconds, no framing zooms past twice the wide shot, and the pet and objects are drawn by depth.

Scripted players through the real game loop under the default tuning (`PetCamReadTests`, 3000 blocks each): always following the stare catches 45.4%, a random spot 33.3%, reading the exception when it shows 68.0%, and reading the wobble but otherwise chasing WANTED 40.9%.

### The art

Everything is pets.v1 grids in the pet palette roles: `PetCamData/room.json` holds the room seen from a high corner camera (two walls meeting at the back corner, a 2:1 floor), its day and night windows, every object intact and wrecked, the effects, the room's palette and the layout (light pools, anchors, crops and where the pet stands).
The room is lit evenly, cool at night and warmer by day, with no light pools: their dithered halos turned every close-up to mush, so the app marks the spots with camera brackets instead. A spot camera is a 2x crop of the same room, and each spot has two wreck footprints off the rug that a close-up can center, where the named wreck is exposed for and gets a yellow evidence tent marked A.
The Pet Cam poses (the stare with the head turned toward its target, the sneak, the swipe, the six acts, the freeze mid-act, the lens stare and the innocent lie-down) are composed by `PetComposer` from the shared art for every breed and outfit, with eye overlays, a held donut and the mugshot's guilty marks in `PetCamData/pet.json` and a crouched sneak stance; the composer's extras are internal and change no shipped frame.
Every wreck is ringed in a light line so it reads at 1x on the dark floor.
`swift run PetGallery <dir> petcam` writes the review sheets: every breed in every pose at 1x and 4x, in the demo look and bare, and the frozen frames and every still of a catch and a miss on each spot.

### The app

- `PetCamStore` follows the `StudyStore` through `StudyObserver`: Start arms the camera at the very moment the session starts, and the focus record that begins at that moment resolves it, in the app or on the next launch, at its real end time.
- `HomeScreen` is the frozen frame with its burn-in on a dark plate, grain and scanlines, the three spots as buttons with CAM 2, CAM 3 and CAM 4 brackets (the armed one bright, the others faint) and the WANTED tag, a hint that names what is on the frame ("Eyeing the plant. The mug is WANTED."), the dodge line and the "Just 5 minutes" dare. The feed keeps one width, gutter and pixel scale in every mode and crops the empty floor when the Timer's stepper needs room; at the accessibility sizes the page scrolls and Start stays pinned. `RecordingScreen` is the monitor during a block: the player's words as the case title ("RE: MY TAX RETURN"), a still CAM tile on lens-cap black whose REC dot is the only thing that blinks, and the countdown.
- `PetCamRoot` lays the tape over everything: a block's end goes from the recording screen through a moment of static straight to the tape, which fades back out to the home screen, and until it is watched the home screen keeps the room and the wall from before the block.
- `TapePlayer` plays the stills with cuts of static and their sounds (`TapeAudio`, ambient, so the Ring/Silent switch mutes it) and ends by itself; its feed shrinks to leave room for the longest caption (down to half the screen's width, below which the caption scrolls under the pinned buttons), its burn-in scales with the picture rather than with Dynamic Type, and the CAUGHT stamp lands where it covers least of the pet and the evidence. `TapeExporter` makes the 1080 by 1920 share clip of about five seconds that loops: it opens on the strike under the case as a headline, cuts to the eye contact with a push-in, slams the stamp in with a flash and a shake by 3.5 seconds, holds with the grain moving and ends on the tape rewinding, with "TABBI CAM 4  OWNER AWAY 25:00" burned into every frame and the synthesized sound bed (`TapeSound`) mastered to -14 LUFS with peaks under -1 dBFS (`Loudness`, an R128 meter), without the dodge line unless the player opts in.
- `MugshotWall` is the case file: six object slots (a silhouette until first caught with, then three rap-sheet pips filled at the first, second and fourth catch), then every tape watched in one column, newest first. A catch is a mugshot with its case number, date and charge under a CHARGE label, the pet's front (a different face from case to case, wearing the evidence: a fish on its head, frosting, a tissue over one ear, soil on its nose, a coffee mustache or a flower) and side, and the wreck as Exhibit A, under a WANTED band when it was the wanted object; a miss is a cold case (the charge in the player's words with SUSPECT AT LARGE, the wreck, the pet as it ended the tape as the only witness, and no count anywhere). Each replays its tape. `PetPicker` is the breed picker, opaque, opened on the current pet.
- The Live Activity and the Dynamic Island are a static CCTV frame (REC, the hidden camera's number, the countdown from `Text(timerInterval:)`, the pet lying still, scanlines), and a filmed block's end notification teases without spoiling: "Tape ready. Something happened while you were out."

Debug builds take `-PetCamQuickBlocks` (one-minute blocks arm the camera and a stop counts after 10 seconds), `-PetCamSeed <hex>` (a fresh game's first seed), `-PetCamTestHooks` (exposes the next strike to UI tests), `-TabbiTimerMinutes <n>` (starts on the Timer at that length) and `-TabbiDemoPet` (Mochi in the Cozy Hoodie and Beanie), and a long press on the camera's burn-in opens the tuning panel: the weights, the exception and its chance, live strike chances, scripted players, one-minute blocks, the demo pet, a replay and a new room.

### Strings for translation

The Pet Cam's strings are English only for now and are written inline (`Text(verbatim:)`) so they are easy to find; they need adding to the String Catalog before a release.
On screen: "What are you avoiding?", "EXHIBIT A", "REW", "Just 5 minutes", "Eyeing the {object}.", "The {object} is wobbling.", "The {object} smells too good.", "The {object} is WANTED.", "Camera hidden at the {spot}.", "Tap another spot to hide the camera there.", "Blocks under {n} minutes are not filmed.", "RE: {dodge}", "CAM {n}, {SPOT}", "Just 5 minutes. Stop any time after that and the tape still plays.", "The camera only films blocks of {n} minutes or more.", "Share", "Share video", "Share with what I was avoiding", "The video could not be made.", "Case file", "No cases yet", "Hide the camera where your pet strikes and catch it in the act. Every tape is filed here.", "CAUGHT WITH {n} OF {m}", "???", "WANTED", "COLD CASE", "SUSPECT: UNKNOWN", "WITNESS", "Your pet", "STOPPED", "TABBI CAM", "Tape ready", "Something happened while you were out."
For VoiceOver: "Live camera", "Camera 1, the living room.", the frozen frame's description ("{pet} is staring at the {object} on the {spot}." and "... is wobbling." or "... smells too good.", and "The {object} is wanted."), "Hide the camera at the {spot}", "Mugshot wall, {n}", "Still {n} of {m}", "Plays the tape again", "Makes a video of this tape", "Optional. Only the tape and the mugshot show it.", "Starts now. Stop any time after five minutes and the tape still plays.", "Recording on camera {n}, the {spot}", "{object}, caught {n} times", "Choose your pet", "{object}, caught", "Not caught with this one yet", "Exhibit A: what is left of the {object}", "Witness: {pet}, lying on the floor", and each still's description in `TapeStillView.describe` (including "Nobody in the picture.", "The {object} lies wrecked on the floor.", one line per act, and the two freezes).
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
A spot camera draws at exactly twice the wide shot's scale and a close-up at four times, the scanlines run along the wide shot's pixel rows, and grain lands on whole device pixels, so the room's dither and the pet are equally sharp in every framing.

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
