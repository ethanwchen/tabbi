import { accessorySlot, wearable, type PetAccessory, type PetOutfit } from "../petCostume";
import { itemParts, type PetItem } from "../petItem";
import { itemCost } from "../petUnlocks";
import {
  radiantArt,
  radiantCosts,
  radiantEffect,
  type PetRadiantIntensity,
  type RadiantArt,
  type RadiantCosts,
  type RadiantEffectArt,
  type RadiantZone,
} from "./radiantArt";

/*
 * Port of RadiantResolver.swift: the Radiant look a pet shows
 * (PetRadiantLook), how the effects of several Radiant items worn together
 * share the frame (RadiantLayout) and the upgrade rules (PetRadiant).
 */

/**
 * The Radiant items a pet shows and how strongly: worn, upgraded items whose
 * effect is on. What a profile turns into for drawing (`radiantLook`), and
 * what Party sends for a friend's pet. Port of PetRadiantLook.
 */
export class PetRadiantLook {
  readonly intensities: ReadonlyMap<PetItem, PetRadiantIntensity>;

  /** Items without an effect and effects turned off are dropped. */
  constructor(intensities: Iterable<readonly [PetItem, PetRadiantIntensity]> = []) {
    const kept = new Map<PetItem, PetRadiantIntensity>();
    for (const [item, intensity] of intensities) {
      if (intensity !== "off" && isRadiantEligible(item)) kept.set(item, intensity);
    }
    this.intensities = kept;
  }

  static readonly none = new PetRadiantLook();

  get isEmpty(): boolean {
    return this.intensities.size === 0;
  }

  /** The look limited to what is worn. */
  worn(outfit: PetOutfit, accessories: readonly PetAccessory[]): PetRadiantLook {
    const wornAccessories = wearable(accessories);
    return new PetRadiantLook(
      [...this.intensities].filter(([item]) => {
        const parts = itemParts(item);
        return parts.kind === "outfit" ? parts.outfit === outfit : wornAccessories.includes(parts.accessory);
      }),
    );
  }

  /** A stable key for caches and equality: the entries sorted by item id. */
  get key(): string {
    return [...this.intensities]
      .map(([item, intensity]) => `${item}:${intensity}`)
      .sort()
      .join(",");
  }

  equals(other: PetRadiantLook): boolean {
    return this.key === other.key;
  }
}

/** One worn effect in a layout. Port of RadiantLayout.Entry. */
export interface RadiantLayoutEntry {
  readonly item: PetItem;
  readonly intensity: PetRadiantIntensity;
  /** Index into the effect's placements. */
  readonly placement: number;
  /** The cycle of the Radiant loop this effect plays in when the effects take turns; undefined when it plays every cycle. */
  readonly turn: number | undefined;
}

/**
 * How the Radiant effects of the items worn together share the frame. Each
 * effect lists placements, its preferred one first; in `slotPriority` order
 * (the hat before the outfit before the aura) each effect takes its first
 * placement whose zones no earlier effect uses. The chest is held by
 * an outfit or neck item someone else wears. Then, if the effects' measured
 * per-tick costs together pass the combined budget on any tick, they take
 * turns. The result depends only on the items worn and their intensities,
 * so the Mac and Windows resolve every look the same way. Port of
 * RadiantLayout.
 */
export class RadiantLayout {
  constructor(
    /** In drawing order (slot priority). */
    readonly entries: readonly RadiantLayoutEntry[],
    /** Cycles of the Radiant loop before the layout repeats: 1, or one per effect when they take turns. */
    readonly cycles: number,
    private readonly art: RadiantArt = radiantArt(),
  ) {}

  /** Ticks of the item clock before the layout repeats. */
  get loop(): number {
    return this.art.loop * this.cycles;
  }

  static resolve(
    look: PetRadiantLook,
    outfit: PetOutfit,
    accessories: readonly PetAccessory[],
    art: RadiantArt = radiantArt(),
    costs: RadiantCosts = radiantCosts(),
  ): RadiantLayout | undefined {
    const worn = look.worn(outfit, accessories);
    const effects: { item: PetItem; intensity: PetRadiantIntensity; effect: RadiantEffectArt }[] = [];
    for (const [item, intensity] of worn.intensities) {
      const itemArt = art.item(item);
      const effect = itemArt && radiantEffect(itemArt, intensity);
      if (effect) effects.push({ item, intensity, effect });
    }
    effects.sort((a, b) => radiantPriority(a.item, art) - radiantPriority(b.item, art));
    if (effects.length === 0) return undefined;
    /* Zones another worn item's art covers: an outfit or neck item fills the chest. */
    const wornAccessories = wearable(accessories);
    const blocked = (item: PetItem): ReadonlySet<RadiantZone> => {
      const chestCovered =
        (outfit !== "none" && item !== `outfit.${outfit}`) ||
        wornAccessories.some((accessory) => accessorySlot(accessory) === "neck" && item !== `accessory.${accessory}`);
      return chestCovered ? new Set<RadiantZone>(["chest"]) : new Set<RadiantZone>();
    };
    /* In slot priority, each effect takes its first placement whose zones are free. The last placement uses no zones, so one always fits. */
    const used = new Set<RadiantZone>();
    const placements = effects.map((entry) => {
      const block = blocked(entry.item);
      let n = entry.effect.placements.findIndex((placement) => [...placement.zones].every((zone) => !used.has(zone) && !block.has(zone)));
      if (n < 0) n = entry.effect.placements.length - 1;
      for (const zone of entry.effect.placements[n]?.zones ?? []) used.add(zone);
      return n;
    });
    /* Take turns when the costs together pass the combined budget. */
    const rows = effects.map(
      (entry, n) => costs.cost(entry.item, entry.intensity, placements[n] ?? 0) ?? Array<number>(art.loop).fill(costs.perTickBudget),
    );
    let peak = 0;
    for (let t = 0; t < art.loop; t++) peak = Math.max(peak, rows.reduce((sum, row) => sum + (row[t] ?? 0), 0));
    const turns = effects.length > 1 && peak > costs.combinedBudget;
    const entries = effects.map(
      (entry, n): RadiantLayoutEntry => ({
        item: entry.item,
        intensity: entry.intensity,
        placement: placements[n] ?? 0,
        turn: turns ? n : undefined,
      }),
    );
    return new RadiantLayout(entries, turns ? effects.length : 1, art);
  }

  /** The tick of each entry's own loop at layout tick `tick`: its loop tick in its turn, and its still (tick 0) in the others' turns. */
  ticks(tick: number, loop: number): number[] {
    const cycle = Math.trunc(tick / loop) % this.cycles;
    return this.entries.map((entry) => (entry.turn === undefined || entry.turn === cycle ? tick % loop : 0));
  }
}

/** Where an item's slot comes in `slotPriority` (an outfit counts as "outfit"). */
export function radiantPriority(item: PetItem, art: RadiantArt = radiantArt()): number {
  const parts = itemParts(item);
  const slot = parts.kind === "outfit" ? "outfit" : accessorySlot(parts.accessory);
  const index = art.slotPriority.indexOf(slot);
  return index < 0 ? art.slotPriority.length : index;
}

/* MARK: PetRadiant, the upgrade rules */

/** The items that have a Radiant effect, in catalog order. */
export function radiantEligibleItems(): PetItem[] {
  return radiantArt().items.map((art) => art.item);
}

export function isRadiantEligible(item: PetItem): boolean {
  return radiantArt().item(item) !== undefined;
}

/**
 * What upgrading `item` costs: `upgradeMultiplier` times its price (5x).
 * The upgrade sits outside the price tiers on purpose: it is a long goal
 * for an item already owned, not a new item.
 */
export function radiantPrice(item: PetItem): number {
  return itemCost(item) * radiantArt().upgradeMultiplier;
}

/** The effect's name ("Orbiting Orb") for an intensity, as written in `radiant.json`, or undefined. */
export function radiantEffectName(item: PetItem, intensity: PetRadiantIntensity): string | undefined {
  const art = radiantArt().item(item);
  return art && radiantEffect(art, intensity)?.name;
}
