import { PetCloset } from "../closet/petCloset";
import type { PetItem } from "../pets/petItem";
import type { Instant } from "../time";
import { nextOccurrence, occurrenceContaining, sameOccurrence, type SeasonalEventOccurrence } from "./seasonalEvent";
import type { SeasonalEventCatalog } from "./seasonalEventCatalog";

/*
 * Port of PetLimitedShelf: one shelf of the Closet's Limited section. The
 * limited items do not fit one row, so the section groups them: the event
 * going on now (or the next one) first, then the study milestones, then
 * every other event's items in the order their next runs start, so the
 * list reads as the year ahead.
 */

export type PetLimitedShelfKind =
  /** The featured event: the run going on now, or the next to start. */
  | { readonly kind: "event"; readonly occurrence: SeasonalEventOccurrence; readonly isActive: boolean }
  /** Limited items that are not seasonal: milestones, the launch week cap and the Founder's Pin. */
  | { readonly kind: "milestones" }
  /** The other events' items, which come back with their next run. */
  | { readonly kind: "laterEvents" };

export interface PetLimitedShelf {
  readonly kind: PetLimitedShelfKind;
  readonly items: readonly PetItem[];
}

export function sameShelfKind(a: PetLimitedShelfKind, b: PetLimitedShelfKind): boolean {
  if (a.kind === "event" && b.kind === "event") return a.isActive === b.isActive && sameOccurrence(a.occurrence, b.occurrence);
  return a.kind === b.kind;
}

/**
 * The run the Limited section features at `instant`: the one going on (the
 * soonest to end when two overlap), or else the next to start.
 */
export function featuredRun(
  catalog: SeasonalEventCatalog,
  instant: Instant,
  timeZone: string,
): { readonly occurrence: SeasonalEventOccurrence; readonly isActive: boolean } | undefined {
  const active = catalog.active(instant, timeZone)[0];
  if (active) return { occurrence: active, isActive: true };
  const next = catalog.next(instant, timeZone);
  return next ? { occurrence: next, isActive: false } : undefined;
}

/** The Limited section's shelves at `instant`, each holding at least one item, and together every limited item once. */
export function limitedShelves(catalog: SeasonalEventCatalog, instant: Instant, timeZone: string): PetLimitedShelf[] {
  const featured = featuredRun(catalog, instant, timeZone);
  const featuredItems = featured?.occurrence.event.rewards.map((reward) => reward.item) ?? [];
  const later = catalog.events
    .filter((event) => event.id !== featured?.occurrence.event.id)
    .flatMap((event) => {
      const run = occurrenceContaining(event, instant, timeZone) ?? nextOccurrence(event, instant, timeZone);
      return run ? [{ event, start: run.start }] : [];
    })
    .sort((a, b) => (a.start !== b.start ? a.start - b.start : a.event.id < b.event.id ? -1 : a.event.id > b.event.id ? 1 : 0))
    .flatMap(({ event }) => event.rewards.map((reward) => reward.item));
  const seasonal = new Set(catalog.events.flatMap((event) => event.rewards.map((reward) => reward.item)));
  const milestones = PetCloset.limitedShelf.filter((item) => !seasonal.has(item));
  const shelves: PetLimitedShelf[] = [];
  if (featured) shelves.push({ kind: { kind: "event", ...featured }, items: featuredItems });
  shelves.push({ kind: { kind: "milestones" }, items: milestones });
  shelves.push({ kind: { kind: "laterEvents" }, items: later });
  return shelves.filter((shelf) => shelf.items.length > 0);
}
