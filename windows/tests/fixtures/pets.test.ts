import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { breedPalette } from "../../src/core/pets/petBreed";
import { PetCloset } from "../../src/core/closet/petCloset";
import { PET_PALETTE_ROLES, colorFromHex, colorHex } from "../../src/core/pets/petPalette";
import { PetProfile } from "../../src/core/pets/petProfile";
import { composeClip, type PetClip } from "../../src/core/pets/petClip";
import { FRAME_SIZE, sitting } from "../../src/core/pets/petComposer";
import { PET_ACCESSORIES, PET_OUTFITS, type PetAccessory, type PetOutfit } from "../../src/core/pets/petCostume";
import { PET_ANIMATIONS, PET_BREEDS, type PetAnimation, type PetBreed } from "../../src/core/pets/petKinds";
import type { PetCanvas } from "../../src/core/pets/petCanvas";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/pets (written by PetGoldenFrameTests on the Mac):
 * every composed frame of every animation for every breed and outfit as a
 * SHA-256, readable run-length frames for a cat and a dog, and every
 * breed's palette. The README says exactly what the digest covers.
 */

interface Dress {
  breed: PetBreed;
  outfit: PetOutfit;
  accessories: PetAccessory[];
}

interface DigestFile {
  schema: string;
  version: number;
  frameSize: number;
  dresses: { dress: Dress; frameCount: number; sha256: string }[];
}

interface FrameFile {
  schema: string;
  version: number;
  frameSize: number;
  clips: {
    dress: Dress;
    animation: PetAnimation;
    loops: boolean;
    frames: { duration: number; bubbleAnchor?: [number, number]; rle: string }[];
  }[];
  sitting: { dress: Dress; rle: string }[];
}

interface PaletteFile {
  schema: string;
  version: number;
  breeds: { breed: PetBreed; colors: Record<string, string>; rim: string; sheen: string }[];
}

interface RenderedFile {
  schema: string;
  version: number;
  frameSize: number;
  frames: { dress: Dress; furTint?: string; colors: string[]; rle: string }[];
}

const digests = loadFixture<DigestFile>("pets/composed-digests.json");
const frames = loadFixture<FrameFile>("pets/frames.json");
const palettes = loadFixture<PaletteFile>("pets/palettes.json");
const rendered = loadFixture<RenderedFile>("pets/rendered.json");

/** Every clip of a dress, in animation declaration order. */
function clipsOf(dress: Dress): PetClip[] {
  return PET_ANIMATIONS.map((animation) =>
    composeClip(animation, dress.breed, { outfit: dress.outfit, accessories: dress.accessories }),
  );
}

/** A growable little-endian byte buffer for the digest input. */
class Bytes {
  private buffer = new Uint8Array(1 << 20);
  private view = new DataView(this.buffer.buffer);
  length = 0;

  private reserve(count: number): void {
    if (this.length + count <= this.buffer.length) return;
    let size = this.buffer.length * 2;
    while (size < this.length + count) size *= 2;
    const next = new Uint8Array(size);
    next.set(this.buffer.subarray(0, this.length));
    this.buffer = next;
    this.view = new DataView(next.buffer);
  }

  byte(value: number): void {
    this.reserve(1);
    this.buffer[this.length++] = value;
  }

  text(value: string): void {
    for (const byte of new TextEncoder().encode(value)) this.byte(byte);
  }

  uint32(value: number): void {
    this.reserve(4);
    this.view.setUint32(this.length, value, true);
    this.length += 4;
  }

  int32(value: number): void {
    this.reserve(4);
    this.view.setInt32(this.length, value, true);
    this.length += 4;
  }

  float64(value: number): void {
    this.reserve(8);
    this.view.setFloat64(this.length, value, true);
    this.length += 8;
  }

  symbols(canvas: PetCanvas): void {
    const text = canvas.symbols();
    this.reserve(text.length);
    for (let i = 0; i < text.length; i++) this.buffer[this.length++] = text.charCodeAt(i);
  }

  get bytes(): Uint8Array {
    return this.buffer.subarray(0, this.length);
  }
}

/** The digest of one dress, as the README lays out its input. */
function digest(dress: Dress): { frameCount: number; sha256: string } {
  const bytes = new Bytes();
  let frameCount = 0;
  const clips = clipsOf(dress);
  PET_ANIMATIONS.forEach((animation, index) => {
    const clip = clips[index];
    if (!clip) throw new Error(`No ${animation} clip`);
    frameCount += clip.frames.length;
    bytes.text(animation);
    bytes.byte(0);
    bytes.uint32(clip.frames.length);
    for (const frame of clip.frames) {
      bytes.float64(frame.duration);
      bytes.byte(frame.bubbleAnchor ? 1 : 0);
      bytes.int32(frame.bubbleAnchor?.x ?? 0);
      bytes.int32(frame.bubbleAnchor?.y ?? 0);
      bytes.symbols(frame.canvas);
      if (frame.itemFrames.length > 0) {
        bytes.uint32(frame.itemFrames.length);
        for (const canvas of frame.itemFrames) bytes.symbols(canvas);
      }
    }
  });
  return { frameCount, sha256: createHash("sha256").update(bytes.bytes).digest("hex") };
}

/** Rows joined by `/`, each a list of runs written as an optional count and a symbol. */
function runLength(rows: readonly string[]): string {
  return rows
    .map((row) => {
      let out = "";
      let previous = "";
      let count = 0;
      const flush = () => {
        if (previous) out += (count > 1 ? String(count) : "") + previous;
      };
      for (const symbol of row) {
        if (symbol === previous) count += 1;
        else {
          flush();
          previous = symbol;
          count = 1;
        }
      }
      flush();
      return out;
    })
    .join("/");
}

function decodeRunLength(text: string): string[] {
  return text.split("/").map((row) => {
    let out = "";
    let count = "";
    for (const character of row) {
      if (character >= "0" && character <= "9") count += character;
      else {
        out += character.repeat(count ? Number(count) : 1);
        count = "";
      }
    }
    return out;
  });
}

function dressName(dress: Dress): string {
  return [dress.breed, dress.outfit, ...dress.accessories].join(" ");
}

describe("pets golden fixtures", () => {
  it("are the version this port reads", () => {
    for (const file of [digests, frames, palettes]) {
      expect(file.schema).toBe("tabbi.pets.golden");
      expect(file.version).toBe(1);
    }
    expect(digests.frameSize).toBe(FRAME_SIZE);
    expect(frames.frameSize).toBe(FRAME_SIZE);
  });

  it("cover every breed bare, in each outfit, in each accessory and in the four full looks", () => {
    const looks: [PetOutfit, PetAccessory[]][] = [
      ["scrubs", ["stethoscope", "roundGlasses", "surgicalCap"]],
      ["whiteCoat", ["bowTie", "coolSunglasses", "headMirror"]],
      ["dinosaurHoodie", ["scarf", "pirateHat"]],
      ["wizardRobe", ["chunkyHeadphones", "blindfoldedSorcerer"]],
    ];
    const expected = PET_BREEDS.flatMap((breed) => [
      ...PET_OUTFITS.map((outfit) => ({ breed, outfit, accessories: [] as PetAccessory[] })),
      ...PET_ACCESSORIES.map((accessory) => ({ breed, outfit: "none" as PetOutfit, accessories: [accessory] })),
      ...looks.map(([outfit, accessories]) => ({ breed, outfit, accessories })),
    ]);
    expect(digests.dresses.map((entry) => entry.dress)).toEqual(expected);
  });

  it("match every breed's palette, rim and sheen", () => {
    expect(palettes.breeds.map((entry) => entry.breed)).toEqual([...PET_BREEDS]);
    for (const entry of palettes.breeds) {
      const palette = breedPalette(entry.breed);
      const colors = Object.fromEntries(PET_PALETTE_ROLES.map((role) => [role, colorHex(palette.color(role))]));
      expect(colors, entry.breed).toEqual(entry.colors);
      expect(colorHex(palette.rim), entry.breed).toBe(entry.rim);
      expect(colorHex(palette.sheen), entry.breed).toBe(entry.sheen);
    }
  });

  it("render every breed, swatch and item to the same colors, rim included", () => {
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    expect(rendered.frames.length).toBe(PET_BREEDS.length * (PetCloset.furSwatches.length + 1) + 2 * (PET_OUTFITS.length - 1 + PET_ACCESSORIES.length));
    for (const entry of rendered.frames) {
      const tint = entry.furTint === undefined ? undefined : colorFromHex(entry.furTint);
      const profile = new PetProfile("", entry.dress.breed, {
        furTint: tint,
        outfit: entry.dress.outfit,
        accessories: entry.dress.accessories,
      });
      const canvas = sitting(entry.dress.breed, { outfit: entry.dress.outfit, accessories: entry.dress.accessories });
      const colors: string[] = [];
      const symbols = canvas.colors(profile.palette).map((color) => {
        if (!color) return ".";
        const hex = colorHex(color);
        let index = colors.indexOf(hex);
        if (index < 0) index = colors.push(hex) - 1;
        return letters[index] ?? "?";
      });
      const rows: string[] = [];
      for (let y = 0; y < canvas.height; y++) rows.push(symbols.slice(y * canvas.width, (y + 1) * canvas.width).join(""));
      const name = `${dressName(entry.dress)} ${entry.furTint ?? "own colors"}`;
      expect(colors, name).toEqual(entry.colors);
      expect(runLength(rows), name).toBe(entry.rle);
    }
  });

  it("match the readable frames of every clip of a cat and a dog", () => {
    for (const clip of frames.clips) {
      const built = composeClip(clip.animation, clip.dress.breed, {
        outfit: clip.dress.outfit,
        accessories: clip.dress.accessories,
      });
      const name = `${dressName(clip.dress)} ${clip.animation}`;
      expect(built.loops, name).toBe(clip.loops);
      expect(
        built.frames.map((frame) => ({
          duration: frame.duration,
          ...(frame.bubbleAnchor ? { bubbleAnchor: [frame.bubbleAnchor.x, frame.bubbleAnchor.y] } : {}),
          rle: runLength(frame.canvas.rows()),
        })),
        name,
      ).toEqual(clip.frames);
    }
  });

  it("match the sitting frame of every breed and item", () => {
    for (const entry of frames.sitting) {
      const canvas = sitting(entry.dress.breed, { outfit: entry.dress.outfit, accessories: entry.dress.accessories });
      expect(runLength(canvas.rows()), dressName(entry.dress)).toBe(entry.rle);
    }
  });

  it("round-trip the run-length encoding", () => {
    const rows = sitting("calico", { outfit: "scrubs", accessories: ["stethoscope"] }).rows();
    expect(decodeRunLength(runLength(rows))).toEqual(rows);
    for (const entry of frames.sitting) expect(runLength(decodeRunLength(entry.rle))).toBe(entry.rle);
  });

  it("match the digest of every frame of every animation of every dress", () => {
    const mismatches: string[] = [];
    for (const entry of digests.dresses) {
      const actual = digest(entry.dress);
      if (actual.frameCount !== entry.frameCount || actual.sha256 !== entry.sha256) {
        mismatches.push(`${dressName(entry.dress)}: ${actual.frameCount} frames ${actual.sha256}`);
      }
    }
    expect(mismatches).toEqual([]);
  }, 120_000);
});
