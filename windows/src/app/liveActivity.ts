/*
 * When Windows' Auto mode draws the closed pill: only while something is
 * live (the handoff's rule for an island that must not cover the top of the
 * screen for nothing). Live is a focus clock running, music playing, a
 * meeting starting within five minutes, or a party's shared session under
 * way. Pure, so the rule and its wake-up times are tested on their own.
 */

import type { ProviderSnapshot } from "../core/providers/providerSnapshot";
import type { Instant, Seconds } from "../core/time";

/** How soon a meeting must start for the pill to show it. */
export const LIVE_MEETING_LEAD: Seconds = 5 * 60;

/* Timed events only: an all-day event is not a meeting to leave for. */
function meetingStartsSoon(snapshot: ProviderSnapshot, now: Instant): boolean {
  return snapshot.events.some((event) => !event.isAllDay && event.start > now && event.start - now <= LIVE_MEETING_LEAD);
}

export function isLive(snapshot: ProviderSnapshot, now: Instant): boolean {
  if (snapshot.focus?.isRunning === true) return true;
  if (snapshot.isPlaying) return true;
  const session = snapshot.party?.session;
  if (session !== undefined && session.remaining(now) > 0) return true;
  return meetingStartsSoon(snapshot, now);
}

/**
 * The next moment `isLive` can change from the clock alone: a meeting
 * coming within the lead or starting, or a party session ending. A focus
 * clock or music only changes with a new snapshot.
 */
export function nextLiveChange(snapshot: ProviderSnapshot, now: Instant): Instant | undefined {
  const moments: Instant[] = [];
  for (const event of snapshot.events) {
    if (event.isAllDay || !(event.start > now)) continue;
    const enters = event.start - LIVE_MEETING_LEAD;
    moments.push(enters > now ? enters : event.start);
  }
  const session = snapshot.party?.session;
  if (session !== undefined && session.endsAt > now) moments.push(session.endsAt);
  return moments.length === 0 ? undefined : Math.min(...moments);
}
