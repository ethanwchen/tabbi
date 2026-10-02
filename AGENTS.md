# NotchDeck — guide for contributors and coding agents

NotchDeck is a macOS menu-bar-less app that turns the MacBook notch into a small,
clickable panel with five modules: Now Playing (Spotify), System (CPU/GPU),
Claude Usage, Today (daily checklist), and Ask Claude.

## Build, test, look

```sh
swift build                                  # must stay warning-free
swift test                                   # NotchDeckCore unit tests
swift run NotchDeck --snapshot snapshots     # render every notch state to PNG
scripts/run.sh                               # bundle + launch the real app
```

You cannot see the screen. **After any UI change, run the snapshot command and
look at the PNGs** (`snapshots/closed.png`, `snapshots/open-<module>.png`).
Judge them against the design rules below before you call the work done.

## Architecture

- `Sources/NotchDeckCore` — pure Swift, no AppKit/SwiftUI. Parsers, models,
  stores, formatting. Everything here gets unit tests in `Tests/NotchDeckCoreTests`.
- `Sources/NotchDeck/Notch` — the window, shape, open/close state, input. Shared;
  change only when your task requires it.
- `Sources/NotchDeck/Design/Theme.swift` — design tokens and shared controls
  (`Card`, `IconButton`). Reuse them; add new shared components here.
- `Sources/NotchDeck/Modules/<Module>/` — one folder per module: a store
  (`ObservableObject`, owned by `AppServices`) and SwiftUI views.
- `Sources/NotchDeck/Modules/ModuleViews.swift` — module → view registry.
- `Sources/NotchDeckCore/Claude` — `ClaudeCLI` (locate + stream `claude -p`) and
  `ClaudeStreamEvent` (stream-json parser). Both Claude modules use these.

Module ownership: when working on one module, keep changes inside its
`Modules/<Module>/` folder and a matching `NotchDeckCore/<Module>/` folder plus
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
