# Connections

Connections is where Tabbi helps someone hook up the apps its tabs read from: Anki, Calendar, Claude, Spotify and Music, alerts, Do Not Disturb and Party.
It is written for a first-year student who has never opened Terminal.

## Rules for every row

- Each integration is one row with a status light, a one-line headline, one plain sentence, and at most one primary button.
- The light is one of four answers: Connected, Needs one step, Not set up, Not installed.
  A short-lived Checking light shows only while a probe runs.
- Every problem state has exactly one obvious next button.
  Connected and Checking rows have none; a connected row may offer one quiet suggestion (Calendar offers Add Google Calendar when no Google account is visible).
- Copy stays at about an 8th-grade reading level and never uses jargon such as CLI, API, localhost, port or error codes.
  `ConnectionStatusTests.testCopyAvoidsJargonAndDashes` checks every state's text.
- Status refreshes when Tabbi becomes active, so a fix made in another app turns green on return.

The rules live in `Sources/TabbiKitCore/Connections`: each integration maps its detected state to a `ConnectionStatus` (light, headline, detail, action, suggestion), so the views only draw what the core decides.

`ConnectionKind` names each row, what it unlocks and the tabs it serves, so Connections lists only what the current tabs use.
In the app, `Sources/Tabbi/Connections` holds `ConnectionsStore` (one per app, `ConnectionsStore.shared`), the read-only `ConnectionProbes` that look at the Mac, and the views.
`ConnectionsList` is the embeddable list of rows: the Settings pane shows it for every relevant row, and onboarding or a tab's empty state can show it for just the rows it needs.
A tab whose problem takes more than one click calls `ConnectionsStore.shared.showHub()`, which opens Settings at Connections (the app installs `hubPresenter` at launch).
Today's Up next card and Plan my day do this when the calendar can't be reached from the notch or Claude is missing, and Ask Claude does it when Claude is missing, each with a single "Connect calendar" or "Set up Claude" button.
The store checks only while a list is on screen, once when it appears and again each time Tabbi becomes active.

## Walkthroughs and priming screens

A step that takes more than one click opens a sheet from the row, and `ConnectionsList` presents it, so onboarding gets the same sheets by embedding the list.
`ConnectionGuide.walkthrough()` (core) gives each guide a title, a one-sentence intro, at most three numbered steps with a symbol each, an optional value to copy (the AnkiConnect code, the Claude setup line, the shortcut names) and exactly one start button, such as "Copy code and open Anki".
While a walkthrough is open, the store checks its row every 3 seconds, so the sheet turns green ("You're all set") and offers Done without the user reporting back.
`ConnectionStatus.finishes(_:openedAsSuggestion:)` decides when that is: a guide opened to fix a problem is done once the row is connected, and Add Google Calendar, opened from a row that already works, is done once a Google account shows up.

`ConnectionPermission.priming` is the screen before a macOS prompt: what the Mac will ask, which button to click (Allow), two short reassurances and a single Continue button that leads straight to the prompt, as Apple's guidance asks.

`swift run Tabbi --snapshot <dir>` writes every walkthrough (`connections-guide-<guide>.png`, plus one finished), and every priming screen (`connections-priming-<permission>.png`), rendered as real sheets.

Why Anki is guided, not installed for the user: Anki installs, updates and checks its own add-ons through Get Add-ons, and writing into its add-on folder from outside could break when Anki changes its layout or while Anki is running.
So Tabbi copies the code 2055492159, opens Anki and shows the three clicks.

Claude's setup needs Terminal once, because the official installer is a single line.
The walkthrough copies that line, opens Terminal and says exactly what to press; signing in uses `claude auth login`, which opens Claude's own sign-in page in the browser, so Tabbi never sees a password or key.

## Integrations

| Row | Detected from | Steps from nothing to connected |
| --- | --- | --- |
| Anki | Anki installed (`net.ankiweb.dtop`, `net.ankiweb.anki`), running, AnkiConnect answering | Get Anki, Open Anki, Show me how (add-on code 2055492159), allow access |
| Calendar | EventKit access and the accounts holding calendars | Connect (priming screen, then the macOS prompt), Open Settings if turned off, Add Google Calendar (Internet Accounts) |
| Claude | `claude` found, then `claude auth status --json` (only `loggedIn` is read) | Show me how (official setup page and a copyable install line), Sign in, Check again |
| Spotify, Music | Installed, then Automation permission | Connect (priming screen, then the macOS prompt), Open Settings if denied |
| Alerts | Notification permission | Connect (priming screen, then the macOS prompt), Open Settings if denied |
| Do Not Disturb | `shortcuts list` contains the two Tabbi Focus shortcuts | Show me how, then Test |
| Party | A chosen name and the server connection | Set up (name and pet), then the friend code to share |

Claude is optional: its row says so in one sentence, and Tabbi never asks for a key or reads credentials.

## Research notes

From the UI and UX research done for Tabbi on 2026-10-02.

- Ask for access only when the person uses the feature that needs it, and keep onboarding about the app, not about macOS.
  A pre-alert (priming) screen is allowed but must have exactly one button that leads to the system alert, titled "Continue" or "Next", not "Allow", with no cancel path that skips the alert.
  Sources: https://developer.apple.com/design/human-interface-guidelines/onboarding, https://developer.apple.com/design/human-interface-guidelines/privacy
- Asking for many permissions at first launch is a top complaint about notch apps ("NotchNook wants permission to control Music").
  Source: https://mezha.media/en/2024/07/22/the-notchnook-app-has-been-released-for-macbook-which-makes-the-camera-cutout-on-top-of-the-screen-functional
- Mature utilities (Bartender, Screen Studio) show a permissions checklist with live status per permission, a button that opens the exact System Settings pane, and notice a grant without a relaunch.
  Sources: https://macbartender.com/Bartender5/PermissionInfo, https://screen.studio/guide/setting-up-permissions
- System Settings can show a permission as granted while the app does not see it (a stale entry after the app is re-signed); offer a "reset and try again" hint.
  Source: https://matthewpalmer.net/vanilla/screen-recording-permission.html
- Open-source notch apps get asked for better installation and permission guidance.
  Source: https://github.com/TheBoredTeam/boring.notch/issues/905
- Each module's empty state should prime its own permission in context ("Connect Calendar to see today's classes") with one button, and Settings should have a page with live status and deep links.
- Absorb complexity (detect Anki, pick the calendar) so the user does not have to (Tesler's Law).
  Source: https://lawsofux.com/teslers-law/
