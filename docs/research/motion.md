# Motion research for Tabbi

Researched 2026-10-02 (pre-research) and 2026-10-05 (this summary).
Target: a SwiftUI notch app on macOS 14 and later.
Items marked "inference" are judgment, not a quoted source.
The design rules that come out of this research live in [docs/design/motion.md](../design/motion.md).

## Principles from Apple's HIG

From the HIG Motion page (https://developer.apple.com/design/human-interface-guidelines/motion):

- "Add motion purposefully, supporting the experience without overshadowing it. Don't add motion for the sake of adding motion."
- "Make motion optional. Not everyone can or wants to experience the motion in your app or game, so it's essential to avoid using it as the only way to communicate important information."
- "Aim for brevity and precision in feedback animations."
- "In apps, generally avoid adding motion to UI interactions that occur frequently."
- "Let people cancel motion. As much as possible, don't make people wait for an animation to complete before they can do anything."
- "Consider using animated symbols where it makes sense" (SF Symbols 5 and later).
- macOS has no platform-specific motion guidance beyond the general rules.

What this means for Tabbi (inference): the notch opens and closes dozens of times a day, so its motion must be short, calm and interruptible, and the panel must accept input while it is still settling.

## Reduce Motion

- SwiftUI: `@Environment(\.accessibilityReduceMotion)`.
  Apple: "If this property's value is true, UI should avoid large animations, especially those that simulate the third dimension."
  Source: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion
- AppKit: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, with changes posted as `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on the workspace notification center.
- Rule for Tabbi (inference): under Reduce Motion there is no scale, stretch, slide, particle or parallax; state changes crossfade in 200 ms or less, or happen instantly.

## Springs

Apple has not published Dynamic Island constants.
The published spring model (WWDC23 "Animate with springs", https://developer.apple.com/videos/play/wwdc2023/10158/):

- A spring is a perceptual `duration` plus a `bounce` from -1 to 1.
  About 0.15 bounce "feels brisk", about 0.3 is noticeably bouncy, and above 0.4 risks feeling exaggerated.
- Conversion with unit mass: `stiffness = (2 pi / duration)^2`, `damping = (1 - bounce) * 4 pi / duration` for bounce >= 0.
  `Spring(duration: 0.5, bounce: 0.2)` gives stiffness 157.9 and damping 20.1 (verified locally, and covered by `MotionTokensTests`).
- Springs keep velocity when retargeted, which is what makes an interrupted animation feel continuous.

SwiftUI presets, evaluated locally in Swift 6.3.3:

| Preset | duration | bounce | damping ratio | settles in |
|---|---|---|---|---|
| `.smooth` | 0.5 | 0.0 | 1.0 | 0.80 s |
| `.snappy` | 0.5 | 0.15 | 0.85 | 0.88 s |
| `.bouncy` | 0.5 | 0.30 | 0.70 | 1.04 s |
| `.spring(response: 0.55, dampingFraction: 0.825)` | 0.55 | 0.175 | 0.825 | 0.98 s |
| `.interactiveSpring` default | 0.15 | 0.14 | 0.86 | 0.29 s |

## Dynamic Island and notch apps

What open-source notch apps ship (source grep, 2026-10-02):

| Project | Open | Close |
|---|---|---|
| Boring Notch `ContentView.swift` | `.spring(response: 0.42, dampingFraction: 0.8)` (bounce 0.2) | `.spring(response: 0.45, dampingFraction: 1.0)` (no bounce) |
| DynamicNotchKit `DynamicNotchStyle.swift` | `.bouncy(duration: 0.4)` on notched Macs | `.smooth(duration: 0.4)` |
| NotchDrop `NotchViewModel.swift` | `.interactiveSpring(duration: 0.5, extraBounce: 0.25)` | same as open |

Sources:
https://github.com/TheBoredTeam/boring.notch/blob/main/boringNotch/ContentView.swift,
https://github.com/MrKai77/DynamicNotchKit/blob/main/Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift,
https://github.com/Lakr233/NotchDrop/blob/main/NotchDrop/NotchViewModel.swift

A recurring complaint about Boring Notch and NotchNook is a wobble or overshoot "pop" when the notch collapses.

"Stretch and settle" traits to recreate (inference from watching the Dynamic Island and the apps above):

1. Asymmetric springs: expand with bounce 0.15 to 0.25, collapse critically damped (bounce 0) and a little faster, so it lands without wobble.
2. The shape leads and the content follows: content fades in 60 to 100 ms after the shape starts, and fades out before the shape collapses.
3. The top edge stays pinned to the hardware notch; width reads as the dominant axis; corner radii grow with height.
4. A small overshoot (about 1.02 to 1.05) is the stretch, reserved for opening and live activity arrivals, never for every hover.
5. Interruptible: retarget mid-flight, never queue animations.
6. Elements keep their relative position between the closed and open states, so the eye can follow them.

Liquid Glass (macOS 26) uses the same spring vocabulary for its morphs (inference: Tabbi stays on macOS 14 APIs and does not depend on glass effects; the notch is hardware-black by design).

## SwiftUI techniques and availability

| API | macOS |
|---|---|
| `TimelineView`, `Canvas` | 12.0 |
| `phaseAnimator`, `keyframeAnimator`, `geometryGroup()`, `.blurReplace`, `visualEffect` | 14.0 |
| `contentTransition(.numericText(value:))` | 14.0 |
| `symbolEffect` `.bounce`, `.pulse`, `.variableColor`, `.scale`, `.appear`, `.disappear`, `.replace` | 14.0 |
| `.wiggle`, `.breathe`, `.rotate` symbol effects | 15.0, gate with `if #available(macOS 15, *)` |
| `.drawOn` / `.drawOff` symbol effects | 26.0 |
| `sensoryFeedback` | 14.0 |
| `NSHapticFeedbackManager` | 10.11 |

Source: Apple's SwiftUI documentation for each symbol, https://developer.apple.com/documentation/swiftui

- `phaseAnimator` without `trigger:` loops forever, a hidden CPU cost in an always-visible notch; prefer the trigger form.
- `matchedGeometryEffect`: one source per id at a time; add `.geometryGroup()` on containers whose children jump during the morph.
- `contentTransition(.numericText(value:))` with `.monospacedDigit()` for timers and counters; cheap at 1 Hz.
- Prefer discrete symbol effects (`value:`); indefinite ones (`isActive:`) must be turned off when idle.

## Particles with TimelineView and Canvas

Rules (https://www.hackingwithswift.com/articles/246/special-effects-with-swiftui, https://developer.apple.com/forums/thread/751126):

- Derive every particle's position from elapsed time and a precomputed seed; never mutate `@State` per frame.
- Resolve symbols once, cap the particle count, and remove the view when the last particle dies so idle CPU returns to zero.
- `TimelineView(.animation)` ticks at display refresh (up to 120 Hz) while in the hierarchy; use `paused:` and `minimumInterval:` (30 fps is plenty for ambient effects).

## Haptics on the Mac

- Haptics only come from a Force Touch trackpad through `NSHapticFeedbackManager`, and only while a finger is on it.
  Apple: "a Force Touch trackpad won't provide haptic feedback if the user isn't touching the trackpad. Call this method only in response to user-initiated actions."
  Source: https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:)
- Patterns are `.generic`, `.alignment` and `.levelChange`; pair each with visual feedback and treat them as garnish.

## Performance in an always-on window

1. Pause or remove `TimelineView`s when the notch is closed, the screen sleeps, or the window is occluded.
2. `.blur`, `.shadow`, masks, `.compositingGroup()` and `.drawingGroup()` render offscreen; avoid them on moving content.
3. Animate `scaleEffect`, `offset` and `opacity`, which are render-only, rather than the frame of large text.
4. Usual idle CPU leaks: indefinite `phaseAnimator`, `repeatForever` animations and `symbolEffect(isActive:)` left on.
   Target (inference): near-zero CPU when idle, under about 5 percent of one core during ambient animation on an M1.
   Source: https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)

## Loading states

- Response time limits: 0.1 s feels instant, 1 s keeps flow, 10 s keeps attention.
  Source: https://www.nngroup.com/articles/response-times-3-important-limits/
- Doherty threshold: give feedback within 400 ms.
  Source: https://lawsofux.com/doherty-threshold/
- Skeletons versus spinners: under 1 s show nothing; 2 to 10 s a spinner for one module or a skeleton for a whole view; over 10 s a progress bar; skeletons must be shaped like the real content.
  Source: https://www.nngroup.com/articles/skeleton-screens/

Rules for Tabbi (inference):

1. Show no indicator for the first 300 ms; once shown, keep it at least 400 ms so it never flickers.
2. Prefer content-shaped skeletons with a shimmer sweeping every 1.2 to 1.5 s; no shimmer under Reduce Motion.
3. For tiny inline waits (a toggle that talks to AppleScript) use optimistic UI: flip immediately, revert with a subtle shake on failure.
4. Show cached content instantly with a stale marker rather than a skeleton.

## Celebrations

Calibration from libraries:

- canvas-confetti defaults: 50 particles, spread 45 degrees, start velocity 45, gravity 1, about 3.3 s, and `disableForReducedMotion`.
  Source: https://github.com/catdad/canvas-confetti
- ConfettiSwiftUI defaults: 20 particles, size 10, opening angle 60 degrees, triggered by incrementing a counter.
  Source: https://github.com/simibac/ConfettiSwiftUI

Rules for Tabbi (inference, consistent with the HIG's "purposeful, brief, optional"):

1. Three tiers: micro (a completed task or Pomodoro: a symbol bounce and a numeric transition, 300 to 500 ms, no particles), medium (daily goal, streak continued: a small burst of 30 to 40 particles inside the notch, 1.2 to 1.6 s), and major (streak milestones, level up: up to about 80 particles, under 2 s, optional soft sound, at most once a day).
2. Only for real events, at most one particle celebration per 10 minutes, never blocking input, confined to the notch panel.
3. Reduce Motion: no particles; a static badge and an opacity-only color pulse.
4. Physics that reads well in a small area: 250 to 450 pt/s upward with plus or minus 35 degrees of spread, gravity about 900 pt/s squared, lifetimes 0.9 to 1.6 s fading over the last 40 percent, gentle rotation, 5 to 7 colors from the app palette.

## Sources

- https://developer.apple.com/design/human-interface-guidelines/motion
- https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion
- https://developer.apple.com/videos/play/wwdc2023/10158/
- https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:)
- https://developer.apple.com/documentation/swiftui/view/drawinggroup(opaque:colormode:)
- https://developer.apple.com/forums/thread/751126
- https://www.hackingwithswift.com/articles/246/special-effects-with-swiftui
- https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-custom-animated-drawings-with-timelineview-and-canvas
- https://www.nngroup.com/articles/response-times-3-important-limits/
- https://www.nngroup.com/articles/skeleton-screens/
- https://lawsofux.com/doherty-threshold/
- https://github.com/TheBoredTeam/boring.notch
- https://github.com/MrKai77/DynamicNotchKit
- https://github.com/Lakr233/NotchDrop
- https://github.com/catdad/canvas-confetti
- https://github.com/simibac/ConfettiSwiftUI
