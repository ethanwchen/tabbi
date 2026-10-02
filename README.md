<p align="center">
  <img src="docs/images/hero.png" alt="NotchDeck open on the Now Playing panel, with the notch expanded into a dark panel showing album artwork, a progress bar and playback controls" width="100%">
</p>

<h1 align="center">NotchDeck</h1>

<p align="center">
  <strong>Turn your MacBook's notch into a tiny command deck.</strong>
  <br>
  Music, system stats, Claude limits, your day and a quick Claude prompt, one click away.
</p>

<p align="center">
  <a href="#install">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#build-from-source">Build from source</a> ·
  <a href="#permissions">Permissions</a> ·
  <a href="#privacy">Privacy</a> ·
  <a href="#faq">FAQ</a>
</p>

---

NotchDeck is a small, native macOS app that lives in the notch.
Closed, it is invisible except for a quiet live activity, like an equalizer while music plays.
Click it and the notch grows into a dark panel with five modules.
Flip between them with a two-finger swipe, the arrow keys or the tab icons, and press Esc to close it again.

It is written in Swift with SwiftUI and AppKit, has no third-party dependencies, no account and no telemetry.

<p align="center">
  <img src="docs/images/closed.png" alt="The closed notch with a small album cover on the left and a green equalizer on the right" width="600">
</p>

## Features

### Now Playing

Album artwork, track, artist, a scrubbable progress bar, and play, skip, shuffle and repeat controls for Spotify and Apple Music.
While music plays, the closed notch shows the cover and a live equalizer.

<img src="docs/images/now-playing.png" alt="Now Playing panel" width="680">

### System

CPU, GPU and memory at a glance, with a short history so you can see spikes, sampled only while the panel is open.

<img src="docs/images/system.png" alt="System panel" width="680">

### Claude Usage

Your 5-hour and weekly Claude limits, read through your own `claude` CLI, plus today's token and message totals from your local Claude Code transcripts.

<img src="docs/images/claude-usage.png" alt="Claude Usage panel" width="680">

### Today

A daily checklist that lives one click away, with progress for the day and quick add.

<img src="docs/images/today.png" alt="Today panel" width="680">

### Ask Claude

A quick question box that streams answers from your local `claude` CLI, with Markdown rendering and follow-up questions.

<img src="docs/images/ask-claude.png" alt="Ask Claude panel" width="680">

## Install

1. Download `NotchDeck-<version>.zip` from the [latest release](https://github.com/ethanwchen/notchdeck/releases/latest).
2. Unzip it and drag **NotchDeck.app** into `/Applications`.
3. Open it once as described below, then click the notch.

NotchDeck has no Dock icon and no menu bar item.
To quit, right-click the notch and choose **Quit NotchDeck**.

### First launch: the app is not notarized

Releases are ad-hoc signed but not notarized, because notarization needs a paid Apple Developer ID.
macOS will therefore refuse to open a freshly downloaded copy the first time.
Use one of these once:

- **System Settings:** try to open the app, then go to **System Settings > Privacy & Security** and click **Open Anyway** next to the NotchDeck message.
- **Right-click:** on macOS 14, right-click (or Control-click) NotchDeck.app in Finder, choose **Open**, then confirm.
- **Terminal:** clear the quarantine flag.

  ```sh
  xattr -dr com.apple.quarantine /Applications/NotchDeck.app
  ```

To verify the download, compare it with the `.sha256` file from the release:

```sh
shasum -a 256 -c NotchDeck-<version>.zip.sha256
```

## Requirements

- macOS 14 Sonoma or later, on Apple silicon or Intel.
- A MacBook with a notch for the full experience. Other displays get a virtual notch at the top center of the screen (see the [FAQ](#faq)).
- Spotify or Apple Music for Now Playing.
- [Claude Code](https://claude.com/claude-code) installed and signed in, for Claude Usage and Ask Claude.

## Build from source

You need Xcode 16 or later, or a Swift 6 toolchain, on macOS 14+.

```sh
git clone https://github.com/ethanwchen/notchdeck.git
cd notchdeck
scripts/run.sh                  # builds build/NotchDeck.app (debug) and launches it
```

Other useful commands:

```sh
swift build                     # compile; must stay warning-free
swift test                      # unit tests for NotchDeckCore
NOTCHDECK_DEMO=1 swift run NotchDeck --snapshot snapshots   # render every notch state to PNG with sample data
scripts/release.sh              # universal, ad-hoc signed release zip in build/release/
```

`NOTCHDECK_DEMO=1` swaps every data source for realistic sample data, so you can try the UI without Spotify, a calendar or the `claude` CLI.

## Permissions

NotchDeck asks for each permission only when the module that needs it is first used.
You can change any of them later in **System Settings > Privacy & Security**.

| Permission | Asked by | Why |
| --- | --- | --- |
| **Automation: Spotify** | Now Playing | Read the current track and send play, pause, skip, seek, shuffle and repeat commands to Spotify through Apple Events. |
| **Automation: Music** | Now Playing | The same for Apple Music. |
| **Calendars** | Today | Show your next events and their video call links. Events are read on your Mac and never leave it. |
| **Notifications** | Today | Tell you when a focus timer ends while the notch is closed. |

Claude Usage and Ask Claude need no system permission.
They run the `claude` command that is already installed and signed in on your Mac.

## Privacy

- **No telemetry, no analytics, no server.** NotchDeck does not phone home.
- **The only network requests it makes itself** are for album artwork URLs that Spotify provides.
- **Claude features go only through your local `claude` CLI.** NotchDeck never reads your Claude credentials or the keychain.
  Ask Claude sends your question to Claude through that CLI, exactly as if you had typed `claude -p` in a terminal.
- **Claude Usage** reads token counts from the transcripts in `~/.claude/projects`, read-only, and never writes there.
  Checking your limits sends a tiny request with the cheapest model, so it never runs until you press refresh once.
  After that, it runs when you press refresh or open the panel 10 or more minutes after the last check.
- **Your checklist** is stored locally in your user Library and nowhere else.

## FAQ

**Does it work on Macs without a notch?**
Yes.
On a display without a notch, NotchDeck draws a virtual notch, a small black pill at the top center of the screen, that opens into the same panel.
It looks most at home on a notched MacBook, though.

**Why does it use the `claude` CLI instead of an API key?**
So NotchDeck never has to handle your credentials.
The CLI is already signed in, already knows your plan and its limits, and keeps your Claude usage in one place.
It also means there is no API key to paste into a third-party app and no extra billing.

**Do I need Claude Code to use NotchDeck?**
No.
Now Playing, System and Today work without it.
The two Claude panels show a short setup hint until the `claude` command is found.

**Why is the app not notarized?**
Notarization requires a paid Apple Developer account.
The release is ad-hoc signed and its checksum is published with every release, and you can always [build it from source](#build-from-source).

**How do I quit it?**
Right-click the notch and choose **Quit NotchDeck**.

**Does it slow my Mac down?**
It is a small native app with no web views.
System sampling and Claude refreshes only run while their panel is open, and Now Playing only resyncs with the player every few seconds while you are looking at it.

## Contributing

Contributions are welcome.
Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the dev setup and the snapshot workflow, and [AGENTS.md](AGENTS.md) for the architecture and design rules.
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md), and report security issues privately as described in [SECURITY.md](SECURITY.md).
Notable changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

NotchDeck is released under the [MIT License](LICENSE).
