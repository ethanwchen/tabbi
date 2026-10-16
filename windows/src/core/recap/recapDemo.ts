import { PetPointsRules } from "../pets/petPointsRules";
import type { Instant } from "../time";
import { RecapArchive } from "./recapArchive";
import { addingWeeks, latestReadyWeek } from "./recapWeek";
import { WeeklyRecap } from "./weeklyRecap";

/*
 * Port of RecapArchive.demo: sample recaps for demo mode, the last few
 * weeks ending at the newest ready week, which is the best one yet and not
 * seen, so the panel shows its card once. One light week sits among them
 * so the list shows how a quieter week reads too.
 */

/* Minutes per day, Monday first, oldest week first. */
const DEMO_WEEKS: readonly { minutes: readonly number[]; cards: number; tasks: number }[] = [
  { minutes: [50, 75, 0, 100, 25, 0, 50], cards: 140, tasks: 9 },
  { minutes: [25, 0, 0, 25, 0, 0, 0], cards: 30, tasks: 3 },
  { minutes: [75, 100, 50, 125, 75, 25, 0], cards: 210, tasks: 12 },
  { minutes: [100, 125, 75, 150, 100, 50, 75], cards: 320, tasks: 17 },
];

export function demoRecapArchive(now: Instant, timeZone: string): RecapArchive {
  const newest = latestReadyWeek(now, timeZone);
  const recaps = DEMO_WEEKS.map((sample, offset) => {
    let streak = 0;
    let run = 0;
    for (const value of sample.minutes) {
      run = WeeklyRecap.isActive(value, 0, 0) ? run + 1 : 0;
      streak = Math.max(streak, run);
    }
    const total = sample.minutes.reduce((sum, value) => sum + value, 0);
    return new WeeklyRecap({
      week: addingWeeks(newest, offset - (DEMO_WEEKS.length - 1)),
      minutesByDay: sample.minutes,
      sessions: Math.trunc(total / 25),
      cardsReviewed: sample.cards,
      tasksDone: sample.tasks,
      points: PetPointsRules.points(total, true),
      longestStreak: streak,
    });
  });
  return new RecapArchive({ recaps, settledWeek: newest, seenWeek: addingWeeks(newest, -1) });
}
