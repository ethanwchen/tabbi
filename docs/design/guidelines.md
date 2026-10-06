# Tabbi design guidelines

These are the rules every Tabbi screen is held to: each module panel, the closed notch, Settings and onboarding, in every theme and kit.
They distill [docs/research/ui-ux.md](../research/ui-ux.md) (Apple HIG, Live Activities, notch apps, cozy study apps, Laws of UX, dense information design), where each rule's sources are listed.
The tokens live in `Sources/TabbiKit/Design/Theme.swift` and the themes in `Sources/TabbiKitCore/Themes/`.
Related pages: [simplicity.md](simplicity.md), [themes.md](themes.md), [motion.md](motion.md), [onboarding.md](onboarding.md).

The top priority is simplicity and everyday usefulness.
When a rule and a feature disagree, remove or hide the feature.

## Principles

1. **Glance first.** The closed notch and each panel's hero answer one question in under a second (Live Activities, Doherty threshold).
2. **One hero per panel.** One dominant element, one primary action, everything else quieter (Hick's law, HIG layout).
3. **Black is the hardware.** The notch and panel body stay opaque and continuous with the camera housing; content sits on `Card` surfaces, never on glass (HIG materials, Liquid Glass guidance).
4. **Less content, not smaller type.** A cramped panel loses rows, not points (information density).
5. **Calm, purposeful motion.** One spring family, no wobble, nothing idles in the closed notch (HIG motion, Boring Notch issues #364 and #335).
6. **Friendly, plain words.** Short sentences, no jargon, never shaming (Forest, Finch, Study Bunny).

## Layout

- The open canvas is fixed at `Theme.Layout.expandedSize` (560 x 236pt); switching tabs never resizes the notch.
- Content keeps `Theme.Layout.contentInset` (20pt) from the panel's sides and never touches an edge or a rounded corner.
- Spacing comes from `Theme.Spacing` only: 2, 4, 8, 12, 16, 24.
  Similar groups use the same gap, and `Card` pads its content by 12pt.
- Corners come from `Theme.Radius` (6, 10, 14) with `.continuous` style.
  A shape nested in a card uses a smaller radius than its card (concentric corners).
- Left edges, baselines and centers line up; no 1 to 2pt drift between rows or between tabs.
- Lists show at most about 3 to 5 rows, then a "+N more" or a scroll only where the list genuinely grows.
- A list cut off by its frame fades out at that edge with `.edgeFade(_:)` (16pt), never a hard clip through a row.
- An element shown beside the closed notch keeps its side when the panel opens (spatial continuity).

## Typography

- One family: SF Rounded through `Theme.Typography` (themes may switch to SF Pro), with `.monospacedDigit()` on every changing number.
- Three text levels per view: the hero (`metric`, 22pt semibold, or a 13pt `title`), body (12pt) and caption (10.5pt).
- Text is never smaller than 10pt.
  SF Symbols used as small glyphs inside a control may go below that, but text may not.
- No Ultralight, Thin or Light weights.
- Hero values, times and counts never truncate; only secondary text may end in an ellipsis, and then it has a `.help` tooltip with the full text.

## Color

- The palette's three text levels have fixed jobs: `primaryText` for content, `secondaryText` for supporting text, `tertiaryText` for metadata.
- Every text level meets WCAG AA (4.5:1) on the brightest card of every theme, glow included, and secondary stays a clear step above tertiary.
  `ThemeCatalogTests.testTextKeepsReadableContrastOnEveryCard` enforces this, so a new theme cannot ship below it.
- One accent per module, from its descriptor (`descriptor.accentColor`), used for the same meaning everywhere.
- Status uses `success`, `warning` and `danger`, and never by color alone: a symbol or a word goes with it.

## Controls

- Every control has a hover state and a `.help(...)` tooltip.
- Primary controls are at least 28 x 28pt (`IconButton` default); nothing clickable is smaller than 20 x 20pt.
- Small floating controls draw with `controlBackground`, which picks the theme's material (Liquid Glass only on macOS 26 and only for controls).
- Destructive actions are small, secondary and away from the primary action.

## Closed notch and tab bar

- The closed shape matches the hardware notch; wings hug it with no gap.
- Each wing shows at most one glyph and one short value ("18m", "5h 86%"), and the two wings are balanced in width.
- The tab bar stays readable with up to 9 tabs: icons and titles keep one size, the selection uses `controlBackground`, and no tab is clipped.
- The tab's title beside the notch shows whole: a slightly long one ("Claude Usage" beside a 185pt notch) shrinks to no less than 88% before it truncates, and it is dropped before it could collide with the gear.
- The pet shortcut (the paw) sits at the far right of the tab row, vertically centered with the tabs, with the same hover treatment as a tab.

## Pets and gamification

- The pet is a companion, not a billboard: it sits in the wing or a corner, never over a module's hero.
- In the closed notch the pet shows only a name the user chose; a pet still going by its breed name shows none, so the wings stay compact.
- Sprites draw at whole-pixel scale (nearest neighbor), so every breed and costume stays crisp at notch size.
- Breeds share one canvas size, baseline and animation timing, so swapping a breed never shifts the layout.
- Reactions follow what the user did (a block finished, cards reviewed) and are immediate; nothing idles or nags in the closed notch.
- Points, streaks and the shop stay off the primary surfaces of everyday tabs.

## States and copy

- Every panel designs its empty, loading, unavailable and error states.
  An empty state is one line of guidance and at most one action ("Connect Calendar to see your day"), never a blank area or a raw error.
  Draw a whole-panel state with the shared `StatusMessage` (`TabbiKit/Components`): the module's glyph in a soft accent badge (a spinner while something is on its way), a title, one line of guidance and the action, so every tab's empty and loading states look alike.
- A figure that is still loading shows a placeholder bar the size of the figure (`.redacted(reason: .placeholder)`), and one caption says what is coming.
  A plain "-" means the value is unknown or not reported, never that it is on its way.
- Copy is sentence case, short and friendly; say what to do, not what went wrong inside.
- Use the product name Tabbi; no emojis and no em dashes (enforced by `scripts/check-style.sh`).

## Motion and accessibility

- Animate with `Theme.Motion` springs (never linear); open and close finish in about 350ms with no overshoot.
- Reduce Motion turns movement into fades, Reduce Transparency turns glass opaque.
- Icon-only buttons have accessibility labels; every gesture has a click or keyboard path.

## Audit checklist

Run `swift run Tabbi --snapshot snapshots --theme all` (and `--kit <id>` for each kit's tabs), open each PNG and mark every item pass or fail.
A screen passes when every item that applies to it passes.

| # | Check | Pass when |
| --- | --- | --- |
| 1 | Canvas | Nothing is clipped at the panel edges or in its rounded corners; content keeps the 20pt side inset. |
| 2 | Opaque body | The panel body is black (or the theme's glow) and continuous with the notch; no glass behind content. |
| 3 | One hero | Exactly one element is clearly the most prominent, and there is one primary action at most. |
| 4 | Type ramp | At most three text sizes; no text below 10pt; no thin weights. |
| 5 | Contrast | Text reads clearly in every theme (AA is enforced by `ThemeCatalogTests`); no hand-picked gray drops below `tertiaryText`. |
| 6 | Grid | Gaps and paddings are on the 4pt scale and similar groups use the same spacing. |
| 7 | Alignment | Left edges, baselines and centers line up across rows, cards and the header. |
| 8 | Corners | Cards use `Theme.Radius`, continuous, and nested shapes are concentric. |
| 9 | Accent | One accent hue per module, used for one meaning; status is never shown by color alone. |
| 10 | Truncation | Hero values, times and counts are whole; truncated secondary text has a tooltip. |
| 11 | Numbers | Changing numbers use monospaced digits. |
| 12 | Controls | Primary controls are at least 28pt, others at least 20pt, each with hover and a tooltip. |
| 13 | Lists | At most about 5 visible rows with an overflow cue; at most about 7 choices per view. |
| 14 | States | Empty, loading, unavailable and error states each show one friendly line and at most one action. |
| 15 | Copy | Sentence case, plain words, Tabbi as the name, no emojis or em dashes. |
| 16 | Closed notch | Each wing shows one glyph and one short value; the wings are balanced and hug the notch. |
| 17 | Tab bar | With up to 9 tabs nothing clips, spacing is even, and the selection and the paw are centered on the row. |
| 18 | Pet | The sprite is crisp at notch size, sits on the shared baseline, and never covers a hero or a control. |
| 19 | Themes | The screen reads equally well in all eight themes (glow, cozy tints, monochrome accents). |
| 20 | Simplicity | Nothing on the screen could be removed or moved under More options without losing everyday use. |

## Before and after sheets

Each fix found by the audit gets a sheet in `docs/design/before-after/`, numbered in order.
Render the snapshots once on the commit before the fix and once after it, then build the sheet:

```sh
scripts/contact-sheet.py snapshots-before snapshots-after docs/design/before-after/NN-topic.png open-closet onboarding-modules
```

Each name is a snapshot file without `.png`; every name becomes one row with the before shot on the left and the after shot on the right.
The script needs Pillow (`pip3 install pillow`).
