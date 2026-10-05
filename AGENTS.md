# Tabbi - guide for contributors and coding agents

Tabbi is a macOS menu-bar-less app that turns the MacBook notch into a small,
clickable panel of tabs. Each tab is a module (Now Playing, System, Claude Usage,
Today, Ask Claude, Focus, and the study modules Study, Anki, Party, Closet),
and a kit picks which ones are on and in what order.

## Build, test, look

```sh
swift build                                  # must stay warning-free
swift test                                   # TabbiKitCore and Tabbi (app wiring) tests
swift run Tabbi --snapshot snapshots         # render every notch state to PNG
swift run Tabbi --snapshot snapshots-medicine --kit medicine  # same, for another kit's tabs
swift run Tabbi --snapshot snapshots-themes --theme all     # every notch shot once per theme, in subfolders
scripts/run.sh [edition]                     # bundle + launch the real app (or an edition)
scripts/bundle.sh                            # build/Tabbi.app
scripts/check-style.sh                       # no em dashes or emojis (swift test runs it too)
```

You cannot see the screen. **After any UI change, run the snapshot command and
look at the PNGs** (`snapshots/closed.png`, `snapshots/open-<module>.png`).
Judge them against the design rules below before you call the work done.

## Architecture

- `Sources/TabbiKitCore` - pure Swift, no AppKit/SwiftUI. Parsers, models,
  stores, formatting. Everything here gets unit tests in `Tests/TabbiKitCoreTests`.
- `Sources/TabbiKit` - shared AppKit/SwiftUI that modules build on:
  `Design/Theme.swift` (design tokens and shared controls `Card`,
  `IconButton`), `Components/` (`ModulePreview`, `ModulePlaceholder`),
  `Notch/` (the panel window, notch shape, screen geometry, the
  open/close and tab state `NotchViewModel`, the `NotchTabBar`, the
  closed-notch wing sizes `NotchPreviewLayout`, the root `NotchView`,
  which the app fills through `NotchContent` closures, and the
  `NotchController` with its `GlobalHotkey`, which places the panel and
  handles pointer, keyboard, swipe and hotkey input while following the
  app state passed in as `NotchInputs`), `Pets/`
  (`PetPlayer`, `PetView`), `Audio/` (`FocusSoundEngine`, which plays a
  `FocusMix` through AVAudioEngine; Study can reuse it) and `Settings/`
  (the toolbar `SettingsWindowController`, which shows whatever
  `SettingsPane`s the app hands it, and the `HotkeyRecorder` shortcut
  field). The app's own panes and their order live in
  `Sources/Tabbi/Settings/AppSettingsPanes.swift`. Everything here is `public`. Reuse it; add new
  shared components here, not inside a module.
- `Sources/Tabbi/Modules/ModuleViews.swift` - hooks the shared notch up
  to the app: the closed notch's live-activity wings, `notchContent`
  (module panels, music wings, Settings) and
  `notchInputs` (settings, hotkey recorder, ticker) built from `AppServices`.
  Shared; change only when your task requires it.
- `Sources/Tabbi/Onboarding/` - first-run setup inside the notch. The
  `OnboardingStore` runs the pure `OnboardingFlow` (`TabbiKitCore/Onboarding`)
  and applies the kit and tabs once the tab step is done; its views fill the
  open notch through `NotchContent.takeover` (a `NotchTakeover`) while
  `NotchViewModel.showsTakeover` is on. Settings > Modules re-runs it.
- `Sources/Tabbi/Modules/<Module>/` - one folder per module: a store
  (`ObservableObject`), SwiftUI views, and a `NotchModule` class (its own
  `static let descriptor` with id, title, symbol, category, accent and
  permissions, `init(context:)`, a panel, an optional Settings toolbar pane
  from `makeSettingsPane()`, and `start()`/`stop()`). The pane and the
  lifecycle follow the module's on/off switch. Modules that share a pane
  return the same id and it shows once: Today and Focus both offer the
  Focus pane, since both show the focus timer.
- `Sources/Tabbi/Modules/ModuleContext.swift` - what every module gets
  in `init(context:)`: its id, the edition, read access to settings and the
  active kit (`kitApplied` fires when the user switches to, resets or
  undoes a kit; on `.undo` put back what the undone switch changed), the
  `ProviderHub`, a logger, the `runMode` (live, demo data, snapshot
  rendering; hand it to your store, never read `TABBI_DEMO` yourself), the edition's
  `storage` (`EditionStorage`: put files in `storage.folder("<Name>")`,
  never in a hardcoded Application Support path, so each edition keeps
  its own data), and `SharedServices`. A module builds and owns its store there and follows
  kit changes itself. A service several modules use is declared as a
  `ModuleContext` extension in its owner's folder and resolved through
  `shared`, so all of them get one instance: `context.focusTimer` (the
  `FocusStore` in `Modules/Focus/`) is how Today, Focus and the pet coach
  share one Pomodoro timer, and `context.focusMode` (the `FocusController`
  beside it) is the one focus mode (sound, playlist, Do Not Disturb) that
  the Pomodoro and Study's deep focus blocks drive. Likewise
  `context.studyPet` (the `ClosetStore` in `Modules/Closet/`) is the one
  owner of the pet's save, and Study and Party follow its `profiles`. A module that takes
  state of its own from a kit's defaults (Focus: the focus sound) reports
  whether it still matches through `usesKitDefaults(of:)`, so Settings
  knows when Reset to Kit Defaults has work to do.
- Persisted formats are versioned. A JSON file (or `UserDefaults` value)
  goes through a `VersionedJSON` schema (`TabbiKitCore/Persistence/`),
  which writes a `schemaVersion` key and runs ordered migration steps on
  older documents; `PlannerRepository.schema` is an example. A change to
  how a preference is stored is a new step in `SettingsSchema`. Never edit
  a step that has shipped, and test the migration.
- `Sources/Tabbi/Modules/NotchModule.swift` - the `NotchModule` protocol
  and `ModuleRegistry`. `Sources/Tabbi/Modules/ModuleList.swift` lists
  every module type, one per line; its `ModuleList.catalog` is the only
  module catalog. Layouts, kit validation, the tab bar, Settings and
  previews all resolve ids through it (SwiftUI views read it from the
  `moduleCatalog` environment value), so no shared code hardcodes a module's
  title, symbol or accent. To add a module: write `<Module>Module` with its
  descriptor and `init(context:)` in its folder and add its line at the end
  of `ModuleList.all`. `AppServices` (the composition root in `App/`)
  creates every listed module with its own context; it holds no module
  stores.
- Shared data providers: a module that has tasks, calendar events, progress
  (e.g. cards due), a focus or break clock or a study tally (today's study
  minutes, sessions and points, which Wrap Up shows) to share returns a
  `ModuleProvision` publisher from `NotchModule.provision`. Any timer engine
  maps its clock into the neutral `ProvidedFocus` (counting down, counting up
  for open-ended phases, paused or idle, plus a phase label and a deep focus
  flag): Today and Focus share their Pomodoro with `FocusTimer.provided(by:)`
  and Study its session with `StudySession.sharedFocus(by:isDeep:at:)`, and
  the ticker, the pet, the coach and Party all read `ProviderSnapshot.focus`
  (when two clocks run, the one started or resumed last). `ProviderHub` (in `Modules/`)
  merges the enabled modules' values into a `ProviderSnapshot`
  (`TabbiKitCore/Providers`). The closed-notch ticker (`TickerStore`) reads
  only that snapshot, and Today lists other
  modules' goals and tasks above its checklist (`sharedTodayItems`) and
  hands their unfinished work to Plan my day (`plannableWork`), so e.g.
  Anki reviews show up there with no Today code. Never reach into
  another module's store; publish what you have and consume the snapshot.
- Ticker highlights: to put a line of your own beside the closed notch
  (Claude Usage's "5h 86%"), publish `TickerHighlight`s in
  `ModuleProvision.highlights` (text, tooltip, tone, priority, optional
  pin, expiry and symbol) and give your descriptor a `highlightTitle`,
  which names the Settings toggle. The ticker shows each module's top
  highlight with the module's symbol and accent and opens the module on
  click; its kind is `TickerKind.highlights(from: id)`, so kits list it
  by module id. Music playing is `ModuleProvision.isPlaying`. A module
  that only refreshes while someone can see it follows
  `context.closedNotchPreview.watchedKinds` (Today reloads the calendar
  while the meeting preview can show).
- Activity log: the snapshot says what is true now; `context.activityLog`
  (`ActivityLog` in `Modules/`, one per app) says what happened. Log
  your own events as `ActivityRecord`s (`TabbiKitCore/Activity`: your
  module id as `source`, an open `ActivityKind` such as
  `focus.completed`, `break.taken`, `cards.reviewed`, `task.completed`
  or one of your own, start and end, a quantity and unit, an optional
  `subject` id and metadata), and read anyone's by day or follow
  `recorded`. The Focus timer, Study, Today and Anki log there, so
  streaks, insights and the pet never need another module's store.
  Records stay on the Mac, one versioned JSON file per day in the
  edition's `Activity` folder; demo and snapshot runs keep them in memory.
- `Sources/TabbiKitCore/Claude` - `ClaudeCLI` (locate + stream `claude -p`) and
  `ClaudeStreamEvent` (stream-json parser). Both Claude modules use these.

Kits are JSON manifests in `Sources/TabbiKitCore/Kits/Bundled`; the format
is documented in `docs/kits.md`.
Editions (branded builds of the same binary with their own name, bundle id,
data folder and preselected kit) are JSON files in
`Sources/TabbiKitCore/Editions/BundledEditions` that the app and
`scripts/assemble.sh` both read (see `Edition.swift`); a new edition is a file.
Tabbi ships one edition, `tabbi`; audiences are served by kits.
On its first live launch, `LegacyDataMigration` moves what the app saved as NotchDeck (or the retired StudyNotch edition) into Tabbi's Application Support folder and preferences, once and without overwriting.
Direction and planned work: `docs/ROADMAP.md`.

Module ownership: when working on one module, keep changes inside its
`Modules/<Module>/` folder and a matching `TabbiKitCore/<Module>/` folder plus
tests. Touch shared files only when unavoidable, and keep those edits minimal.

## Adding a module

A new vertical is its own files plus one line in `ModuleList.swift`.
`Tests/TabbiTests/LeetCodeFixture/LeetCodeModule.swift` is a complete example (a "LeetCode daily" module), and `LeetCodeAcceptanceTests` proves it plugs in that way: it builds `AppServices` from `ModuleList.all + [LeetCodeModule.self]` and checks every shared surface.

1. Create `Sources/Tabbi/Modules/<Module>/` with a store (`ObservableObject`), its SwiftUI panel, and `<Module>Module: NotchModule`.
   Pure logic (parsers, models, formatting) goes in `Sources/TabbiKitCore/<Module>/` with tests in `Tests/TabbiKitCoreTests`.
2. Declare `nonisolated static let descriptor = ModuleDescriptor(...)`: id, title, SF Symbol, a one-line `summary` for the Settings "Add More" library, category (an open `ModuleCategory`: use a built-in one or declare your own beside the module, as the fixture's `.coding` does), accent, permissions, `network` with each host its code connects to (none for the fixture), `highlightTitle` if it shows a line in the ticker, `ownsFocusClock: true` if it runs a focus clock of its own, `headerShortcut` (a label and a letter key) if it opens from a button at the far right of the header instead of a tab (the Closet's paw, key P), and `setup` with the first-run onboarding steps it needs (`OnboardingSetupStep` in `TabbiKitCore/Onboarding`: `.pet`, `.anki`, `.calendar`, `.studyMethod`, `.party`, or one of your own), which onboarding asks only when the module is on.
   Draw a step in the notch from `makeSetupView(for:done:)` (call `done` to move on); without one, onboarding shows a card that points to the module's tab.
   The tab bar, Settings, kit validation and previews read title, symbol and accent from here, and Today shows such a module's clock in place of its Pomodoro, so a layout has one timer.
   If kits can configure the module, declare the keys of its `moduleSettings` section as `kitSettings: KitSettingsSchema([...])`, so kit validation warns about typos and out-of-range values there; the fixture declares `minutesPerProblem`.
3. In `init(context:)`, build the store and follow what the context offers (`kitApplied`, `providers.$snapshot`, shared services).
   Read your kit section with `context.activeKit?.defaults.settings(for: context.id)` and again on each `kitApplied`, leniently: a value that doesn't fit keeps your default.
   Start background work in `start()` and undo it in `stop()`; the registry calls them when the module's switch changes.
   In demo mode (`context.isDemo`, from `context.runMode`) show realistic sample data and touch no network, calendar or CLI; in a snapshot run (`context.isSnapshot`) play no sound and save nothing.
4. Share what you have through `provision`: `tasks` and `progress` show in Today and Plan my day, `progress` also in the ticker's progress preview, and `highlights` as the module's own ticker line.
   The fixture publishes a task ("LeetCode: Two Sum", about 20 min), a goal ("LeetCode daily, 1 problem left") and a highlight that goes away once the problem is solved.
   Log what the user did in `context.activityLog`: the fixture records a `problem.solved` activity of its own kind when the problem is solved.
5. Add `<Module>Module.self,` at the end of `ModuleList.all`.
   A kit can now list the module id in `modules` and in its `ticker` field; until that line exists, kit validation reports both as unknown.
6. Optionally return a Settings pane from `makeSettingsPane()`.
   A kit that ships with the app is a separate change: its JSON file, named after its id and with a `pickerOrder`, in `Sources/TabbiKitCore/Kits/Bundled`, which `KitLibrary.bundled` lists (see `docs/kits.md`).

The module itself needs no edits to `AppServices`, the ticker, Today, `Theme`, layouts or the catalog.
If a module seems to need one, the provider protocols are missing something: extend them in a separate change rather than special-casing the module.

## Writing style

- No emojis and no em dashes anywhere in the repo: UI strings, README and
  docs, code comments, kit descriptions, commit messages and release notes.
  Use a plain hyphen, a period, a comma, a colon or parentheses instead.
- `scripts/check-style.sh` fails on either character in a tracked text file,
  and `WritingStyleTests` runs it in `swift test`. A test that needs one as
  input data writes it as an escape (`"\u{1F3A7}"`).
- The product is called Tabbi. NotchDeck and StudyNotch are old names; the
  StudyNotch edition is now the Med School kit.

## Design rules

- The notch is hardware-black (`Theme.Palette.background`). Content sits on
  `Card` surfaces. Never use light backgrounds or system window chrome.
- Every panel renders inside the same fixed canvas
  (`Theme.Layout.expandedSize`, minus header and insets ≈ 500×150 pt). Design
  for that size; no scrolling except in lists that can genuinely grow.
- One accent color per module, from its descriptor: `<Module>Module.descriptor.accentColor`
  inside the module, `catalog.descriptor(for: id).accentColor` in shared views.
- Rounded SF type from `Theme.Typography`; changing numbers use
  `.monospacedDigit()` so they don't jitter.
- Spacing on the 4pt grid via `Theme.Spacing`; corners via `Theme.Radius`
  with `.continuous` style.
- Animate state changes with `Theme.Motion` springs; never linear.
- Clear hierarchy: one primary element per panel, secondary text in
  `secondaryText`, metadata in `tertiaryText`.
- Every control has a hover state and a `.help(...)` tooltip.
- Design empty, loading, and error states (e.g. Spotify not running, `claude`
  not found). Never show a blank panel or a raw error dump.

## Rules

- No third-party dependencies without a strong reason stated in the PR.
- Privacy: no network calls except what a module inherently needs (album
  artwork URLs), and every host a module's code connects to is listed in its
  descriptor's `network` (`ModuleNetworkAccess`: host and purpose), which the
  kit import sheet shows before a kit turns the module on. No telemetry. Claude features only go through the user's
  local `claude` CLI via `ClaudeCLI` - never read credentials or the keychain.
- Never poll faster than needed; stop timers when a panel isn't visible if
  the data is only shown there.
- Keep `swift build` warning-free and `swift test` green.
  `TabbiKitCore` and its tests build in Swift 6 language mode; the other
  targets stay in Swift 5 mode with complete concurrency checking, so a
  data race there shows up as a warning to fix.
- Public types and non-obvious logic get a short doc comment explaining why.
