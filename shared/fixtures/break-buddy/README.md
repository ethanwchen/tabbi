# Break buddy golden fixtures

Written by `Tests/TabbiKitCoreTests/BreakBuddyGoldenTests.swift` from `BreakMove`, `BreakBuddyPlanner`, `BreakBuddyPreferences` and `WaterTally` (`Sources/TabbiKitCore/BreakBuddy`).
They pin the break buddy's pure logic, so a port plans the same move for the same break and counts the same glasses of water.
The Windows app does not show the break buddy yet; it only reads the `sip` and `breathe` pet clips, which `pets/` pins.

The file has `schema` (`tabbi.break-buddy.golden`) and `version` (1).
Times are seconds since 1970.

- `constants`: every move with its pet clip (`animation`), its full length in seconds and its SF Symbol; the planner's `minimumBreak`, `longBreak`, `sipEvery` and `rotation`; the `UserDefaults` key and version of the saved preferences; and the activity kinds, unit and source the water tally logs.
- `plans`: each `input` is one break (`source`, `breakStartedAt`, `breakLength`), the time it is planned at (`now`) and the saved `preferences`.
  The `output` has the break's `breakKey`, the `moment` (absent when the break gets none) and the `preferences` to save afterwards, which equal the input's when there is no moment.
- `runs`: breaks in a row, break `i` starting at `firstStart + i * 3600` and planned as it starts, each with the preferences the one before left; `moves` is the move each break got, or null.
- `tallies`: sample activity `records` (a water record carries the unit `glass`), and for the local `day` in `timeZone` the `glasses` of water and the done `moves`, in order.

Rules the fixture pins that are easy to miss:

- A break gets nothing when the buddy is off, every move is off, its `breakKey` is the saved `lastBreakKey`, or less than `minimumBreak` of it is left at `now`.
- A break of `longBreak` or more suggests standing up; otherwise every `sipEvery`th planned break suggests a sip (when `breaksSinceSip + 1` reaches it); otherwise the move after `lastMove` in `rotation`, skipping moves that are off.
- `lastMove` is the last move the rotation picked: standing up and sips leave it as it was, so the rotation carries on after them.
- When no rotation move is on, the first move that is on, in `constants.moves` order.
- A moment lasts the move's length, but at most half of what is left of the break, rounded down to whole seconds.
- `breaksSinceSip` goes back to 0 after a sip and grows by one after any other planned break.
- Glasses count only the break buddy's own `water.logged` records (source `closet`) for the local day of their end, adding up their quantities; moves come from `break.move` records' `subject`, skipping names this build does not know.
- Neither kind earns points or keeps a streak, and a skipped move is never logged.
