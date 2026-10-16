/*
 * The Mac's `CelebrationCenter`: the one place real events ask for a
 * celebration, so every module shares the pacer's limits and a burst plays
 * where it can be seen. It plays nothing while no stage is on screen (an
 * unseen event uses up no allowance); otherwise it asks the pacer for a
 * tier and publishes the celebration for the open panel's stage. When the
 * pacer says no while a panel is open, the event nods instead: the source
 * module's tab bounces once. Haptics and the macOS system sounds have no
 * Windows equivalent here; a host may play a cue through `onPlay`.
 */

import { CelebrationPacer, type CelebrationStyle, type CelebrationTier } from "../../core/motion/celebration";
import type { AppTheme } from "../../core/themes/appTheme";
import { makeCelebration, type Celebration } from "./Celebration";

export interface CelebrationNod {
  readonly id: number;
  readonly source: string;
}

export interface CelebrationCenterOptions {
  /** False for snapshot runs, which play nothing. */
  readonly isEnabled?: boolean;
  /** Seconds since the epoch, for the pacer; `Date.now() / 1000` by default. */
  readonly now?: () => number;
  readonly timeZone?: string;
  /** Called when a celebration is admitted, so a host can play a soft cue if Settings allow one. */
  readonly onPlay?: (tier: CelebrationTier, hasOwnSound: boolean) => void;
}

type Listener = () => void;

export class CelebrationCenter {
  current: Celebration | undefined;
  nod: CelebrationNod | undefined;
  private stages = 0;
  private readonly pacer = new CelebrationPacer();
  private readonly listeners = new Set<Listener>();
  private readonly isEnabled: boolean;
  private readonly now: () => number;
  private readonly timeZone: string;
  private readonly onPlay: ((tier: CelebrationTier, hasOwnSound: boolean) => void) | undefined;

  constructor({ isEnabled = true, now = () => Date.now() / 1000, timeZone = "UTC", onPlay }: CelebrationCenterOptions = {}) {
    this.isEnabled = isEnabled;
    this.now = now;
    this.timeZone = timeZone;
    this.onPlay = onPlay;
  }

  /** True while an open panel can show a celebration. */
  get isShowing(): boolean {
    return this.stages > 0;
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify(): void {
    for (const listener of this.listeners) listener();
  }

  /**
   * Plays a celebration for a real event if one fits: the tier that plays,
   * or undefined when no stage is showing or the pacer says it is too soon
   * (then, with a `source`, that module's tab nods instead).
   */
  celebrate(
    tier: CelebrationTier,
    style: CelebrationStyle,
    accent: string,
    theme: AppTheme,
    source?: string,
    hasOwnSound = false,
  ): CelebrationTier | undefined {
    if (!this.isEnabled || !this.isShowing) return undefined;
    const admitted = this.pacer.admit(tier, this.now(), this.timeZone);
    if (!admitted) {
      if (source !== undefined) {
        this.nod = { id: (this.nod?.id ?? 0) + 1, source };
        this.notify();
      }
      return undefined;
    }
    this.current = makeCelebration({ tier: admitted, style, accent, theme });
    this.onPlay?.(admitted, hasOwnSound);
    this.notify();
    return admitted;
  }

  stageAppeared(): void {
    this.stages += 1;
  }

  stageDisappeared(): void {
    this.stages = Math.max(0, this.stages - 1);
  }
}

/** The tab that bounces for a nod: the source module's, or the open one when the source has no tab. */
export function nodTab(nod: CelebrationNod, enabled: readonly string[], selected: string): string {
  return enabled.includes(nod.source) ? nod.source : selected;
}
