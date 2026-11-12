import type { PetCanvas } from "../petCanvas";
import type { PetItem } from "../petItem";
import type { PetAnimation } from "../petKinds";
import { radiantArt, radiantEffect, type RadiantPlacement } from "./radiantArt";
import {
  RadiantGeometry,
  RadiantItemScene,
  newRadiantReport,
  renderRadiant,
  type RadiantRenderReport,
} from "./radiantRenderer";
import type { RadiantLayout } from "./radiantResolver";

/*
 * Port of RadiantComposer.swift (PetComposer.radiantFrames): one step of a
 * clip with its Radiant effects.
 */

function gcd(a: number, b: number): number {
  return b === 0 ? a : gcd(b, a % b);
}

/**
 * One step of a clip with its Radiant effects: the step's normal frames (one
 * per tick of the items' own loop) drawn over the Radiant loop.
 * `without(item, phase)` is the same step without that item (undefined:
 * without any item), finished like the normal frames, so each effect knows
 * its item's pixels and where the bare pet is.
 */
export function radiantFrames(
  layout: RadiantLayout,
  normal: readonly PetCanvas[],
  animation: PetAnimation,
  ceiling: number | undefined,
  report: RadiantRenderReport,
  without: (item: PetItem | undefined, phase: number) => PetCanvas,
): PetCanvas[] {
  const art = radiantArt();
  const normalLoop = Math.max(1, normal.length);
  const total = (normalLoop / gcd(normalLoop, layout.loop)) * layout.loop;
  const bare = without(undefined, 0);
  const withoutItem = new Map<PetItem, PetCanvas[]>();
  for (const entry of layout.entries) {
    if (withoutItem.has(entry.item)) continue;
    const frames: PetCanvas[] = [];
    for (let phase = 0; phase < normalLoop; phase++) frames.push(without(entry.item, phase));
    withoutItem.set(entry.item, frames);
  }
  /* Each item's pixels per phase of the items' own loop, measured once. */
  const scenes = layout.entries.map((entry) => {
    const frames = withoutItem.get(entry.item) ?? [];
    const out: RadiantItemScene[] = [];
    for (let phase = 0; phase < normalLoop; phase++) {
      out.push(new RadiantItemScene(normal[phase] as PetCanvas, frames[phase] as PetCanvas));
    }
    return out;
  });
  const geometry = new RadiantGeometry(bare);
  const placements = layout.entries.map((entry): RadiantPlacement => {
    const itemArt = art.item(entry.item);
    const placement = itemArt && radiantEffect(itemArt, entry.intensity)?.placements[entry.placement];
    if (!placement) throw new Error(`No Radiant placement ${entry.placement} for ${entry.item} ${entry.intensity}`);
    return placement;
  });
  const hanging = animation === "peekIn" || animation === "peekOut";
  const frames: PetCanvas[] = [];
  for (let t = 0; t < total; t++) {
    const phase = t % normalLoop;
    const dressed = normal[phase] as PetCanvas;
    const ticks = layout.ticks(t, art.loop);
    const jobs = layout.entries.map((_, n) => ({
      placement: placements[n] as RadiantPlacement,
      tick: ticks[n] ?? 0,
      item: (scenes[n] as RadiantItemScene[])[phase] as RadiantItemScene,
    }));
    /* Each frame starts with no pixel claimed; the report adds up collisions. */
    const frameReport = newRadiantReport();
    frames.push(renderRadiant(jobs, dressed, bare, { geometry, hanging, ceiling, art, report: frameReport }));
    report.collisions += frameReport.collisions;
  }
  return frames;
}
