import type { Instant, Seconds } from "../time";
import { tickerItemIsPinned, tickerItemKind, type TickerItem } from "./tickerItem";
import type { TickerKind } from "./tickerKind";

/**
 * Port of TickerRotation: decides which ticker item the closed island shows.
 *
 * A pinned item (an imminent or current meeting) always wins. Otherwise the
 * available items take turns, each held for `interval` seconds. The user can
 * also move on by hand (`advance`), which holds the chosen item for a full
 * turn, even over a pin, so a peek at the song during a meeting countdown
 * isn't snatched away at once. The state is just "which kind, since when",
 * and callers pass `now`, so the rotation is deterministic and survives
 * items appearing and vanishing between ticks.
 */
export class TickerRotation {
  /** Seconds each item holds. Set after creation it is taken as is, with no one-second floor. */
  interval: Seconds;
  private currentKindValue: TickerKind | undefined;
  private shownSinceValue: Instant | undefined;
  /** The kinds of the last `update`'s items, in order, so that when the kind on screen vanishes its successor still takes over. */
  private order: TickerKind[] = [];
  /** Until when an item the user cycled to holds the island over a pin. */
  private heldUntil: Instant | undefined;

  constructor(interval: Seconds) {
    this.interval = Math.max(interval, 1);
  }

  /** Kind on screen after the last `update`, undefined when the island is plain. */
  get currentKind(): TickerKind | undefined {
    return this.currentKindValue;
  }

  /** When `currentKind` came on screen. */
  get shownSince(): Instant | undefined {
    return this.shownSinceValue;
  }

  /**
   * Advances the rotation to `now` and returns the item to show. The
   * returned item carries fresh data (e.g. a countdown) even when the kind on
   * screen hasn't changed.
   */
  update(items: readonly TickerItem[], now: Instant): TickerItem | undefined {
    const previousOrder = this.order;
    this.order = items.map(tickerItemKind);
    const first = items[0];
    if (first === undefined) {
      this.currentKindValue = undefined;
      this.shownSinceValue = undefined;
      this.heldUntil = undefined;
      return undefined;
    }
    const currentKind = this.currentKindValue;
    if (this.heldUntil !== undefined && now < this.heldUntil && currentKind !== undefined) {
      const held = items.find((item) => tickerItemKind(item) === currentKind);
      if (held !== undefined) return held;
    }
    this.heldUntil = undefined;
    const pinned = items.find(tickerItemIsPinned);
    if (pinned !== undefined) {
      /* Keep the original start so that once the pin lifts the rotation moves on at once rather than holding a stale item. */
      if (currentKind !== tickerItemKind(pinned)) this.show(tickerItemKind(pinned), now);
      return pinned;
    }
    const shownSince = this.shownSinceValue;
    if (currentKind !== undefined && shownSince !== undefined && now - shownSince < this.interval) {
      const current = items.find((item) => tickerItemKind(item) === currentKind);
      if (current !== undefined) return current;
    }
    const next = TickerRotation.nextItem(currentKind, items, first, previousOrder);
    this.show(tickerItemKind(next), now);
    return next;
  }

  /**
   * Moves on to the item after the one on screen right away, as when the
   * user swipes down or middle-clicks the closed island, and returns it. The
   * chosen item holds for a full `interval`, pinned or not, then the rotation
   * (or a pin) carries on. With one item or none there is nothing to cycle
   * to, and the item on screen stays.
   */
  advance(items: readonly TickerItem[], now: Instant): TickerItem | undefined {
    const first = items[0];
    if (items.length <= 1 || first === undefined) return this.update(items, now);
    const previousOrder = this.order;
    this.order = items.map(tickerItemKind);
    const next = TickerRotation.nextItem(this.currentKindValue, items, first, previousOrder);
    this.show(tickerItemKind(next), now);
    this.heldUntil = now + this.interval;
    return next;
  }

  private show(kind: TickerKind, now: Instant): void {
    this.currentKindValue = kind;
    this.shownSinceValue = now;
  }

  /**
   * The first item whose kind comes after `kind` in rotation order, wrapping
   * around. If `kind` itself vanished, the first kind that followed it last
   * time and is still there takes over, so the order the user sees stays
   * stable. `first` is `items[0]`, so there is always an item to show.
   */
  private static nextItem(
    kind: TickerKind | undefined,
    items: readonly TickerItem[],
    first: TickerItem,
    previousOrder: readonly TickerKind[],
  ): TickerItem {
    if (kind === undefined) return first;
    const position = items.findIndex((item) => tickerItemKind(item) === kind);
    if (position >= 0) return items[(position + 1) % items.length] ?? first;
    const previous = previousOrder.indexOf(kind);
    if (previous < 0) return first;
    for (const candidate of previousOrder.slice(previous + 1)) {
      const item = items.find((entry) => tickerItemKind(entry) === candidate);
      if (item !== undefined) return item;
    }
    return first;
  }
}
