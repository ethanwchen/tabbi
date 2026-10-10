<p align="center">
  <img src="docs/images/icon.png" alt="Tabbi app icon" width="128" height="128">
</p>

<h1 align="center">Tabbi</h1>

<p align="center">
  A little cat for your laptop notch.
</p>

<p align="center">
  <a href="https://github.com/ethanwchen/tabbi/releases/latest"><img src="https://img.shields.io/github/v/release/ethanwchen/tabbi?label=download&color=E8A15F" alt="Download the latest release"></a>
  <a href="https://buymeacoffee.com/ethanpolar"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-ethanpolar-F4D57E?logo=buymeacoffee&logoColor=2A231D" alt="Buy me a coffee"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-555?logo=apple" alt="macOS 14 or later">
  <a href="https://github.com/ethanwchen/tabbi/actions/workflows/ci.yml"><img src="https://github.com/ethanwchen/tabbi/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-6B8E5A" alt="MIT License"></a>
</p>

<p align="center">
  <img src="docs/images/hero.gif" alt="The closed notch with a pixel cat opens into the Timer tab (a Pomodoro timer at 15:14), then switches to Today, Anki, Party and the pet's Closet before closing again" width="100%">
</p>

Click the notch and it opens into a small panel of tabs.
A pixel cat lives there too, and it cheers you on while you work.

- **Focus timer** with study methods like Pomodoro, focus sounds and Do Not Disturb.
- **Today:** your to-do list, your next meeting and a Plan my day that fits work into free time.
- **Now Playing and Ask AI:** music controls, and Claude, Codex, Gemini or a free local Ollama model in the notch.
- **Anki, study with friends and a pet** that earns outfits from your study points.
- **Private by design:** no account needed, no analytics and no telemetry.

## Install

1. Download Tabbi from [tabbinotch.com](https://tabbinotch.com) or the [latest release](https://github.com/ethanwchen/tabbi/releases/latest).
2. Drag **Tabbi** into **Applications**, open it, then click the notch and pick a kit.

Tabbi is free and open source, and it keeps itself up to date.
It needs macOS 14 Sonoma or later, and a Mac without a notch gets a small virtual one at the top of the screen.
Right-click the notch for **Settings** and **Quit Tabbi**.
[docs/install.md](docs/install.md) covers Homebrew, updates, troubleshooting and uninstalling.

## Tabs

Essentials opens with four tabs, plus a paw for your pet.
Med School adds Anki.

<table>
  <tr>
    <td width="50%"><img src="docs/images/study.png" alt="Timer tab"><br><b>Timer.</b> Quick 5, 10 or 25 minute countdowns, or a study method like Pomodoro, with points for the pet.</td>
    <td width="50%"><img src="docs/images/today.png" alt="Today tab"><br><b>Today.</b> Your to-do list, what's next on the calendar and Plan my day.</td>
  </tr>
  <tr>
    <td><img src="docs/images/now-playing.png" alt="Now Playing tab"><br><b>Now Playing.</b> Spotify and Apple Music (or SoundCloud in Safari or Chrome, if you turn it on), with artwork, shuffle, repeat and a like button.</td>
    <td><img src="docs/images/ask-claude.png" alt="Ask AI tab"><br><b>Ask AI.</b> Pick Claude, Codex, Gemini or Ollama, type a question and press Return; attach a screenshot or open a bigger view.</td>
  </tr>
  <tr>
    <td><img src="docs/images/anki.png" alt="Anki tab"><br><b>Anki.</b> Cards due today in your decks, through AnkiConnect; click a deck to study it.</td>
    <td><img src="docs/images/closet.png" alt="Closet, the pet page"><br><b>Closet.</b> Tap the paw to dress up your pet with what your study points unlock.</td>
  </tr>
</table>

More tabs are in **Settings > Tabs > Add more**:

<table>
  <tr>
    <td width="50%"><img src="docs/images/schedule.png" alt="Schedule tab"><br><b>Schedule.</b> Your day and week as a timeline, planned on your Mac.</td>
    <td width="50%"><img src="docs/images/party.png" alt="Party tab"><br><b>Party.</b> Study with friends and see who is focusing.</td>
  </tr>
  <tr>
    <td><img src="docs/images/claude-usage.png" alt="AI Usage tab"><br><b>AI Usage.</b> Your Claude Code or Codex 5-hour and weekly limits and today's tokens.</td>
    <td><img src="docs/images/system.png" alt="System tab"><br><b>System.</b> CPU, GPU and memory at a glance.</td>
  </tr>
</table>

Closed, the notch stays black and shows one quiet live activity beside it: your next meeting, the song playing, a timer or your pet.

<p align="center">
  <img src="docs/images/closed-pet.png" alt="The closed notch with a pixel cat on the left and its name on the right" width="600">
</p>

## Kits

A kit is a premade set of tabs for one kind of user.
Tabbi ships Essentials and Med School, adds any other tab from **Add more**, and you can switch, reset or import kits in **Settings > Tabs**.
Kits are small JSON files, and [docs/kits.md](docs/kits.md) shows how to write your own.

## Privacy

Tabbi has no account, no analytics and no telemetry.
It only connects where a tab needs to: album artwork for Now Playing, AnkiConnect on your own Mac, and the friends server while Party is on.
Update checks download Tabbi's release feed from GitHub once a day; you can turn them off in **Settings > About**.
AI features talk only to the AI you pick in **Settings > Connections**: a command line tool you already use (Claude Code, Codex or Gemini CLI), a hosted API with your own key, which stays in your keychain, or Ollama on your own Mac.
Tabbi never reads a command line tool's credentials.

<details>
<summary><b>What each permission is for</b></summary>

Tabbi asks for a permission only when the tab that needs it is first used.
**Settings > Connections** shows what your tabs need and fixes it in one click (see [docs/connections.md](docs/connections.md)).

| Permission | Asked by | Why |
| --- | --- | --- |
| Automation: Spotify, Music | Now Playing, focus mode | Read the current track, control playback and start a focus playlist. |
| Automation: Safari or Chrome | Now Playing, only once you turn on SoundCloud | Read and control the SoundCloud tab. |
| Calendars | Today, Schedule | Show your events and add the planned blocks you accept. Events never leave your Mac. |
| Notifications | Today, Focus, Closet (only once you turn on the daily reminder) | Tell you when a timer ends while the notch is closed, and send the optional daily study reminder. |
| Screen Recording | Ask AI | Attach a screenshot to a question. The image goes only to the AI you picked. |

AI Usage needs no system permission.
Plan my day plans on your Mac without an AI.
Refine and Wrap up send your task titles and today's events to the AI you picked in Settings > Connections, only when you press them.
AI Usage reads token counts from `~/.claude/projects`, or from `~/.codex/sessions` while Codex is your AI, read-only.

</details>

<details>
<summary><b>FAQ</b></summary>

**Do I need an AI?**
No.
Only Ask AI, Wrap up and the optional Refine use one, and they ask you to pick an AI in **Settings > Connections** first.

**Command line tool or API key?**
Either.
A command line tool keeps your usage on the plan you already have, and Tabbi never handles its credentials.
An API key or Ollama works without any tool installed, and is the only option in the App Store edition.

**How do I update or uninstall it?**
Tabbi updates itself; right-click the notch and choose **Check for Updates…** to check now.
To uninstall, quit it and drag it from Applications to the Trash; [docs/install.md](docs/install.md#uninstall) also lists where your data lives.

**Does it hide in fullscreen apps or on other displays?**
By default it steps aside while an app is fullscreen and shows on every display.
Both are switches in **Settings > General**.

**Does it slow my Mac down?**
It is a small native app with no web views, and tabs only refresh while you can see them.

</details>

## Build from source

```sh
git clone https://github.com/ethanwchen/tabbi.git && cd tabbi
scripts/run.sh                                   # build and launch build/Tabbi.app
TABBI_DEMO=1 swift run Tabbi --snapshot snapshots   # render every panel to PNG with sample data
```

You need Xcode 26 or later; the app runs on macOS 14 or later.
The only third-party dependency is Sparkle, for updates.

## Contributing

Contributions are welcome.
Start with [CONTRIBUTING.md](CONTRIBUTING.md), then [AGENTS.md](AGENTS.md) for the architecture and design rules, and [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md) and report security issues as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
