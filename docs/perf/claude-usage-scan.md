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

`ClaudeUsageLogScanner` (`Sources/NotchKitCore/ClaudeUsage`) now:

- skips files whose modification time is before the window using `stat`, without opening them;
- reads with POSIX `read` into one reused `malloc`'d buffer (256 KB, grown only for a longer line and capped at 32 MB), so reading allocates nothing per chunk;
- walks lines in place with `memchr` and only decodes lines that pass a byte prefilter, decoding just the fields it needs;
- wraps line processing in `autoreleasepool`, in case decoding autoreleases anything;
- persists each file's offset and the window's records to `~/Library/Application Support/NotchDeck/ClaudeUsage/scan-index.json`, so unchanged bytes are never read again, even after a relaunch;
- calls `malloc_zone_pressure_relief` after the first scan of a launch or after reading more than 32 MB.

The store still runs scans off the main thread at utility priority and coalesces requests that arrive mid-scan into one follow-up scan.

## Measurements

Release bundle (`scripts/bundle.sh notchdeck release`), real data (1.2 GB, 1,664 files, 987 MB modified in the last 7 days), `footprint <pid>` 15 s after launch, Apple Silicon, macOS 26.6.

| Build | Footprint |
| --- | --- |
| Before | 952 MB |
| After, first launch (no index, reads the whole week) | 40 MB |
| After, later launches (index on disk) | 47-49 MB |
| Launch scan disabled (reference) | 25 MB |
| `NOTCHDECK_DEMO=1` | 15 MB |

The live heap after a scan is about 6.5 MB (`heap <pid>`); the rest of the gap to the reference is small-zone fragmentation from the roughly 11k retained records.

`ClaudeUsageScanMemoryTests` scans a synthetic 431 MB corpus and asserts peak footprint growth under 60 MB along with exact totals.
The new scanner grows about 20 MB and finishes in about 0.7 s in a debug build; the old one grew 445 MB on the same corpus.

Stats were checked against an independent Python implementation over the real transcripts: the same 11,039 message ids and token totals.
