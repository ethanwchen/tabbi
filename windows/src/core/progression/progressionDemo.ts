import { ACTIVITY_KINDS, ACTIVITY_METADATA, ACTIVITY_UNITS, makeActivityRecord, type ActivityRecord } from "../activity/activityRecord";
import { PetMilestoneProgress } from "../closet/petLimited";
import { MODULE_IDS } from "../modules/moduleId";
import type { DayCalendar } from "../streaks/dayCalendar";
import type { Instant } from "../time";
import { PetProgression } from "./petProgression";
import { ProgressTally } from "./progressTally";

/*
 * Port of ProgressionDemo.swift: the demo Goals shelf, a few months in: the
 * milestones' demo focus, the newest stretches run with three methods and
 * the last three finished with friends in Party, plus flashcards, tasks,
 * break moves and water. Three mastery outfits are earned.
 */
export function progressionDemo(today: Instant, calendar: DayCalendar): PetProgression {
  const focus = PetMilestoneProgress.demoRecords(today, calendar);
  const methods = ["pomodoro", "fiftyTwoSeventeen", "flowtime"];
  const records: ActivityRecord[] = [];
  let next = 0;
  const id = () => `progress-demo-${++next}`;
  focus.forEach((record, index) => {
    const fromEnd = focus.length - 1 - index;
    const metadata: Record<string, string> = { ...record.metadata, [ACTIVITY_METADATA.method]: methods[index % methods.length] ?? "pomodoro" };
    let source = record.source;
    if (fromEnd < 3) {
      source = MODULE_IDS.party;
      metadata[ACTIVITY_METADATA.outcome] = "completed";
      metadata.friends = "2";
    }
    records.push({ ...record, source, metadata });
    const end = record.end;
    /* A second finished block on two days in three, so the demo's session count passes the Apprentice Robe's 75. */
    if (index % 3 !== 0) {
      records.push(makeActivityRecord({ id: id(), source, kind: ACTIVITY_KINDS.focusCompleted, start: end + 1800, end: end + 3300, quantity: 25, unit: ACTIVITY_UNITS.minutes, metadata }));
    }
    records.push(makeActivityRecord({ id: id(), source: MODULE_IDS.anki, kind: ACTIVITY_KINDS.cardsReviewed, start: end, quantity: 45, unit: ACTIVITY_UNITS.cards }));
    if (index % 3 === 0) {
      records.push(makeActivityRecord({ id: id(), source: MODULE_IDS.planner, kind: ACTIVITY_KINDS.taskCompleted, start: end, quantity: 1, subject: `demo-task-${index}` }));
    }
    if (index % 2 === 0) {
      records.push(makeActivityRecord({ id: id(), source: MODULE_IDS.closet, kind: "water.logged", start: end, quantity: 1, unit: "glass" }));
      records.push(makeActivityRecord({ id: id(), source: MODULE_IDS.closet, kind: "water.logged", start: end + 60, quantity: 1, unit: "glass" }));
    }
    if (index % 4 === 0) {
      records.push(makeActivityRecord({ id: id(), source: MODULE_IDS.closet, kind: "break.move", start: end, subject: "stretch" }));
    }
  });
  const progression = new PetProgression(undefined, new ProgressTally(records, calendar));
  progression.refresh(today, [], calendar);
  progression.markSeen();
  return progression;
}
