import crewFile from "@mac/Pets/PetArt/crew.json";
import { colorFromHex, type PetColor } from "../pets/petPalette";
import type { PetBitmap } from "../pets/petRenderer";
import { CREW_LAURELS, type CrewLaurel } from "./crewModels";

/*
 * Port of CrewCrest, CrewCrestArt and CrewCrestSet: a crew's crest, drawn
 * from the Mac's data file `Pets/PetArt/crew.json` (format `crewCrests.v1`,
 * never a copy), so new frames and emblems are data, not code. Every layer
 * is a grid of palette characters (`.` is clear, a later layer paints only
 * its own cells): the laurel first (for the weekly top 3), then the frame,
 * the emblem centered in the frame's slot, and up to three trophy pips. `C`, `D` and
 * `H` take the crew color's base, shade and highlight, a crew color may set
 * further roles of its own (the emblem outline), `g` and `h` take the rank's
 * leaf and shade, and every other character has a fixed color. Nearest
 * neighbor only, like the pets and badges. shared/fixtures/crews/crests.json
 * pins the pixels of a spread of crests and every palette.
 */

export const CREW_CRESTS_SCHEMA = "crewCrests.v1";
/** CSS pixels per sprite pixel in crew rows and pages (48 px). */
export const CREW_CREST_REGULAR_PIXEL_SIZE = 1.5;
/** CSS pixels per sprite pixel in tight rows and pickers (32 px). */
export const CREW_CREST_COMPACT_PIXEL_SIZE = 1;
/** CSS pixels per sprite pixel in the builder's preview (64 px). */
export const CREW_CREST_LARGE_PIXEL_SIZE = 2;
/** The most trophy pips a crest shows. */
export const CREW_CREST_MAX_PIPS = 3;

/** A crew's crest: a frame filled with the crew color, an emblem in its slot, and the color. */
export interface CrewCrest {
  readonly frame: string;
  readonly emblem: string;
  readonly color: string;
}

export interface CrewCrestFrame {
  readonly id: string;
  readonly name: string;
  /** Where the emblem's top-left corner lands. */
  readonly slot: { readonly x: number; readonly y: number };
  readonly pixels: readonly (string | undefined)[];
}

export interface CrewCrestEmblem {
  readonly id: string;
  readonly name: string;
  /** Any size from 1 up to the slot; it is centered in the frame's slot. */
  readonly width: number;
  readonly height: number;
  readonly pixels: readonly (string | undefined)[];
}

export interface CrewTones {
  readonly base: PetColor;
  readonly shade: PetColor;
  readonly highlight: PetColor;
  /** Further characters this crew color sets, such as the emblem outline that turns light on a dark crew color. */
  readonly overrides: ReadonlyMap<string, PetColor>;
}

export interface CrewCrestSet {
  /** The canvas side. */
  readonly grid: number;
  /** The emblem's side. */
  readonly slot: number;
  readonly frames: readonly CrewCrestFrame[];
  readonly emblems: readonly CrewCrestEmblem[];
  /** Crew colors in picker order. */
  readonly colorIDs: readonly string[];
  readonly colors: ReadonlyMap<string, CrewTones>;
  readonly fixed: ReadonlyMap<string, PetColor>;
  readonly ranks: ReadonlyMap<CrewLaurel, { readonly leaf: PetColor; readonly shade: PetColor }>;
  readonly laurel: readonly (string | undefined)[];
  readonly pip: {
    readonly side: number;
    readonly pixels: readonly (string | undefined)[];
  };
  readonly pipPositions: readonly { readonly x: number; readonly y: number }[];
}

export class CrewCrestLoadError extends Error {}

const CREW_CHARACTERS = { base: "C", shade: "D", highlight: "H" } as const;
const RANK_CHARACTERS = { leaf: "g", shade: "h" } as const;

function fail(reason: string): never {
  throw new CrewCrestLoadError(reason);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function strings(value: unknown, what: string): string[] {
  if (!Array.isArray(value) || !value.every((item) => typeof item === "string")) fail(`${what} is not a list of rows`);
  return value as string[];
}

/** Parses and checks one `crewCrests.v1` file, with the rules of CrewCrestSet.decode. */
export function decodeCrewCrestSet(raw: unknown): CrewCrestSet {
  if (!isRecord(raw)) fail("not an object");
  if (raw.schema !== CREW_CRESTS_SCHEMA) fail(`Unsupported schema "${String(raw.schema)}"; expected "${CREW_CRESTS_SCHEMA}"`);
  const grid = raw.grid;
  const slot = raw.slot;
  if (typeof grid !== "number" || !Number.isInteger(grid) || grid < 8 || grid > 64 || typeof slot !== "number" || !Number.isInteger(slot) || slot < 1 || slot > grid) {
    fail("bad grid or slot size");
  }
  const hex = (value: unknown, what: string): PetColor => (typeof value === "string" ? colorFromHex(value) : undefined) ?? fail(`${what}: bad color ${String(value)}`);

  if (!isRecord(raw.palette)) fail("palette");
  const fixed = new Map<string, PetColor>();
  const known = new Set<string>();
  const byRole = new Map<string, string>();
  for (const [key, role] of Object.entries(raw.palette)) {
    if ([...key].length !== 1 || key === ".") fail(`palette key ${key}`);
    if (!isRecord(role) || typeof role.role !== "string") fail(`palette.${key}`);
    known.add(key);
    byRole.set(role.role, key);
    if (role.hex !== undefined && role.hex !== null) fixed.set(key, hex(role.hex, `palette.${key}`));
  }
  for (const c of [CREW_CHARACTERS.base, CREW_CHARACTERS.shade, CREW_CHARACTERS.highlight, RANK_CHARACTERS.leaf, RANK_CHARACTERS.shade]) {
    if (!known.has(c)) fail(`palette lacks ${c}`);
  }

  const parse = (rowsIn: unknown, name: string, width: number, height: number): (string | undefined)[] => {
    const rows = strings(rowsIn, name);
    if (rows.length !== height || !rows.every((row) => [...row].length === width)) fail(`${name} must be ${width} by ${height}`);
    const pixels: (string | undefined)[] = [];
    for (const row of rows) {
      for (const c of row) {
        if (c === ".") {
          pixels.push(undefined);
          continue;
        }
        if (!known.has(c)) fail(`${name}: unknown character ${c}`);
        pixels.push(c);
      }
    }
    return pixels;
  };

  if (!Array.isArray(raw.frames)) fail("frames");
  const frames: CrewCrestFrame[] = [];
  for (const frame of raw.frames) {
    if (!isRecord(frame) || typeof frame.id !== "string" || frame.id === "" || frames.some((f) => f.id === frame.id)) fail(`frame id ${isRecord(frame) ? String(frame.id) : ""}`);
    const position = frame.slot;
    if (!Array.isArray(position) || position.length !== 2 || !position.every((v) => typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= grid - slot)) {
      fail(`frame ${frame.id}: slot outside the grid`);
    }
    frames.push({
      id: frame.id,
      name: typeof frame.name === "string" ? frame.name : frame.id,
      slot: { x: position[0] as number, y: position[1] as number },
      pixels: parse(frame.grid, `frame ${frame.id}`, grid, grid),
    });
  }
  if (!Array.isArray(raw.emblems)) fail("emblems");
  const emblems: CrewCrestEmblem[] = [];
  for (const emblem of raw.emblems) {
    if (!isRecord(emblem) || typeof emblem.id !== "string" || emblem.id === "" || emblems.some((e) => e.id === emblem.id)) fail(`emblem id ${isRecord(emblem) ? String(emblem.id) : ""}`);
    const rows = strings(emblem.grid, `emblem ${emblem.id}`);
    const width = [...(rows[0] ?? "")].length;
    const height = rows.length;
    if (width < 1 || width > slot || height < 1 || height > slot) fail(`emblem ${emblem.id} must fit the ${slot} by ${slot} slot`);
    emblems.push({
      id: emblem.id,
      name: typeof emblem.name === "string" ? emblem.name : emblem.id,
      width,
      height,
      pixels: parse(rows, `emblem ${emblem.id}`, width, height),
    });
  }
  if (!Array.isArray(raw.crewColors) || frames.length === 0 || emblems.length === 0 || raw.crewColors.length === 0) fail("no frames, emblems or colors");

  const colors = new Map<string, CrewTones>();
  const colorIDs: string[] = [];
  for (const color of raw.crewColors) {
    if (!isRecord(color) || typeof color.id !== "string" || colors.has(color.id)) fail(`color id ${isRecord(color) ? String(color.id) : ""}`);
    const overrides = new Map<string, PetColor>();
    for (const [role, value] of Object.entries(color)) {
      if (["id", "base", "shade", "hi"].includes(role)) continue;
      const c = byRole.get(role) ?? fail(`color ${color.id}: unknown role ${role}`);
      overrides.set(c, hex(value, `${color.id}.${role}`));
    }
    colors.set(color.id, {
      base: hex(color.base, color.id),
      shade: hex(color.shade, color.id),
      highlight: hex(color.hi, color.id),
      overrides,
    });
    colorIDs.push(color.id);
  }
  /* Every character must get a color from the fixed table, the crew color, the rank or every crew color's own role. */
  const crewSet = new Set<string>([CREW_CHARACTERS.base, CREW_CHARACTERS.shade, CREW_CHARACTERS.highlight]);
  const rankSet = new Set<string>([RANK_CHARACTERS.leaf, RANK_CHARACTERS.shade]);
  for (const c of known) {
    if (fixed.has(c) || crewSet.has(c) || rankSet.has(c)) continue;
    if (![...colors.values()].every((tones) => tones.overrides.has(c))) fail(`character ${c} has no color for every crew color`);
  }
  if (!isRecord(raw.ranks)) fail("ranks");
  const ranks = new Map<CrewLaurel, { leaf: PetColor; shade: PetColor }>();
  for (const laurel of CREW_LAURELS) {
    const rank = raw.ranks[laurel];
    if (!isRecord(rank)) fail(`ranks.${laurel} missing`);
    ranks.set(laurel, {
      leaf: hex(rank.leaf, "rank"),
      shade: hex(rank.shade, "rank"),
    });
  }
  const pipRows = strings(raw.pip, "pip");
  const pipSide = pipRows.length;
  const pip = {
    side: pipSide,
    pixels: parse(pipRows, "pip", pipSide, pipSide),
  };
  if (!Array.isArray(raw.pipPositions)) fail("pipPositions");
  const pipPositions = raw.pipPositions.map((position: unknown) => {
    if (!Array.isArray(position) || position.length !== 2 || !position.every((v) => typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= grid - pipSide)) {
      fail("pip position outside the grid");
    }
    return { x: position[0] as number, y: position[1] as number };
  });
  return {
    grid,
    slot,
    frames,
    emblems,
    colorIDs,
    colors,
    fixed,
    ranks,
    laurel: parse(raw.laurel, "laurel", grid, grid),
    pip,
    pipPositions,
  };
}

let shipped: CrewCrestSet | undefined;

/** The shipped crest art. It ships inside the app, so a broken file is a build mistake and throws. */
export function crewCrestArt(): CrewCrestSet {
  shipped ??= decodeCrewCrestSet(crewFile);
  return shipped;
}

export function crestFrame(id: string, set: CrewCrestSet = crewCrestArt()): CrewCrestFrame {
  return set.frames.find((frame) => frame.id === id) ?? (set.frames[0] as CrewCrestFrame);
}

export function crestEmblem(id: string, set: CrewCrestSet = crewCrestArt()): CrewCrestEmblem {
  return set.emblems.find((emblem) => emblem.id === id) ?? (set.emblems[0] as CrewCrestEmblem);
}

/** The same crest with every id this app has no art for replaced by the first one. */
export function resolvedCrest(crest: CrewCrest, set: CrewCrestSet = crewCrestArt()): CrewCrest {
  return {
    frame: crestFrame(crest.frame, set).id,
    emblem: crestEmblem(crest.emblem, set).id,
    color: set.colors.has(crest.color) ? crest.color : (set.colorIDs[0] ?? crest.color),
  };
}

export function defaultCrest(set: CrewCrestSet = crewCrestArt()): CrewCrest {
  return {
    frame: set.frames[0]?.id ?? "",
    emblem: set.emblems[0]?.id ?? "",
    color: set.colorIDs[0] ?? "",
  };
}

/** A random crest, for the builder's Shuffle. */
export function randomCrest(random: () => number = Math.random, set: CrewCrestSet = crewCrestArt()): CrewCrest {
  const pick = <T>(list: readonly T[]): T => list[Math.min(list.length - 1, Math.floor(random() * list.length))] as T;
  return {
    frame: pick(set.frames).id,
    emblem: pick(set.emblems).id,
    color: pick(set.colorIDs),
  };
}

/** The layers, in order: laurel, frame, emblem at the frame's slot, pips. Characters row-major, undefined for clear. */
export function composeCrest(crest: CrewCrest, withLaurel: boolean, pips: number, set: CrewCrestSet = crewCrestArt()): (string | undefined)[] {
  const grid = set.grid;
  const pixels: (string | undefined)[] = withLaurel ? [...set.laurel] : new Array<string | undefined>(grid * grid).fill(undefined);
  const frame = crestFrame(crest.frame, set);
  frame.pixels.forEach((c, index) => {
    if (c !== undefined) pixels[index] = c;
  });
  /* The emblem is centered in the frame's slot (a full-size emblem lands at the slot itself). */
  const emblem = crestEmblem(crest.emblem, set);
  const ox = frame.slot.x + Math.floor((set.slot - emblem.width) / 2);
  const oy = frame.slot.y + Math.floor((set.slot - emblem.height) / 2);
  for (let y = 0; y < emblem.height; y++) {
    for (let x = 0; x < emblem.width; x++) {
      const c = emblem.pixels[y * emblem.width + x];
      if (c !== undefined) pixels[(oy + y) * grid + ox + x] = c;
    }
  }
  for (const position of set.pipPositions.slice(0, Math.max(0, pips))) {
    for (let y = 0; y < set.pip.side; y++) {
      for (let x = 0; x < set.pip.side; x++) {
        const c = set.pip.pixels[y * set.pip.side + x];
        if (c !== undefined) pixels[(position.y + y) * grid + position.x + x] = c;
      }
    }
  }
  return pixels;
}

/** Every character's color for one crew color (the first for an unknown id) and laurel. */
export function crestPalette(color: string, laurel: CrewLaurel | undefined, set: CrewCrestSet = crewCrestArt()): Map<string, PetColor> {
  const palette = new Map(set.fixed);
  const tones = set.colors.get(color) ?? set.colors.get(set.colorIDs[0] ?? "");
  if (tones !== undefined) {
    palette.set(CREW_CHARACTERS.base, tones.base);
    palette.set(CREW_CHARACTERS.shade, tones.shade);
    palette.set(CREW_CHARACTERS.highlight, tones.highlight);
    for (const [c, value] of tones.overrides) palette.set(c, value);
  }
  const rank = laurel === undefined ? undefined : set.ranks.get(laurel);
  if (rank !== undefined) {
    palette.set(RANK_CHARACTERS.leaf, rank.leaf);
    palette.set(RANK_CHARACTERS.shade, rank.shade);
  }
  return palette;
}

/** Whole device pixels per sprite pixel, as the badges do. */
export function crewCrestScale(pixelSize: number, devicePixelRatio: number): number {
  return Math.max(1, Math.round(pixelSize * devicePixelRatio));
}

const bitmaps = new Map<string, PetBitmap>();

/** Sprite pixels as straight RGBA, each one an exact `scale` block, like `PixelImage.render`. */
export function pixelBitmap(colors: readonly (PetColor | undefined)[], spriteWidth: number, spriteHeight: number, scale: number): PetBitmap {
  const width = spriteWidth * scale;
  const height = spriteHeight * scale;
  const data = new Uint8ClampedArray(width * height * 4);
  for (let sy = 0; sy < spriteHeight; sy++) {
    for (let sx = 0; sx < spriteWidth; sx++) {
      const color = colors[sy * spriteWidth + sx];
      if (!color) continue;
      for (let dy = 0; dy < scale; dy++) {
        let offset = ((sy * scale + dy) * width + sx * scale) * 4;
        for (let dx = 0; dx < scale; dx++) {
          data[offset] = color.red;
          data[offset + 1] = color.green;
          data[offset + 2] = color.blue;
          data[offset + 3] = color.alpha;
          offset += 4;
        }
      }
    }
  }
  return { width, height, data };
}

/** Keeps a bitmap cache bounded: a builder session can try a few hundred crests. */
function cached(key: string, make: () => PetBitmap): PetBitmap {
  const hit = bitmaps.get(key);
  if (hit) return hit;
  if (bitmaps.size > 2000) bitmaps.clear();
  const bitmap = make();
  bitmaps.set(key, bitmap);
  return bitmap;
}

/** The crest as straight RGBA, each sprite pixel an exact `scale` block, cached. */
export function crewCrestBitmap(crestIn: CrewCrest, laurel: CrewLaurel | undefined, pipsIn: number, scaleIn: number): PetBitmap {
  const set = crewCrestArt();
  const crest = resolvedCrest(crestIn, set);
  const pips = Math.min(Math.max(Math.trunc(pipsIn), 0), CREW_CREST_MAX_PIPS);
  const scale = Math.max(1, Math.trunc(scaleIn));
  return cached(`${crest.frame}|${crest.emblem}|${crest.color}|${laurel ?? "none"}|${pips}|${scale}`, () => {
    const palette = crestPalette(crest.color, laurel, set);
    const characters = composeCrest(crest, laurel !== undefined, pips, set);
    return pixelBitmap(
      characters.map((c) => (c === undefined ? undefined : palette.get(c))),
      set.grid,
      set.grid,
      scale,
    );
  });
}

/** An emblem alone in a crew color (its outline follows the color), for the editor's emblem picker. */
export function crewEmblemBitmap(emblemID: string, color: string, scaleIn: number): PetBitmap {
  const set = crewCrestArt();
  const emblem = crestEmblem(emblemID, set);
  const scale = Math.max(1, Math.trunc(scaleIn));
  return cached(`emblem|${emblem.id}|${color}|${scale}`, () => {
    const palette = crestPalette(color, undefined, set);
    return pixelBitmap(
      emblem.pixels.map((c) => (c === undefined ? undefined : palette.get(c))),
      emblem.width,
      emblem.height,
      scale,
    );
  });
}

/*
 * Port of CrewMedalArt: the pixel medal of the tallies and a crew's history,
 * in the badge style: a ribbon in ink, an outlined disc with one highlight
 * and one shade, in the metal's colors.
 */
export const CREW_MEDAL_WIDTH = 9;
export const CREW_MEDAL_HEIGHT = 10;
export const CREW_MEDAL_GRID: readonly string[] = ["...OO....", "..OQqO...", "..OQqO...", ".OOOOOO..", "OMHHMMMO.", "OMHMMMmO.", "OMMMMMmO.", "OMMMmmmO.", ".OMmmmO..", "..OOOO..."];

/** The colors of every character for a metal. */
export function crewMedalPalette(metal: CrewLaurel): Record<string, string> {
  const ink = { O: "#2A1A14", Q: "#3F4A78", q: "#2C3456" };
  switch (metal) {
    case "gold":
      return { ...ink, M: "#F2C14E", H: "#FFE9A6", m: "#C98A2A" };
    case "silver":
      return { ...ink, M: "#C7D1DE", H: "#FFFFFF", m: "#8E9BAB" };
    case "bronze":
      return { ...ink, M: "#D9945C", H: "#F3C1A0", m: "#A8683A" };
  }
}

/** The medal's pixels as colors, row-major, undefined for clear. */
export function crewMedalColors(metal: CrewLaurel): (PetColor | undefined)[] {
  const palette = crewMedalPalette(metal);
  return CREW_MEDAL_GRID.flatMap((row) => [...row].map((c) => (c === "." || palette[c] === undefined ? undefined : colorFromHex(palette[c]))));
}

export function crewMedalBitmap(metal: CrewLaurel, scaleIn: number): PetBitmap {
  const scale = Math.max(1, Math.trunc(scaleIn));
  return cached(`medal|${metal}|${scale}`, () => pixelBitmap(crewMedalColors(metal), CREW_MEDAL_WIDTH, CREW_MEDAL_HEIGHT, scale));
}
