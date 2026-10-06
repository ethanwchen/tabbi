# Tabbi UI and UX research

Research date: 2026-10-02.
Scope: a SwiftUI notch app (macOS 14+, tested on macOS 26 Tahoe) with a fixed open canvas of about 560x236pt on a black notch background.
Modules: study timer, Anki, calendar (Today / Plan My Day), Spotify, Ask Claude, pixel pets, study parties.
Audience: everyday productivity users first, with students (the Med School kit) as a cozy-but-clean second audience.

Notation: "HIG" means Apple Human Interface Guidelines.
Statements marked "(convention)" are widely used industry practice rather than a quoted Apple rule.

---

## 1. Apple HIG for macOS

### 1.1 Typography

macOS built-in text styles (SF Pro, no Dynamic Type on macOS):

| Style | Weight | Size (pt) | Line height (pt) | Emphasized |
| --- | --- | --- | --- | --- |
| Large Title | Regular | 26 | 32 | Bold |
| Title 1 | Regular | 22 | 26 | Bold |
| Title 2 | Regular | 17 | 22 | Bold |
| Title 3 | Regular | 15 | 20 | Semibold |
| Headline | Bold | 13 | 16 | Heavy |
| Body | Regular | 13 | 16 | Semibold |
| Callout | Regular | 12 | 15 | Semibold |
| Subheadline | Regular | 11 | 14 | Semibold |
| Footnote | Regular | 10 | 13 | Semibold |
| Caption 1 | Regular | 10 | 13 | Medium |
| Caption 2 | Medium | 10 | 13 | Semibold |

Key rules:

- macOS default text size is 13pt and the minimum is 10pt.
- Avoid Ultralight, Thin, and Light weights, especially at small sizes; prefer Regular, Medium, Semibold, Bold.
- Minimize the number of typefaces; use weight, size, and color for hierarchy instead.
- SF Pro Rounded is a sanctioned alternate voice for soft or rounded UI, which suits a "cozy" brand without leaving the system font.
- SF Symbols use the same nine weights as SF, so match symbol weight to adjacent text weight.
- In running apps the system adjusts tracking automatically, so do not hand-tune tracking in SwiftUI unless mimicking a mockup.
- For live numbers (timers, counts) use monospaced digits (`.monospacedDigit()`) so values do not jitter as they change (convention, consistent with Live Activities numeric content transitions).

Live Activities add a glanceability rule that applies directly to a notch: "Use large, heavier-weight text, a medium weight or higher. Use small text sparingly and make sure key information is legible at a glance."

Sources:
- https://developer.apple.com/design/human-interface-guidelines/typography
- https://developer.apple.com/design/human-interface-guidelines/live-activities

### 1.2 Spacing and layout

- Order content by importance: top and leading side first.
- Align elements to make them scannable; people assume aligned items are related and indented items are subordinate.
- Group related items with negative space, container shapes, or separator lines.
- Use progressive disclosure (disclosure, menus, nested views) to keep layouts clean.
- macOS: avoid displaying content behind the camera housing at the top edge of a window.
- Live Activities: "Use consistent margins and concentric placement."
  Match the corner radius of inner rounded shapes to the outer radius minus the margin (SwiftUI `ContainerRelativeShape`).
- Live Activities: "Don't draw content all the way to the edge of the Dynamic Island"; separate blocks with an inset container shape or a thick line.
- Standard Live Activity Lock Screen margin is 14pt, a useful outer margin reference for a 560x236 panel.
- Control size on macOS: default 28x28pt, minimum 20x20pt.
- Spacing between controls: about 12pt padding around bezeled elements, about 24pt around unbezeled elements' visible edges.
- A 4pt base grid with 8, 12, 16, 20, 24 steps is standard practice for dense panels (convention).

Sources:
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/design/human-interface-guidelines/accessibility

### 1.3 Color

- Avoid using the same color to mean different things; keep status and interactivity colors consistent.
- Prefer system and semantic colors (`.primary`, `.secondary`, `controlAccentColor`); they adapt to Increase Contrast and appearance.
- Do not redefine semantic meanings (for example, do not use separator color as text).
- macOS exposes `controlAccentColor`, the accent the user picked in System Settings; respecting it is a premium signal.
- Dynamic Island guidance: Live Activities use a black opaque background, and Apple recommends "bold colors for text and objects to convey the personality and brand of your app."
  This maps directly to a black notch panel: one bold module tint per module, used sparingly.
- Tint the key line (the thin edge that separates the island from dark content) to match content.
- Liquid Glass color: apply color sparingly; to emphasize a primary action, tint the background rather than the symbol or text.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/color
- https://developer.apple.com/design/human-interface-guidelines/live-activities

### 1.4 SF Symbols

- Nine weights (ultralight to black) matched to SF; three scales (small, medium, large) relative to cap height.
- Four rendering modes: monochrome, hierarchical, palette, multicolor.
  Hierarchical with a single module tint gives depth without extra colors.
- Variable color is for changing values (capacity, progress), not for depth.
- Fill variants add emphasis and suit selected states.
- Symbol animations: Bounce (an action occurred), Scale (persistent emphasis), Replace (state change; down-up, up-up, off-up).
  "Make sure that animations serve a clear purpose."
- SF Symbols 7 adds gradient rendering, best at larger sizes.

Source: https://developer.apple.com/design/human-interface-guidelines/sf-symbols

### 1.5 Accessibility

Contrast minimums used by Accessibility Inspector:

| Text size | Weight | Minimum ratio |
| --- | --- | --- |
| Up to 17pt | All | 4.5:1 |
| 18pt and up | All | 3:1 |
| All | Bold | 3:1 |

- If default contrast falls short, provide a higher contrast scheme when Increase Contrast is on (SwiftUI `@Environment(\.colorSchemeContrast)`).
- Convey information with more than color alone (shapes, icons, text).
- Describe the interface for VoiceOver: label every icon-only button, group composite rows, expose timer value as a readable string.
- Offer alternatives to gestures: any swipe or hover action needs a clickable or keyboard path.
- Support Full Keyboard Access; do not override system shortcuts.
- Minimize time-boxed UI; "Prefer dismissing views with an explicit action."
  This matters for auto-collapsing notch panels and auto-dismissing toasts.
- Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): reduce automatic and repetitive animation, tighten springs to reduce bounce, replace x/y/z transitions with fades, avoid animating into and out of blurs, avoid animating depth.
- Reduce Transparency (`@Environment(\.accessibilityReduceTransparency)`): swap translucent materials for opaque fills.
- Let people control audio playback; never autoplay sound.

Source: https://developer.apple.com/design/human-interface-guidelines/accessibility

### 1.6 Motion

- "Add motion purposefully"; gratuitous animation distracts and can cause discomfort.
- "In apps, generally avoid adding motion to UI interactions that occur frequently."
  Opening and closing the notch happens dozens of times a day, so the transition must be short and calm.
- "Let people cancel motion"; never block input until an animation finishes.
- Live Activities cap system and custom animations at two seconds and use them "only to bring attention to content updates."
- Animate layout changes by moving existing elements to new positions rather than removing and re-adding them.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/motion
- https://developer.apple.com/design/human-interface-guidelines/live-activities

### 1.7 Liquid Glass on macOS 26

What Apple says:

- Liquid Glass "forms a distinct functional layer for controls and navigation elements" floating above content.
- "Don't use Liquid Glass in the content layer."
  Use standard materials for content backgrounds; exception: transient controls like sliders and toggles take on glass while being manipulated.
- "Use Liquid Glass effects sparingly" on custom controls; limit to the most important functional elements.
- Two variants: regular (blurs and adjusts luminosity, legible by default, use for text-heavy components) and clear (highly translucent, only over visually rich media).
- With clear glass over bright content, add a dark dimming layer of about 35% opacity.
- Glass appearance changes with Reduce Transparency, Increase Contrast, and the user's preferred glass look, so never rely on its exact color.
- Standard materials: choose by semantic purpose, not by the color they impart; use vibrant system colors on top; thicker materials give better contrast for fine text.
- macOS offers two blending modes: behind window and within window.

How this applies to a black notch:

- The notch itself is a hardware-black region, and Apple's own Dynamic Island uses an opaque black background, not glass.
  Keep the panel body opaque black so it reads as an extension of the hardware.
- Use glass only for small floating controls (for example a transient scrubber or a hover toolbar), never for module cards or text containers.
- Glass on near-black has almost nothing to refract, so it mostly looks like gray fog; prefer subtle fills like `white.opacity(0.06 to 0.10)` for cards (convention).
- Gate any glass behind `if #available(macOS 26, *)` with `.glassEffect()` and fall back to `.regularMaterial` or an opaque fill on macOS 14 and 15, and always to opaque when Reduce Transparency is on.
- Group multiple glass elements in a `GlassEffectContainer` so they blend and morph instead of stacking glass on glass.

Criticism worth heeding: Nielsen Norman Group found Liquid Glass in iOS 26 reduces contrast and legibility over complex backgrounds and makes the interface feel "restless" and attention-pulling.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/materials
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://www.nngroup.com/articles/liquid-glass/
- https://www.osnews.com/story/143522/liquid-glass-is-cracked-and-usability-suffers-in-ios-26/
- https://en.wikipedia.org/wiki/Liquid_Glass

---

## 2. Dynamic Island and Live Activities patterns for a Mac notch

Apple's presentations and how they map:

| iPhone presentation | Apple definition | Tabbi mapping |
| --- | --- | --- |
| Compact | One activity; a leading element and a trailing element on either side of the camera, reading as one unit | Closed notch "wings": left shows module glyph, right shows live value (for example a timer ring and 18:42) |
| Minimal | Multiple activities; one attached, one detached circle | Closed notch with two concurrent states: highest priority on one wing, a small badge on the other |
| Expanded | Touch and hold reveals a larger version | Hover or click opens the 560x236 panel |
| Lock Screen | Banner with layout similar to expanded | Optional transient toast (for example "Pomodoro done") |

Rules to carry over:

- Compact: "Focus on the most important information."
- Compact: design leading and trailing "to read as a single piece of information" with consistent color and typography.
- Compact: "Keep content as narrow as possible and ensure it's snug against the TrueDepth camera"; no padding between content and the camera.
  On Mac this means wings hug the hardware notch edges with no gap.
- Compact: keep leading and trailing balanced in width; use shortened units or less precision (for example "18m" not "18:42.3").
- Minimal: show updated info rather than a logo when possible (Timer shows remaining time, not an icon).
- Expanded: "Maintain the relative placement of elements"; the expanded view is an enlarged compact view, so the timer that was on the right wing should stay on the right side when the panel opens.
- Expanded: "Wrap content tightly around the TrueDepth camera" to diminish its presence.
- Expanded height can grow or shrink with content; prefer shrinking when there is less to show.
- Interactivity: "prefer limiting it to a single element" to avoid mis-taps; only for things people start, pause, resume.
- Update only when content changes; alert only for essential updates.
- Rotate multiple events through one surface rather than spawning many.
- End promptly; keep a summary visible 15 to 30 minutes at most.
- Avoid sensitive info in glanceable surfaces; show an innocuous summary (relevant for calendar titles and Ask Claude prompts while screen sharing).
- Dynamic Island corner radius is 44pt and matches the camera shape; inner shapes should be concentric.
- Compact element size on iPhone is about 52 to 62pt wide by 36.67pt tall, which gives a sense of how little belongs in a closed wing.
- Apple says to use iOS dimensions for Live Activities shown in the Mac menu bar.

Glanceability rules synthesized:

- One number, one glyph, one color per wing.
- Readable in under one second from normal viewing distance.
- Motion only when the value changes meaningfully (minute rollover, phase change), never idle looping in the closed state.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://infinum.com/?p=28092
- https://9to5mac.com/2022/09/26/iphone-14-pro-live-activities-guidelines/

---

## 3. Teardown: notch apps and cozy study apps

### 3.1 Notch apps

**NotchNook (lo.cafe, paid)**
- Hover makes the notch react; click expands into the "nook" with media controls, shortcuts, and widgets.
- File Tray: drag a file onto the notch to park it, then drag it out later from any Space; AirDrop drop target.
- Premium feel: soft spring expansion, hover acknowledgement before commit, consistent rounded black shape.
- Complaints in reviews: too many permission prompts at once ("NotchNook wants permission to control Music"); a collapse animation that shrinks to slightly larger than the real notch and then pops, making the notch look like it changes size; limited media source support at launch; file tray offered only two options.
- Sources: https://digitaltrends.com/?p=3652635, https://mezha.media/en/2024/07/22/the-notchnook-app-has-been-released-for-macbook-which-makes-the-camera-cutout-on-top-of-the-screen-functional, https://alternativeto.net/software/notchnook/about

**Alcove (paid, about $13.99)**
- Explicitly designed to mimic iPhone Dynamic Island "as closely as possible in feel and behavior."
- Fluid transitions, swipe gestures, live activities, HUD replacement for volume and brightness, calendar alerts, lock screen widgets.
- Premium feel: fidelity to Apple motion curves, replacing the Tahoe system HUD so the notch is the single place for transient status.
- Complaint: price relative to feature set.
- Sources: https://tryalcove.com, https://www.slashgear.com/2175261/macos-apps-give-features-apple-doesnt-include/, https://alternativeto.net/software/alcove/about

**Boring Notch (open source, GPL-3.0, free, macOS 14+)**
- Music controls with visualizer, calendar, camera mirror, battery, file shelf with AirDrop, HUD replacement, notification mirroring with a queue.
- Most-upvoted issues are the best available evidence of what users dislike in notch apps:
  - #364 and #335: requests to disable the "jiggly wobbly" open and close animation.
  - #316 and #407: closing animation not fitted to the real notch; app notch drawn smaller than the hardware notch.
  - #119, #239, #137, #663: hide the notch UI in fullscreen and on external displays.
  - #1359, #814: macOS fullscreen title bar gets stuck when notch hover is enabled.
  - #110: exclude specific apps.
  - #338: too much battery use.
  - #161: be fully transparent unless hovered, to keep screenshots and recordings clean.
  - #121: notch covering menu bar text.
  - #1353: open notch too wide.
  - #35: shadow too heavy in collapsed mode.
  - #905: better installation guidance (Gatekeeper, permissions).
- Sources: https://github.com/TheBoredTeam/boring.notch, https://github.com/TheBoredTeam/boring.notch/issues/364, https://github.com/TheBoredTeam/boring.notch/issues/119, https://github.com/TheBoredTeam/boring.notch/issues/316, https://github.com/TheBoredTeam/boring.notch/issues/338, https://github.com/TheBoredTeam/boring.notch/issues/161, https://github.com/TheBoredTeam/boring.notch/issues/1359

**DynamicLake Pro (paid)**
- Hover or click responds; HUD replacement, calendar, music, interactive notifications, timer widget, Live Activities, "DynaDrop" multi-file drag and drop, Liquid Glass appearance option, also works on non-notch Macs.
- Reviews praise a reorganized, cleaner settings panel and smoother animations after updates, which shows settings polish is part of perceived quality.
- Sources: https://thesweetbits.com/tools/dynamiclake-review/, https://macsources.com/dynamiclake-pro-app-review/

**TopNotch (free)**
- Does one thing: hides the notch by painting a black band into the wallpaper, with rounded corners and multi-display support.
- Lesson: the popularity of a "make it disappear" app means a large group wants the notch region to stay calm and black when idle.
- Sources: https://betanews.com/2021/10/28/hide-the-macbook-pro-notch-for-free-with-topnotch/, https://www.techradar.com/news/cant-stand-the-macbook-notch-theres-an-app-for-that

**What makes notch apps feel premium (synthesis)**
- The closed shape is pixel-identical to the hardware notch (same width, height, bottom corner radius); any mismatch reads as broken.
- Two-stage interaction: hover gives a small acknowledgement (slight grow or glow), click or dwell commits to open.
- One spring curve used everywhere, critically damped or near it, with no visible wobble.
- Opaque black body, subtle inner cards, a single accent per module.
- Stays out of the way: hides in fullscreen, on external displays without a notch, during screen recording if asked.
- Drag-and-drop target that lights up when a file is dragged near the notch.
- Low idle CPU and battery.

### 3.2 Cozy study and planning apps

**Forest**
- Core loop: plant a tree; it grows while you focus and withers if you leave.
- Onboarding plants the first seedling within seconds, teaching through doing.
- Loss aversion drives use; real tree planting partnership adds meaning.
- Complaints: dead trees remain as guilt reminders; accidental starts kill trees; sync issues across platforms; browser version cannot cancel or tag sessions.
- Lesson for Tabbi: keep a short grace window to cancel without penalty, never shame, and allow tagging.
- Sources: https://screensdesign.com/showcase/forest-focus-for-productivity, https://boxesandarrows.com/how-to-use-gamification-in-mobile-apps-a-case-study, https://addons.mozilla.org/de/firefox/addon/forest-stay-focused-be-present/reviews/1510235/, https://clickup.com/learn/topic/productivity/tools/forest/

**Finch**
- Onboarding begins by hatching a pet, framing everything around nurture; users set their own goals.
- Strong feedback: each completion triggers a pet reaction and message.
- Critique: onboarding mixes customization with mental health assessment (violates progressive disclosure); some actions do not trigger feedback, so users doubt input registered; home screen clutter (checklists, shop, journeys, premium prompts); core features paywalled.
- Lesson: pet reactions must be reliable and immediate; keep shop and upsell off the primary surface.
- Sources: https://ixd.prattsi.org/2025/09/design-critique-finch-ios-app-2/, https://screensdesign.com/showcase/finch-self-care-pet

**Study Bunny**
- Focus timer with a bunny companion, coins to buy items and music, to-do list, flashcards, study tracker; pausing gives motivational advice rather than punishment.
- Ratings around 4.3 to 4.6 across regions.
- Lesson: a companion that encourages, plus light collection, is enough; flashcards plus timer in one place matches the med student loop.
- Source: https://appfollow.io/ios/study-bunny-focus-timer/1478345385?country=us

**Flora**
- Pomodoro with growable plants, real tree donations, and social sessions where friends plant together and a failure is visible to the group.
- Lesson: social accountability works, but visible failure should be opt-in and gentle for study parties.
- Sources: https://www.businessofbusiness.com/articles/flora-focus-productivity-app-review/, https://www.commonsensemedia.org/app-reviews/flora-focus-habit-tracker

**Structured**
- One screen: a vertical timeline where block height is proportional to duration, so gaps and overload are visible at a glance; color-coded blocks; Apple Design Award finalist for Inclusivity, praised for ADHD time blindness.
- Lesson for Plan My Day: show time proportionally (a horizontal mini timeline fits a 560pt wide panel), color by category, make free gaps visible.
- Sources: https://daveswift.com/structured/, https://blog.saner.ai/structured-review/, https://apps.apple.com/app/structured-daily-planner/id1499198946

### 3.3 Interaction patterns summary

| Pattern | Best practice | Pitfall |
| --- | --- | --- |
| Hover | Acknowledge within about 100ms; open after a short dwell (about 150 to 300ms) or on click | Opening on pass-through cursor movement toward menu bar items |
| Click | Click the closed notch to open; click outside or move away to close | Requiring precise clicks on tiny targets |
| Close | Close on mouse exit with a short grace delay; never close while a text field is focused or a drag is in progress | Collapsing while the user is typing a Claude prompt |
| Gestures | Two-finger horizontal swipe to change module, always mirrored by visible tabs | Swipe-only navigation (fails accessibility) |
| Drag and drop | Notch lights up as a drop target when a drag starts nearby | Silent drop zones |
| Fullscreen | Hide or go fully passive in fullscreen apps and on non-notch displays | Stuck fullscreen title bars, covering video |
| Keyboard | Global shortcut to open, arrow or number keys to switch modules, Escape to close | Mouse-only |

---

## 4. Laws of UX applied to a tiny dense panel

**Fitts's Law** (time to target depends on distance and size)
- The notch sits on the top screen edge, so the cursor can be thrown upward and stops at the edge; treat the full top edge band of the notch as an infinite-height target for opening.
- Inside the panel, primary actions (start/pause, next card) should be the largest targets, at least 28x28pt, and placed where the cursor enters (near the top center).
- Keep destructive actions small and away from primary ones.
- Source: https://lawsofux.com/fittss-law/

**Hick's Law** (decision time grows with number and complexity of choices)
- Show at most one primary action per module surface and at most about 5 to 7 module tabs.
- Hide rarely used module settings behind a single overflow or in Settings.
- Source: https://lawsofux.com/hicks-law/

**Miller's Law** (working memory holds about 7 plus or minus 2 items; chunk information)
- Chunk: a card shows one fact group (for example Anki: due, new, review counts as one chunk).
- Limit visible items in lists to about 3 to 5 (next three events, three tasks) with "+N more."
- Source: https://lawsofux.com/millers-law/

**Jakob's Law** (users expect your product to work like others they know)
- Users already know Dynamic Island, NotchNook, and Boring Notch: hover to react, click to expand, black pill, media controls in the familiar play/pause layout.
- Use standard macOS controls, standard keyboard shortcuts (Cmd+, for settings, Escape to close), and the system accent color.
- Source: https://lawsofux.com/jakobs-law/

**Aesthetic-Usability Effect** (attractive design is perceived as more usable)
- Polish buys tolerance for the small canvas; pixel pets and a warm accent can make density feel friendly rather than cramped.
- Aesthetics must not mask real issues; test with real tasks.
- Source: https://lawsofux.com/aesthetic-usability-effect/

**Doherty Threshold** (feedback within 400ms keeps users engaged)
- Notch must acknowledge hover in well under 400ms, ideally within one or two frames.
- Panel open animation should complete in about 250 to 350ms (convention), and content must be ready, not loading, when it lands.
- Remote data (Spotify, calendar, Anki, Claude) should render cached state immediately and update in place; show streaming text for Claude.
- Source: https://lawsofux.com/doherty-threshold/

Related laws worth applying:
- Law of Common Region and Proximity: group with subtle card fills and spacing instead of borders (https://lawsofux.com/law-of-common-region/, https://lawsofux.com/law-of-proximity/).
- Goal-Gradient Effect: show progress toward the session goal (ring filling) to motivate completion (https://lawsofux.com/goal-gradient-effect/).
- Peak-End Rule: make the end of a study session delightful (pet reaction, summary) (https://lawsofux.com/peak-end-rule/).
- Tesler's Law: absorb complexity (auto-detect Anki, auto-pick calendar) so the user does not have to (https://lawsofux.com/teslers-law/).

---

## 5. Information density techniques for small panels

1. **One hero per module.**
   Every module view has exactly one dominant element (timer digits, current card count, now-playing art, next event) at Title 1 to Large Title size, with everything else at Callout to Footnote.
2. **Three-level type ramp only.**
   Hero (22 to 26pt semibold rounded), primary (13pt), secondary (11pt in `.secondary`), with 10pt as the floor.
3. **Hierarchy through opacity, not borders.**
   Use primary, secondary, tertiary label colors and card fills at low white opacity; avoid outlines that add visual noise on black.
4. **Proportional representation.**
   Time as length (mini timeline), progress as rings or bars, counts as numbers; let shapes carry meaning so text can shrink.
5. **Abbreviate and round.**
   "2h 15m," "in 12m," "38 due" instead of full sentences; less precision for glance views as Apple recommends for compact presentations.
6. **Top-N with overflow.**
   Show the next three items and a "+4" chip that opens more.
7. **Progressive disclosure inside the canvas.**
   Hover a row to reveal secondary actions; click to drill into a module detail that replaces the panel content with a back affordance.
8. **Fixed grid, fixed slots.**
   Use a consistent column structure (for example a left hero column and right detail column) across modules so the eye knows where to look.
9. **Stable layout.**
   Reserve space for values that change (monospaced digits, fixed width labels) so nothing shifts when data updates.
10. **Edge to edge awareness.**
    Keep a consistent outer margin (about 14 to 16pt) and concentric inner radii; nothing touches the panel edge.
11. **Empty states that teach.**
    When a module has no data, use one line of guidance and one button, not a blank area.
12. **Density is about reading, not pixels.**
    The fix for a cramped screen is usually less content, not smaller type.

Sources:
- https://www.nngroup.com/videos/progressive-disclosure/
- https://www.nngroup.com/articles/progressive-disclosure/
- https://uxdesign.cc/designing-for-information-density-69775165a18e
- https://www.algolia.com/blog/ux/information-density-and-progressive-disclosure-search-ux
- https://developer.apple.com/design/human-interface-guidelines/layout

---

## 6. First-run and onboarding for Mac utilities

Apple guidance:
- Ideally people understand the app by using it; if onboarding is needed, make it "fast, fun, and optional."
- "Teach through interactivity"; prefer context-specific tips over a single long flow.
- Keep onboarding about your app, not about how to use macOS.
- Request access only to data you need, and ideally wait until the person uses the feature that needs it.
- Purpose strings: a brief, complete, specific sentence describing how the data is used.
- Pre-alert screens are allowed but must have exactly one button that clearly leads to the system alert, titled "Continue" or "Next," not "Allow," and no cancel path that skips the alert.
- Prefer letting people experience the app before asking for ratings or purchases.

Mac utility specifics:
- Notch apps commonly need several permissions (Calendar via EventKit, Automation/Apple Events to control Music or Spotify, Accessibility for some HUD or input features, possibly Screen Recording, notifications).
  Asking for them all at first launch is a top complaint (NotchNook review).
- Mature utilities like Bartender and Screen Studio show a permissions checklist with live status per permission, a button that deep-links to the exact System Settings pane, and auto-detect when permission is granted so the user does not need to relaunch.
- Handle the known failure where System Settings shows a permission as granted but the app does not see it (stale TCC entry after re-signing); provide a "Reset and try again" hint.
- Boring Notch users asked for better installation guidance (#905), which matters for an open-source, possibly unsigned or ad hoc signed build.

Recommended Tabbi first run:
1. Launch shows the notch reacting once (a gentle pulse) and a single tooltip-like hint: "Hover the notch to open Tabbi."
2. The first open shows the timer module working with zero permissions, so value appears in seconds (Forest-style "plant your first seed").
3. Pet hatch or pet choice as a one-step delight moment, skippable (Finch-style framing without the long questionnaire).
4. Each other module shows a friendly empty state that primes its own permission in context ("Connect Calendar to see today's classes" with one Continue button that triggers the system prompt).
5. Settings includes a Permissions page with live status and deep links.
6. Pick modules: let users disable modules they do not need, which reduces Hick's Law load and permissions.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/onboarding
- https://developer.apple.com/design/human-interface-guidelines/privacy
- https://macbartender.com/Bartender5/PermissionInfo
- https://screen.studio/guide/setting-up-permissions
- https://matthewpalmer.net/vanilla/screen-recording-permission.html
- https://github.com/TheBoredTeam/boring.notch/issues/905
- https://mezha.media/en/2024/07/22/the-notchnook-app-has-been-released-for-macbook-which-makes-the-camera-cutout-on-top-of-the-screen-functional

---

## 7. Screenshot audit checklist (25 rules)

Each rule is phrased so an agent can mark pass or fail from a screenshot (and, where noted, a short screen recording or settings toggle).

1. **Notch fit:** The closed shape matches the hardware notch exactly in width, height, and bottom corner radius, with no visible sliver of wallpaper or overhang on either side.
2. **Opaque body:** The panel background is solid black continuous with the notch; no gray haze, no glass over the panel body.
3. **Concentric corners:** Every inner card's corner radius equals the outer radius minus its inset, and no element pokes into a rounded corner.
4. **Outer margin:** All content keeps a consistent outer margin of about 14 to 16pt; nothing touches the panel edge.
5. **One hero:** Each module view has exactly one visually dominant element, clearly larger or bolder than everything else.
6. **Type floor:** No text is smaller than 10pt, and body text is about 13pt.
7. **Type ramp:** No more than three distinct text sizes and one typeface family (SF Pro or SF Pro Rounded, plus monospaced digits) are visible in a single view.
8. **No thin weights:** No Ultralight, Thin, or Light weights appear, especially at small sizes.
9. **Contrast:** Text under 18pt reaches at least 4.5:1 against its background; larger or bold text reaches at least 3:1; secondary gray text on black is checked, not assumed.
10. **Color discipline:** At most one accent hue per module is visible, used consistently for the same meaning, and the same color never means two different things.
11. **Not color alone:** Every state shown by color (overdue, running, paused, error) is also shown by a symbol, shape, or text.
12. **Symbol weight match:** SF Symbols match the weight of adjacent text and share one rendering style per view.
13. **Alignment:** Elements align to a common grid; left edges, baselines, and centers line up with no 1 to 2pt drift.
14. **Spacing rhythm:** Gaps between elements come from a single scale (for example 4, 8, 12, 16, 24) and similar groups use identical spacing.
15. **Target size:** Every clickable control is at least 20x20pt and primary controls at least 28x28pt, with visible separation between adjacent controls.
16. **Item limit:** Lists show at most about 3 to 5 items with an overflow indicator, and a view offers at most about 5 to 7 navigational choices.
17. **No truncation of key data:** The hero value, event times, and counts are never truncated or ellipsized; only secondary text may truncate.
18. **Stable numerals:** Changing numbers use monospaced digits so layout does not shift between frames.
19. **Closed state glanceability:** In the closed or compact state, each side shows at most one glyph and one short value, readable in under a second, with balanced widths.
20. **Spatial continuity:** An element shown in the closed state (for example the timer on the right wing) appears in the same relative position when the panel opens.
21. **Empty states:** Modules without data show a one-line explanation and a single clear action, never a blank area or a raw error.
22. **No dead ends or upsells:** No ads, promo banners, or shop prompts appear on primary module surfaces.
23. **Privacy at a glance:** Sensitive content (calendar titles, Claude prompts) can be hidden or summarized, and the closed state never shows full private text.
24. **Accessibility modes:** With Reduce Transparency on, any translucent element becomes opaque; with Increase Contrast on, text and separators get stronger; with Reduce Motion on, open and close use a fade or instant change with no bounce (verify via toggle and recording).
25. **Calm motion and context:** Open and close complete in under about 350ms with no wobble or overshoot, nothing animates idly in the closed state, and the notch UI hides in fullscreen apps and on displays without a notch (verify via recording).
