import type { Instant } from "../time";
import { sampleEventsFor } from "../planner/plannerSampleData";
import { PLANNER_VIEWED_DAYS } from "../planner/plannerViewedDay";
import type { PlannerSampleDay } from "../planner/todayPlanSettings";
import type { UpcomingEvent } from "../planner/upcomingEvent";
import type { CalendarFeedStatus, CalendarSource } from "./calendarSource";

/**
 * The calendar demo and snapshot runs show: the planner's sample events
 * for yesterday, today and tomorrow around `now`, in the kit's sample day.
 * No I/O, so a demo never touches the network or the disk.
 */
export class DemoCalendarSource implements CalendarSource {
  constructor(
    private readonly options: { readonly now: () => Instant; readonly timeZone: () => string; readonly kind?: PlannerSampleDay },
  ) {}

  async events(from: Instant, to: Instant): Promise<UpcomingEvent[]> {
    const now = this.options.now();
    const timeZone = this.options.timeZone();
    const kind = this.options.kind ?? "work";
    return PLANNER_VIEWED_DAYS.flatMap((viewed) => sampleEventsFor(viewed, now, kind, timeZone))
      .filter((event) => (event.end > event.start ? event.start < to && event.end > from : event.start >= from && event.start < to))
      .sort((a, b) => a.start - b.start || a.end - b.end || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  }

  async reload(): Promise<void> {
    /* Sample data never changes. */
  }

  status(): CalendarFeedStatus[] {
    return [{ subscriptionID: "demo", name: "Demo", hasData: true }];
  }
}
