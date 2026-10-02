# Changelog

All notable changes to NotchDeck are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

The first public release.

### Added

#### The notch

- A native notch panel that opens on click and closes with Esc or a click outside.
- A quiet live activity while closed, such as the album cover and an equalizer while music plays.
- Five modules you can switch between with a two-finger swipe, the arrow keys or the tab icons.
- A virtual notch at the top center of the screen on displays without a notch.
- A shared dark design system: one accent color per module, rounded SF type, 4 pt spacing and spring animations.
- Demo mode (`NOTCHDECK_DEMO=1`) that swaps every data source for realistic sample data.
- `--snapshot <dir>` renders every notch state to PNG for design review.

#### Now Playing

- Album artwork, track, artist, a scrubbable progress bar, and play, skip, shuffle and repeat controls.
- Works with Spotify and Apple Music, following whichever player is active.
- Clean empty states when no music app is running.

#### System

- Live CPU, GPU and memory usage with a short history, sampled only while the panel is open.

#### Claude Usage

- Your 5-hour and weekly Claude limits, read through your local `claude` CLI.
- Today's token and message totals from your local Claude Code transcripts, read-only.

#### Today

- A daily checklist with quick add and progress for the day, stored locally.
- An Up Next card with your next calendar events and their video call links.
- A focus timer that can be linked to a checklist task and notifies you when a session ends.

#### Ask Claude

- A quick question box that streams answers from your local `claude` CLI, with Markdown rendering and follow-up questions.

#### Settings

- Choose and reorder modules, open on hover, haptics, and which display the notch lives on.
- A global hotkey (⌃⌥Space by default) to toggle the notch.
- Launch at login.

#### Project

- A programmatically drawn app icon (`scripts/make-icon.swift`).
- `scripts/release.sh`, which builds a universal (Apple silicon and Intel), ad-hoc signed release zip with a SHA-256 checksum.
- A GitHub Actions workflow that builds and tests on macOS.
- README screenshots generated from demo mode (`docs/make-screenshots.swift`).
- Contributing guide, Code of Conduct, security policy, and issue and pull request templates.

[0.1.0]: https://github.com/ethanwchen/notchdeck/releases/tag/v0.1.0
