/*
 * Port of RecapMoment: the recap's moment in the island. The first time
 * the user opens the island after a week's recap is ready, its card fills
 * the open island once, until they press Done or close the island.
 * Whatever already owns the takeover slot (first-run onboarding) comes
 * first, so a recap never interrupts it and waits for the next open.
 */

import type { ModuleContext } from "../../../app/context";
import { Store } from "../../../app/store";
import { takeoverSlot, type NotchTakeover } from "../../../app/takeover";
import { recapNotice } from "../../../core/recap/recapNotice";
import type { RecapCheer, WeeklyRecap } from "../../../core/recap/weeklyRecap";
import type { RecapStore } from "./recapStore";

/** A recap on show, with its warm line worked out when it appeared. */
export interface RecapShown {
  readonly recap: WeeklyRecap;
  readonly cheer: RecapCheer;
}

export interface RecapMomentState {
  /** The recap filling the island now, undefined when the tabs show. */
  readonly shown: RecapShown | undefined;
}

export class RecapMoment extends Store<RecapMomentState> {
  private isEnabled: boolean;
  private isStarted = false;
  private isFollowingSwitch = false;
  /** The takeover this moment put in the slot, so Done clears only its own. */
  private own: NotchTakeover | undefined;
  private readonly stops: (() => void)[] = [];

  constructor(
    private readonly context: ModuleContext,
    readonly store: RecapStore,
    /** Draws the card for a recap on show. */
    private readonly makeTakeover: (shown: RecapShown, done: () => void) => NotchTakeover,
  ) {
    super({ shown: undefined });
    this.isEnabled = context.settings.current.weeklyRecapEnabled;
    store.onScheduledBuild = () => this.notifyIfDue();
    this.stops.push(store.reopened.on((recap) => this.show(recap)));
    /* The Settings switch: off hides a card on show and stops the Sunday build; back on builds what is ready. */
    this.stops.push(
      context.settings.settings.subscribe(() => {
        this.setEnabled(context.settings.current.weeklyRecapEnabled);
      }),
    );
  }

  /** Says once that the newest recap is ready, unless the user already saw its card or turned recaps off. Demo and snapshot runs post nothing. */
  private notifyIfDue(): void {
    if (!this.isEnabled || this.isFollowingSwitch || this.state.shown !== undefined || this.context.isDemo || this.context.isSnapshot) return;
    const recap = this.store.unnotified;
    if (recap === undefined) return;
    this.store.markNotified(recap.week);
    const notice = recapNotice(recap, this.store.cheer(recap));
    void this.context.host.notify(notice.title, notice.body).catch((error: unknown) => this.context.logger.error("The recap's toast could not be shown", error));
  }

  private get isBlocked(): boolean {
    const slot = takeoverSlot(this.context.shared).get();
    return slot !== undefined && slot !== this.own;
  }

  /**
   * The user opened the island: builds what is ready (a PC that slept
   * through Sunday evening catches up here) and shows the newest unseen
   * recap. It counts as seen (and is saved) the moment it shows, so a later
   * open, a relaunch or a quit never brings it back.
   */
  async islandOpened(): Promise<void> {
    /* A snapshot run draws the card only when asked for it, never over every other module's shot. */
    if (!this.isEnabled || this.state.shown !== undefined || this.isBlocked || this.context.isSnapshot) return;
    await this.store.refresh();
    const recap = this.store.unseen;
    if (recap === undefined || this.state.shown !== undefined || this.isBlocked) return;
    this.present({ recap, cheer: this.store.cheer(recap) });
    this.store.markSeen(recap.week);
  }

  /** Shows a past recap picked from the list. The island is already open, so the takeover simply replaces the tabs until Done. */
  private show(recap: WeeklyRecap): void {
    if (!this.isEnabled || this.isBlocked) return;
    this.present({ recap, cheer: this.store.cheer(recap) });
  }

  /** Shows `shown` without marking it seen: the snapshot harness's way in. */
  present(shown: RecapShown): void {
    const slot = takeoverSlot(this.context.shared);
    const takeover = this.makeTakeover(shown, () => this.dismiss());
    this.own = takeover;
    this.setState({ shown });
    slot.set(takeover);
  }

  /** Done: back to the tabs. */
  dismiss(): void {
    const slot = takeoverSlot(this.context.shared);
    if (this.own !== undefined && slot.get() === this.own) slot.set(undefined);
    this.own = undefined;
    this.setState({ shown: undefined });
  }

  /** The user closed the island: a card on show is done with, so the next open shows the tabs. */
  islandClosed(): void {
    this.dismiss();
  }

  private setEnabled(enabled: boolean): void {
    if (enabled === this.isEnabled) return;
    this.isEnabled = enabled;
    this.store.setEnabled(enabled);
    if (!enabled) this.dismiss();
    if (!this.isStarted) return;
    if (!enabled) return this.store.stop();
    /* The user is in Settings right now: the next open shows the card, with no toast about it. */
    this.isFollowingSwitch = true;
    this.store.start();
    this.isFollowingSwitch = false;
  }

  start(): void {
    this.isStarted = true;
    if (this.isEnabled) this.store.start();
  }

  stop(): void {
    this.isStarted = false;
    this.store.stop();
  }

  dispose(): void {
    this.stop();
    for (const stop of this.stops) stop();
    this.stops.length = 0;
  }
}
