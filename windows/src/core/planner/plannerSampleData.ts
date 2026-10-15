import type { Instant } from "../time";
import { settingTime } from "../calendar/zonedCalendar";
import { floorSlot } from "./dayPlan";
import type { MeetingLink } from "./meetingLink";
import { PlannerDay, plannerItem, type PlannerItem } from "./plannerDay";
import { dayKeyStart, plannerDayKeyOf, type PlannerDayKey } from "./plannerDayKey";
import { viewedDayKey, type PlannerViewedDay } from "./plannerViewedDay";
import type { PlannerSampleDay } from "./todayPlanSettings";
import { upcomingEvent, type EventColor, type UpcomingEvent } from "./upcomingEvent";
import { sampleUUID } from "./uuid";

/*
 * Port of PlannerSampleData: the realistic day demo mode shows on Today,
 * the checklist and the calendar. Never touches disk. Titles are neutral
 * and brand-free, since store screenshots show them.
 */

const WORK: EventColor = { red: 0.2, green: 0.55, blue: 0.98 };
const PERSONAL: EventColor = { red: 0.98, green: 0.62, blue: 0.2 };
const SCHOOL: EventColor = { red: 0.36, green: 0.78, blue: 0.47 };
const CLINICAL: EventColor = { red: 0.93, green: 0.35, blue: 0.38 };
const ZOOM: MeetingLink = { provider: "zoom", url: "https://zoom.us/j/5551234567" };
const MEET: MeetingLink = { provider: "googleMeet", url: "https://meet.google.com/abc-defg-hij" };

/**
 * A realistic, partly finished day. The first unfinished item always has
 * the same id, so the demo focus timer links to it whichever `kind` it is.
 */
export function samplePlannerDay(date: PlannerDayKey, kind: PlannerSampleDay, timeZone: string): PlannerDay {
  const start = dayKeyStart(date, timeZone);
  const at = (hour: number, minute: number) => start + hour * 3600 + minute * 60;
  const entries: [string, Instant, Instant | undefined][] =
    kind === "work"
      ? [
          ["Outline the history essay", at(8, 40), at(9, 25)],
          ["Reply to Sam about Saturday", at(8, 45), at(10, 5)],
          ["Read chapter 4", at(9, 0), undefined],
        ]
      : [
          ["Read the cardiac pathology notes", at(7, 30), at(9, 40)],
          ["Watch the heart failure lecture recording", at(7, 35), at(11, 15)],
          ["Cardio practice questions", at(7, 40), undefined],
          ["Email the clerkship office about Friday", at(7, 45), at(12, 5)],
          ["Renal notes", at(7, 50), undefined],
        ];
  const items = entries.map(([title, created, completed], index) =>
    plannerItem({ id: sampleUUID(index + 1), title, isDone: completed !== undefined, createdAt: created, completedAt: completed }),
  );
  return new PlannerDay(date, items);
}

/**
 * The sample list for `viewed`, counted from `today`: yesterday mostly
 * done, with one leftover already carried to today (it shares the id of
 * today's first open item) and two still waiting to be moved, and
 * tomorrow with a couple of tasks planned ahead.
 */
export function samplePlannerDayFor(
  viewed: PlannerViewedDay,
  today: PlannerDayKey,
  kind: PlannerSampleDay,
  timeZone: string,
): PlannerDay {
  const date = viewedDayKey(viewed, today);
  if (viewed === "today") return samplePlannerDay(date, kind, timeZone);
  const start = dayKeyStart(date, timeZone);
  const at = (hour: number, minute: number) => start + hour * 3600 + minute * 60;
  const item = (number: number, title: string, created: Instant, completed?: Instant): PlannerItem =>
    plannerItem({ id: sampleUUID(number), title, isDone: completed !== undefined, createdAt: created, completedAt: completed });
  if (viewed === "yesterday") {
    return new PlannerDay(
      date,
      kind === "work"
        ? [
            item(101, "Finish the lab report", at(8, 30), at(9, 20)),
            item(3, "Read chapter 4", at(8, 35)),
            item(102, "Practice Spanish vocab", at(8, 40)),
            item(103, "Do the laundry", at(8, 50), at(13, 10)),
            item(104, "Call the dentist", at(9, 0)),
          ]
        : [
            item(101, "Anki: cardio deck", at(7, 30), at(8, 45)),
            item(3, "Cardio practice questions", at(7, 35)),
            item(102, "Review the ECG handout", at(7, 40)),
            item(103, "Pathology lecture notes", at(7, 45), at(14, 20)),
            item(104, "Pick up the white coat", at(7, 50)),
          ],
    );
  }
  return new PlannerDay(
    date,
    kind === "work"
      ? [item(201, "Draft the essay intro", at(-6, 10)), item(202, "Buy a birthday card for Mia", at(-6, 15))]
      : [item(201, "Pre-read: renal physiology", at(-6, 10)), item(202, "Book the OSCE practice room", at(-6, 15))],
    true,
  );
}

/**
 * Realistic events around `now`: a study group under way with a Meet link,
 * a Zoom call shortly after and a plain block later (or a lecture, lab and
 * skills session for `medicine`). Times are relative to `now` and land on
 * five-minute marks, so badges always read naturally.
 */
export function sampleEvents(now: Instant, kind: PlannerSampleDay = "work"): UpcomingEvent[] {
  const slot = floorSlot(now);
  const minute = 60;
  if (kind === "medicine") {
    return [
      upcomingEvent({
        id: "demo-lecture",
        title: "Cardiology lecture",
        start: slot - 10 * minute,
        end: slot + 20 * minute,
        calendarColor: SCHOOL,
        meetingLink: ZOOM,
      }),
      upcomingEvent({
        id: "demo-lab",
        title: "Anatomy lab: thorax",
        start: slot + 30 * minute,
        end: slot + 90 * minute,
        calendarColor: SCHOOL,
      }),
      upcomingEvent({
        id: "demo-skills",
        title: "Clinical skills session",
        start: slot + 200 * minute,
        end: slot + 260 * minute,
        calendarColor: CLINICAL,
      }),
    ];
  }
  return [
    upcomingEvent({
      id: "demo-study-group",
      title: "Study group",
      start: slot - 10 * minute,
      end: slot + 20 * minute,
      calendarColor: WORK,
      meetingLink: MEET,
    }),
    upcomingEvent({
      id: "demo-review",
      title: "Design review",
      start: slot + 15 * minute,
      end: slot + 45 * minute,
      calendarColor: WORK,
      meetingLink: ZOOM,
    }),
    upcomingEvent({
      id: "demo-yoga",
      title: "Yoga class",
      start: slot + 95 * minute,
      end: slot + 125 * minute,
      calendarColor: PERSONAL,
    }),
  ];
}

/** Demo events for the day `viewed` names: `sampleEvents` for today, a plain day at fixed hours otherwise. */
export function sampleEventsFor(viewed: PlannerViewedDay, now: Instant, kind: PlannerSampleDay, timeZone: string): UpcomingEvent[] {
  if (viewed === "today") return sampleEvents(now, kind);
  const start = dayKeyStart(viewedDayKey(viewed, plannerDayKeyOf(now, timeZone)), timeZone);
  const prefix = viewed === "yesterday" ? "demo-yesterday" : "demo-tomorrow";
  const event = (id: string, title: string, hour: number, minute: number, minutes: number, color: EventColor, link?: MeetingLink) => {
    const begins = settingTime(start, hour, minute, 0, timeZone);
    return upcomingEvent({
      id: `${prefix}-${id}`,
      title,
      start: begins,
      end: begins + minutes * 60,
      calendarColor: color,
      meetingLink: link,
    });
  };
  if (viewed === "yesterday") {
    return kind === "work"
      ? [
          event("lecture", "Biology lecture", 9, 30, 60, WORK, ZOOM),
          event("lunch", "Lunch with Jordan", 12, 30, 60, PERSONAL),
          event("review", "Design review", 15, 0, 45, WORK),
        ]
      : [event("lecture", "Pathology lecture", 8, 0, 90, SCHOOL), event("rounds", "Ward rounds", 13, 0, 120, CLINICAL)];
  }
  return kind === "work"
    ? [event("lecture", "Biology lecture", 9, 30, 60, WORK, ZOOM), event("gym", "Gym with Alex", 18, 0, 60, PERSONAL)]
    : [event("lecture", "Renal physiology lecture", 8, 0, 90, SCHOOL), event("osce", "OSCE practice", 13, 30, 60, CLINICAL)];
}
