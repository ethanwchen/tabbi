/*
 * Port of TickerStore: drives the live preview of the closed island.
 *
 * It builds TickerSources from the merged ProviderSnapshot, filters them by
 * the user's preview settings, and runs TickerRotation to pick the item on
 * screen. It knows no module: whatever the enabled modules provide is what
 * it shows. The clock only runs while the island is closed, and then wakes
 * only when the screen can change: the next rotation turn, the next change
 * TickerSources predicts, or every second while a running focus clock is
 * showing. It also says whether anything is live, which Windows' Auto mode
 * uses to draw the pill at all.
 */

import { allTickerKinds, type TickerKind } from "../core/ticker/tickerKind";
import { tickerItemIsPinned, tickerItemKind, type TickerItem } from "../core/ticker/tickerItem";
import { TickerRotation } from "../core/ticker/tickerRotation";
import { TickerSources } from "../core/ticker/tickerSources";
import { MeetingNudgeWatch, type MeetingNudge } from "../core/ticker/meetingNudge";
import { settingsShowsPreview, type AppSettings } from "../core/settings/appSettings";
import type { ModuleCatalog } from "../core/modules/moduleCatalog";
import type { ProviderSnapshot } from "../core/providers/providerSnapshot";
import type { Instant } from "../core/time";
import type { ClosedPreview } from "./closedPreview";
import { isLive, nextLiveChange } from "./liveActivity";
import { Store, type Readable } from "./store";

/** A one-shot wake-up at a wall-clock moment, in seconds since 1970. */
export interface TickerAlarm {
  schedule(at: Instant): void;
  cancel(): void;
  dispose(): void;
}

export interface TickerState {
  /** The item beside the closed island; undefined keeps the pill plain (or hidden). */
  readonly item: TickerItem | undefined;
  /** Something is live, so Auto mode draws the pill. */
  readonly live: boolean;
}

export interface TickerStoreOptions {
  readonly settings: Readable<AppSettings>;
  readonly snapshot: Readable<ProviderSnapshot>;
  readonly catalog: ModuleCatalog;
  readonly preview: ClosedPreview;
  readonly now: () => Instant;
  /** Makes the alarm that wakes the store; it calls `fire` at the scheduled moment. */
  readonly alarm: (fire: () => void) => TickerAlarm;
}

export class TickerStore extends Store<TickerState> {
  private sources = new TickerSources();
  private settings: AppSettings;
  private readonly rotation: TickerRotation;
  private readonly nudges = new MeetingNudgeWatch();
  private nudge: MeetingNudge | undefined;
  /** False while the island is open, where the preview isn't visible. */
  private active = true;
  private rotates = false;
  private readonly alarm: TickerAlarm;
  private readonly stops: (() => void)[] = [];

  constructor(private readonly options: TickerStoreOptions) {
    super({ item: undefined, live: false });
    this.settings = options.settings.get();
    this.rotation = new TickerRotation(this.settings.notchPreview.interval);
    this.alarm = options.alarm(() => this.refresh());
    this.sources = TickerSources.of(options.snapshot.get());
    this.stops.push(
      options.snapshot.subscribe(() => {
        this.sources = TickerSources.of(options.snapshot.get());
        this.refresh();
      }),
      options.settings.subscribe(() => {
        this.settings = options.settings.get();
        this.rotation.interval = this.settings.notchPreview.interval;
        this.refresh();
      }),
    );
    this.refresh();
  }

  /** Pauses the clock while the island is open, and catches up on close. */
  setActive(active: boolean): void {
    if (active === this.active) return;
    this.active = active;
    this.refresh();
  }

  /** Shows the next live activity now (a middle-click on the pill). Returns whether the pill changed. */
  cycle(): boolean {
    const now = this.options.now();
    if (!this.active) return false;
    const items = this.items(now);
    if (items.length <= 1) return false;
    const next = this.nudging(this.rotation.advance(items, now), now);
    this.rotates = true;
    const changed = next === undefined || this.state.item === undefined || tickerItemKind(next) !== tickerItemKind(this.state.item);
    this.setState({ item: next });
    this.schedule(now);
    return changed;
  }

  /** Stops following the snapshot and the settings, and cancels the clock. */
  dispose(): void {
    for (const stop of this.stops) stop();
    this.alarm.dispose();
  }

  /** Re-reads the clock now, e.g. after the PC wakes. */
  refresh(): void {
    const now = this.options.now();
    const watched = this.active ? new Set(allTickerKinds(this.options.catalog).filter((kind) => this.shows(kind))) : new Set<TickerKind>();
    this.options.preview.setWatched(watched);
    const snapshot = this.options.snapshot.get();
    if (this.active) {
      const items = this.items(now);
      const next = this.nudging(this.rotation.update(items, now), now);
      this.rotates = items.length > 1 && next !== undefined && !tickerItemIsPinned(next);
      this.setState({ item: next, live: isLive(snapshot, now) });
    } else {
      this.setState({ live: isLive(snapshot, now) });
    }
    this.schedule(now);
  }

  private shows = (kind: TickerKind): boolean => settingsShowsPreview(this.settings, kind);

  private items(now: Instant): TickerItem[] {
    return this.sources.items(now, this.shows);
  }

  /** `item`, glowing if it is a meeting whose nudge is playing; a meeting coming within the lead starts its nudge once. */
  private nudging(item: TickerItem | undefined, now: Instant): TickerItem | undefined {
    if (item?.type !== "meeting") return item;
    if (this.nudge?.isShowing(now) !== true) {
      const started = this.nudges.nudge(this.sources, now);
      if (started !== undefined) this.nudge = started;
    }
    const imminent = this.sources.imminentMeeting(now);
    const key = imminent === undefined ? undefined : MeetingNudgeWatch.key(imminent);
    const isNudging = this.nudge !== undefined && this.nudge.isShowing(now) && this.nudge.key === key;
    return { type: "meeting", meeting: { ...item.meeting, isNudging } };
  }

  private schedule(now: Instant): void {
    const wakes: (Instant | undefined)[] = [nextLiveChange(this.options.snapshot.get(), now)];
    if (this.active) {
      wakes.push(this.sources.nextChange(now, this.shows));
      if (this.nudge?.isShowing(now) === true) wakes.push(this.nudge.endsAt);
      const shownSince = this.rotation.shownSince;
      if (this.rotates && shownSince !== undefined) wakes.push(shownSince + this.rotation.interval);
      const item = this.state.item;
      if (item?.type === "focus" && item.focus.isRunning) wakes.push(now + 1);
    }
    const due = wakes.filter((at): at is Instant => at !== undefined);
    if (due.length === 0) this.alarm.cancel();
    else this.alarm.schedule(Math.max(Math.min(...due), now));
  }
}
