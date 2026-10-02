# NotchDeck — guide for contributors and coding agents

NotchDeck is a macOS menu-bar-less app that turns the MacBook notch into a small,
clickable panel with five modules: Now Playing (Spotify, Apple Music), System (CPU/GPU),
Claude Usage, Today (daily checklist), and Ask Claude.

## Build, test, look

```sh
swift build                                  # must stay warning-free
swift test                                   # NotchKitCore unit tests
swift run NotchDeck --snapshot snapshots     # render every notch state to PNG
swift run NotchDeck --snapshot snapshots-medicine --kit medicine  # same, for another kit's tabs
swift run NotchDeck --snapshot snapshots-study --edition studynotch  # as the StudyNotch edition
scripts/run.sh [studynotch]                  # bundle + launch the real app (or an edition)
scripts/bundle.sh studynotch                 # build/StudyNotch.app, Medicine kit preselected
```

You cannot see the screen. **After any UI change, run the snapshot command and
look at the PNGs** (`snapshots/closed.png`, `snapshots/open-<module>.png`).
Judge them against the design rules below before you call the work done.

## Architecture

- `Sources/NotchKitCore` — pure Swift, no AppKit/SwiftUI. Parsers, models,
  stores, formatting. Everything here gets unit tests in `Tests/NotchKitCoreTests`.
- `Sources/NotchKit` — shared AppKit/SwiftUI that modules build on:
  `Design/Theme.swift` (design tokens and shared controls `Card`,
  `IconButton`), `Components/` (`ModulePreview`, `ModulePlaceholder`),
  `Notch/` (the panel window, notch shape and screen geometry) and `Pets/`
  (`PetPlayer`, `PetView`). Everything here is `public`. Reuse it; add new
  shared components here, not inside a module.
- `Sources/NotchDeck/Notch` — the notch controller, view and open/close state,
  which assemble the app's modules. Shared; change only when your task
  requires it.
- `Sources/NotchDeck/Modules/<Module>/` — one folder per module: a store
  (`ObservableObject`, owned by `AppServices`), SwiftUI views, and a
  `NotchModule` class (descriptor, panel, an optional Settings toolbar pane
  from `makeSettingsPane()`, and `start()`/`stop()`). The pane and the
  lifecycle follow the module's on/off switch; Today's pane is Focus.
- `Sources/NotchDeck/Modules/NotchModule.swift` — the `NotchModule` protocol
  and `ModuleRegistry`. To add a module: add its `ModuleDescriptor` to
  `ModuleCatalog.builtIn`, write `<Module>Module` in its folder, and list it
  once in `AppServices.modules`.
- Shared data providers: a module that has tasks, calendar events, progress
  (e.g. cards due) or a focus timer to share returns a `ModuleProvision`
  publisher from `NotchModule.provision`. `ProviderHub` (in `Modules/`)
  merges the enabled modules' values into a `ProviderSnapshot`
  (`NotchKitCore/Providers`). The ticker reads it, and Today lists other
  modules' goals and tasks above its checklist (`sharedTodayItems`), so
  e.g. Anki reviews show up there with no Today code. Never reach into
  another module's store; publish what you have and consume the snapshot.
- `Sources/NotchDeck/Modules/ModuleViews.swift` — the closed notch's
  live-activity wings.
- `Sources/NotchKitCore/Claude` — `ClaudeCLI` (locate + stream `claude -p`) and
  `ClaudeStreamEvent` (stream-json parser). Both Claude modules use these.

Kits are JSON manifests in `Sources/NotchKitCore/Kits/Bundled`; the format
is documented in `docs/kits.md`. Direction and planned work: `docs/ROADMAP.md`.

Module ownership: when working on one module, keep changes inside its
`Modules/<Module>/` folder and a matching `NotchKitCore/<Module>/` folder plus
tests. Touch shared files only when unavoidable, and keep those edits minimal.

## Design rules

- The notch is hardware-black (`Theme.Palette.background`). Content sits on
  `Card` surfaces. Never use light backgrounds or system window chrome.
- Every panel renders inside the same fixed canvas
  (`Theme.Layout.expandedSize`, minus header and insets ≈ 500×150 pt). Design
  for that size; no scrolling except in lists that can genuinely grow.
- One accent color per module: `Theme.Palette.accent(for:)`.
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
  artwork URLs). No telemetry. Claude features only go through the user's
  local `claude` CLI via `ClaudeCLI` — never read credentials or the keychain.
- Never poll faster than needed; stop timers when a panel isn't visible if
  the data is only shown there.
- Keep `swift build` warning-free and `swift test` green.
- Public types and non-obvious logic get a short doc comment explaining why.
