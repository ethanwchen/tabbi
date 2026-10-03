# Claude Usage transcript scan: memory

The Claude Usage panel computes today's and the last seven days' token totals from Claude Code's session transcripts in `~/.claude/projects`.
On a heavy user's Mac that folder holds 1.2 GB across 1,660 `.jsonl` files, and about 1 GB of it was modified within the last week.

## The bug

A release build idled at 0% CPU but `footprint` reported 952 MB, almost all of it dirty `MALLOC_SMALL` pages.
With `NOTCHDECK_DEMO=1` (no scan) the same build used 14 MB.

The scanner already skipped files older than the window and read in 1 MB chunks, but each chunk came from `FileHandle.read(upToCount:)`, which returns an autoreleased `NSData`.
The whole scan is one synchronous job on a Swift concurrency thread, whose autorelease pool is not drained until the job ends.
So every chunk of the week's transcripts stayed alive until the scan finished, and the freed pages were never handed back to the OS.

## The fix

`ClaudeUsageLogScanner` (`Sources/TabbiKitCore/ClaudeUsage`) now:

- skips files whose modification time is before the window using `stat`, without opening them;
- reads with POSIX `read` into one reused `malloc`'d buffer (256 KB, grown only for a longer line and capped at 32 MB), so reading allocates nothing per chunk;
- walks lines in place with `memchr` and only decodes lines that pass a byte prefilter, decoding just the fields it needs;
- wraps line processing in `autoreleasepool`, in case decoding autoreleases anything;
- keeps records as fixed-size values keyed by the first 128 bits of the message id's SHA-256, with model names interned, so a week of records is a few flat tables instead of about 22k small heap strings;
- persists each file's offset and the window's records (packed into one binary blob) to `~/Library/Application Support/NotchDeck/ClaudeUsage/scan-index.json`, so unchanged bytes are never read again, even after a relaunch;
- calls `malloc_zone_pressure_relief` after the first scan of a launch or after reading more than 32 MB.

The store still runs scans off the main thread at utility priority and coalesces requests that arrive mid-scan into one follow-up scan.

## Measurements

Release bundle (`scripts/bundle.sh notchdeck release`), real data (1.2 GB, 1,664 files, 987 MB modified in the last 7 days), `footprint <pid>` 15 s after launch, Apple Silicon, macOS 26.6.

| Build | Footprint |
| --- | --- |
| Before | 952 MB |
| After, first launch (no index, reads the whole week) | 40 MB |
| After, later launches (index on disk) | 31-32 MB |
| Launch scan disabled (reference) | 25 MB |
| `NOTCHDECK_DEMO=1` | 15 MB |

The first version of the fix kept each record's message id and model as Swift strings.
Those 22k long-lived small allocations sat between the scan's transient garbage and pinned fragmented `MALLOC_SMALL` pages, so later launches measured 47-49 MB.
Compact records brought the scan's own growth (measured in-process over the real data) from 27 MB to 15 MB on a first scan and from 30 MB to 11 MB when loading the index.

`ClaudeUsageScanMemoryTests` scans a synthetic 431 MB corpus and asserts peak footprint growth under 60 MB along with exact totals.
The new scanner grows about 20 MB and finishes in about 0.7 s in a debug build; the old one grew 445 MB on the same corpus.

Stats were checked against an independent Python implementation over the real transcripts: identical per-model message counts and token totals for today and the last seven days, both after a first scan and after incremental scans from a persisted index.
