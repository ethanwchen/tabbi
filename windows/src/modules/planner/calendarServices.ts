/*
 * The calendar, declared here because Today owns it: Today and the Schedule
 * read one CalendarSource, so a feed is fetched once however many tabs show
 * it. Live runs read the ICS addresses the user added (through the host,
 * with each feed's last good copy cached); demo and snapshot runs show the
 * planner's sample day and touch nothing.
 */

import type { ModuleContext } from "../../app/context";
import { serviceKey } from "../../app/sharedServices";
import { IcsCalendarSource, loadCalendarSubscriptions, type CalendarSource } from "../../core/calendar/calendarSource";
import { DemoCalendarSource } from "../../core/calendar/demoCalendarSource";
import { isEphemeral } from "../../core/modules/runMode";
import { todayPlanSettingsFromKit } from "../../core/planner/todayPlanSettings";

const CALENDAR = serviceKey<CalendarSource>("planner.calendar");

/** The one calendar source. */
export function calendarSource(context: ModuleContext): CalendarSource {
  return context.shared.resolve(CALENDAR, () => {
    const now = () => context.now();
    const timeZone = () => context.timeZone();
    if (isEphemeral(context.runMode)) {
      return new DemoCalendarSource({ now, timeZone, kind: todayPlanSettingsFromKit(context.activeKit?.defaults).sampleDay });
    }
    const source = new IcsCalendarSource({
      subscriptions: [],
      fetcher: (url) => context.host.fetchCalendar(url),
      /* The feeds name their own documents inside the Calendars folder. */
      store: context.storage.root("cache"),
      now,
      timeZone,
    });
    /* The saved feeds arrive a moment after launch; until then the source has none. */
    void loadCalendarSubscriptions(context.storage.root())
      .then((subscriptions) => source.setSubscriptions(subscriptions))
      .catch((error: unknown) => context.logger.error("could not read the calendar feeds", error));
    return source;
  });
}

/** The message the Settings window posts on Today's "calendar" channel after the saved feeds change. */
export const CALENDAR_SUBSCRIPTIONS_CHANGED = { type: "subscriptions" } as const;

/** Whether `message` says the saved feeds changed. */
export function isCalendarSubscriptionsChange(message: unknown): boolean {
  return typeof message === "object" && message !== null && (message as { type?: unknown }).type === CALENDAR_SUBSCRIPTIONS_CHANGED.type;
}

/**
 * Reads the saved feeds again into this window's source and fetches them,
 * after Settings added or removed one. A demo source has no feeds to read.
 */
export async function reloadCalendarSubscriptions(context: ModuleContext): Promise<void> {
  const source = calendarSource(context);
  if (!(source instanceof IcsCalendarSource)) return;
  source.setSubscriptions(await loadCalendarSubscriptions(context.storage.root()));
  await source.reload();
}
