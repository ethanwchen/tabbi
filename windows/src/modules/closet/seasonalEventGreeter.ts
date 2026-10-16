/*
 * Port of SeasonalEventGreeter: marks the start of a seasonal event with
 * one small moment. The first time Tabbi runs during the event, the pet
 * beside the closed island does a little dance; each run is greeted once
 * (`SeasonalEventGreeting`), so it is never repeated, and the Closet's
 * banner says the rest. The Mac's cheer goes through its CelebrationCenter
 * to the ticker; here the greeter publishes the dance as `greeted`, and the
 * Closet's preview pet celebrates, so the moment is never lost while the
 * closed island's cheers are not wired yet.
 */

import type { ModuleContext } from "../../app/context";
import { Emitter } from "../../app/store";
import { SeasonalEventGreeting } from "../../core/events/seasonalEventGreeting";
import type { SeasonalEventOccurrence } from "../../core/events/seasonalEvent";
import type { DocumentStore } from "../../core/persistence/documentStore";
import type { Instant } from "../../core/time";
import { WallClockAlarm } from "../../ui/kit/clock";
import { alarmTimers } from "./alarmTimers";

export class SeasonalEventGreeter {
  /** A beat after launch, so the closed island is up before the pet dances. */
  static readonly launchDelay = 4;

  /** The runs greeted, as they start. */
  readonly greeted = new Emitter<readonly SeasonalEventOccurrence[]>();

  private greeting = new SeasonalEventGreeting();
  private readonly store: DocumentStore | undefined;
  private unreadable = false;
  private readonly loaded: Promise<void>;
  private readonly alarm = new WallClockAlarm(() => this.check(), alarmTimers(() => this.now()));

  constructor(
    private readonly context: ModuleContext,
    /** The moment to read events at: the Closet's `seasonNow`, which a demo pins. */
    private readonly now: () => Instant,
  ) {
    this.store = context.isDemo || context.isSnapshot ? undefined : context.storage.root();
    this.loaded = this.store === undefined ? Promise.resolve() : this.load(this.store);
  }

  private async load(store: DocumentStore): Promise<void> {
    try {
      this.greeting = (await SeasonalEventGreeting.load(store)) ?? this.greeting;
    } catch (error) {
      this.unreadable = true;
      this.context.logger.error("The seasonal greetings file could not be read; greeting from memory", error);
    }
  }

  start(): void {
    this.alarm.schedule((this.context.now() + SeasonalEventGreeter.launchDelay) * 1000);
  }

  stop(): void {
    this.alarm.cancel();
  }

  /** Greets a run that just started (or was never greeted), then waits for the next one to start. A demo's pinned moment never moves, so it greets once per launch. */
  check(): void {
    void this.loaded.then(() => {
      const moment = this.now();
      const zone = this.context.timeZone();
      const due = this.greeting.greet(moment, zone);
      if (due.length > 0) {
        this.greeted.emit(due);
        this.persist();
      }
      if (this.context.isDemo) return;
      const next = SeasonalEventGreeting.nextCheck(moment, zone);
      if (next !== undefined) this.alarm.schedule(next * 1000);
    });
  }

  private persist(): void {
    const store = this.store;
    if (store === undefined || this.unreadable) return;
    void this.greeting.write(store).catch((error: unknown) => this.context.logger.error("The seasonal greetings file could not be written", error));
  }
}
