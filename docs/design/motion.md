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
| `Motion.check` | duration 0.4, bounce 0.25 | A checkbox turning on: fill pop, check draw-on, small bounce. |
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
- The closed-notch wings are equal in width, so the shape stays centered on the camera, and they are only as wide as the longer side needs (at most `NotchPreviewLayout.maxWingWidth`, 120 pt).
  A preview with two parts puts one in each wing instead of one long line beside an empty wing: a meeting shows its icon and countdown on the left and its title on the right.

## Loading

- `Spinner(tint:size:lineWidth:)` (`Sources/TabbiKit/Components/Loading/`) is the one spinner: an arc in the module accent that turns once a second.
  Never use `ProgressView`, whose AppKit-backed spinner doesn't render in snapshots and ignores the accent.
- `.spinning(isActive)` turns a glyph (a refresh or sync button) while work runs; its clock is paused while inactive.
- Both draw from a `TimelineView` capped at 30 fps (`LoaderClock.frameRate`), so they stop as soon as they leave the screen and draw the same frame for the same date.
- Under Reduce Motion they stop turning and breathe instead: opacity eases between 35% and 100% over 1.6 s (`LoaderClock.breathingOpacity`).
- Content that has a known shape (a list of rows, a paragraph) loads as a skeleton instead of a spinner: `SkeletonLine(fraction:)` and `SkeletonLine(width:)` lines laid out like the real content, so nothing jumps when it arrives, with `.shimmering()` on the group.
  The highlight is masked to the lines and sweeps across in 1.4 s, easing in and out from fully off one edge to fully off the other (`LoaderClock.shimmerOffset`); under Reduce Motion the skeleton breathes instead.
  Plan My Day and the Wrap-up summary use it.
- `ProgressRing(progress:tint:track:lineWidth:)` is the one progress ring: a faint track and an arc in the accent that fills clockwise from twelve o'clock, with the readout inside.
  The arc follows its value with the content spring, so a ticking timer glides instead of stepping.
  A small drop unwinds, but a drop of more than half the ring is a new start (a Pomodoro phase change, a usage window that rolled over), so the arc snaps to the new value instead of sweeping backwards (`RingProgress.change`).
  Missing or non-finite values draw an empty ring (`RingProgress.clamped`).
  Focus, Study, Anki, Claude Usage and Today's rings use it; Today's shared-goal checkbox keeps its own ring because it turns into a filled check.
- `PawLoader(tint:size:label:)` is the loader for longer waits (a few seconds or more): a trail of four paw prints that press in left, right, left, right, as if the pet were trotting past, then fade behind it (`PawTrail`).
  A print presses in over 120 ms, landing 15% large and settling, then fades over 1.1 s; prints are 320 ms apart and each walk ends with a short pause, 2.24 s in all.
  Ask Claude's "Thinking" bubble and Anki's starting-up tile use it; quick waits keep `Spinner`.
  It stays invisible for 300 ms and then fades in over 200 ms (`PawTrail.revealOpacity`), so a fast answer never flashes it; snapshot runs set `\.loaderRevealDelay` to 0.
  Under Reduce Motion the whole trail stands still and breathes.
  `--snapshot` renders `motion-loader-paws.png` (one frame per step), `motion-loader-paws-in-context.png` and `motion-loader-paws-reduced.png`.
- Show no loader for waits under about 300 ms; pair a loader with a short label that says what is happening.

## Celebrations

Celebrations confirm a real event; they are brief, optional and never block input.

- Three tiers.
  A checked-off task gets a symbol bounce and a numeric transition, with no particles.
  A finished focus session or study block, a daily goal met or a streak continued gets a `.burst`: 36 particles, gone within 1.5 s.
  A streak milestone, a level up or an unlock gets a `.milestone`: 72 particles, gone within 2 s.
- `CelebrationPacer` (`Sources/TabbiKitCore/Motion/Celebration.swift`) keeps them rare: at most one burst every ten minutes, and one milestone a day (a second milestone that day plays as a burst).
  When it says no, play the symbol bounce instead.
- `CelebrationBurst` is the particle model: a seeded set of particles whose position, rotation, scale and opacity are pure functions of elapsed time (a fast launch within 35 degrees of vertical, gravity slowed by drag to a 200 pt/s fall, a pop in over 120 ms and a fade over the last 40% of each life).
  Nothing changes per frame, so the same moment always draws the same picture.
- Styles are `.confetti`, `.sparkles`, `.hearts` and `.pawPrints`, each drawn from paths (no image assets) in the module accent plus companions from the app palette.
- A module celebrates a real event through `context.celebrations` (`CelebrationCenter` in `Sources/TabbiKit/Components/Celebration/`): `celebrations.celebrate(.burst, style: .confetti, accent: <Module>Module.descriptor.accentColor)`.
  The center holds the one app-wide pacer, plays nothing while the notch is closed (an unseen event uses up no allowance), taps a `.levelChange` haptic when Settings allows haptics (only felt with a finger on a Force Touch trackpad), and returns the tier that played, or nil so the caller can fall back to its symbol bounce.
  Snapshot runs celebrate nothing.
- Every open panel is a stage (`.celebrationStage(center)`, added once in `ModuleViews.notchContent`), so the burst plays over whichever panel is open.
  The overlay draws with `Canvas` from a `TimelineView` capped at 60 fps, ignores hits, and leaves the hierarchy when the last particle is gone.
  A celebration keeps the date of its event: a panel that appears mid-burst (a tab switch) picks it up where it is, and one that appears later shows nothing.
- Wired today, each only while a panel is open:
  a focus session of the shared Pomodoro that finishes plays a confetti burst in the Focus accent,
  a Study block that finishes plays a paw print burst in the Study accent (beside the corner pet's hop),
  buying a Closet item with points plays a sparkle milestone in the Closet accent (beside the pet's celebration),
  and an Anki review streak that reaches a milestone length plays a confetti milestone in the Anki accent.
- Streak milestones are round lengths only (`StreakMilestone` in `Sources/TabbiKitCore/Motion/`): 7, 14, 30, 50, 100, 200 and 365 days, then every 100 days and every whole year.
  The first look after launch only sets the baseline, a jump past several milestones counts the largest once, and a milestone reached while the notch was closed plays on the next open panel unless the streak broke meanwhile.
- Under Reduce Motion nothing moves: a soft glow of the accent brightens and fades in place over 0.9 s (`CelebrationGlow`).
- `--snapshot` renders a frame strip for each style and tier (`motion-celebration-<style>-<tier>.png`) and for the glow (`motion-celebration-reduced.png`).

## Micro-interactions

Controls answer the pointer with `TactileButtonStyle`, which replaces `.plain` on notch buttons.
A press sinks the control with the press spring (180 ms, no bounce); release springs back with the hover spring.
The amounts live in `TactileFeedback` (`TabbiKitCore/Motion/`, tested in `TactileFeedbackTests`) and move a control's edges by only a few points:

| Preset | Pressed | Hover lift | Use for |
| --- | --- | --- | --- |
| `.control` | 0.92 | 1.06 | icon buttons, transport buttons, tabs |
| `.pill` | 0.97 | 1.03 | labeled pills, artwork, rows |

- `.buttonStyle(.tactile)` is a small control that sinks when pressed.
- `.buttonStyle(.tactile(.pill, lifts: true))` also lifts on hover; use it for one primary control (the play button, the artwork, an empty state's action) rather than for every button, so the lift stays meaningful.
- The label keeps its own hover colors (surface to `surfaceHover`); the style only adds the motion, scoped so it never retimes the label's own changes.
- Disabled buttons neither sink nor lift.
- Under Reduce Motion nothing scales: a press dims the control to 70% instead.
- Adopted by `IconButton`, the tab bar, the Now Playing controls, the Focus, Study and Anki action pills, Study's method rows and the Today focus card's play ring.
- `--snapshot` renders `motion-press.png`: rest, hover, pressed and Reduce Motion pressed for an icon, a play button and a pill.

Checkboxes use `CheckGlyph(isOn:tint:ring:size:)`.
Turning on, the accent fill pops in from the center and the check stroke draws on, short leg first, driven by the check spring (400 ms, bounce 0.25).
The spring's small overshoot swells the fill by at most 8% and is the toggle's bounce; the stroke never overdraws.
Turning off retracts it with the snappy spring, without a bounce.
The timing is pure in `CheckDraw` (`TabbiKitCore/Motion/`, tested in `CheckDrawTests`): the check starts drawing at 30% progress, while the fill still grows until 55%.
- Under Reduce Motion nothing grows or draws: the finished check crossfades in over the ring.
- Adopted by Today's checklist (the checkbox is also `.tactile`) and by the check of shared rows, which keeps its own progress ring (`ring: nil`).
- `--snapshot` renders `motion-check.png`: the draw sampled along the spring at 48 pt and at row size, then the Reduce Motion crossfade.

## Reduce Motion

Every animation has a calm fallback.
In a view, read `@Environment(\.accessibilityReduceMotion)` and pass it to `Motion.adapted`, `Motion.notch(opening:reduceMotion:)`, `Motion.staggered` or the shared transitions, or use `.motion(_:value:)`, which reads it for you.
Outside a view, `withMotion` reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
Under Reduce Motion there is no scale, stretch, slide or particle: things crossfade in 180 ms.

## Rules

- Use the tokens; never a literal duration or a linear animation.
- Animate `opacity`, `offset` and `scaleEffect`; avoid animating blur or shadow on moving content.
  The notch shape itself carries no shadow: it morphs on every frame of open and close, and its own clip would hide a shadow anyway.
- Never loop an animation while idle: no `repeatForever`, no `phaseAnimator` without a trigger, and pause every `TimelineView` that is off-screen or has nothing to show.
- Gate newer symbol effects: `.wiggle`, `.breathe` and `.rotate` need macOS 15, `.drawOn` needs macOS 26.
