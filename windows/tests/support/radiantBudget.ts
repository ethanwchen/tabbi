import { describe, expect, it } from "vitest";
import { PET_BREEDS } from "../../src/core/pets/petKinds";
import type { PetItem } from "../../src/core/pets/petItem";
import { radiantArt, radiantCosts, radiantEffect } from "../../src/core/pets/radiant/radiantArt";
import { audit, singleLayout } from "./radiantAudit";

/*
 * Port of the Mac's RadiantBudgetTests: every placement of the given
 * effects, on all breeds, in every animation, frame and tick, full size and
 * under the closed notch's ceiling, keeps off the eyes and face, inside the
 * margin and below the ceiling, and changes exactly as many pixels from one
 * tick to the next as `radiant-costs.json` records (the costs are the most
 * over every breed, so the whole table is recomputed here).
 */
export function describeRadiantBudget(items: readonly PetItem[]): void {
  describe("Radiant costs", () => {
    for (const item of items) {
      for (const intensity of ["bold", "subtle"] as const) {
        it(`${item} ${intensity} matches radiant-costs.json`, () => {
          const itemArt = radiantArt().item(item);
          const effect = itemArt && radiantEffect(itemArt, intensity);
          expect(effect).toBeDefined();
          const costs = radiantCosts();
          effect?.placements.forEach((_, placement) => {
            const layout = singleLayout(item, intensity, placement);
            let worst = Array<number>(layout.loop).fill(0);
            for (const breed of PET_BREEDS) {
              const result = audit([item], layout, breed);
              const label = `${item} ${intensity} placement ${placement} on ${breed}`;
              expect({ label, eye: result.eyeHits, face: result.faceHits, margin: result.marginHits, ceiling: result.ceilingHits, collisions: result.collisions }).toEqual({
                label,
                eye: 0,
                face: 0,
                margin: 0,
                ceiling: 0,
                collisions: 0,
              });
              worst = worst.map((value, t) => Math.max(value, result.maxChange[t] ?? 0));
            }
            expect({ placement, costs: worst }).toEqual({ placement, costs: costs.cost(item, intensity, placement) });
            expect(Math.max(...worst)).toBeLessThanOrEqual(costs.perTickBudget);
          });
        }, 600_000);
      }
    }
  });
}
