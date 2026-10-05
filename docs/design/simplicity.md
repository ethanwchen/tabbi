# Tabbi simplicity

Tabbi should be useful in the first minute, with no trip to Settings, and stay quiet after that.
This page records what the simplicity pass removed, merged or hid, why, and how many clicks the common actions take.

## Principles

- **Fewer choices, sensible defaults.** A fresh install works with the Essentials kit as it ships: Timer, Today, Now Playing and Ask Claude, with the pet as a paw at the far right of the tab row.
- **One obvious action per screen.** Each panel has one primary button (Start focus, Add a task, play, Ask) and everything else is secondary.
- **Progressive disclosure.** Rare settings sit under **More options**, collapsed by default, never in the main path.
- **Plain words.** Sections and tabs are named for what they do (Timer, Today, Look), not for how they work.
- **Nothing that nags.** Permissions are asked only by a tab that is on, inside a step that shows what they are for (see [onboarding.md](onboarding.md)).

## What changed and why

### Removed or renamed

- **Study is called Timer.** Most people want a countdown, not a study session, so the tab header, the Tabs list and Today's timer card say Timer.
  The module id stays `study`, so kits and saved data are unchanged.
- **"Study time" became "Focus time"** in Today's daily goal row, for the same reason.
- **Today's idle timer card** no longer reads "Study timer / Start a session in Study"; it shows one action, "Start a timer", which opens the Timer tab.
- **Skip on the plain Timer.** A single countdown has no next phase, so its skip button is hidden; reset stops it.

### Merged

- **Eight or more Settings panes became five:** General, Tabs, Look, Connections and About.
  Before, the toolbar listed General, Appearance, Modules, Connections, Preview, Shortcuts, one pane per module with settings, Claude and About, and it grew each time a module was turned on.
- **Preview and Shortcuts merged into General.** Live activity is one switch there, and the global shortcut is one row with a one-line footer for the fixed in-notch keys.
- **Modules and Kit merged into Tabs.** The kit picker, the list of your tabs (drag to reorder) and the Add more library are one page.
- **Module panes became Options buttons** on their tab row in Tabs, opened as a sheet with a Done button.
  Today and Focus share one Options sheet (the focus sound and Do Not Disturb), because both show the same focus timer.
- **The Claude pane moved into Connections**, beside every other link to the outside world, and shows only while a Claude tab is on.
- **Appearance became Look**, with a live mini preview of each theme.

### Hidden under More options

| Section | Tucked away | Why |
| --- | --- | --- |
| General | Haptics, celebration sound, which display, live activity interval and items | The defaults suit almost everyone. |
| Tabs | Import Kit, Remove Kit, Run Setup Again, Reset to Kit Defaults | Used once, if ever. |
| Connections | The Claude CLI location | Found automatically; only needed for unusual installs. |

### Added, because they earn their place

- **A plain Timer**, the method the Essentials Timer tab starts on: 5, 10 and 25 minute chips that start the countdown in one click, and a stepper for any other length, with no breaks or rounds.
  On a countdown that is already running or paused, a chip only changes its length.
  Pomodoro and the other focus methods stay one menu away, and the Med School kit still starts on Pomodoro.
- **Everyday questions in Ask Claude.** The empty chat suggests dinner ideas, a polite reminder and focus tips instead of developer questions, and its one line of copy is shorter.
- **Instant task capture.** When the global shortcut opens the notch on Today, the cursor starts in the Add a task field.
  Opening with the pointer does not steal focus, so a hover-opened notch still closes when the pointer leaves.
- **Reset to Defaults** at the bottom of General and Look.
  It is disabled when nothing would change and says "Back to defaults" after a reset.
  It leaves launch at login, your tabs, your theme choice in General and the Claude location alone.
- **Plain status in Connections.** A row never says connected when it is not: Do Not Disturb that is turned off says so with a Turn on button, an Anki key that blocks access is caught, and a build that can't ask for the calendar says so instead of offering Connect.

### Kept on purpose

- **No search field in Settings.** Every section shows fewer than about ten settings before More options, so a search would add a control without saving a click.
- **Five sections, no more.** A new module adds an Options button on its tab row, never a toolbar item.

## Two-click map

Counted from the closed notch, with the default settings (open on click, Essentials kit).
The global shortcut is Control-Option-Space and can be changed in **Settings > General**.

| Action | How | Clicks |
| --- | --- | --- |
| Add a task | Shortcut on Today, then type; or click the notch, then the Add a task field | 0 (shortcut) or 2 |
| Start a 5, 10 or 25 minute timer | Click the notch (on Timer), then a length chip | 2 |
| Start a Pomodoro | Click the notch (on Timer), then Start focus once Pomodoro is picked in the method menu (it stays picked) | 2 (4 the first time) |
| Play or pause music | Click the playing music wing, then play or pause | 2 |
| Ask Claude | Shortcut on Ask Claude, then type; or click the notch, then the Ask Claude tab, then type | 0 (shortcut) or 2 |
| Check a task off | Click the notch (on Today), then its circle | 2 |
| Open a meeting or timer shown beside the notch | Click it | 1 |
| Switch tabs | Click the notch, then a tab (or arrow keys, 1-9, a two-finger swipe) | 2 |
| Open Settings | Click the notch, then the gear; or right-click the notch, then Settings | 2 |
| See your pet | Click the notch, then the paw | 2 |

The notch reopens on the last tab used, and clicking a live activity opens the tab it belongs to, so a tab you just used is usually one click away.

## First minute, as a new user

1. Tabbi opens the notch on setup: pick Essentials (one tap), answer one question, keep the suggested tabs, name the pet.
   Every step can be skipped.
2. The notch opens on the first tab with something to do right away: a 5, 10 or 25 minute chip, the Add a task field, or Ask Claude anything with three example questions.
3. Nothing needs Settings.
   Calendar and Music ask for access from their own tab, the first time they are used.
