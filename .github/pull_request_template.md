## Summary

<!-- What does this change, and why? Link the issue it fixes, for example "Fixes #12". -->

## Screenshots

<!--
For any visual change, attach before and after PNGs from:
  TABBI_DEMO=1 swift run Tabbi --snapshot snapshots-demo
  swift run Tabbi --snapshot snapshots-live
Delete this section if the change has no UI.
-->

## Checklist

- [ ] `swift build` has zero warnings.
- [ ] `swift test` passes, and new logic in `TabbiKitCore` has tests.
- [ ] UI changes follow the [design rules](https://github.com/ethanwchen/notchdeck/blob/main/AGENTS.md#design-rules), and I checked the demo and live snapshots.
- [ ] Demo mode (`TABBI_DEMO=1`) still shows realistic sample data for anything I added.
- [ ] No telemetry, no new network calls, and no new dependencies (or the reason is explained above).
- [ ] The title follows [Conventional Commits](https://www.conventionalcommits.org/), for example `feat(today): add a focus timer`.
