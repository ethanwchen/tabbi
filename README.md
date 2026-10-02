# NotchDeck

Turn your MacBook's notch into a tiny command deck. Hover to peek, click to
open, swipe or use ← → to flip between:

- **Now Playing:** Spotify artwork, track, scrubber, and controls; a live
  equalizer beside the closed notch while music plays
- **System:** CPU, GPU, and memory at a glance
- **Claude Usage:** your 5-hour and weekly Claude limits, read from your own
  `claude` CLI
- **Today:** a daily checklist that lives one click away
- **Ask Claude:** a quick question box that streams answers from your `claude` CLI

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

## Contributing

See [AGENTS.md](AGENTS.md) for architecture, design rules, and how to preview UI
changes with `swift run NotchDeck --snapshot snapshots`.

## License

MIT
