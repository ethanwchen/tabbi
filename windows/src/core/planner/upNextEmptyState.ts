import { tr } from "../localization/tr";
import type { PlannerViewedDay } from "./plannerViewedDay";

/** Port of UpNextEmptyState.Situation: why Up next has no event to show. */
export type UpNextSituation =
  /** Calendar access was never requested. */
  | "notAsked"
  /** Access is denied. */
  | "denied"
  /** No calendar is connected here yet, so Connections takes over (on Windows: no calendar feed added). */
  | "unavailable"
  /** Every calendar is local and today is empty: the real calendar most likely lives in an online account. */
  | "noAccounts"
  /** Nothing on any calendar today. */
  | "freeDay"
  /** Today had events, and they're all over. */
  | "dayDone"
  /** Nothing on any calendar tomorrow. */
  | "freeTomorrow"
  /** Nothing was on any calendar yesterday. */
  | "freeYesterday";

/** Port of UpNextEmptyState.Action: the one action that would fix the state. */
export type UpNextAction = "requestAccess" | "openPrivacySettings" | "openInternetAccounts" | "openConnections";

/**
 * Port of UpNextEmptyState: what Up next says when it has no event to
 * show. The kit names what the calendar holds ("lectures, labs, and
 * shifts"), so a study kit reads naturally.
 *
 * On Windows calendars come from ICS feeds: a source with no feed is
 * `unavailable` (open Connections), and one with feeds counts as having
 * accounts. The Mac-only situations (`notAsked`, `denied`, `noAccounts`)
 * keep the Mac's copy for parity; `calendarSourceSituation` never gives them.
 */
export interface UpNextEmptyState {
  readonly symbol: string;
  readonly title: string;
  readonly detail: string;
  readonly action?: UpNextAction;
  /** The action button's label and tooltip; empty without an action. */
  readonly actionTitle: string;
  readonly actionHelp: string;
}

/** The kit's phrase in the user's language when it is one the app ships; a kit's own phrase stays as written. */
export function localizedUpNextEvents(phrase: string): string {
  return tr(phrase);
}

export function upNextEmptyState(situation: UpNextSituation, upNextEvents: string, appName: string): UpNextEmptyState {
  const events = localizedUpNextEvents(upNextEvents);
  const plain = (symbol: string, title: string, detail: string): UpNextEmptyState => ({
    symbol,
    title,
    detail,
    actionTitle: "",
    actionHelp: "",
  });
  switch (situation) {
    case "notAsked":
      return {
        symbol: "calendar",
        title: tr("See what's next"),
        detail: tr("Today's %@. Google calendars show up once added in Internet Accounts.", events),
        action: "requestAccess",
        actionTitle: tr("Show calendar"),
        actionHelp: tr("Allow %@ to read your calendars", appName),
      };
    case "denied":
      return {
        symbol: "calendar.badge.exclamationmark",
        title: tr("Calendar access is off"),
        detail: tr("Allow %@ in Privacy & Security.", appName),
        action: "openPrivacySettings",
        actionTitle: tr("Open Settings"),
        actionHelp: tr("Open Calendars privacy settings"),
      };
    case "unavailable":
      return {
        symbol: "calendar",
        title: tr("Connect your calendar"),
        detail: tr("See your %@ here. It only takes a moment.", events),
        action: "openConnections",
        actionTitle: tr("Connect calendar"),
        actionHelp: tr("Open Connections to connect your calendar"),
      };
    case "noAccounts":
      return {
        symbol: "calendar.badge.plus",
        title: tr("Add your calendar"),
        detail: tr("Using Google? Add it in Internet Accounts to see your %@ here.", events),
        action: "openInternetAccounts",
        actionTitle: tr("Internet Accounts"),
        actionHelp: tr("Open Internet Accounts to add a Google, Exchange or iCloud calendar"),
      };
    case "freeDay":
      return plain("calendar.badge.checkmark", tr("Nothing on today"), tr("No events on your calendars today."));
    case "dayDone":
      return plain("calendar.badge.checkmark", tr("No more events today"), tr("The rest of the day is yours."));
    case "freeTomorrow":
      return plain("calendar.badge.checkmark", tr("Free all day"), tr("Nothing on your calendars tomorrow."));
    case "freeYesterday":
      return plain("calendar", tr("A free day"), tr("Nothing was on your calendars yesterday."));
  }
}

/**
 * Which empty state fits a granted calendar with nothing left today, or
 * undefined when there are events to list. `hasAccounts` says whether any
 * calendar syncs from an online account.
 */
export function grantedSituation(upcoming: number, eventsToday: number, hasAccounts: boolean): UpNextSituation | undefined {
  if (upcoming !== 0) return undefined;
  if (eventsToday > 0) return "dayDone";
  return hasAccounts ? "freeDay" : "noAccounts";
}

/** The same for `day`: for yesterday or tomorrow, whether that whole day had any timed event. */
export function grantedSituationOn(
  day: PlannerViewedDay,
  upcoming: number,
  eventsThatDay: number,
  hasAccounts: boolean,
): UpNextSituation | undefined {
  if (day === "today") return grantedSituation(upcoming, eventsThatDay, hasAccounts);
  if (eventsThatDay !== 0) return undefined;
  if (!hasAccounts) return "noAccounts";
  return day === "tomorrow" ? "freeTomorrow" : "freeYesterday";
}

/**
 * The situation for a Windows calendar source: no feed added means
 * `unavailable` (Connections adds one); with feeds, the granted rules
 * apply with every feed counting as an online account.
 */
export function calendarSourceSituation(
  day: PlannerViewedDay,
  hasSubscriptions: boolean,
  upcoming: number,
  eventsThatDay: number,
): UpNextSituation | undefined {
  if (!hasSubscriptions) return "unavailable";
  return grantedSituationOn(day, upcoming, eventsThatDay, true);
}
