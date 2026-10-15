# Closet golden fixtures

Written by `Tests/TabbiKitCoreTests/ClosetGoldenTests.swift` from `PetItem`, `PetPointsRules`, `PetEconomy`, `PetPriceTier`, `PetItemTheme`, `PetPointsLedger`, `PetCloset`, `PetStudyAward`, `UnlockProgress`, `PetLimitedEdition`, `PetMilestoneProgress`, `StreakFreezeRules`, `StudyStreak`, `SeasonalEventCatalog`, `PetLimitedShelf` and `SeasonalEventTally`.
They pin every Closet item's price, tier, shelf and unlock rule, how study turns into points, and what the Closet does with those points, so the Windows port charges, pays and unlocks exactly like the Mac.
Prices and rules live in Swift, so the port reads them from this file (or checks its own copy against it) instead of from a data file.

The file has `schema` (`tabbi.closet.golden`) and `version` (1).
Times are seconds since 1970, item ids are `outfit.<raw>` or `accessory.<raw>`, and days are local `yyyy-MM-dd` strings.
Every time zone is an IANA name, and every calendar is Gregorian in that zone (Lunar New Year is written on the Chinese calendar in the same zone).

- `rules`: the points rules and the typical study habit prices are set against.
  A session earns `pointsPerMinute` per whole minute once it lasts `minimumMinutes`, plus `completionBonus` when it ran to its end and lasted at least `bonusMinutes`.
  A finished Party stay adds `sharedBonusPerFriend` per friend, at most `maxSharedBonus`.
  The typical habit is `typicalBlocksPerDay` blocks of `typicalBlockMinutes` on `typicalStudyDaysPerWeek` days, which pays `pointsPerTypicalBlock`, `pointsPerTypicalDay` and `pointsPerTypicalWeek`.
  An extra streak freeze costs `streakFreezePrice`, at most `streakFreezeMaxHeld` extras are held, and every calendar week has `streakFreezeFreePerWeek` free one.
  `unlockNearSessions` is how few sessions count as close to the next unlock, `minutesForStudyDay` is the focused minutes that make a day count toward a streak, `latestRelease` is the catalog release that wears a "New" badge, and `milestoneGoals` gives each milestone's goal in days (`weekStreak`), minutes (`fiftyHours`) or sessions (`firstParty`).
- `tiers`: each price tier (`free`, `starter`, `midTier`, `showpiece`) with its inclusive `minPrice` and `maxPrice`.
- `items`: every item in `PetItem.allCases` order: the shop cheapest first, then the limited edition items.
  Each has `kind` (`outfit` or `accessory`), `cost` in points, `tier`, `theme` (its wardrobe shelf), `release`, `isFree` (owned from the start), `isLimited`, `isNew` (shows the "New" badge until owned), and for accessories the `slot` (`neck`, `face`, `head`, `back` or `aura`) and `coversEyes`.
  A limited item also has `limited`: its `edition`, its `source` and `sourceID` (`milestone` with the milestone, `event` with the server event that grants it, or `season` with the seasonal event), `milestoneGoal` or `seasonFocusMinutes`, and its animated `effect`.
- `catalog`: `shopOrder` (every item points can buy, plus the free starters), `wardrobe` (the grid: the shop without `outfit.none`), `limitedShelf`, and the themed `shelves`, each cheapest first.
- `points`, `sharedPoints`: the points for a solo session of `minutes` (`completed` or cut short) and for a Party stay with `friends` (`finished` or cut short).
- `pace`: for sample `points`, the typical blocks, days and weeks they take, rounded up, and the shop's `studyToEarn` line (blocks up to a day's points, days up to a week's, weeks beyond, empty for nothing).
- `tierLookups`: the tier whose range holds `cost`, absent for a price in a gap between tiers.
- `ledgers`: a stored ledger `json` and, when it decodes, the `output`: `earned`, `spent`, `balance`, the `purchased` and `granted` ids, `nextUnlock` (the cheapest shop item not owned), and `encoded`, the ledger written back with sorted keys and no whitespace.
- `unlockProgress`: the end-of-session bar for an `input` (`balance` now, the points the session `earned`, the `purchased` items, and `pointsPerSession`, absent for a plain look), and its `output`, absent when every shop item is owned.
  The output has the goal `item` and `cost`, `balanceBefore`, `balance`, the pace used, `missing`, `isReady`, both bar `fraction`s, `sessionsLeft`, `isNear` and the `line` under the bar.
- `closets`: each starts a Closet from `start` (a tuxedo cat's `outfit` and `accessories`, and the ledger's `earned`, `spent`, `purchased` and `granted`), records the cleaned-up `initial` state, and lists `steps`.
  A step's `op` is one of:
  - `study`: a solo session of `minutes`, `completed` or not; the `outcome` has the `points` earned.
  - `gift`: a surprise gift's `points`.
  - `party`: a Party stay of `minutes` ending at `at`, with `friends`, `finished` or not.
  - `record`: a `focus.completed` activity record (`recordID`, `source`, `quantity` minutes, ending at `at`, with its `outcome` metadata, absent for none), credited as a cut-short phase.
  - `tap`: a tap on the wardrobe tile `item`; the `outcome.tap` is `wore`, `tookOff`, `boughtAndWore`, `needsPoints` (with `missing`) or `notEarnedYet`.
  - `buy`: a direct purchase of `item`; the `outcome.purchase` is `bought`, `alreadyOwned`, `notForSale` or `notEnoughPoints` (with `missing`).
  - `grant`: the item `ids` the server granted; `outcome.granted` lists the ones that are new.
  A `party` or `record` that earned points has the `award` (sessions, minutes, points, the items it made affordable as `unlocked`, `isLevelUp`, the bubble's `headline` and `unlockLine`, and `pointsText`) and the unlock `progress` right after it; one that earned nothing has neither.
  `after` is the Closet after the step: the ledger, what the pet wears, `nextUnlock` with `nextUnlockMissing`, and `states`, every item's state (`wearing`, `owned`, `affordable`, `locked` or `unearned`).
- `milestones`: activity `records` read in `timeZone` on `today`, and what they give: total `focusMinutes`, the `studyDays`, `finishedPartySessions`, the `longestStreak` and `currentStreak`, each milestone's capped `value`, `isReached` and Limited shelf `progress` (`value`, `goal`, `label`, `fraction`), and the items `unlocked` for a Closet that owned none.
  A record has `id`, `source`, `kind`, `unit`, `start`, `end`, `quantity` and its `outcome` metadata (absent for none).
- `freezes`: buying extra streak freezes with a ledger of `earned` points, the `studyDays`, and the calendar's `firstWeekday` (1 is Sunday, 2 is Monday).
  Each buy at `at` records the `result` (`bought`, `holdingLimit` or `notEnoughPoints` with `missing`), the `balance`, and the streak's `extraFreezes` and `freezesReady` after it.
- `windows`: the next runs of each seasonal event after `from` in each time zone, each found after the previous run's start, with its `id` (event and Gregorian start year), `start` (local midnight of the first day) and `end` (local midnight after the last day).
- `moments`: the seasonal events at `at` in `timeZone`: the `active` runs (soonest to end first), the `next` run to start, the `featured` run with `isActive`, and the Limited section's `shelves` in order: `event` (the featured run's items), `milestones` (limited items that are not seasonal) and `laterEvents` (the other events' items in the order their next runs start), each present only with items.
- `seasonalTallies`: activity `records` tallied per event run in `timeZone`, with every item `earned`, each run's `focusMinutes`, `earned` items and `nextReward`, the Limited shelf `progress` of each seasonal item at each query (only while its event runs), and the items `unlocked` for a Closet that owned none.

Rules the fixture pins that are easy to miss:

- Every paid price is distinct and sits inside one tier; limited edition items cost 0 but are never free, never for sale, and cannot be bought or tapped into.
- A session under `minimumMinutes` earns nothing at all, and the completion bonus needs both a finished session and `bonusMinutes`; a cut-short Party stay earns no team bonus.
- Negative friend counts count as none, and a negative gift adds nothing.
- A stored ledger drops unknown ids, free items and limited items from `purchased`, keeps only limited items in `granted`, refunds 30 points for a Cozy Scarf bought before it was free, and clamps `spent` to `earned` (and both to at least 0).
- A ledger buy checks ownership first, then whether the item is for sale, then the balance; a streak freeze checks the holding limit before the balance.
- Only skipped or abandoned records are paid from the log; completed and stopped phases, records with no outcome, and Party records are not, and the quantity rounds down to whole minutes.
- An award's `unlocked` items are shop items that were not affordable before it and are now.
- The unlock goal is the cheapest unowned shop item that the points before the session could not buy, so a session that makes an item affordable fills the bar instead of jumping to the next goal; a pace of 0 or less falls back to a typical block.
- Tapping a worn outfit (even `outfit.none`) takes it off, and wearing an accessory takes off whatever shares its slot, or any face item under one that covers the eyes.
- A profile that wears items the ledger does not own is undressed as soon as the save is built.
- A day counts toward a streak when its focused minutes reach `minutesForStudyDay`, summed over the day's records in the given time zone; a record counts toward the day it ended.
  The same record id counts once, only `focus.completed` records in minutes count, and a Party record counts as a finished session only with the `completed` outcome.
- The current streak runs back from today, or from yesterday when today has no study yet; the week streak milestone is reached by the longest run ever, while its shelf progress shows the current run.
- Hours on the shelf round down, so a goal never shows as met before it is.
- An event run includes its first local midnight and excludes the midnight after its last day, a record counts toward every run going on when it ended, and an item earned in a past run stays earned.

A port replays only the inputs and compares every recorded output.
Compare numbers within 1e-9: fractions and minute totals are computed.
