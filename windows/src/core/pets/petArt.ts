import animationsFile from "@mac/Pets/PetArt/animations.json";
import breedsFile from "@mac/Pets/PetArt/breeds.json";
import catFile from "@mac/Pets/PetArt/cat.json";
import costumeFile from "@mac/Pets/PetArt/costume.json";
import dogFile from "@mac/Pets/PetArt/dog.json";
import effectFile from "@mac/Pets/PetArt/effect.json";
import pawFile from "@mac/Pets/PetArt/paw.json";
import propFile from "@mac/Pets/PetArt/prop.json";
import tailFile from "@mac/Pets/PetArt/tail.json";
import walkFile from "@mac/Pets/PetArt/walk.json";
import { PET_ANIMATIONS, PET_BODY_SHAPES, PET_BREEDS, PET_SPECIES, isOneOf } from "./petKinds";
import type { PetAnimation, PetBodyShape, PetBreed, PetSpecies } from "./petKinds";
import { colorFromHex, isPetPaletteRole, type PaletteOverrides, type PetPaletteRole } from "./petPalette";
import { PetArtLoadError, invalidValue, parseTimeline, type PetTimeline } from "./petTimeline";
import { SpriteGrid, isPetPatternZone, type PetPatternZone } from "./spriteGrid";

/*
 * Port of PetArt and PetArtFile: the hand-drawn pet art, read from the
 * `pets.v1` JSON files the Mac app ships (`Sources/TabbiKitCore/Pets/PetArt`),
 * never a copy. Each file is checked as it loads, the way the Mac's decoder
 * does; `tests/unit/pets/petArt.test.ts` also validates each against
 * `shared/schemas/pets.v1.schema.json` with Ajv.
 */

/** The version every art file declares in its `schema` key. */
export const PET_ART_SCHEMA = "pets.v1";

/** A grid drawn for each body family, the size of and stamped at the body's origin. */
export interface CostumeBodyItem {
  readonly cat: SpriteGrid;
  readonly dog: SpriteGrid;
  readonly longDog: SpriteGrid;
  /** Over the cat and dog walking torso. */
  readonly walk: SpriteGrid;
  /** Over the dachshund walking torso. */
  readonly walkLong: SpriteGrid;
  /** Rows every grid reaches above its body's top row. */
  readonly rise: number;
  /** The rest of an animated item's loop, after these still grids. */
  readonly moreFrames: readonly CostumeBodyItem[];
}

/** A face item: a grid for cat faces and one for dog faces, and the row that lands on the eye row. */
export interface CostumeFaceItem {
  readonly cat: SpriteGrid;
  readonly dog: SpriteGrid;
  readonly eyeRow: number;
  readonly moreFrames: readonly CostumeFaceItem[];
}

/** A hat-like item and the grid row that lands on the head's skull top. */
export interface CostumeHeadItem {
  readonly grid: SpriteGrid;
  readonly sitRow: number;
  readonly moreFrames: readonly SpriteGrid[];
}

/** An item loop for one view and its offset (from the body origin, or the frame corner for auras). */
export interface CostumePlacement {
  readonly x: number;
  readonly y: number;
  readonly frames: readonly SpriteGrid[];
}

/** An item worn behind the pet, such as wings. */
export interface CostumeBackItem {
  readonly cat: CostumePlacement;
  readonly dog: CostumePlacement;
  readonly longDog: CostumePlacement;
  readonly walk: CostumePlacement;
  readonly walkLong: CostumePlacement;
}

/** An item that floats in the air around the pet, such as falling petals. */
export interface CostumeAuraItem {
  readonly front: CostumePlacement;
  readonly side: CostumePlacement;
  readonly longDog: CostumePlacement;
}

/** Frames in an item's loop; 1 for an item that stays still. */
export function bodyFrameCount(item: CostumeBodyItem): number {
  return 1 + item.moreFrames.length;
}

/** The item as drawn on frame `phase` of the item clock. */
export function bodyFrame(item: CostumeBodyItem, phase: number): CostumeBodyItem {
  const index = phase % bodyFrameCount(item);
  return index === 0 ? item : (item.moreFrames[index - 1] ?? item);
}

export function faceFrameCount(item: CostumeFaceItem): number {
  return 1 + item.moreFrames.length;
}

export function faceFrame(item: CostumeFaceItem, phase: number): CostumeFaceItem {
  const index = phase % faceFrameCount(item);
  return index === 0 ? item : (item.moreFrames[index - 1] ?? item);
}

export function headFrameCount(item: CostumeHeadItem): number {
  return 1 + item.moreFrames.length;
}

export function headGrid(item: CostumeHeadItem, phase: number): SpriteGrid {
  const index = phase % headFrameCount(item);
  return index === 0 ? item.grid : (item.moreFrames[index - 1] ?? item.grid);
}

/** Frames in a back item's loop, the same for every body family. */
export function backFrameCount(item: CostumeBackItem): number {
  return item.cat.frames.length;
}

/** Frames in an aura item's loop, the same for both views. */
export function auraFrameCount(item: CostumeAuraItem): number {
  return item.front.frames.length;
}

/** One breed as `breeds.json` defines it. */
export interface BreedDefinition {
  readonly name: string;
  readonly bodyShape: PetBodyShape;
  readonly hasTail: boolean;
  readonly palette: PaletteOverrides;
  readonly pattern: Partial<Record<PetPatternZone, PetPaletteRole>>;
}

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function entries(value: unknown, path: string): [string, unknown][] {
  if (value === undefined) return [];
  if (!isObject(value)) throw invalidValue(path, JSON.stringify(value));
  return Object.entries(value);
}

function parse(rows: unknown, name: string): SpriteGrid {
  if (!Array.isArray(rows) || !rows.every((row) => typeof row === "string")) {
    throw new PetArtLoadError(`Grid "${name}": not an array of rows`);
  }
  try {
    return SpriteGrid.fromRows(rows);
  } catch (error) {
    throw new PetArtLoadError(`Grid "${name}": ${error instanceof Error ? error.message : String(error)}`);
  }
}

function integer(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) throw invalidValue(path, String(value));
  return value;
}

/** Every frame of an item's loop is drawn over the same spot, so it must be the size of the still grid. */
function sameSize(frame: SpriteGrid, still: SpriteGrid, name: string): void {
  if (frame.width !== still.width || frame.height !== still.height) {
    throw new PetArtLoadError(
      `Grid "${name}": ${frame.width}x${frame.height} differs from the item's ${still.width}x${still.height} still grid`,
    );
  }
}

function colors(raw: unknown, path: string): PaletteOverrides {
  const out: PaletteOverrides = {};
  for (const [role, hex] of entries(raw, path)) {
    if (!isPetPaletteRole(role)) throw invalidValue(path, role);
    const color = typeof hex === "string" ? colorFromHex(hex) : undefined;
    if (!color) throw invalidValue(`${path}.${role}`, String(hex));
    out[role] = color;
  }
  return out;
}

const BODY_FAMILIES = ["cat", "dog", "longDog", "walk", "walkLong"] as const;

/**
 * One `pets.v1` file: named grids and sequences and, in the costume file,
 * the items with their anchors; or the breeds; or the animation timelines.
 * Port of PetArtFile.
 */
export class PetArtFile {
  readonly grids = new Map<string, SpriteGrid>();
  readonly sequences = new Map<string, SpriteGrid[]>();
  readonly bodyItems = new Map<string, CostumeBodyItem>();
  readonly faceItems = new Map<string, CostumeFaceItem>();
  readonly headItems = new Map<string, CostumeHeadItem>();
  readonly backItems = new Map<string, CostumeBackItem>();
  readonly auraItems = new Map<string, CostumeAuraItem>();
  basePalette: PaletteOverrides = {};
  readonly bodyShapes = new Map<PetBodyShape, PetSpecies>();
  /** Breeds in file order, the order pickers list them in. */
  readonly breedOrder: PetBreed[] = [];
  readonly breeds = new Map<PetBreed, BreedDefinition>();
  readonly animations = new Map<PetAnimation, PetTimeline>();
  /** Seconds each frame of an animated costume item's loop stays on screen (costume file only). */
  itemFrameDuration: number | undefined;

  grid(name: string): SpriteGrid {
    return lookUp(this.grids, name, "grid");
  }

  sequence(name: string): SpriteGrid[] {
    return lookUp(this.sequences, name, "sequence");
  }

  bodyItem(name: string): CostumeBodyItem {
    return lookUp(this.bodyItems, name, "body item");
  }

  faceItem(name: string): CostumeFaceItem {
    return lookUp(this.faceItems, name, "face item");
  }

  headItem(name: string): CostumeHeadItem {
    return lookUp(this.headItems, name, "head item");
  }

  backItem(name: string): CostumeBackItem {
    return lookUp(this.backItems, name, "back item");
  }

  auraItem(name: string): CostumeAuraItem {
    return lookUp(this.auraItems, name, "aura item");
  }

  species(shape: PetBodyShape): PetSpecies {
    return lookUp(this.bodyShapes, shape, "body shape");
  }

  breed(breed: PetBreed): BreedDefinition {
    return lookUp(this.breeds, breed, "breed");
  }

  timeline(animation: PetAnimation): PetTimeline {
    return lookUp(this.animations, animation, "animation");
  }

  /** Parses a file, checking its schema version and every grid. */
  static decode(raw: unknown): PetArtFile {
    if (!isObject(raw)) throw new PetArtLoadError("Pet art file is not an object");
    if (raw.schema !== PET_ART_SCHEMA) {
      throw new PetArtLoadError(`Unsupported schema "${String(raw.schema)}"; expected "${PET_ART_SCHEMA}"`);
    }
    const file = new PetArtFile();
    for (const [name, rows] of entries(raw.grids, "grids")) file.grids.set(name, parse(rows, name));
    for (const [name, frames] of entries(raw.sequences, "sequences")) {
      if (!Array.isArray(frames)) throw invalidValue(`sequences.${name}`, JSON.stringify(frames));
      file.sequences.set(
        name,
        frames.map((rows: unknown, index) => parse(rows, `${name}[${index}]`)),
      );
    }
    for (const [name, item] of entries(raw.bodyItems, "bodyItems")) {
      if (!isObject(item)) throw invalidValue(`bodyItems.${name}`, JSON.stringify(item));
      const rise = item.rise === undefined ? 0 : integer(item.rise, `${name}.rise`);
      const grids = (frame: Json, path: string) => ({
        cat: parse(frame.cat, `${path}.cat`),
        dog: parse(frame.dog, `${path}.dog`),
        longDog: parse(frame.longDog, `${path}.longDog`),
        walk: parse(frame.walk, `${path}.walk`),
        walkLong: parse(frame.walkLong, `${path}.walkLong`),
        rise,
      });
      const still = grids(item, name);
      const rawFrames = item.frames ?? [];
      if (!Array.isArray(rawFrames)) throw invalidValue(`${name}.frames`, JSON.stringify(rawFrames));
      const moreFrames = rawFrames.map((frame: unknown, index): CostumeBodyItem => {
        const path = `${name}.frames[${index}]`;
        if (!isObject(frame)) throw invalidValue(path, JSON.stringify(frame));
        const moving = grids(frame, path);
        for (const family of BODY_FAMILIES) sameSize(moving[family], still[family], `${path}.${family}`);
        return { ...moving, moreFrames: [] };
      });
      file.bodyItems.set(name, { ...still, moreFrames });
    }
    for (const [name, item] of entries(raw.faceItems, "faceItems")) {
      if (!isObject(item)) throw invalidValue(`faceItems.${name}`, JSON.stringify(item));
      const eyeRow = integer(item.eyeRow, `${name}.eyeRow`);
      const cat = parse(item.cat, `${name}.cat`);
      const dog = parse(item.dog, `${name}.dog`);
      const rawFrames = item.frames ?? [];
      if (!Array.isArray(rawFrames)) throw invalidValue(`${name}.frames`, JSON.stringify(rawFrames));
      const moreFrames = rawFrames.map((frame: unknown, index): CostumeFaceItem => {
        const path = `${name}.frames[${index}]`;
        if (!isObject(frame)) throw invalidValue(path, JSON.stringify(frame));
        const moving = { cat: parse(frame.cat, `${path}.cat`), dog: parse(frame.dog, `${path}.dog`), eyeRow, moreFrames: [] };
        sameSize(moving.cat, cat, `${path}.cat`);
        sameSize(moving.dog, dog, `${path}.dog`);
        return moving;
      });
      file.faceItems.set(name, { cat, dog, eyeRow, moreFrames });
    }
    for (const [name, item] of entries(raw.headItems, "headItems")) {
      if (!isObject(item)) throw invalidValue(`headItems.${name}`, JSON.stringify(item));
      const grid = parse(item.grid, `${name}.grid`);
      const rawFrames = item.frames ?? [];
      if (!Array.isArray(rawFrames)) throw invalidValue(`${name}.frames`, JSON.stringify(rawFrames));
      const moreFrames = rawFrames.map((rows: unknown, index) => {
        const path = `${name}.frames[${index}]`;
        const frame = parse(rows, path);
        sameSize(frame, grid, path);
        return frame;
      });
      file.headItems.set(name, { grid, sitRow: integer(item.sitRow, `${name}.sitRow`), moreFrames });
    }
    const placement = (value: unknown, path: string): CostumePlacement => {
      if (!isObject(value)) throw invalidValue(path, JSON.stringify(value));
      const rawFrames = value.frames;
      if (!Array.isArray(rawFrames) || rawFrames.length === 0) {
        throw new PetArtLoadError(`Grid "${path}": no frames`);
      }
      const frames = rawFrames.map((rows: unknown, index) => parse(rows, `${path}.frames[${index}]`));
      frames.forEach((frame, index) => {
        if (index > 0 && frames[0]) sameSize(frame, frames[0], `${path}.frames[${index}]`);
      });
      return { x: integer(value.x, `${path}.x`), y: integer(value.y, `${path}.y`), frames };
    };
    for (const [name, item] of entries(raw.backItems, "backItems")) {
      if (!isObject(item)) throw invalidValue(`backItems.${name}`, JSON.stringify(item));
      const back: CostumeBackItem = {
        cat: placement(item.cat, `${name}.cat`),
        dog: placement(item.dog, `${name}.dog`),
        longDog: placement(item.longDog, `${name}.longDog`),
        walk: placement(item.walk, `${name}.walk`),
        walkLong: placement(item.walkLong, `${name}.walkLong`),
      };
      /* Every family plays the loop in step on the one item clock. */
      for (const family of ["dog", "longDog", "walk", "walkLong"] as const) {
        if (back[family].frames.length !== backFrameCount(back)) {
          throw new PetArtLoadError(
            `Grid "${name}.${family}": ${back[family].frames.length} frames differ from the cat's ${backFrameCount(back)}`,
          );
        }
      }
      file.backItems.set(name, back);
    }
    for (const [name, item] of entries(raw.auraItems, "auraItems")) {
      if (!isObject(item)) throw invalidValue(`auraItems.${name}`, JSON.stringify(item));
      const front = placement(item.front, `${name}.front`);
      const aura: CostumeAuraItem = {
        front,
        side: placement(item.side, `${name}.side`),
        longDog: item.longDog === undefined ? front : placement(item.longDog, `${name}.longDog`),
      };
      for (const view of ["side", "longDog"] as const) {
        if (aura[view].frames.length !== auraFrameCount(aura)) {
          throw new PetArtLoadError(
            `Grid "${name}.${view}": ${aura[view].frames.length} frames differ from the front's ${auraFrameCount(aura)}`,
          );
        }
      }
      file.auraItems.set(name, aura);
    }
    if (raw.itemFrameDuration !== undefined) {
      const duration = raw.itemFrameDuration;
      if (typeof duration !== "number" || !(duration > 0)) throw invalidValue("itemFrameDuration", String(duration));
      file.itemFrameDuration = duration;
    }
    if (raw.basePalette !== undefined) file.basePalette = colors(raw.basePalette, "basePalette");
    for (const [name, shape] of entries(raw.bodyShapes, "bodyShapes")) {
      if (!isOneOf(PET_BODY_SHAPES, name)) throw invalidValue("bodyShapes", name);
      const species = isObject(shape) ? shape.species : undefined;
      if (typeof species !== "string" || !isOneOf(PET_SPECIES, species)) {
        throw invalidValue(`bodyShapes.${name}.species`, String(species));
      }
      file.bodyShapes.set(name, species);
    }
    const rawBreeds = raw.breeds ?? [];
    if (!Array.isArray(rawBreeds)) throw invalidValue("breeds", JSON.stringify(rawBreeds));
    rawBreeds.forEach((entry: unknown, index) => {
      const path = `breeds[${index}]`;
      if (!isObject(entry)) throw invalidValue(path, JSON.stringify(entry));
      const id = String(entry.id);
      if (!isOneOf(PET_BREEDS, id)) throw invalidValue(`${path}.id`, id);
      const bodyShape = String(entry.bodyShape);
      if (!isOneOf(PET_BODY_SHAPES, bodyShape)) throw invalidValue(`${path}.bodyShape`, bodyShape);
      if (typeof entry.name !== "string") throw invalidValue(`${path}.name`, String(entry.name));
      if (typeof entry.hasTail !== "boolean") throw invalidValue(`${path}.hasTail`, String(entry.hasTail));
      const pattern: Partial<Record<PetPatternZone, PetPaletteRole>> = {};
      for (const [zone, role] of entries(entry.pattern, `${path}.pattern`)) {
        if (!isPetPatternZone(zone)) throw invalidValue(`${path}.pattern`, zone);
        if (typeof role !== "string" || !isPetPaletteRole(role)) throw invalidValue(`${path}.pattern.${zone}`, String(role));
        pattern[zone] = role;
      }
      file.breedOrder.push(id);
      file.breeds.set(id, {
        name: entry.name,
        bodyShape,
        hasTail: entry.hasTail,
        palette: colors(entry.palette, `${path}.palette`),
        pattern,
      });
    });
    for (const [name, timeline] of entries(raw.animations, "animations")) {
      if (!isOneOf(PET_ANIMATIONS, name)) throw invalidValue("animations", name);
      file.animations.set(name, parseTimeline(timeline, `animations.${name}`));
    }
    return file;
  }
}

function lookUp<Key, Value>(table: Map<Key, Value>, name: Key, kind: string): Value {
  const value = table.get(name);
  if (value === undefined) throw new PetArtLoadError(`No pet art ${kind} named "${String(name)}"`);
  return value;
}

/** The raw files, by the name the Mac loads them under. */
export const PET_ART_SOURCES = {
  cat: catFile,
  dog: dogFile,
  costume: costumeFile,
  effect: effectFile,
  paw: pawFile,
  prop: propFile,
  tail: tailFile,
  walk: walkFile,
  breeds: breedsFile,
  animations: animationsFile,
} as const;

export type PetArtName = keyof typeof PET_ART_SOURCES;

const loaded = new Map<PetArtName, PetArtFile>();

/**
 * One art file, parsed on first use. The art ships with the app, so a broken
 * file is a build mistake: this throws with the reason (and a unit test
 * loads every file) instead of drawing a broken pet.
 */
export function petArt(name: PetArtName): PetArtFile {
  let file = loaded.get(name);
  if (!file) {
    try {
      file = PetArtFile.decode(PET_ART_SOURCES[name]);
    } catch (error) {
      throw new PetArtLoadError(`Invalid pet art ${name}.json: ${error instanceof Error ? error.message : String(error)}`);
    }
    loaded.set(name, file);
  }
  return file;
}
