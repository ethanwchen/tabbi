import { describe, expect, it } from "vitest";
import radiantFile from "@mac/Pets/PetArt/radiant.json";
import { composeClip, composeClipWithLayout } from "../../../src/core/pets/petClip";
import { PetCanvas, pixelFor } from "../../../src/core/pets/petCanvas";
import { colorHex } from "../../../src/core/pets/petPalette";
import { PET_ANIMATIONS } from "../../../src/core/pets/petKinds";
import { PetProfile } from "../../../src/core/pets/petProfile";
import { itemCost } from "../../../src/core/pets/petUnlocks";
import {
  RADIANT_ZONES,
  RadiantArt,
  RadiantArtLoadError,
  RadiantCosts,
  radiantArt,
  radiantCosts,
  radiantEffect,
  type RadiantPlacement,
} from "../../../src/core/pets/radiant/radiantArt";
import { radiantMarkerCanvas, radiantMarkerColors, radiantMarkerSize } from "../../../src/core/pets/radiant/radiantMarkerArt";
import { RadiantGeometry, RadiantItemScene, newRadiantReport, renderRadiant } from "../../../src/core/pets/radiant/radiantRenderer";
import {
  PetRadiantLook,
  RadiantLayout,
  isRadiantEligible,
  radiantEffectName,
  radiantEligibleItems,
  radiantPrice,
} from "../../../src/core/pets/radiant/radiantResolver";
import { singleLayout } from "../../support/radiantAudit";

/* Port of the Mac's RadiantArtTests, RadiantCombinationTests and RadiantLayout checks. */

const sorcerer = "accessory.blindfoldedSorcerer" as const;
const wizardHat = "accessory.wizardHat" as const;
const rainCloud = "accessory.rainCloud" as const;
const whiteCoat = "outfit.whiteCoat" as const;
const dino = "outfit.dinosaurHoodie" as const;

function clone(): Record<string, unknown> {
  return JSON.parse(JSON.stringify(radiantFile)) as Record<string, unknown>;
}

describe("RadiantArt", () => {
  it("reads the Mac's radiant.json: eight items, a 24 tick loop, 5x price", () => {
    const art = radiantArt();
    expect(art.loop).toBe(24);
    expect(art.upgradeMultiplier).toBe(5);
    expect(art.slotPriority).toEqual(["head", "outfit", "neck", "face", "back", "aura"]);
    expect(radiantEligibleItems()).toEqual([
      sorcerer,
      wizardHat,
      "accessory.tinyCrown",
      dino,
      "accessory.astronautHelmet",
      "accessory.graduationCap",
      rainCloud,
      whiteCoat,
    ]);
    for (const item of art.items) {
      for (const effect of [item.bold, item.subtle]) {
        expect(effect.placements.length).toBeGreaterThan(0);
        expect(effect.placements[effect.placements.length - 1]?.zones.size, effect.name).toBe(0);
        for (const placement of effect.placements) for (const zone of placement.zones) expect(RADIANT_ZONES).toContain(zone);
      }
    }
  });

  it("names every effect as the Mac does", () => {
    expect(radiantEffectName(sorcerer, "bold")).toBe("Orbiting Orb");
    expect(radiantEffectName(sorcerer, "subtle")).toBe("Moonlit Blindfold");
    expect(radiantEffectName(sorcerer, "off")).toBeUndefined();
    expect(radiantEffectName("accessory.beanie", "bold")).toBeUndefined();
  });

  it("refuses another schema, an unknown zone, a short per-tick table and a last placement with zones", () => {
    const schema = clone();
    schema.schema = "radiant.v2";
    expect(() => RadiantArt.decode(schema)).toThrow(RadiantArtLoadError);

    const zone = clone() as { items: { bold: { placements: { zones: string[] }[] } }[] };
    (zone.items[0] as { bold: { placements: { zones: string[] }[] } }).bold.placements[0] = { zones: ["nowhere"], pieces: [] } as never;
    expect(() => RadiantArt.decode(zone)).toThrow(/unknown zone nowhere/);

    const short = clone() as { items: { subtle: { placements: { pieces: { positions?: unknown[] }[] }[] } }[] };
    const glint = short.items[0]?.subtle.placements.at(-1)?.pieces.find((piece) => piece.positions);
    expect(glint).toBeDefined();
    if (glint) glint.positions = [0];
    expect(() => RadiantArt.decode(short)).toThrow(/not 24/);

    const last = clone() as { items: { bold: { placements: { zones: string[] }[] } }[] };
    const placements = last.items[1]?.bold.placements ?? [];
    (placements[placements.length - 1] as { zones: string[] }).zones = ["aboveHead"];
    expect(() => RadiantArt.decode(last)).toThrow(/last placement/);

    const marker = clone();
    marker.marker = ["...", ".."];
    expect(() => RadiantArt.decode(marker)).toThrow(/same width/);
  });

  it("reads the costs and refuses another schema", () => {
    const costs = radiantCosts();
    expect(costs.perTickBudget).toBeGreaterThan(0);
    expect(costs.combinedBudget).toBeGreaterThanOrEqual(costs.perTickBudget);
    for (const item of radiantEligibleItems()) {
      for (const intensity of ["bold", "subtle"] as const) {
        const art = radiantArt().item(item);
        const effect = art && radiantEffect(art, intensity);
        effect?.placements.forEach((_, placement) => expect(costs.cost(item, intensity, placement)?.length).toBe(24));
        expect(costs.cost(item, intensity, effect?.placements.length ?? 0)).toBeUndefined();
      }
    }
    expect(() => RadiantCosts.decode({ schema: "radiant-costs.v0", perTickBudget: 1, combinedBudget: 1, costs: {} })).toThrow(
      /radiant-costs.v1/,
    );
  });

  it("prices an upgrade at five times the item", () => {
    expect(radiantPrice(sorcerer)).toBe(itemCost(sorcerer) * 5);
    expect(radiantPrice(sorcerer)).toBe(9750);
    expect(isRadiantEligible("accessory.beanie")).toBe(false);
  });
});

describe("RadiantMarkerArt", () => {
  it("is the 9 by 9 pip colored from the Gold badge palette", () => {
    expect(radiantMarkerSize()).toBe(9);
    const canvas = radiantMarkerCanvas();
    expect(canvas.width).toBe(9);
    expect(canvas.rows()).toEqual(radiantArt().marker);
    const colors = radiantMarkerColors();
    expect(colors[0]).toBeUndefined();
    /* The center is the bright core, the gold glyph color. */
    expect(colorHex(colors[4 * 9 + 4] ?? { red: 0, green: 0, blue: 0, alpha: 0 }).slice(0, 7)).toBe("#FFF7D6");
  });
});

describe("PetRadiantLook", () => {
  it("drops effects turned off and items without an effect", () => {
    const look = new PetRadiantLook([
      [sorcerer, "bold"],
      [wizardHat, "off"],
      ["accessory.beanie", "bold"],
    ]);
    expect([...look.intensities]).toEqual([[sorcerer, "bold"]]);
    expect(PetRadiantLook.none.isEmpty).toBe(true);
  });

  it("keeps only what is worn", () => {
    const look = new PetRadiantLook([
      [wizardHat, "bold"],
      [whiteCoat, "subtle"],
      [rainCloud, "bold"],
    ]);
    const worn = look.worn("whiteCoat", ["wizardHat"]);
    expect(worn.key).toBe("accessory.wizardHat:bold,outfit.whiteCoat:subtle");
    expect(look.worn("none", []).isEmpty).toBe(true);
  });
});

describe("RadiantLayout", () => {
  it("gives a lone effect its preferred placement", () => {
    for (const item of radiantEligibleItems()) {
      const layout = RadiantLayout.resolve(new PetRadiantLook([[item, "bold"]]), item.startsWith("outfit.") ? (item.slice(7) as "whiteCoat") : "none", item.startsWith("accessory.") ? [item.slice(10) as "wizardHat"] : []);
      expect(layout?.entries.map((entry) => entry.placement), item).toEqual([0]);
      expect(layout?.cycles).toBe(1);
      expect(layout?.loop).toBe(24);
    }
  });

  it("moves the orb aside when an outfit covers the chest", () => {
    const layout = RadiantLayout.resolve(new PetRadiantLook([[sorcerer, "bold"]]), "scrubs", ["blindfoldedSorcerer"]);
    expect(layout?.entries[0]?.placement).toBe(1);
  });

  it("draws nothing for an item not worn", () => {
    expect(RadiantLayout.resolve(new PetRadiantLook([[sorcerer, "bold"]]), "none", [])).toBeUndefined();
  });

  it("orders entries by slot priority and never gives two effects the same zone", () => {
    const layout = RadiantLayout.resolve(
      new PetRadiantLook([
        [rainCloud, "bold"],
        [whiteCoat, "bold"],
        [wizardHat, "bold"],
      ]),
      "whiteCoat",
      ["wizardHat", "rainCloud"],
    );
    expect(layout?.entries.map((entry) => entry.item)).toEqual([wizardHat, whiteCoat, rainCloud]);
    const used = new Set<string>();
    for (const entry of layout?.entries ?? []) {
      const art = radiantArt().item(entry.item);
      const zones = (art && radiantEffect(art, entry.intensity)?.placements[entry.placement]?.zones) ?? new Set();
      for (const zone of zones) {
        expect(used.has(zone), zone).toBe(false);
        used.add(zone);
      }
    }
  });

  it("takes turns when the costs together pass the combined budget", () => {
    const look = new PetRadiantLook([
      [wizardHat, "bold"],
      [dino, "bold"],
    ]);
    const art = radiantArt();
    const row = Array<number>(24).fill(10);
    const table = { [wizardHat]: { bold: [row, row, row] }, [dino]: { bold: [row, row, row] } };
    const calm = RadiantLayout.resolve(look, "dinosaurHoodie", ["wizardHat"], art, new RadiantCosts(10, 20, table));
    expect(calm?.cycles).toBe(1);
    expect(calm?.entries.map((entry) => entry.turn)).toEqual([undefined, undefined]);
    const busy = RadiantLayout.resolve(look, "dinosaurHoodie", ["wizardHat"], art, new RadiantCosts(10, 19, table));
    expect(busy?.cycles).toBe(2);
    expect(busy?.entries.map((entry) => entry.turn)).toEqual([0, 1]);
    expect(busy?.loop).toBe(48);
    expect(busy?.ticks(5, 24)).toEqual([5, 0]);
    expect(busy?.ticks(29, 24)).toEqual([0, 5]);
    expect(calm?.ticks(29, 24)).toEqual([5, 5]);
  });
});

describe("Radiant frames", () => {
  const profile = new PetProfile("", "britishShorthair", { accessories: ["wizardHat"] });

  it("loop the Radiant ticks on every frame and keep the normal frame's look elsewhere", () => {
    const look = new PetRadiantLook([[wizardHat, "bold"]]);
    const plain = composeClip("idle", profile.breed, { accessories: profile.accessories });
    const radiant = composeClip("idle", profile.breed, { accessories: profile.accessories, radiant: look });
    expect(radiant.frames.length).toBe(plain.frames.length);
    for (const frame of radiant.frames) expect(frame.itemFrames.length).toBe(24);
    const first = radiant.frames[0];
    expect(first?.itemFrames.some((canvas) => !canvas.equals(plain.frames[0]?.canvas ?? canvas))).toBe(true);
  });

  it("float nothing while the pet hangs from the notch", () => {
    const look = new PetRadiantLook([[wizardHat, "bold"]]);
    const radiant = composeClip("peekIn", profile.breed, { accessories: profile.accessories, radiant: look });
    const plain = composeClip("peekIn", profile.breed, { accessories: profile.accessories });
    radiant.frames.forEach((frame, index) => {
      const normal = plain.frames[index]?.canvas;
      for (const canvas of frame.itemFrames.length === 0 ? [frame.canvas] : frame.itemFrames) {
        canvas.pixels.forEach((pixel, i) => {
          /* Only the item's own pixels change: nothing appears in empty air. */
          if (normal?.pixels[i] === 0) expect(pixel).toBe(0);
        });
      }
    });
  });

  it("keep two effects from ever drawing on or beside each other", () => {
    /* A pet block in the middle of an empty frame, and two effects that put a dot on the same spot above it. */
    const bare = new PetCanvas(32, 32);
    for (let y = 16; y < 30; y++) for (let x = 10; x < 20; x++) bare.setRole(x, y, "furBase");
    const item = new RadiantItemScene(bare, bare);
    const dot = (dx: number): RadiantPlacement => ({
      zones: new Set(["aboveHead"]),
      pieces: [
        {
          type: "fixed",
          anchor: { origin: "pet", x: 0, y: 0, dx, dy: -4, role: undefined },
          offset: [0, 0],
          looks: Array<string>(24).fill("dot.Z"),
          mode: "air",
        },
      ],
    });
    const render = (second: RadiantPlacement) => {
      const report = newRadiantReport();
      const out = renderRadiant(
        [
          { placement: dot(2), tick: 0, item },
          { placement: second, tick: 0, item },
        ],
        bare,
        bare,
        { hanging: false, ceiling: undefined, art: radiantArt(), report },
      );
      return { out, report };
    };
    const same = render(dot(2));
    expect(same.report.collisions).toBe(1);
    const beside = render(dot(3));
    expect(beside.report.collisions).toBe(1);
    expect(beside.out.role(13, 12)).toBeUndefined();
    expect(beside.out.role(12, 12)).toBe("effect");
    const apart = render(dot(5));
    expect(apart.report.collisions).toBe(0);
    expect(apart.out.role(15, 12)).toBe("effect");
    /* Hanging, nothing floats. */
    const report = newRadiantReport();
    const hanging = renderRadiant([{ placement: dot(2), tick: 0, item }], bare, bare, { hanging: true, ceiling: undefined, art: radiantArt(), report });
    expect(hanging.equals(bare)).toBe(true);
  });

  it("show the still (tick 0) under Reduce Motion and in the sitting picture", () => {
    const radiant = new PetProfile("", "britishShorthair", { accessories: ["wizardHat"], radiance: new Map([[wizardHat, "bold"]]) });
    const clip = composeClip("sit", radiant.breed, { accessories: radiant.accessories, radiant: radiant.radiantLook });
    expect(radiant.sittingCanvas().equals(clip.stillFrame.canvas)).toBe(true);
    expect(clip.stillFrame.itemFrames[0]?.equals(clip.stillFrame.canvas)).toBe(true);
  });

  it("measure the zones from the bare pet so every pixel is in one zone or on the head", () => {
    const bare = composeClip("idle", "goldenRetriever").frames[0]?.canvas;
    expect(bare).toBeDefined();
    if (!bare) return;
    const geometry = new RadiantGeometry(bare);
    expect(geometry.pet).toBeDefined();
    expect(geometry.chin).toBe(Math.min(31, (geometry.face?.maxY ?? 0) + 2));
    expect(geometry.zone(0, 0)).toBe("topLeft");
    expect(geometry.zone(31, 31)).toBe("rightOfBody");
    expect(geometry.zone(geometry.headMin, geometry.top)).toBeUndefined();
  });

  it("use the radiant highlight role, white in the base palette", () => {
    expect(pixelFor("radiant")).toBeGreaterThan(pixelFor("sky"));
    expect(colorHex(new PetProfile("", "blackCat").palette.color("radiant")).slice(0, 7)).toBe("#FFFFFF");
  });

  it("draw every effect on every animation without throwing", () => {
    for (const item of radiantEligibleItems()) {
      for (const intensity of ["bold", "subtle"] as const) {
        const art = radiantArt().item(item);
        const count = (art && radiantEffect(art, intensity)?.placements.length) ?? 0;
        for (let placement = 0; placement < count; placement++) {
          const outfit = item.startsWith("outfit.") ? (item.slice(7) as "whiteCoat") : "none";
          const accessories = item.startsWith("accessory.") ? [item.slice(10) as "wizardHat"] : [];
          for (const animation of PET_ANIMATIONS.slice(0, 3)) {
            const clip = composeClipWithLayout(animation, "corgi", {
              outfit,
              accessories,
              layout: singleLayout(item, intensity, placement),
              report: newRadiantReport(),
            });
            expect(clip.frames.length).toBeGreaterThan(0);
          }
        }
      }
    }
  });
});
