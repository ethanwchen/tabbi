# Tabbi motion system

Motion in Tabbi is calm, fast and interruptible.
It explains where things come from and confirms what just happened; it never carries information on its own.
The research behind these values is in [docs/research/motion.md](../research/motion.md).

## Where it lives

- `Sources/TabbiKitCore/Motion/`: the values as pure numbers (`SpringSpec`, `MotionTokens`), tested in `MotionTokensTests` (no overshoot on close, open and close done within their budgets, stagger caps).
- `Sources/TabbiKit/Design/Motion/`: the SwiftUI side.
  `Motion` turns the tokens into `Animation`s, `AnyTransition.notchContent` and `.tabSwitch` are the shared transitions, and `.motion(_:value:)` and `withMotion` apply an animation with the Reduce Motion fallback built in.
- `Theme.Motion.notch`, `.snappy` and `.content` are shorthands for the same values, so existing call sites follow the system.

## Tokens

| Token | Spring | Use |
|---|---|---|
| `Motion.open` | duration 0.45, bounce 0.2 | The notch opening: a small stretch, then it settles. |
| `Motion.close` | duration 0.38, bounce 0 | The notch closing: faster than opening, no overshoot, so it lands. |
| `Motion.hover` | duration 0.25, bounce 0.1 | Hover growth of the closed notch and hover lift of controls (done in 150 to 300 ms). |
| `Motion.snappy` | duration 0.26, bounce 0.14 | Selection, toggles and other small state changes. |
| `Motion.content` | duration 0.34, bounce 0.1 | Content swaps inside the open notch: tabs, phases, list changes. |
| `Motion.press` | duration 0.18, bounce 0 | Press feedback on controls. |
| `Motion.contentIn` | ease out 0.22 s after 0.08 s | Panel content trailing the opening shape. |
| `Motion.contentOut` | ease in 0.12 s | Panel content leaving before the shape collapses. |
| `Motion.reduced` | ease in out 0.18 s | The Reduce Motion replacement for every spring. |

Staggered entrances use `MotionTokens.stagger(index)`: 30 ms per item, capped at 150 ms in total, and no stagger under Reduce Motion (`Motion.staggered`).

## The notch

- Opening uses `Motion.open`; the content trails the shape by 80 ms and grows slightly from the top edge (`AnyTransition.notchContent`).
- Closing uses `Motion.close`; the content fades out in 120 ms, before the shape has collapsed.
- Hovering the closed notch uses `Motion.hover`.
- Switching tabs slides the new panel 24 pt in the direction of travel while it fades (`AnyTransition.tabSwitch`), so the header and the notch never move.
- Every animation is a spring that SwiftUI retargets mid-flight, so a second click or a pointer leaving never waits for the first animation.

## Loading

- `Spinner(tint:size:lineWidth:)` (`Sources/TabbiKit/Components/Loading/`) is the one spinner: an arc in the module accent that turns once a second.
  Never use `ProgressView`, whose AppKit-backed spinner doesn't render in snapshots and ignores the accent.
- `.spinning(isActive)` turns a glyph (a refresh or sync button) while work runs; its clock is paused while inactive.
- Both draw from a `TimelineView` capped at 30 fps (`LoaderClock.frameRate`), so they stop as soon as they leave the screen and draw the same frame for the same date.
- Under Reduce Motion they stop turning and breathe instead: opacity eases between 35% and 100% over 1.6 s (`LoaderClock.breathingOpacity`).
- Show no loader for waits under about 300 ms; pair a loader with a short label that says what is happening.

## Reduce Motion

Every animation has a calm fallback.
In a view, read `@Environment(\.accessibilityReduceMotion)` and pass it to `Motion.adapted`, `Motion.notch(opening:reduceMotion:)`, `Motion.staggered` or the shared transitions, or use `.motion(_:value:)`, which reads it for you.
Outside a view, `withMotion` reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
Under Reduce Motion there is no scale, stretch, slide or particle: things crossfade in 180 ms.

## Rules

- Use the tokens; never a literal duration or a linear animation.
- Animate `opacity`, `offset` and `scaleEffect`; avoid animating blur or shadow on moving content.
- Never loop an animation while idle: no `repeatForever`, no `phaseAnimator` without a trigger, and pause every `TimelineView` that is off-screen or has nothing to show.
- Gate newer symbol effects: `.wiggle`, `.breathe` and `.rotate` need macOS 15, `.drawOn` needs macOS 26.
