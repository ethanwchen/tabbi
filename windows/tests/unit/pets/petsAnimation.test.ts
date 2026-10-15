import { describe, expect, it } from "vitest";
import { breedHasTail, breedSpecies } from "../../../src/core/pets/petBreed";
import { PetCanvas } from "../../../src/core/pets/petCanvas";
import { FRAME_SIZE, sitting } from "../../../src/core/pets/petComposer";
import { PET_ANIMATIONS, PET_BREEDS } from "../../../src/core/pets/petKinds";
import type { PetPaletteRole } from "../../../src/core/pets/petPalette";
import { petPose } from "../../../src/core/pets/petPose";
import {
  BASELINE,
  bounds,
  clip,
  contains,
  count,
  distinct,
  edges,
  key,
  max,
  onlyOutline,
  roles,
  same,
} from "./support";

// Port of PetsAnimationTests.swift: every animation's frames for every breed.

function eyePixels(canvas: PetCanvas): number {
  return count(canvas, "eye", "pupil", "eyeLight");
}

function petPixels(canvas: PetCanvas): number {
  return roles(canvas).filter((role) => role !== undefined && role !== "effect" && role !== "heart").length;
}

// The highest opaque row within columns [from, to), or the canvas height if empty.
function opaqueTop(canvas: PetCanvas, from: number, to: number): number {
  for (let y = 0; y < canvas.height; y++) {
    for (let x = from; x < to; x++) if (canvas.role(x, y) !== undefined) return y;
  }
  return canvas.height;
}

// The pet alone, with floating effects cleared.
function removingEffects(canvas: PetCanvas): PetCanvas {
  const copy = canvas.copy();
  for (let y = 0; y < copy.height; y++) {
    for (let x = 0; x < copy.width; x++) if (copy.role(x, y) === "effect") copy.setRole(x, y, undefined);
  }
  return copy;
}

// Opaque pixels on the floor row in the frame's left half.
function leftFloorPixels(canvas: PetCanvas): number {
  let n = 0;
  for (let x = 0; x < canvas.width / 2; x++) if (canvas.role(x, BASELINE) !== undefined) n++;
  return n;
}

// The lowest row with a pixel that is not an effect.
function bottomRow(canvas: PetCanvas): number {
  let bottom = -1;
  roles(canvas).forEach((role, index) => {
    if (role !== undefined && role !== "effect") bottom = Math.max(bottom, Math.floor(index / FRAME_SIZE));
  });
  return bottom;
}

describe("PetAnimation", () => {
  it("every animation builds for every breed with positive durations", () => {
    for (const breed of PET_BREEDS) {
      for (const animation of PET_ANIMATIONS) {
        const built = clip(animation, breed);
        expect(built.frames.length, `${animation} ${breed}`).toBeGreaterThan(0);
        expect(built.frames.every((frame) => frame.duration > 0), `${animation} ${breed}`).toBe(true);
        expect(built.frames.every((frame) => frame.canvas.width === FRAME_SIZE), animation).toBe(true);
      }
    }
  });

  it("looping clips wrap and one-shot clips hold their last frame", () => {
    const idle = clip("idle", "calico");
    expect(idle.loops).toBe(true);
    expect(idle.frameIndex(0)).toBe(0);
    expect(idle.frameIndex((idle.frames[0]?.duration ?? 0) + 0.01)).toBe(1);
    expect(idle.frameIndex(idle.duration + 0.01), "wraps after one pass").toBe(0);

    const celebrate = clip("celebrate", "calico");
    expect(celebrate.loops).toBe(false);
    expect(celebrate.frameIndex(celebrate.duration * 3)).toBe(celebrate.frames.length - 1);
    expect(celebrate.frameIndex(-1), "negative time shows the first frame").toBe(0);
  });

  it("frame timing follows each frame's duration", () => {
    const built = clip("sleep", "beagle");
    let start = 0;
    built.frames.forEach((frame, index) => {
      expect(built.frameIndex(start)).toBe(index);
      expect(built.frameIndex(start + frame.duration * 0.99)).toBe(index);
      start += frame.duration;
    });
  });

  it("resting animations keep the paws on the baseline", () => {
    for (const breed of PET_BREEDS) {
      for (const animation of ["idle", "blink", "sit", "sleep"] as const) {
        for (const frame of clip(animation, breed).frames) {
          expect(bounds(frame.canvas).maxY, `${animation} ${breed}`).toBe(BASELINE);
        }
      }
    }
  });

  it("blink and sleep close the eyes and sleep drifts z's", () => {
    for (const breed of PET_BREEDS) {
      const open = sitting(breed);
      const blink = clip("blink", breed).frames[0]?.canvas ?? open;
      expect(contains(blink, "eyeLight"), `closed eyes have no highlight: ${breed}`).toBe(false);
      expect(eyePixels(blink), breed).toBeLessThan(eyePixels(open));
      expect(blink.equals(open)).toBe(false);

      const sleep = clip("sleep", breed);
      expect(sleep.frames.every((frame) => !contains(frame.canvas, "eyeLight")), breed).toBe(true);
      expect(sleep.frames.some((frame) => contains(frame.canvas, "effect")), `a z appears: ${breed}`).toBe(true);
    }
  });

  it("sleeping dogs close their mouth but keep their cheeks", () => {
    for (const breed of PET_BREEDS) {
      const awake = count(sitting(breed), "blush");
      const happy = clip("celebrate", breed).frames.map((frame) => count(frame.canvas, "blush"));
      expect(happy.every((n) => n === awake), `celebrating keeps the tongue: ${breed}`).toBe(true);
      for (const frame of clip("sleep", breed).frames) {
        const asleep = count(frame.canvas, "blush");
        if (breedSpecies(breed) === "dog") {
          expect(asleep, `the tongue is tucked in: ${breed}`).toBeLessThan(awake);
          expect(asleep, `cheeks stay rosy: ${breed}`).toBeGreaterThanOrEqual(4);
        } else {
          expect(asleep, `cats have no tongue to tuck in: ${breed}`).toBe(awake);
        }
      }
    }
  });

  it("celebration hops, shows a heart and lands back on the baseline", () => {
    for (const breed of PET_BREEDS) {
      const built = clip("celebrate", breed, { outfit: "whiteCoat", accessories: ["graduationCap"] });
      const lowest = built.frames.map((frame) => bounds(frame.canvas).maxY);
      expect(Math.min(...lowest), `the pet leaves the ground: ${breed}`).toBeLessThan(BASELINE);
      expect(lowest.at(-1), `and lands again: ${breed}`).toBe(BASELINE);
      expect(built.frames.some((frame) => contains(frame.canvas, "heart")), breed).toBe(true);
      const resting = petPixels(built.frames[0]?.canvas ?? new PetCanvas(1, 1));
      for (const frame of built.frames) expect(petPixels(frame.canvas), `nothing clipped mid-hop: ${breed}`).toBe(resting);
    }
  });

  it("alert frames carry a speech bubble anchor beside the head", () => {
    for (const breed of PET_BREEDS) {
      const built = clip("alert", breed, { accessories: ["beanie"] });
      expect(built.loops).toBe(false);
      for (const frame of built.frames) {
        const anchor = frame.bubbleAnchor;
        expect(anchor, breed).toBeDefined();
        if (!anchor) continue;
        const found = bounds(frame.canvas);
        expect(anchor.x >= 0 && anchor.x < FRAME_SIZE, breed).toBe(true);
        expect(anchor.y >= found.minY && anchor.y <= found.maxY, `anchor on the pet: ${breed}`).toBe(true);
        expect(anchor.x, `right side of the head: ${breed}`).toBeGreaterThan(FRAME_SIZE / 2);
      }
    }
    expect(clip("idle", "corgi").frames[0]?.bubbleAnchor).toBeUndefined();
  });

  it("peek lowers the head out of the top edge and peek out reverses it", () => {
    for (const breed of PET_BREEDS) {
      const peekIn = clip("peekIn", breed);
      expect(peekIn.frames[0]?.canvas.opaqueBounds, `starts hidden in the notch: ${breed}`).toBeUndefined();
      const out = peekIn.frames.at(-1)?.canvas ?? new PetCanvas(1, 1);
      expect(bounds(out).minY, `paws hold the top edge: ${breed}`).toBe(0);
      expect(eyePixels(out), `whole face visible: ${breed}`).toBe(eyePixels(sitting(breed)));
      const shown = peekIn.frames.map((frame) => petPixels(frame.canvas)).slice(0, -1);
      expect(shown, breed).toEqual([...shown].sort((a, b) => a - b));

      const peekOut = clip("peekOut", breed);
      expect(peekOut.frames.map((frame) => key(frame.canvas)), breed).toEqual(
        peekIn.frames.map((frame) => key(frame.canvas)).reverse(),
      );
    }
  });

  it("costumes follow every animation", () => {
    const plain = clip("celebrate", "labrador");
    const dressed = clip("celebrate", "labrador", { outfit: "scrubs", accessories: ["surgicalCap"] });
    plain.frames.forEach((frame, index) => {
      const other = dressed.frames[index];
      expect(same(frame.canvas, other?.canvas)).toBe(false);
      expect(other && contains(other.canvas, "costumeBase")).toBe(true);
    });
    const peek = clip("peekIn", "labrador", { outfit: "scrubs", accessories: ["surgicalCap"] });
    const hanging = peek.frames.at(-1)?.canvas ?? new PetCanvas(1, 1);
    expect(contains(hanging, "costumeBase"), "the cap shows while peeking").toBe(true);
  });

  it("walk cycle loops, steps and stays inside the frame", () => {
    for (const breed of PET_BREEDS) {
      const built = clip("walk", breed, { outfit: "whiteCoat", accessories: ["scarf", "graduationCap"] });
      expect(built.loops).toBe(true);
      expect(built.frames.length, breed).toBe(4);
      const canvases = built.frames.map((frame) => frame.canvas);
      expect(same(canvases[0], canvases[1]), `contact and passing steps differ: ${breed}`).toBe(false);
      expect(same(canvases[0], canvases[2]), `the legs swap on the second contact: ${breed}`).toBe(false);
      for (const canvas of canvases) {
        expect(bounds(canvas).maxY, `paws stay on the baseline: ${breed}`).toBe(BASELINE);
        expect(onlyOutline(edges(canvas)), `nothing clipped: ${breed}`).toBe(true);
        expect(contains(canvas, "coat"), `the coat follows the walk: ${breed}`).toBe(true);
      }
      const walk = bounds(clip("walk", breed).frames[0]?.canvas ?? new PetCanvas(1, 1));
      expect(walk.maxX - walk.minX, breed).toBeGreaterThan(walk.maxY - walk.minY + 4);
    }
  });

  it("walking costumes never cover the face", () => {
    for (const breed of PET_BREEDS) {
      const plain = clip("walk", breed);
      const dressed = clip("walk", breed, { outfit: "scrubs", accessories: ["stethoscope", "roundGlasses", "surgicalCap"] });
      plain.frames.forEach((a, index) => {
        const b = dressed.frames[index]?.canvas ?? new PetCanvas(1, 1);
        expect(eyePixels(b), breed).toBe(eyePixels(a.canvas));
        expect(count(b, "nose"), breed).toBe(count(a.canvas, "nose"));
      });
    }
  });

  it("walking scarf wraps the neck as a band, not a thin stroke", () => {
    for (const breed of PET_BREEDS) {
      const plain = clip("walk", breed);
      const dressed = clip("walk", breed, { accessories: ["scarf"] });
      plain.frames.forEach((a, index) => {
        const b = dressed.frames[index]?.canvas ?? new PetCanvas(1, 1);
        const xs: number[] = [];
        const ys: number[] = [];
        for (let y = 0; y < FRAME_SIZE; y++) {
          for (let x = 0; x < FRAME_SIZE; x++) {
            if (a.canvas.role(x, y) !== b.role(x, y)) {
              xs.push(x);
              ys.push(y);
            }
          }
        }
        const label = `${breed} frame ${index}`;
        expect(xs.length, `the scarf is easy to see: ${label}`).toBeGreaterThanOrEqual(12);
        expect(Math.max(...ys) - Math.min(...ys), label).toBeGreaterThanOrEqual(4);
        expect(Math.max(...xs) - Math.min(...xs), `the scarf stays at the neck: ${label}`).toBeLessThanOrEqual(8);
      });
    }
  });

  it("stretch bows down and rises back to standing", () => {
    for (const breed of PET_BREEDS) {
      const look = { outfit: "scrubs" as const, accessories: ["stethoscope", "beanie"] as const };
      const built = clip("stretch", breed, look);
      expect(built.loops).toBe(false);
      const canvases = built.frames.map((frame) => frame.canvas);
      const standing = clip("walk", breed, look).frames[1]?.canvas ?? new PetCanvas(1, 1);
      expect(same(canvases[0], standing), breed).toBe(true);
      expect(same(canvases.at(-1), standing), breed).toBe(true);
      for (const canvas of canvases) {
        expect(bounds(canvas).maxY, `paws stay on the baseline: ${breed}`).toBe(BASELINE);
        expect(onlyOutline(edges(canvas)), `nothing clipped: ${breed}`).toBe(true);
        expect(contains(canvas, "costumeBase"), `scrubs follow the bow: ${breed}`).toBe(true);
      }
      const bow = max(canvases, (canvas) => opaqueTop(canvas, 0, 12));
      expect(opaqueTop(bow, 0, 12), breed).toBeGreaterThan(opaqueTop(standing, 0, 12) + 1);
      expect(opaqueTop(bow, 24, 30), `the rump stays up: ${breed}`).toBe(opaqueTop(standing, 24, 30));
      expect(eyePixels(bow), breed).toBeLessThan(eyePixels(standing));
    }
  });

  it("yawn opens the mouth wide with eyes squeezed and settles back", () => {
    for (const breed of PET_BREEDS) {
      const built = clip("yawn", breed, { accessories: ["graduationCap"] });
      expect(built.loops).toBe(false);
      const sat = sitting(breed, { accessories: ["graduationCap"] });
      expect(same(built.frames[0]?.canvas, sat), `starts from sitting: ${breed}`).toBe(true);
      expect(same(built.frames.at(-1)?.canvas, sat), `and settles back: ${breed}`).toBe(true);
      for (const frame of built.frames) {
        expect(bounds(frame.canvas).maxY, breed).toBe(BASELINE);
        let topClear = true;
        for (let x = 0; x < FRAME_SIZE; x++) if (frame.canvas.role(x, 0) !== undefined) topClear = false;
        expect(topClear, `tipping the head back clips nothing: ${breed}`).toBe(true);
      }
      const wide = max(built.frames, (frame) => frame.duration).canvas;
      expect(contains(wide, "eyeLight"), `squeezed shut: ${breed}`).toBe(false);
      expect(count(wide, "mouth"), `the mouth opens: ${breed}`).toBeGreaterThan(count(sat, "mouth") + 3);
      expect(contains(wide, "blush"), breed).toBe(true);
    }
  });

  it("hop bounces twice with dust and lands sitting", () => {
    for (const breed of PET_BREEDS) {
      const look = { outfit: "whiteCoat" as const, accessories: ["graduationCap"] as const };
      const built = clip("hop", breed, look);
      expect(built.loops).toBe(false);
      const airborne = built.frames.map((frame) => bottomRow(frame.canvas) < BASELINE);
      const takeoffs = airborne.filter((up, index) => up && !(airborne[index - 1] ?? false)).length;
      expect(takeoffs, breed).toBe(2);
      expect(same(built.frames.at(-1)?.canvas, sitting(breed, look)), breed).toBe(true);
      const landings = built.frames.filter((frame) => contains(frame.canvas, "effect"));
      expect(landings.length, `a dust puff on each landing: ${breed}`).toBe(2);
      expect(built.frames.some((frame) => contains(frame.canvas, "heart")), `no heart: ${breed}`).toBe(false);
      for (const frame of built.frames) {
        const top: (PetPaletteRole | undefined)[] = [];
        for (let x = 0; x < FRAME_SIZE; x++) top.push(frame.canvas.role(x, 0));
        expect(onlyOutline(top), `the cap never clips off the top: ${breed}`).toBe(true);
      }
    }
  });

  it("typing taps alternate paws on a laptop and pauses to read", () => {
    for (const breed of PET_BREEDS) {
      const accessories = ["roundGlasses"] as const;
      const built = clip("typing", breed, { accessories });
      expect(built.loops, "plays for the whole focus session").toBe(true);
      for (const frame of built.frames) {
        expect(bounds(frame.canvas).maxY, breed).toBe(BASELINE);
        expect(contains(frame.canvas, "metal"), `the laptop is always there: ${breed}`).toBe(true);
        expect(contains(frame.canvas, "eyeLight"), `eyes on the screen: ${breed}`).toBe(true);
      }
      const laptop = (tap: number) => sitting(breed, { pose: petPose({ prop: { kind: "laptop", tap } }), accessories });
      const resting = laptop(0);
      const left = laptop(-1);
      const right = laptop(1);
      expect(distinct([resting, left, right]), breed).toBe(3);
      const canvases = built.frames.map((frame) => frame.canvas);
      expect(canvases.some((c) => c.equals(left)) && canvases.some((c) => c.equals(right)), `both paws type: ${breed}`).toBe(
        true,
      );
      expect(
        built.frames.filter((frame) => frame.canvas.equals(left) || frame.canvas.equals(right)).every((frame) => frame.duration < 0.2),
      ).toBe(true);
      const pause = max(built.frames, (frame) => frame.duration);
      expect(pause.duration).toBeGreaterThanOrEqual(0.5);
      expect(pause.canvas.equals(resting), `reading nods the head: ${breed}`).toBe(false);
    }
  });

  it("coffee raises the mug to the mouth for a sip with steam between sips", () => {
    const mugTop = (canvas: PetCanvas): number | undefined => {
      const rows = roles(canvas).flatMap((role, index) => (role === "accessoryBase" ? [Math.floor(index / canvas.width)] : []));
      return rows.length === 0 ? undefined : Math.min(...rows);
    };
    for (const breed of PET_BREEDS) {
      const built = clip("coffee", breed);
      expect(built.loops, "plays for the whole break").toBe(true);
      const resting = mugTop(built.frames[0]?.canvas ?? new PetCanvas(1, 1));
      expect(resting, `a mug in the lap: ${breed}`).toBeDefined();
      for (const frame of built.frames) {
        expect(bounds(frame.canvas).maxY, breed).toBe(BASELINE);
        expect(mugTop(frame.canvas), `the mug never leaves the paws: ${breed}`).toBeDefined();
      }
      const sip = max(built.frames, (frame) => frame.duration).canvas;
      expect(mugTop(sip), `raised to the mouth: ${breed}`).toBeLessThanOrEqual((resting ?? 0) - 4);
      expect(contains(sip, "eyeLight"), `eyes closed while sipping: ${breed}`).toBe(false);
      const plain = sitting(breed, { pose: petPose({ prop: { kind: "mug", raise: 0 } }) });
      expect(built.frames.some((frame) => !frame.canvas.equals(plain) && mugTop(frame.canvas) === resting), breed).toBe(true);
    }
  });

  it("wave lifts a paw beside the head and swings it back and forth", () => {
    for (const breed of PET_BREEDS) {
      const built = clip("wave", breed, { outfit: "whiteCoat" });
      expect(built.loops).toBe(false);
      const sat = sitting(breed, { outfit: "whiteCoat" });
      expect(same(built.frames.at(-1)?.canvas, sat), `settles back: ${breed}`).toBe(true);
      const wave = (swing: number) =>
        sitting(breed, { pose: petPose({ eyes: "happy", gesture: { kind: "wave", swing } }), outfit: "whiteCoat" });
      const out = wave(0);
      const back = wave(1);
      expect(out.equals(back), breed).toBe(false);
      const swings = built.frames.map((frame) => frame.canvas).filter((c) => c.equals(out) || c.equals(back));
      expect(swings.filter((c) => c.equals(out)).length, breed).toBeGreaterThanOrEqual(3);
      expect(swings.every((c, index) => index === 0 || !c.equals(swings[index - 1] ?? c)), `swings alternate: ${breed}`).toBe(true);
      expect(leftFloorPixels(out), `the paw leaves the floor: ${breed}`).toBeLessThan(leftFloorPixels(sat));
      for (const frame of built.frames) {
        expect(bounds(frame.canvas).maxY, breed).toBe(BASELINE);
        expect(onlyOutline(edges(frame.canvas)), `nothing clipped: ${breed}`).toBe(true);
      }
    }
  });

  it("groom licks the raised paw then washes the face", () => {
    for (const breed of PET_BREEDS) {
      const accessories = ["scarf"] as const;
      const built = clip("groom", breed, { accessories });
      expect(built.loops).toBe(false);
      const sat = sitting(breed, { accessories });
      expect(same(built.frames.at(-1)?.canvas, sat), `settles back: ${breed}`).toBe(true);
      const lick = sitting(breed, {
        pose: petPose({ eyes: "closed", mouth: "open", gesture: { kind: "groom", reach: 1 } }),
        accessories,
      });
      const canvases = built.frames.map((frame) => frame.canvas);
      expect(canvases.filter((c) => c.equals(lick)).length, `three licks: ${breed}`).toBe(3);
      expect(leftFloorPixels(lick), `the paw leaves the floor: ${breed}`).toBeLessThan(leftFloorPixels(sat));
      canvases.forEach((canvas, index) => {
        const next = canvases[index + 1];
        if (canvas.equals(lick) && next) expect(next.equals(lick), breed).toBe(false);
      });
      const wash = sitting(breed, {
        pose: petPose({ eyes: "closed", gesture: { kind: "groom", reach: 2 }, headDrop: 1 }),
        accessories,
      });
      expect(canvases.some((c) => c.equals(wash)), breed).toBe(true);
      expect(wash.equals(lick)).toBe(false);
      for (const frame of built.frames.slice(1, built.frames.length - 2)) {
        expect(contains(frame.canvas, "eyeLight"), `eyes shut while grooming: ${breed}`).toBe(false);
      }
      for (const frame of built.frames) expect(bounds(frame.canvas).maxY, breed).toBe(BASELINE);
    }
  });

  it("tail swish sweeps the tail out twice and leaves the rest of the pet still", () => {
    for (const breed of PET_BREEDS) {
      const accessories = ["scarf"] as const;
      const built = clip("tailSwish", breed, { accessories });
      expect(built.loops).toBe(false);
      const sat = sitting(breed, { accessories });
      expect(same(built.frames[0]?.canvas, sat), `starts sitting: ${breed}`).toBe(true);
      expect(same(built.frames.at(-1)?.canvas, sat), `settles back: ${breed}`).toBe(true);
      const out = sitting(breed, { pose: petPose({ tailSwing: 2 }), accessories });
      expect(bounds(out).maxX, `the tail reaches out: ${breed}`).toBeGreaterThan(bounds(sat).maxX);
      const canvases = built.frames.map((frame) => frame.canvas);
      const sweeps = canvases.filter((c, index) => {
        const previous = canvases[index - 1];
        return previous !== undefined && previous.equals(sat) && !c.equals(sat);
      }).length;
      expect(sweeps, breed).toBe(2);
      expect(canvases.some((c) => c.equals(out)), breed).toBe(true);
      for (const canvas of canvases) {
        for (let y = 0; y <= BASELINE; y++) {
          for (let x = 0; x < 16; x++) {
            if (canvas.role(x, y) !== sat.role(x, y)) expect.fail(`${breed} at ${x},${y}`);
          }
        }
        expect(bounds(canvas).maxY, breed).toBe(BASELINE);
        const edge: (PetPaletteRole | undefined)[] = [];
        for (let y = 0; y <= BASELINE; y++) edge.push(canvas.role(BASELINE, y));
        expect(onlyOutline(edge), `nothing clipped: ${breed}`).toBe(true);
      }
    }
  });

  it("nap curls up low on the floor, breathing with the tail wrapped in front", () => {
    for (const breed of PET_BREEDS) {
      const accessories = ["graduationCap", "scarf"] as const;
      const built = clip("nap", breed, { accessories });
      expect(built.loops, `naps until woken: ${breed}`).toBe(true);
      const sleeping = clip("sleep", breed, { accessories });
      const sittingTop = bounds(sleeping.frames[0]?.canvas ?? new PetCanvas(1, 1)).minY;
      const canvases = built.frames.map((frame) => frame.canvas);
      for (const canvas of canvases) {
        const found = bounds(canvas);
        expect(found.maxY, `lies on the floor: ${breed}`).toBe(BASELINE);
        expect(found.minY, `the cap is not clipped: ${breed}`).toBeGreaterThan(0);
        expect(contains(canvas, "eyeLight"), `eyes shut: ${breed}`).toBe(false);
        const edge: (PetPaletteRole | undefined)[] = [];
        for (let y = 0; y <= BASELINE; y++) edge.push(canvas.role(BASELINE, y));
        expect(edge.every((role) => role === undefined || role === "outline" || role === "effect"), breed).toBe(true);
      }
      const first = canvases[0] ?? new PetCanvas(1, 1);
      const pet = roles(first).flatMap((role, index) =>
        role !== undefined && role !== "effect" ? [Math.floor(index / FRAME_SIZE)] : [],
      );
      expect(Math.min(...pet), breed).toBeGreaterThan(sittingTop + 2);
      expect(distinct(canvases.map(removingEffects)), `breathes: ${breed}`).toBeGreaterThan(1);
      expect(canvases.some((c) => contains(c, "effect")), breed).toBe(true);
      if (breedHasTail(breed)) expect(first.role(4, BASELINE - 1), `tail tip: ${breed}`).toBeDefined();
    }
  });

  it("play pats the toy away, watches it and catches it when it comes back", () => {
    for (const breed of PET_BREEDS) {
      const built = clip("play", breed);
      expect(built.loops).toBe(false);
      const toyRole: PetPaletteRole = breedSpecies(breed) === "cat" ? "accessoryShade" : "heart";
      const toy = (canvas: PetCanvas): { left: number; bottom: number } => {
        const xs: number[] = [];
        const ys: number[] = [];
        for (let y = 0; y < canvas.height; y++) {
          for (let x = 0; x < canvas.width; x++) {
            if (canvas.role(x, y) === toyRole) {
              xs.push(x);
              ys.push(y);
            }
          }
        }
        if (xs.length === 0) throw new Error(`toy shows: ${breed}`);
        return { left: Math.min(...xs), bottom: Math.max(...ys) };
      };
      const canvases = built.frames.map((frame) => frame.canvas);
      const rest = toy(canvases[0] ?? new PetCanvas(1, 1));
      expect(toy(canvases.at(-1) ?? new PetCanvas(1, 1)).left, `the toy comes back: ${breed}`).toBe(rest.left);
      const lefts = canvases.map((canvas) => toy(canvas).left);
      const furthest = lefts.indexOf(Math.min(...lefts));
      expect(lefts[furthest], `rolls well away: ${breed}`).toBeLessThanOrEqual(rest.left - 8);
      const bottoms = canvases.map((canvas) => toy(canvas).bottom);
      if (breedSpecies(breed) === "dog") {
        expect(bottoms.some((bottom) => bottom < rest.bottom - 1), `the ball bounces: ${breed}`).toBe(true);
      } else {
        expect(bottoms.every((bottom) => bottom === rest.bottom), `the yarn stays on the floor: ${breed}`).toBe(true);
      }
      const floorPaws = leftFloorPixels(canvases[0] ?? new PetCanvas(1, 1));
      const pats = canvases.flatMap((canvas, index) =>
        leftFloorPixels(canvas) < floorPaws && lefts[index] === rest.left ? [index] : [],
      );
      expect(pats.some((index) => index < furthest) && pats.some((index) => index > furthest), breed).toBe(true);
      expect(canvases.some((c) => !contains(c, "eyeLight")), `happy eyes as it rolls: ${breed}`).toBe(true);
      for (const canvas of canvases) {
        expect(bounds(canvas).maxY, breed).toBe(BASELINE);
        const sides: (PetPaletteRole | undefined)[] = [];
        for (let i = 0; i <= BASELINE; i++) sides.push(canvas.role(0, i), canvas.role(BASELINE, i), canvas.role(i, 0));
        expect(onlyOutline(sides), `nothing clipped: ${breed}`).toBe(true);
      }
    }
  });

  it("canvas shift and flip", () => {
    const canvas = new PetCanvas(3, 3);
    canvas.setRole(0, 0, "eye");
    const shifted = canvas.shifted(1, 2);
    expect(shifted.role(1, 2)).toBe("eye");
    expect(shifted.role(0, 0)).toBeUndefined();
    expect(canvas.shifted(0, -1).opaqueBounds, "moved off the canvas is clipped").toBeUndefined();
    expect(canvas.flippedVertically().role(0, 2)).toBe("eye");
    expect(canvas.flippedVertically().flippedVertically().equals(canvas)).toBe(true);
  });
});
