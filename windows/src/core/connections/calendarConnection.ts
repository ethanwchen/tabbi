import type { CalendarFeedError, CalendarFeedStatus, CalendarSubscription } from "../calendar/calendarSource";
import { tr } from "../localization/tr";
import { chainChecks, connectionCheck, connectionDiagnosis, type ConnectionCheckOutcome, type ConnectionDiagnosis } from "./connectionDiagnosis";
import { ConnectionActions, connectionStatus, type ConnectionStatus } from "./connectionStatus";

/*
 * Port of CalendarConnection.swift for Windows. The Mac reads the calendars
 * macOS knows through EventKit, so its row is about a permission prompt and
 * Internet Accounts; Windows has neither, and Today reads subscribed ICS
 * feeds instead (core/calendar). So this row is about the feeds: none added
 * yet, still loading, one that fails (and why), or all loading fine, with
 * the same quiet suggestion to add a Google calendar.
 */

/** One subscribed feed, as far as the row reads it. */
export interface CalendarFeedState {
  /** The name the user gave it; shown in the row, never in support details. */
  readonly name: string;
  /** Why the last fetch failed; undefined after a good one. */
  readonly lastError?: CalendarFeedError;
  /** Whether a good copy has been fetched. */
  readonly hasData: boolean;
  /** Whether it is a Google Calendar link. */
  readonly isGoogle: boolean;
}

/** Where the calendar connection stands: the feeds and how each one is doing. Port of CalendarConnectionState. */
export interface CalendarConnectionState {
  readonly feeds: readonly CalendarFeedState[];
}

/** Whether a feed address is a Google Calendar link (`calendar.google.com`). */
export function isGoogleCalendarAddress(address: string): boolean {
  try {
    const url = new URL(address.trim().replace(/^webcals?:\/\//i, "https://"));
    return url.hostname.toLowerCase() === "calendar.google.com";
  } catch {
    return false;
  }
}

/** The row's state from the saved subscriptions and the source's feed statuses. */
export function calendarConnectionState(
  subscriptions: readonly CalendarSubscription[],
  statuses: readonly CalendarFeedStatus[],
): CalendarConnectionState {
  return {
    feeds: subscriptions.map((subscription) => {
      const status = statuses.find((candidate) => candidate.subscriptionID === subscription.id);
      const feed: { -readonly [Key in keyof CalendarFeedState]: CalendarFeedState[Key] } = {
        name: subscription.name,
        hasData: status?.hasData ?? false,
        isGoogle: isGoogleCalendarAddress(subscription.url),
      };
      if (status?.lastError !== undefined) feed.lastError = status.lastError;
      return feed;
    }),
  };
}

function failing(state: CalendarConnectionState): CalendarFeedState | undefined {
  return state.feeds.find((feed) => feed.lastError !== undefined);
}

function loading(state: CalendarConnectionState): boolean {
  return state.feeds.some((feed) => !feed.hasData && feed.lastError === undefined);
}

function hasGoogle(state: CalendarConnectionState): boolean {
  return state.feeds.some((feed) => feed.isGoogle);
}

export function calendarConnectionStatus(state: CalendarConnectionState): ConnectionStatus {
  if (state.feeds.length === 0) {
    return connectionStatus("notSetUp", tr("Calendar isn't connected"), tr("Add your calendar's link from Google, Outlook or iCloud to see its events here."), {
      action: ConnectionActions.setUp,
    });
  }
  const failed = failing(state);
  if (failed) {
    switch (failed.lastError) {
      case "unreachable":
        return connectionStatus("needsStep", tr("Tabbi can't reach %@", failed.name), tr("Check that you're online, then check again."), {
          action: ConnectionActions.checkAgain,
        });
      default:
        return connectionStatus("needsStep", tr("%@ isn't a calendar link", failed.name), tr("Copy the calendar's iCal or ICS link again and paste it in."), {
          action: ConnectionActions.setUp,
        });
    }
  }
  if (loading(state)) return connectionStatus("checking", tr("Loading your calendars"), tr("This takes a second."));
  return connectionStatus("connected", tr("Calendar is connected"), tr("Today's events show up in Tabbi."), {
    ...(hasGoogle(state) ? {} : { suggestion: ConnectionActions.showGuide("googleCalendar") }),
  });
}

function failureAnswer(feed: CalendarFeedState): string {
  switch (feed.lastError) {
    case "unreachable":
      return tr("No. Tabbi can't reach %@ right now.", feed.name);
    case "notACalendar":
      return tr("No. %@ didn't send a calendar.", feed.name);
    default:
      return tr("No. %@ isn't a web address Tabbi can open.", feed.name);
  }
}

export function calendarDiagnosis(state: CalendarConnectionState): ConnectionDiagnosis {
  const count = state.feeds.length;
  const failed = failing(state);
  const loads: ConnectionCheckOutcome | undefined = failed ? "failed" : loading(state) ? undefined : "passed";
  const checks = chainChecks([
    {
      question: tr("Did you add a calendar link?"),
      outcome: count > 0 ? "passed" : "failed",
      answer: count > 0 ? tr("Yes.") : tr("Not yet. Copy your calendar's link from Google, Outlook or iCloud."),
    },
    { question: tr("Do your calendars load?"), outcome: loads, answer: failed ? failureAnswer(failed) : tr("Yes.") },
  ]);
  if (count > 0 && loads === "passed") {
    checks.push(
      hasGoogle(state)
        ? connectionCheck(tr("Is a Google calendar in Tabbi?"), "passed", tr("Yes."))
        : connectionCheck(tr("Is a Google calendar in Tabbi?"), "note", tr("No. That's fine if you don't use Google. The Calendar row can add it.")),
    );
  }
  /* Feed names and links are the user's own, so only counts and the error's kind go to support. */
  const failingCount = state.feeds.filter((feed) => feed.lastError !== undefined).length;
  const loadingCount = state.feeds.filter((feed) => !feed.hasData && feed.lastError === undefined).length;
  const error = failed?.lastError === undefined ? "" : ` error=${failed.lastError}`;
  return connectionDiagnosis({
    kind: "calendar",
    status: calendarConnectionStatus(state),
    checks,
    technical: `calendar.feeds=${count} loading=${loadingCount} failing=${failingCount}${error} google=${hasGoogle(state)}`,
  });
}
