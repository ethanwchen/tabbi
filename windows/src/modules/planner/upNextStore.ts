/*
 * Port of UpNextStore: today's remaining calendar events for the Today
 * panel's "Up next" card, read from the one calendar source (ICS feeds on
 * Windows, samples in demo runs) plus the blocks the user kept in Today.
 *
 * While the panel is visible the list refreshes on every minute boundary,
 * so "in 12 min" badges stay true; the closed island's meeting preview
 * keeps it refreshing the same way while it is on, and while neither needs
 * events nothing runs. While the checklist shows yesterday or tomorrow, the
 * card lists that whole day instead; `events` stays today's, which the
 * ticker's meeting preview reads.
 */

import type { ModuleContext } from "../../app/context";
import { Store } from "../../app/store";
import type { CalendarSource } from "../../core/calendar/calendarSource";
import type { MeetingLink } from "../../core/planner/meetingLink";
import { addingDaysToKey, dayKeyStart, plannerDayKeyOf, type PlannerDayKey } from "../../core/planner/plannerDayKey";
import { viewedDayKey, type PlannerViewedDay } from "../../core/planner/plannerViewedDay";
import { calendarSourceSituation, type UpNextSituation } from "../../core/planner/upNextEmptyState";
import { agenda, upNext, type UpcomingEvent } from "../../core/planner/upcomingEvent";
import type { Instant } from "../../core/time";
import type { PlannedBlocksStore } from "./plannedBlocks";

export interface UpNextState {
  /** The moment badges are measured against; advances once a minute while visible. */
  readonly now: Instant;
  /** The day the card lists. Today unless the checklist steps away. */
  readonly viewing: PlannerViewedDay;
  /** Up to three events still ahead today, soonest first. */
  readonly events: readonly UpcomingEvent[];
  /** How many timed events today has in all, finished ones included, so an empty list can tell "day is done" from "nothing on". */
  readonly eventsToday: number;
  /** The first few timed events of the other day shown, earliest first, and how many it has in all. */
  readonly otherEvents: readonly UpcomingEvent[];
  readonly otherEventCount: number;
  /** Whether any calendar feed is set up; without one the card offers Connections. */
  readonly hasSubscriptions: boolean;
  /** True until the first read of the day shown has landed. */
  readonly isLoading: boolean;
}

/** Only `hasSubscriptions` is read from the source; a demo source always has data. */
function hasSubscriptions(source: CalendarSource): boolean {
  return source.status().length > 0;
}

export class UpNextStore extends Store<UpNextState> {
  private isVisible = false;
  private isPreviewWatching = false;
  private tick: ReturnType<typeof setTimeout> | undefined;
  /** Bumped on every reload so a stale read never lands over a fresh one. */
  private generation = 0;

  constructor(
    private readonly context: ModuleContext,
    private readonly source: CalendarSource,
    private readonly planned: PlannedBlocksStore,
  ) {
    super({
      now: context.now(),
      viewing: "today",
      events: [],
      eventsToday: 0,
      otherEvents: [],
      otherEventCount: 0,
      hasSubscriptions: hasSubscriptions(source),
      isLoading: true,
    });
  }

  /** The events the card lists for the day it shows. */
  get shownEvents(): readonly UpcomingEvent[] {
    return this.state.viewing === "today" ? this.state.events : this.state.otherEvents;
  }

  /** The empty state for the day shown, or undefined when there are events to list (or none have been read yet). */
  get emptySituation(): UpNextSituation | undefined {
    const state = this.state;
    if (state.isLoading && state.hasSubscriptions) return undefined;
    const count = state.viewing === "today" ? state.eventsToday : state.otherEventCount;
    return calendarSourceSituation(state.viewing, state.hasSubscriptions, this.shownEvents.length, count);
  }

  /** True while the panel or the closed-island preview needs fresh events. */
  private get isWatched(): boolean {
    return this.isVisible || this.isPreviewWatching;
  }

  /** Call when the panel appears and disappears. */
  setVisible(visible: boolean): void {
    if (visible === this.isVisible) return;
    const wasWatched = this.isWatched;
    this.isVisible = visible;
    this.watchedDidChange(wasWatched);
  }

  /** Call while the closed island's preview can show a meeting, so it learns about events added since the panel was last open. */
  setPreviewWatching(watching: boolean): void {
    if (watching === this.isPreviewWatching) return;
    const wasWatched = this.isWatched;
    this.isPreviewWatching = watching;
    this.watchedDidChange(wasWatched);
  }

  /** Lists `day` in the card: today's next events, or all of yesterday or tomorrow. Follows the checklist's day stepper. */
  show(day: PlannerViewedDay): void {
    if (day === this.state.viewing) return;
    this.setState({ viewing: day, otherEvents: [], otherEventCount: 0, isLoading: day !== "today" });
    void this.reload();
  }

  /** Every event on `day` (calendar and kept blocks), for Plan my day. */
  async planEvents(day: PlannerViewedDay): Promise<UpcomingEvent[]> {
    const timeZone = this.context.timeZone();
    const key = viewedDayKey(day, plannerDayKeyOf(this.context.now(), timeZone));
    return this.eventsOn(key);
  }

  /** Reads the day shown (and today) again now. */
  async reload(): Promise<void> {
    const generation = ++this.generation;
    const now = this.context.now();
    const timeZone = this.context.timeZone();
    const today = plannerDayKeyOf(now, timeZone);
    const viewing = this.state.viewing;
    const [todayEvents, otherAll] = await Promise.all([
      this.eventsOn(today),
      viewing === "today" ? Promise.resolve([]) : this.eventsOn(viewedDayKey(viewing, today)),
    ]);
    if (generation !== this.generation) return;
    const timed = (events: readonly UpcomingEvent[]) => events.filter((event) => !event.isAllDay).length;
    this.setState({
      now,
      events: upNext(todayEvents, now),
      eventsToday: timed(todayEvents),
      otherEvents: viewing === "today" ? [] : agenda(otherAll),
      otherEventCount: viewing === "today" ? 0 : timed(otherAll),
      hasSubscriptions: hasSubscriptions(this.source),
      isLoading: false,
    });
  }

  /** Opens a video call in the default browser. */
  join(link: MeetingLink): void {
    void this.context.host.openUrl(link.url).catch((error: unknown) => this.context.logger.error("could not open the meeting link", error));
  }

  /** Snapshot runs only: shows the card as a day with no calendar feed, or an empty day. */
  showForSnapshot(preview: "noCalendar" | "freeDay"): void {
    this.generation += 1;
    this.setState({
      events: [],
      eventsToday: 0,
      otherEvents: [],
      otherEventCount: 0,
      hasSubscriptions: preview !== "noCalendar",
      isLoading: false,
    });
  }

  private async eventsOn(key: PlannerDayKey): Promise<UpcomingEvent[]> {
    const timeZone = this.context.timeZone();
    const from = dayKeyStart(key, timeZone);
    const to = dayKeyStart(addingDaysToKey(key, 1), timeZone);
    const [calendar, kept] = await Promise.all([
      this.source.events(from, to).catch((error: unknown) => {
        this.context.logger.error("could not read the calendar", error);
        return [] as UpcomingEvent[];
      }),
      this.planned.events(from, to),
    ]);
    return [...calendar, ...kept];
  }

  private watchedDidChange(wasWatched: boolean): void {
    if (this.isWatched === wasWatched) return;
    if (this.isWatched) {
      void this.reload();
      this.scheduleTick();
    } else {
      this.cancelTick();
    }
  }

  /** Fires just after the next whole minute, then reschedules itself, so badges change in step with the clock. */
  private scheduleTick(): void {
    this.cancelTick();
    /* A snapshot run draws one still moment. */
    if (this.context.isSnapshot) return;
    const now = this.context.now();
    const wait = 60 - (now % 60) + 0.05;
    this.tick = setTimeout(() => {
      this.tick = undefined;
      if (!this.isWatched) return;
      void this.reload();
      this.scheduleTick();
    }, wait * 1000);
  }

  private cancelTick(): void {
    if (this.tick !== undefined) clearTimeout(this.tick);
    this.tick = undefined;
  }
}
