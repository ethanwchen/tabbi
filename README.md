# NotchDeck

Turn your MacBook's notch into a tiny command deck. Hover to peek, click to
open, swipe or use ← → to flip between:

- **Now Playing:** Spotify artwork, track, scrubber, and controls; a live
  equalizer beside the closed notch while music plays
- **System:** CPU, GPU, and memory at a glance
- **Claude Usage:** your 5-hour and weekly Claude limits, read from your own
  `claude` CLI, plus today's token and message totals from your local Claude
  Code transcripts
- **Today:** a daily checklist that lives one click away
- **Ask Claude:** a quick question box that streams answers from your `claude` CLI

Press Control-Option-Space anywhere to toggle the notch.
Open Settings from the gear in the open notch or by right-clicking it to launch
at login, open on hover, pick a display, reorder or hide modules, change the
hotkey, or point NotchDeck at a specific `claude` binary.

> Status: early development.

## Requirements

- macOS 14+ (works best on a notched MacBook; other displays get a virtual pill)
- Spotify desktop app for Now Playing
- [Claude Code](https://claude.com/claude-code) signed in, for the Claude modules

## Build and run

```sh
git clone https://github.com/ethanwchen/notchdeck && cd notchdeck
scripts/run.sh            # builds build/NotchDeck.app and launches it
```

The first time you open Now Playing, macOS asks permission for NotchDeck to
control Spotify.

## Privacy

NotchDeck has no telemetry and no server. Claude features run through the
`claude` CLI already on your Mac; NotchDeck never reads your credentials.
Claude Usage reads token counts from the transcripts in `~/.claude/projects`
read-only and never writes there. Each limits refresh sends a tiny `claude`
request, so it only runs when you open the panel after 10+ minutes or press
refresh.

## Contributing

See [AGENTS.md](AGENTS.md) for architecture, design rules, and how to preview UI
changes with `swift run NotchDeck --snapshot snapshots`.

## License

MIT
