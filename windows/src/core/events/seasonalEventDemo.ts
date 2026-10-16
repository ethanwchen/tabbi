import { ACTIVITY_KINDS, ACTIVITY_UNITS, makeActivityRecord, type ActivityRecord } from "../activity/activityRecord";
import { addingDays } from "../calendar/zonedCalendar";
import type { Instant } from "../time";
import { featuredRun } from "./petLimitedShelf";
import { occurrenceContains, SeasonalEventTally } from "./seasonalEvent";
import { SeasonalEventCatalog } from "./seasonalEventCatalog";

/*
 * Port of SeasonalEventDemo: the demo season. A demo should show an event
 * going on, with progress toward its first item, whatever the real date
 * is, so it pins the Closet's seasonal clock to a moment in the featured
 * run (the one going on, or else the next) and logs two focus sessions in
 * that run.
 */
export interface SeasonalEventDemo {
  /** Noon on the third day of the featured run. */
  readonly moment: Instant;
  /** An hour of focus logged on the run's second and third mornings. */
  readonly tally: SeasonalEventTally;
}

/* `days` days then `hours` hours after `start`, as Calendar.date(byAdding:) adds day and hour components. */
function after(start: Instant, days: number, hours: number, timeZone: string): Instant {
  return addingDays(start, days, timeZone) + hours * 3600;
}

export function seasonalEventDemo(
  today: Instant,
  timeZone: string,
  catalog: SeasonalEventCatalog = SeasonalEventCatalog.bundled,
): SeasonalEventDemo | undefined {
  const run = featuredRun(catalog, today, timeZone)?.occurrence;
  if (!run) return undefined;
  const moment = after(run.start, 2, 12, timeZone);
  if (!occurrenceContains(run, moment)) return undefined;
  const session = (day: number, minutes: number, index: number): ActivityRecord => {
    const end = after(run.start, day, 10, timeZone);
    return makeActivityRecord({
      id: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
      source: "focus",
      kind: ACTIVITY_KINDS.focusCompleted,
      start: end - minutes * 60,
      end,
      quantity: minutes,
      unit: ACTIVITY_UNITS.minutes,
    });
  };
  return { moment, tally: new SeasonalEventTally(catalog, timeZone, [session(1, 35, 1), session(2, 25, 2)]) };
}
