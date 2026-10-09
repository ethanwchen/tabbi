# Show HN

Post on a weekday morning, US Eastern time, from Ethan's own account.
Link to the GitHub repo, not the website: HN readers want the code.
Do not ask anyone to upvote, and do not share a direct link asking for votes.

## Title

Show HN: Tabbi - a focus timer, to-do list and pet cat in your Mac's notch

(74 characters. HN allows 80.)

## URL

https://github.com/ethanwchen/tabbi

## First comment

Hi HN, I'm Ethan.

Tabbi is a small native macOS app that turns the notch into a clickable panel of tabs.
I built it because I study on a laptop and kept losing my timer and my to-do list behind windows.
The notch is always visible and mostly wasted space, so I put them there.

What it does:

- A focus timer (Pomodoro and a few other study methods), with focus sounds and Do Not Disturb.
- Today: a to-do list, your next calendar event, and Plan my day, which fits tasks into free time. The planner is a plain local algorithm, not an LLM.
- Now Playing for Spotify and Apple Music.
- Ask Claude and Claude Usage, which go through your local `claude` CLI. Tabbi never reads credentials or the keychain.
- Anki (through AnkiConnect) and a pixel cat that earns outfits from your study points.

Some technical notes:

- Swift, SwiftUI and AppKit, built with SwiftPM. The only dependency is Sparkle, for updates.
- Every tab is a module behind one protocol, and a "kit" is a small JSON file that picks which tabs are on and in what order. Adding a module is its own folder plus one line in a list.
- Modules share data through a provider snapshot instead of reaching into each other, so the closed-notch ticker and Today can show another tab's tasks without special cases.
- There is a demo mode (`TABBI_DEMO=1`) and a snapshot renderer (`swift run Tabbi --snapshot out`) that draws every panel to PNG. All the screenshots in the README come from it.
- No account, no analytics, no telemetry. Each module lists every host it connects to, and Tabbi shows that list before a kit turns a module on.

It is free and MIT licensed, signed and notarized, for macOS 14 and later.
Macs without a notch get a small virtual one.

I would love feedback, especially on what feels unnecessary.
I am trying hard to keep it simple.
