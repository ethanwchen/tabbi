# Windows phase 0: shared data

Status of phase 0 from `docs/windows/plan.md`: the Mac app's shared pieces move to platform-neutral data, with nothing a Mac user can see changing.

## Done

- `shared/` exists, with golden fixtures under `shared/fixtures/`.
- Pet golden fixtures (`shared/fixtures/pets/`), recorded from the Swift string-grid art before any of it moved:
  a SHA-256 digest of every composed frame of every animation for every breed in each outfit, each accessory and four full looks (612 dresses, 76,500 frames),
  readable run-length frames for a cat and a dog,
  and every breed's palette.
  `PetGoldenFrameTests` compares the live composer against them on every `swift test`.
- Pet art is data: every hand-drawn grid (cat, dog, costume, effect, paw, prop, tail and walk art, 127 grids and 12 frame sequences) is in the `pets.v1` JSON files in `Sources/TabbiKitCore/Pets/PetArt/`, a SwiftPM resource like the kits.
  Costume items carry their anchors (`rise`, `eyeRow`, `sitRow`) beside their grids.
  `PetArt` loads them, checking the schema version and every grid; the Swift in `Pets/Art/` only names the grids and generates the procedural pieces (legs, wrapped tails, the groom arm).
  `shared/schemas/pets.v1.schema.json` describes the format for the TypeScript port, and `PetArtTests` keeps its symbol pattern equal to the Swift sprite legend.
  The pet golden fixtures did not change, and the demo snapshots are pixel-identical to the commit before the move (the PNG bytes of 17 shots differ, their pixels do not).
- Breeds are data: `PetArt/breeds.json` (also `pets.v1`) holds the base palette, the species of each body shape, and each breed's name, body shape, tail, palette and pattern, in picker order.
  `PetBreed` and `PetBodyShape` keep only their cases (the ids pet saves store).
  An export of every breed definition from the new data path is identical to one taken from the old Swift switches, and `PetArtTests` keeps the schema's role, zone and species lists equal to the Swift enums.
  The pet golden fixtures (digests and palettes) did not change.

- Animation timelines are data: `PetArt/animations.json` (also `pets.v1`) holds, for each of the 19 animations, whether it loops, the frame a still pet holds, and per frame the duration, pose, stance, vertical shift, effects (grid name and position, fixed or from the head in the clip's first frame), steam wisp, dust and speech bubble.
  `PetComposer.clip` reads the timeline and keeps only the placement code (composing a pose, painting effects behind the pet, finding the paws for dust).
  One rule moved from the timeline into the composer: a toy's `bounce` lifts only a dog's ball, so the data needs no per-species values.
  The pet golden fixtures (every frame's pixels, duration and bubble anchor, and each clip's `loops`) did not change.
  Demo snapshots match the commit before, apart from shots that change between any two runs of the same build: live clocks, and the playing pet in the Closet and the onboarding pet step, whose idle breath is caught at whatever moment the shot is taken.
  Re-rendered, those pet shots matched the earlier commit pixel for pixel.

- Themes are data: `Sources/TabbiKitCore/Themes/themes.json` (`themes.v1`) holds every theme in picker order (names, family, accent treatment, typeface, motion, controls, surfaces and palette), the default theme, the old kit value `notch`, and the glass sheen of glass cards.
  `ThemeCatalog` loads it and checks the schema version, unique ids, every id it or Swift refers to, and that color components are in 0...1.
  What the values do (accent treatments, gentle motion, the glass material) stays in Swift.
  `shared/fixtures/themes/themes.json`, recorded from the Swift catalog before the move, pins every resolved color and what each accent treatment makes of every module accent; `ThemeGoldenTests` compares within 1e-9, because the old code computed the cozy text colors (`0.9580000000000001`) that the data writes as typed (`0.958`).
  `shared/schemas/themes.v1.schema.json` describes the format, and `ThemeFileTests` keeps its enums and palette roles equal to Swift.

- Study methods are data: `Sources/TabbiKitCore/StudyMethods/study-methods.json` (`study-methods.v1`) holds every method in picker order (focus, break, long break, review phase, question count, and its info copy: name, tagline, how-to, evidence and rating), the info footnote, the evidence badge labels, the 1 min...4 h phase clamp, the Anki sprint's break hint, and the Timer and Custom stepper limits.
  `StudyMethodFile` loads it and checks the schema version, one method per kind, lengths inside the clamp, positive counts, a label per rating, and that the Timer and Custom start on lengths their steppers can show.
  The named presets (`StudyMethod.pomodoro` and so on), `StudyTimerLength.standard` and `StudyCustomRhythm.standard` read the data; the rules (`nextPhase`, phase lengths, Flowtime breaks, stepping, labels) stay in Swift.
  `shared/fixtures/study-methods/study-methods.json`, recorded from the Swift methods before the move, pins every method's parameters, phase lengths, phase order over eight rounds, labels and copy, plus Flowtime breaks around every tier edge, sprint goals and Timer steps; `StudyMethodGoldenTests` compares exactly and was shown to fail on a one-value change.
  `shared/schemas/study-methods.v1.schema.json` describes the format, and `StudyMethodFileTests` keeps its enums equal to Swift.
  The Med School kit's demo snapshots, plus the Study picker, Custom lengths, three info popovers and five running methods, match the commit before, apart from live clocks (a ring tip and a count-up second) and the pet's idle breath; the one other differing shot matched pixel for pixel when re-rendered.

- Kits, editions and the Party catalog, which were already data, have JSON Schema files: `shared/schemas/kit.v1.schema.json`, `edition.v1.schema.json` and `catalog.v1.schema.json`.
  The kit schema accepts only kits the Mac app loads (apart from the 64 KB file limit and bundled ids, which a schema can't express), and leaves to `KitValidation` what the app only warns about: unknown modules, previews, themes and fields, and module settings that don't fit.
  `SharedSchemaTests` keeps each schema's fields, limits and version range equal to the Swift decoders, and checks sample ids, names, bundle ids and icon names against both the schema patterns and `KitManifest.decode` or `Edition.decode`.
  The bundled kits, the edition and the catalog pass their schemas in a JSON Schema validator, and the tests were shown to fail on a changed limit, pattern, field name or reserved key.

- Stream-json fixture for the TypeScript port: `shared/fixtures/claude-stream/stream-json.json` holds 34 raw `claude -p` lines (session start, rate limits with and without windows, text deltas, assistant messages with tool use and thinking, results, and malformed lines) with the event each parses to, and 13 Ask Claude exchanges as steps (ask, feed a line, the CLI exits, stop, retry, retry a lost session) with the chat after every step.
  `ClaudeStreamGoldenTests` checks the parser and `ClaudeAskConversation` against it, and also replays the fixture's own inputs, which is what the port does; it was shown to fail on a one-string change.

- Focus timer fixture for the TypeScript port: `shared/fixtures/focus-timer/focus-timer.json` holds countdown readouts around their rounding edges, and 15 Pomodoro sequences as steps (start, pause, reset, skip, advance the clock, change the lengths), with the timer, what the focus card shows, the shared focus clock, and each finished phase's notification and activity record after every step.
  They cover a full cycle with a pause, sleeping through one or more phases, skips while running, idle and paused, resets, no-ops, custom and clamped lengths, and lengths changed mid-phase.
  `FocusTimerGoldenTests` checks the timer against it and replays the fixture's own inputs; it was shown to fail on a one-string change.

- Ticker fixture for the TypeScript port: `shared/fixtures/ticker/ticker.json` holds 19 sets of ticker sources (meetings, music, the shared focus clock, tasks, goals, module highlights, the pet and the party) read at chosen moments with chosen kinds turned on, each with the items the closed notch can show, their display strings and the next moment they can change.
  They cover the meeting pin and horizon edges, minute rounding, an imminent meeting beating one under way, idle, paused and counting-up clocks, goals that wait for a start, highlight priority, ties, pins and expiry, every pet mood, and the party cap.
  It also holds 13 rotation sequences: holding and wrapping, vanished items handing over, new items joining, pins holding the notch, and interval changes.
  `TickerGoldenTests` checks `TickerSources` and `TickerRotation` against it and replays the fixture's own inputs; it was shown to fail on a one-string change.

- Plan my day fixture for the TypeScript port: `shared/fixtures/plan-my-day/plan-my-day.json` holds 19 days (a workday, study days with each study method, long work split up to the focus limit, an evening, after 10 pm, a packed calendar, a meeting under way, a daylight saving change and a day east of UTC), each planned all three ways: on device with reasons and leftovers, as a study day, and from recorded Claude answers, with the free time, the full Claude and refine prompts, what the parser and validator make of each answer, and what the panel shows.
  It also holds 4 proposal sequences (dismiss, refine, and add as time passes and meetings arrive, with a writer that fails), with the events written and the proposal after every step.
  `PlanMyDayGoldenTests` checks the planners against it and replays the fixture's own inputs; it was shown to fail on a one-string change.
  Found along the way: the study-day planner and the Claude prompt treat a goal that waits for a start (Study's daily study-time goal) as work, so a Med School day plans a review block named "Study time", while the on-device planner leaves such goals out.
  The fixture records today's behavior; a fix belongs to the Today module and re-records it.

## Next

1. Logic fixture for the TypeScript port: study session sequences.
2. Snapshot comparison against `main`, pixel for pixel.
