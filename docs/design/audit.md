# Design audit record

This is the record of the whole-product design pass against the [audit checklist](guidelines.md#audit-checklist).
Each row is a group of snapshots, rendered with `swift run Tabbi --snapshot` (live and with `TABBI_DEMO=1`), and the result after the fixes listed beside it.
The numbers in the Fixes column are the before and after sheets in [before-after/](before-after/).

## How it was run

- Every screen of the default kit, live and demo, in Midnight.
- The main panels (Today, Timer, Focus, Schedule, System, Claude Usage, Now Playing, Ask Claude, Anki, Party, Closet) in all eight themes with `--theme all`.
- The Med School kit (`--kit medicine`) for its tabs and every Settings pane.
- The Schedule states that need `TABBI_SCHEDULE_PREVIEW` (`selected`, `week`, `plan`, `plan-refining`, `plan-week`, `plan-week-selected`, and the empty states).
- Every pet breed, animation, outfit and accessory at notch size (the sheets in [pets/](pets/)), and the paw shortcut in every theme.

## Results

| Screens | Result | Fixes |
| --- | --- | --- |
| Closed notch (`closed*`) | Pass | 06: an unnamed pet no longer widens the wing with its breed name |
| Tab bar (`open-header-*`, 4 to 10 tabs, More menu) | Pass | 02: long titles shrink a little before they truncate |
| Paw shortcut (`open-pet-shortcut`, all themes) | Pass | Press feedback now matches the tabs |
| Today (`open-planner`) | Pass | None |
| Timer (`open-study`) | Pass | 05, 08: the method title and the dial no longer repeat "Timer" |
| Focus (`open-focus`) | Pass | 07: one card for the task, sound and Do Not Disturb |
| Schedule, day and week, every preview state | Pass | 10: the now line passes behind block titles |
| System (`open-system`) | Pass | 03: a CPU figure still being measured shows a placeholder |
| Claude Usage (`open-claudeUsage`) | Pass | Demo data names a current model |
| Ask Claude (`open-claudeAsk*`) | Pass | 04, 11: empty and loading states use the shared `StatusMessage` |
| Now Playing (`open-spotify`) | Pass | 04 |
| Anki (`open-anki`) | Pass | 04, and no text below 10pt |
| Party (`open-party`) | Pass | None |
| Closet (`open-closet*`) | Pass | 09: the wardrobe fades out at its bottom edge |
| Coach bubbles (`coach-*`) | Pass | None |
| Onboarding (`onboarding-*`) | Pass | 01: Back and Continue are back inside the notch |
| Settings and Connections (`settings-*`, `connections-*`) | Pass | None |
| Motion (`motion-*`) | Pass | None |
| Pets (`pets/*.png`) | Pass | None needed |
| Text contrast, every theme | Pass | Secondary and tertiary text raised to WCAG AA, enforced by `ThemeCatalogTests` |

## Left as is on purpose

- Today shows both the "Focus time" goal row and the timer card: one reports progress, the other starts the clock.
- Very short proposed blocks on the Schedule day timeline show no title (it would be only an ellipsis); the tooltip and the strip under the timeline name them.
- On a new pet, the Closet footer names the Beanie, which sits on a shelf below the fold; reordering shelves would change behavior, and the fade shows there is more below.
