# Streaks, heatmap and weekly recap golden fixtures

Written by `Tests/TabbiKitCoreTests/StreaksRecapGoldenTests.swift` from `PetMilestoneProgress`, `StudyStreak`, `StreakFreezeRules`, `StreakMilestone`, `StudyHeatmap`, `RecapWeek`, `WeeklyRecap`, `RecapCheer` and `RecapStat`.
They pin what the activity log adds up to, so the Windows port shows the same streak, freezes, study chart and weekly recaps from the same records.

The file has `schema` (`tabbi.streaks-recap.golden`) and `version` (1).
Times are seconds since 1970, days are local `yyyy-MM-dd` days, and minutes are minutes.

- `constants`: one free freeze per week, the price and holding limit of extra freezes, the minutes that make a study day, the milestone lengths, the chart's levels and labeled weekdays (1 is Sunday), the recap's ready hour and light-week minutes, the points rules the recap uses, the Party `friends` metadata key, and the locale of the recap stats (`en_US`).
- `milestones`: `checks` say whether each `length` is a milestone, and each of `steps` is a streak seen at `from` (null: no baseline yet) and then at `to`, with the milestone it `reached` (null for none).
- `cases`: each has an `input` and the `output` it gives.
  - `input` holds the `timeZone` (an IANA name; every day is a local day in it), the calendar's `firstWeekday` (1 is Sunday, 2 is Monday), `today`, the activity `records` (the same shape as the activity log fixture's record inputs), `freezePurchases` (when each extra freeze was bought), and how many `recentDays`, `heatmapWeeks` and `recapWeeks` to show, with `monthLabelMinimumWeeks` for the chart's month labels.
  - `progress` reads the records: focused `minutesByDay` (every day with any, oldest first, after today too), the `studyDays`, the `longestStreak` ever and the `currentStreak` without freezes.
  - `streak` is `StudyStreak` over the study days and purchases: `length`, `studiedToday`, `isActive`, `needsStudyToday`, every `frozenDays` entry, `freeFreezeAvailable` this week, `extraFreezes` held, `canBuyFreeze`, `freezesReady`, the `recentDays` strip ending today (each `studied`, `frozen`, `missed` or `today`), the length read at the same time a day earlier (`lengthYesterday`), and the milestone reached growing from it (`milestoneReached`).
  - `heatmap` is the Closet's chart from `progress.minutesByDay`: `today`, the row `weekdays`, the `weeks` oldest first (each with its `start`, seven `days` from the first weekday, null after today, its `minutes` and `studiedDays`), `lastThirtyDaysMinutes`, the `bestDay` ever and the `monthLabels` (column index and start).
    A day has its whole `minutes`, `level` (0 to 4) and `isToday`.
  - `recaps` gives the week `containingWeek` today, the `latestReadyWeek`, and the recaps of the `recapWeeks` weeks ending with it, oldest first.
    A recap has its Monday `week`, Sunday `end`, `readyDate`, `minutesByDay` (Monday first), `sessions`, `cardsReviewed`, `tasksDone`, `points`, `longestStreak`, `focusMinutes`, `isEmpty`, `bestDay`, its `cheer` against the case's other recaps, and its `stats` (`kind` and `value` in the stats locale).

Rules the fixture pins that are easy to miss:

- A record counts toward the local day it ended on, and only `focus.completed` records in `min` with a positive quantity add focused minutes; a day is a study day from 5 minutes, summed over the day.
- Today is never frozen or missed; a missed day while a streak runs uses the free freeze of its calendar week (the calendar's first weekday decides the week), then the oldest extra freeze bought on an earlier day, otherwise the streak ends.
  A freeze bought on the missed day or later cannot repair it, and no freeze is spent while there is no streak.
- A frozen day keeps the streak but does not add to it; `frozenDays` keeps freezes from earlier runs too.
- The chart rounds each day's minutes, ignores days after today, and on a tie names the later day best.
- Recap weeks run Monday to Sunday whatever the first weekday, and a recap is ready at 18:00 local wall-clock time on its Sunday, even on a daylight saving Sunday; at exactly 18:00 it is ready.
- A recap counts every record in its week, even ones after today, and each id once.
  A session is a focus record with no outcome, `completed` or `stopped`; points use the whole minutes of each record (24.6 minutes earn 24 points and no bonus), so a day can be a study day with no points.
  A Party stay earns the team bonus (5 per friend, at most 15) only when it finished (`completed` or no outcome); one cut short earns its minutes without bonuses.
  Tasks count once per `subject`, and each task without one counts; card quantities are cut to whole cards.
- The recap's streak counts days with at least 5 focused minutes, any cards or any task.
- The cheer is `rest` for an empty week, `light` under 60 minutes, `firstWeek` with no earlier non-empty recap, `bestYet` above every earlier week, `moreThanLastWeek` above the week right before, and `steady` otherwise.
- A recap stat with nothing to show is left out, and a one-day streak is not a stat; numbers group digits in the stats locale (`1,320`) and the best day is a short weekday name (`Thu`).

The stat labels (`sessions`, `best day`) are localized strings, left to the formatting fixture.
A port replays only the inputs and compares every recorded output.
