/*
 * Port of RecapStore: the weekly recaps. It builds each finished week's
 * numbers from the shared activity log on Sunday evening, keeps them in a
 * `RecapArchive` saved in the edition's `Recaps` folder, and says which
 * recap the island should show once and which still needs its toast.
 *
 * It reads only the activity log, so a recap counts whatever any module
 * logged. Demo runs show the demo archive and build nothing; demo and
 * snapshot runs never read or write the file.
 */

import type { ModuleContext } from "../../../app/context";
import { Emitter, Store } from "../../../app/store";
import type { DocumentStore } from "../../../core/persistence/documentStore";
import { RecapArchive } from "../../../core/recap/recapArchive";
import { demoRecapArchive } from "../../../core/recap/recapDemo";
import { addingWeeks, latestReadyWeek, recapReadyDate, recapWeekEnd } from "../../../core/recap/recapWeek";
import { WeeklyRecap, type RecapCheer } from "../../../core/recap/weeklyRecap";
import type { RecapWeek } from "../../../core/recap/recapWeek";
import { dayKeyStart } from "../../../core/planner/plannerDayKey";
import type { Instant } from "../../../core/time";
import { WallClockAlarm } from "../../../ui/kit/clock";
import { alarmTimers } from "../alarmTimers";

export interface RecapStoreState {
  readonly archive: RecapArchive;
  /** The user's Weekly recap switch, mirrored here so the list of past recaps hides with it. */
  readonly isEnabled: boolean;
}

export class RecapStore extends Store<RecapStoreState> {
  /** A past recap the user picked from the list, for the island to show. */
  readonly reopened = new Emitter<WeeklyRecap>();
  /** Runs after a build on start or at Sunday evening, not after the one on opening the island, which shows the card instead. */
  onScheduledBuild: (() => void) | undefined;

  private readonly store: DocumentStore | undefined;
  private readonly builds: boolean;
  private unreadable = false;
  private readonly loaded: Promise<void>;
  private readonly alarm = new WallClockAlarm(() => {
    void this.buildOnSchedule().then(() => this.scheduleNextBuild());
  }, alarmTimers(() => this.context.now()));
  /** Builds run one after another, so a Sunday alarm and an island opening never write the archive twice at once. */
  private building: Promise<void> = Promise.resolve();

  constructor(private readonly context: ModuleContext) {
    const isDemo = context.isDemo;
    super({ archive: isDemo ? demoRecapArchive(context.now(), context.timeZone()) : new RecapArchive(), isEnabled: context.settings.current.weeklyRecapEnabled });
    this.builds = !isDemo;
    this.store = isDemo || context.isSnapshot ? undefined : context.storage.root();
    this.loaded = this.store === undefined ? Promise.resolve() : this.load(this.store);
  }

  private async load(store: DocumentStore): Promise<void> {
    try {
      const archive = await RecapArchive.load(store);
      if (archive !== undefined) this.setState({ archive });
    } catch (error) {
      this.unreadable = true;
      this.context.logger.error("The recap archive could not be read; it is left alone", error);
    }
  }

  get archive(): RecapArchive {
    return this.state.archive;
  }

  get isEnabled(): boolean {
    return this.state.isEnabled;
  }

  setEnabled(enabled: boolean): void {
    this.setState({ isEnabled: enabled });
  }

  /**
   * Builds the weeks that are ready now and saves when anything changed.
   * Called on start, at each Sunday evening and when the island opens, so
   * a PC that slept through Sunday still gets its recap.
   */
  refresh(): Promise<void> {
    if (!this.builds) return Promise.resolve();
    const run = this.building.then(() => this.build());
    this.building = run.catch(() => undefined);
    return run;
  }

  private async build(): Promise<void> {
    await this.loaded;
    const now = this.context.now();
    const zone = this.context.timeZone();
    const archive = this.state.archive.copy();
    let changed = archive.skipStaleWeeks(now, zone);
    for (const week of archive.weeksToBuild(now, zone)) {
      const records = await this.context.activityLog.recordsBetween(week, recapWeekEnd(week));
      const recap = WeeklyRecap.fromRecords(week, records, zone);
      changed = archive.record(recap, now, zone) || changed;
    }
    if (!changed) return;
    this.setState({ archive });
    await this.save();
  }

  /** The newest recap, when the user hasn't seen its card yet. */
  get unseen(): WeeklyRecap | undefined {
    return this.state.archive.unseen;
  }

  /** The newest recap, when it still needs its toast. */
  get unnotified(): WeeklyRecap | undefined {
    return this.state.archive.unnotified;
  }

  /** Shows `recap` in the island again, from the list of past recaps. */
  reopen(recap: WeeklyRecap): void {
    if (!this.state.isEnabled) return;
    this.reopened.emit(recap);
  }

  /** `recap`'s warm line, against the weeks before it. */
  cheer(recap: WeeklyRecap): RecapCheer {
    return this.state.archive.cheer(recap);
  }

  markSeen(week: RecapWeek): void {
    const archive = this.state.archive.copy();
    if (!archive.markSeen(week)) return;
    this.setState({ archive });
    void this.save();
  }

  markNotified(week: RecapWeek): void {
    const archive = this.state.archive.copy();
    if (!archive.markNotified(week)) return;
    this.setState({ archive });
    void this.save();
  }

  /** Builds what is ready and wakes again for the next Sunday evening. */
  start(): void {
    void this.buildOnSchedule().then(() => this.scheduleNextBuild());
  }

  stop(): void {
    this.alarm.cancel();
  }

  /** When the archive next has work: Monday midnight while the newest ready week can still change (to settle it), else next Sunday evening. */
  get nextBuildDate(): Instant {
    const now = this.context.now();
    const zone = this.context.timeZone();
    const latest = latestReadyWeek(now, zone);
    const next = addingWeeks(latest, 1);
    if (this.state.archive.weeksToBuild(now, zone).includes(latest)) return dayKeyStart(next, zone);
    return recapReadyDate(next, zone);
  }

  private async buildOnSchedule(): Promise<void> {
    await this.refresh();
    this.onScheduledBuild?.();
  }

  private scheduleNextBuild(): void {
    if (!this.builds) return;
    this.alarm.schedule(this.nextBuildDate * 1000);
  }

  /** Merges in what is on disk first, so another copy of the app writing the same file never brings back a week the user has already seen. */
  private async save(): Promise<void> {
    const store = this.store;
    if (store === undefined) return;
    await this.loaded;
    if (this.unreadable) return;
    try {
      const saved = await RecapArchive.load(store).catch(() => undefined);
      const archive = this.state.archive.copy();
      if (saved !== undefined && archive.merge(saved)) this.setState({ archive });
      await this.state.archive.write(store);
    } catch (error) {
      this.context.logger.error("The recap archive could not be written", error);
    }
  }
}
