import type { Instant, Seconds } from "../time";
import { tickerPet, type TickerItem } from "../ticker/tickerItem";
import { TICKER_KINDS, type TickerKind } from "../ticker/tickerKind";
import type { TickerSources } from "../ticker/tickerSources";

/** Port of PetCheer.Kind. */
export type PetCheerKind =
  /** A focus session finished: two happy hops with sparkles. */
  | "dance"
  /** A goal for today was reached: one hop, wearing a tiny crown while the cheer lasts. */
  | "crown"
  /** The PC started charging: one hop, then a sip from the tiny mug while a charging bolt shows. */
  | "sip";

/**
 * Port of PetCheer: a short moment where the pet beside the closed island
 * celebrates a real event, a little dance with a sparkle burst when a focus
 * session finishes, a tiny crown when a goal for today is reached, or a sip
 * from its mug when the PC starts charging.
 *
 * It takes the closed island over for `length` (a few seconds), even when
 * the ticker was showing something else, and then the ticker carries on
 * where it was. A value, so the ticker can tell when it is over without a
 * timer of its own.
 */
export class PetCheer {
  /** How long a cheer holds the closed island: two hops and the burst, never in the way. */
  static readonly duration: Seconds = 2.2;
  /** How long a sip holds it: the hop, the mug's steam and the sip, ending on the pet's happy eyes. */
  static readonly sipDuration: Seconds = 4.6;

  constructor(
    readonly kind: PetCheerKind,
    /** Grows with each cheer, so two cheers in a row are still two changes. */
    readonly id: number,
    readonly startedAt: Instant,
  ) {}

  /** How long this cheer holds the closed island. */
  get length(): Seconds {
    return this.kind === "sip" ? PetCheer.sipDuration : PetCheer.duration;
  }

  /** When the pet goes back to what it was doing. */
  get endsAt(): Instant {
    return this.startedAt + this.length;
  }

  /** Whether the cheer is on screen at `date`; a clock set back before the start shows nothing. */
  isShowing(date: Instant): boolean {
    return date >= this.startedAt && date < this.endsAt;
  }
}

/**
 * Port of TickerSources.cheering: the closed-island item while `cheer` plays
 * at `now`, the pet in its current mood, cheering (for a crown wearing the
 * Closet's Tiny Crown in place of its hat, for a sip holding its mug).
 * Undefined when the cheer is over or there is no pet to show (the Closet is
 * off or the user hid the pet preview), so the normal rotation keeps the
 * island.
 */
export function tickerCheering(
  sources: TickerSources,
  cheer: PetCheer | undefined,
  now: Instant,
  enabled: (kind: TickerKind) => boolean,
): TickerItem | undefined {
  if (cheer === undefined || !cheer.isShowing(now) || !enabled(TICKER_KINDS.pet)) return undefined;
  const item = sources.items(now, new Set([TICKER_KINDS.pet]))[0];
  if (item?.type !== "pet") return undefined;
  const pet = item.pet;
  /* A copy, so the crown never lands on the pet the Closet owns. */
  const profile = pet.profile.copy();
  if (cheer.kind === "crown") profile.wear("tinyCrown");
  return {
    type: "pet",
    pet: tickerPet({ ...pet, profile, cheer, mood: cheer.kind === "sip" ? "onBreak" : pet.mood }),
  };
}
