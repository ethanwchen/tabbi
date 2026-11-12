import { composeClip, composeClipWithLayout, type PetClip } from "../../src/core/pets/petClip";
import type { PetCanvas } from "../../src/core/pets/petCanvas";
import { accessorySlot, type PetAccessory, type PetOutfit } from "../../src/core/pets/petCostume";
import { itemParts, type PetItem } from "../../src/core/pets/petItem";
import { PET_ANIMATIONS, type PetAnimation, type PetBreed } from "../../src/core/pets/petKinds";
import type { PetRadiantIntensity } from "../../src/core/pets/radiant/radiantArt";
import { RadiantGeometry, newRadiantReport } from "../../src/core/pets/radiant/radiantRenderer";
import { RadiantLayout, radiantEligibleItems } from "../../src/core/pets/radiant/radiantResolver";

/*
 * Port of the Mac's RadiantAudit test helper: renders looks with a given
 * layout and reports, per frame and tick, what the effects changed, which is
 * how `radiant-costs.json` is measured (RadiantBudgetTests).
 */

/** The outfit and accessories wearing `items`. */
export function wearing(items: readonly PetItem[]): { outfit: PetOutfit; accessories: PetAccessory[] } {
  let outfit: PetOutfit = "none";
  const accessories: PetAccessory[] = [];
  for (const item of items) {
    const parts = itemParts(item);
    if (parts.kind === "outfit") outfit = parts.outfit;
    else accessories.push(parts.accessory);
  }
  return { outfit, accessories };
}

export function slotOf(item: PetItem): string {
  const parts = itemParts(item);
  return parts.kind === "outfit" ? "outfit" : accessorySlot(parts.accessory);
}

/** Every pair and triple of Radiant items that can be worn together, in the Mac's order. */
export function radiantCombinations(): PetItem[][] {
  const items = radiantEligibleItems();
  const sets: PetItem[][] = [];
  items.forEach((a, i) => {
    for (const b of items.slice(i + 1)) if (slotOf(a) !== slotOf(b)) sets.push([a, b]);
  });
  items.forEach((a, i) => {
    items.forEach((b, j) => {
      if (j <= i || slotOf(a) === slotOf(b)) return;
      for (const c of items.slice(j + 1)) if (slotOf(c) !== slotOf(a) && slotOf(c) !== slotOf(b)) sets.push([a, b, c]);
    });
  });
  return sets;
}

export interface AuditResult {
  maxChange: number[];
  collisions: number;
  eyeHits: number;
  faceHits: number;
  marginHits: number;
  ceilingHits: number;
}

function ticksOf(clip: PetClip, index: number): readonly PetCanvas[] {
  const frame = clip.frames[index];
  if (!frame) throw new Error("No frame");
  return frame.itemFrames.length === 0 ? [frame.canvas] : frame.itemFrames;
}

/** How far a frame moved down under the notch ceiling. */
export function shift(full: PetCanvas, shown: PetCanvas): number {
  const pet: number[] = [];
  full.pixels.forEach((pixel, i) => {
    if (pixel !== 0 && !RadiantGeometry.effectPixels.has(pixel)) pet.push(i);
  });
  const score = (d: number) => {
    let count = 0;
    for (const i of pet) {
      const j = i + d * full.width;
      if (j < shown.pixels.length && shown.pixels[j] === full.pixels[i]) count++;
    }
    return count;
  };
  let best = 0;
  let bestScore = score(0);
  for (let d = 1; d <= 12; d++) {
    const value = score(d);
    if (value > bestScore) {
      best = d;
      bestScore = value;
    }
  }
  return best;
}

/**
 * Renders every animation of `items` on `breed` with `layout`, full size and
 * under the notch ceiling, and checks every frame and tick. `maxChange[t]` is
 * the most effect pixels that change from tick t-1 to t over every frame.
 */
export function audit(
  items: readonly PetItem[],
  layout: RadiantLayout,
  breed: PetBreed,
  animations: readonly PetAnimation[] = PET_ANIMATIONS,
  ceilings: readonly (number | undefined)[] = [undefined, 2],
): AuditResult {
  const { outfit, accessories } = wearing(items);
  const result: AuditResult = {
    maxChange: Array<number>(layout.loop).fill(0),
    collisions: 0,
    eyeHits: 0,
    faceHits: 0,
    marginHits: 0,
    ceilingHits: 0,
  };
  for (const animation of animations) {
    const bare = composeClip(animation, breed);
    let fullNormal: PetClip | undefined;
    for (const ceiling of ceilings) {
      const report = newRadiantReport();
      const options = { outfit, accessories, ...(ceiling === undefined ? {} : { ceiling }) };
      const radiant = composeClipWithLayout(animation, breed, { ...options, layout, report });
      const normal = composeClipWithLayout(animation, breed, { ...options, layout: undefined, report: newRadiantReport() });
      if (ceiling === undefined) fullNormal = normal;
      const full =
        ceiling === undefined
          ? normal
          : (fullNormal ?? composeClipWithLayout(animation, breed, { outfit, accessories, layout: undefined, report: newRadiantReport() }));
      result.collisions += report.collisions;
      radiant.frames.forEach((_, frameIndex) => {
        const ticks = ticksOf(radiant, frameIndex);
        const plain = ticksOf(normal, frameIndex);
        const plainCanvas = normal.frames[frameIndex]?.canvas as PetCanvas;
        const drop = ceiling === undefined ? 0 : shift(full.frames[frameIndex]?.canvas as PetCanvas, plainCanvas);
        const bareCanvas = (bare.frames[frameIndex]?.canvas as PetCanvas).shifted(0, drop);
        const geometry = new RadiantGeometry(bareCanvas);
        const face = geometry.faceGuard;
        const barePixels = bareCanvas.pixels;
        ticks.forEach((canvas, t) => {
          const r = canvas.pixels;
          const count = ticks.length;
          const n = (plain[t % plain.length] as PetCanvas).pixels;
          const p = (ticks[(t + count - 1) % count] as PetCanvas).pixels;
          const pn = (plain[((t + count - 1) % count) % plain.length] as PetCanvas).pixels;
          const width = canvas.width;
          const height = canvas.height;
          let change = 0;
          for (let i = 0; i < r.length; i++) {
            if (r[i] !== p[i] && (r[i] !== n[i] || p[i] !== pn[i])) change++;
            if (r[i] === n[i]) continue;
            const x = i % width;
            const y = Math.trunc(i / width);
            const under = n[i] ?? 0;
            if (under !== 0) {
              if (RadiantGeometry.eyePixels.has(under)) result.eyeHits++;
              if (RadiantGeometry.facePixels.has(under)) result.faceHits++;
              if (under === barePixels[i] && face?.contains(x, y)) result.faceHits++;
            } else {
              if (x < 1 || x > width - 2 || y < 1 || y > height - 2) result.marginHits++;
              if (ceiling !== undefined && y < ceiling && r[i] !== 0) result.ceilingHits++;
            }
          }
          const slot = t % layout.loop;
          if (count > 1 && change > (result.maxChange[slot] ?? 0)) result.maxChange[slot] = change;
        });
      });
    }
  }
  return result;
}

export function singleLayout(item: PetItem, intensity: PetRadiantIntensity, placement: number): RadiantLayout {
  return new RadiantLayout([{ item, intensity, placement, turn: undefined }], 1);
}
