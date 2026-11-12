import radiantFile from "@mac/Pets/PetArt/radiant.json";
import radiantCostsFile from "@mac/Pets/PetArt/radiant-costs.json";
import { roleFromSymbol } from "../petPalette";
import { pixelFor } from "../petCanvas";
import { itemFromID, type PetItem } from "../petItem";

/*
 * Port of RadiantArt.swift: the Radiant effects, read from the Mac's
 * `Pets/PetArt/radiant.json` (`radiant.v1`), and their measured per-tick
 * pixel costs from `radiant-costs.json` (`radiant-costs.v1`). Both apps read
 * these files in place, so the Mac and Windows draw the same effects. The
 * decoder checks every piece the way the Mac's does.
 */

/**
 * How strongly a Radiant item shows its effect, picked per item in the
 * Closet. A new upgrade starts on `bold`; `off` keeps the upgrade but draws
 * the normal item. Port of PetRadiantIntensity.
 */
export const PET_RADIANT_INTENSITIES = ["bold", "subtle", "off"] as const;
export type PetRadiantIntensity = (typeof PET_RADIANT_INTENSITIES)[number];

export function isPetRadiantIntensity(value: unknown): value is PetRadiantIntensity {
  return typeof value === "string" && (PET_RADIANT_INTENSITIES as readonly string[]).includes(value);
}

/**
 * A named part of the space around the pet that a Radiant effect may draw
 * its particles in. The zones split every frame into disjoint regions,
 * measured from the bare pet in that very frame (`RadiantGeometry`), so two
 * effects given different zones can never draw on the same pixel. Port of
 * RadiantZone.
 */
export const RADIANT_ZONES = [
  /* Above the head, between its left and right edges. */
  "aboveHead",
  /* Above the head and left (or right) of it: the frame's top corners. */
  "topLeft",
  "topRight",
  /* Beside the head, from its top down to the chin. */
  "leftOfHead",
  "rightOfHead",
  /* Beside the body, below the chin. */
  "leftOfBody",
  "rightOfBody",
  /* The body's front below the chin, between its edges: only an effect that passes in front of the pet uses it. */
  "chest",
] as const;
export type RadiantZone = (typeof RADIANT_ZONES)[number];

/** One pixel of a particle shape, around its center; `pixel` is the canvas value (`pixelFor(role)`). */
export interface RadiantPixel {
  readonly dx: number;
  readonly dy: number;
  readonly pixel: number;
}

/** One shape a particle can take. */
export interface RadiantShape {
  readonly pixels: readonly RadiantPixel[];
}

/** Where a piece is placed from in each frame. Port of RadiantAnchor. */
export interface RadiantAnchor {
  /**
   * `item` the bounds of the item's own pixels, `itemTip` its topmost pixel
   * (the rightmost on that row), `pet` the bounds of the bare pet, `itemRole`
   * the bounds of the item's pixels of one role.
   */
  readonly origin: "item" | "itemTip" | "pet" | "itemRole";
  /** Percent across and down the bounds, rounded down. */
  readonly x: number;
  readonly y: number;
  readonly dx: number;
  readonly dy: number;
  /** The role's canvas value, for `itemRole`. */
  readonly role: number | undefined;
}

/**
 * How a particle is drawn: `air` whole in the free air, `behind` pixel by
 * pixel in the free air, `behindItem` the same but it may touch the item,
 * `orbit` in front of the fur with an outline ring on its near side.
 */
export type RadiantParticleMode = "air" | "behind" | "behindItem" | "orbit";
const PARTICLE_MODES: readonly RadiantParticleMode[] = ["air", "behind", "behindItem", "orbit"];

/** Which particles of a piece are mirrored. */
export type RadiantMirror = "none" | "alternate" | "item";
const MIRRORS: readonly RadiantMirror[] = ["none", "alternate", "item"];

/** A set of roles, as canvas values. */
export type RadiantRoles = ReadonlySet<number>;

/**
 * One part of an effect. Every per-tick table has one entry per tick of the
 * Radiant loop, spelled out in the data. Port of RadiantPiece; role values
 * are canvas values (`pixelFor(role)`).
 */
export type RadiantPiece =
  | {
      readonly type: "glint";
      readonly roles: RadiantRoles;
      readonly color: number;
      readonly width: number;
      readonly slope: number;
      readonly slant: number;
      readonly rows: number | undefined;
      readonly near: number | undefined;
      readonly positions: readonly (number | null)[];
    }
  | {
      readonly type: "blink";
      readonly roles: RadiantRoles;
      readonly which: readonly number[];
      readonly color: number;
      readonly ticks: ReadonlySet<number>;
    }
  | {
      readonly type: "hop";
      readonly roles: RadiantRoles;
      readonly color: number;
      readonly abovePercent: number;
      readonly groups: readonly (number | null)[];
      readonly spark: string | undefined;
    }
  | {
      readonly type: "particles";
      readonly anchor: RadiantAnchor;
      readonly path: readonly (readonly number[])[];
      readonly starts: readonly number[];
      readonly looks: readonly (string | null)[];
      readonly mode: RadiantParticleMode;
      readonly mirror: RadiantMirror;
    }
  | {
      readonly type: "fixed";
      readonly anchor: RadiantAnchor;
      readonly offset: readonly number[];
      readonly looks: readonly (string | null)[];
      readonly mode: RadiantParticleMode;
    }
  | {
      readonly type: "swing";
      readonly roles: RadiantRoles;
      readonly fromMid: number;
      readonly toMax: number;
      readonly fromRow: number;
      readonly steps: readonly number[];
    }
  | {
      readonly type: "grid";
      readonly anchor: RadiantAnchor;
      readonly rows: readonly string[];
      readonly columns: readonly (readonly number[] | null)[];
      readonly mode: RadiantParticleMode;
    }
  | {
      readonly type: "trace";
      readonly pulse: readonly number[];
      readonly window: number;
      readonly pens: readonly (number | null)[];
      readonly line: number;
      readonly pen: number;
      readonly fade: number;
      readonly baseline: number;
      readonly left: number;
    }
  | {
      readonly type: "surfaceTrace";
      readonly roles: RadiantRoles;
      readonly pulse: readonly number[];
      readonly window: number;
      readonly pens: readonly (number | null)[];
      readonly line: number;
      readonly pen: number;
      readonly rowPercent: number;
    }
  | {
      readonly type: "satellite";
      readonly anchor: RadiantAnchor;
      readonly body: string;
      readonly moon: readonly (readonly number[])[];
      readonly near: number;
      readonly far: number;
    };

/**
 * One way to lay out an effect: the zones its particles may use and the
 * pieces it draws. Every effect ends on a placement with no zones.
 */
export interface RadiantPlacement {
  readonly zones: ReadonlySet<RadiantZone>;
  readonly pieces: readonly RadiantPiece[];
}

export interface RadiantEffectArt {
  readonly name: string;
  readonly placements: readonly RadiantPlacement[];
}

export interface RadiantItemArt {
  readonly item: PetItem;
  readonly subtle: RadiantEffectArt;
  readonly bold: RadiantEffectArt;
}

/** The item's effect at an intensity, or undefined when it is off. */
export function radiantEffect(art: RadiantItemArt, intensity: PetRadiantIntensity): RadiantEffectArt | undefined {
  return intensity === "bold" ? art.bold : intensity === "subtle" ? art.subtle : undefined;
}

export class RadiantArtLoadError extends Error {}

export const RADIANT_SCHEMA = "radiant.v1";
export const RADIANT_COSTS_SCHEMA = "radiant-costs.v1";

type Json = Record<string, unknown>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalid(reason: string): RadiantArtLoadError {
  return new RadiantArtLoadError(reason);
}

function isInt(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value);
}

/** The Radiant effects, read from `radiant.json`. Port of RadiantArt. */
export class RadiantArt {
  constructor(
    /** Ticks of the item clock in every Radiant loop. */
    readonly loop: number,
    /** A Radiant upgrade costs this many times the item's price. */
    readonly upgradeMultiplier: number,
    /** The order slots claim zones in when several Radiant items are worn. */
    readonly slotPriority: readonly string[],
    readonly shapes: ReadonlyMap<string, RadiantShape>,
    /** The Closet tile's Radiant pip (`radiantMarkerArt`). */
    readonly marker: readonly string[],
    /** In catalog order. */
    readonly items: readonly RadiantItemArt[],
  ) {}

  item(item: PetItem): RadiantItemArt | undefined {
    return this.items.find((art) => art.item === item);
  }

  static decode(raw: unknown): RadiantArt {
    if (!isObject(raw)) throw invalid("radiant.json is not an object");
    if (raw.schema !== RADIANT_SCHEMA) {
      throw invalid(`Unsupported schema "${String(raw.schema)}"; expected "${RADIANT_SCHEMA}"`);
    }
    const loop = raw.loop;
    const multiplier = raw.upgradeMultiplier;
    if (!isInt(loop) || !isInt(multiplier)) throw invalid("radiant.json needs a whole loop and upgradeMultiplier");
    const slotPriority = stringList(raw.slotPriority, "slotPriority");
    const marker = stringList(raw.marker, "marker");
    if (!isObject(raw.shapes)) throw invalid("radiant.json needs shapes");
    const shapes = new Map<string, RadiantShape>();
    for (const [name, shape] of Object.entries(raw.shapes)) {
      if (!isObject(shape)) throw invalid(`Shape "${name}" is not an object`);
      const rows = stringList(shape.rows, `${name}.rows`);
      const origin = shape.origin;
      if (!Array.isArray(origin) || origin.length < 2 || !origin.every(isInt)) throw invalid(`Shape "${name}": bad origin`);
      const pixels: RadiantPixel[] = [];
      rows.forEach((row, y) => {
        [...row].forEach((symbol, x) => {
          if (symbol === ".") return;
          const role = roleFromSymbol(symbol);
          if (role === undefined) throw invalid(`Shape "${name}": unknown symbol ${symbol}`);
          pixels.push({ dx: x - (origin[0] as number), dy: y - (origin[1] as number), pixel: pixelFor(role) });
        });
      });
      shapes.set(name, { pixels });
    }
    if (!Array.isArray(raw.items)) throw invalid("radiant.json needs items");
    const items = raw.items.map((entry: unknown): RadiantItemArt => {
      if (!isObject(entry)) throw invalid("An item is not an object");
      const id = String(entry.item);
      const item = itemFromID(id);
      if (item === undefined) throw invalid(`Unknown item ${id}`);
      return { item, subtle: effectArt(entry.subtle, loop, shapes), bold: effectArt(entry.bold, loop, shapes) };
    });
    const width = marker[0]?.length;
    if (width === undefined || !marker.every((row) => row.length === width)) {
      throw invalid("The marker's rows must all be the same width");
    }
    return new RadiantArt(loop, multiplier, slotPriority, shapes, marker, items);
  }
}

function stringList(value: unknown, key: string): string[] {
  if (!Array.isArray(value) || !value.every((entry) => typeof entry === "string")) throw invalid(`${key} must list strings`);
  return value as string[];
}

function effectArt(raw: unknown, loop: number, shapes: ReadonlyMap<string, RadiantShape>): RadiantEffectArt {
  if (!isObject(raw)) throw invalid("An effect is not an object");
  const name = String(raw.name);
  if (typeof raw.name !== "string") throw invalid("An effect needs a name");
  if (!Array.isArray(raw.placements)) throw invalid(`${name}: no placements`);
  const placements = raw.placements as unknown[];
  const last = placements[placements.length - 1];
  if (!isObject(last) || !Array.isArray(last.zones) || last.zones.length !== 0) {
    throw invalid(`${name}: the last placement must use no zones`);
  }
  return {
    name,
    placements: placements.map((placement): RadiantPlacement => {
      if (!isObject(placement)) throw invalid(`${name}: a placement is not an object`);
      const zones = new Set<RadiantZone>();
      for (const zone of stringList(placement.zones, `${name}.zones`)) {
        if (!(RADIANT_ZONES as readonly string[]).includes(zone)) throw invalid(`${name}: unknown zone ${zone}`);
        zones.add(zone as RadiantZone);
      }
      if (!Array.isArray(placement.pieces)) throw invalid(`${name}: a placement needs pieces`);
      return { zones, pieces: placement.pieces.map((piece: unknown) => decodePiece(piece, name, loop, shapes)) };
    }),
  };
}

/** A role symbol as a canvas value. */
function role(symbol: unknown, effect: string): number {
  if (typeof symbol !== "string" || symbol.length !== 1) throw invalid(`${effect}: unknown role ${String(symbol)}`);
  const found = roleFromSymbol(symbol);
  if (found === undefined) throw invalid(`${effect}: unknown role ${symbol}`);
  return pixelFor(found);
}

function decodePiece(raw: unknown, effect: string, loop: number, shapes: ReadonlyMap<string, RadiantShape>): RadiantPiece {
  if (!isObject(raw)) throw invalid(`${effect}: a piece is not an object`);
  const type = String(raw.type);
  const need = <T>(value: T | undefined | null, key: string): T => {
    if (value === undefined || value === null) throw invalid(`${effect}: ${type} needs ${key}`);
    return value;
  };
  const int = (key: string): number | undefined => {
    const value = raw[key];
    if (value === undefined || value === null) return undefined;
    if (!isInt(value)) throw invalid(`${effect}: ${type} ${key} must be a whole number`);
    return value;
  };
  const ints = (key: string): number[] | undefined => {
    const value = raw[key];
    if (value === undefined || value === null) return undefined;
    if (!Array.isArray(value) || !value.every(isInt)) throw invalid(`${effect}: ${type} ${key} must list whole numbers`);
    return value as number[];
  };
  const optionalInts = (key: string): (number | null)[] | undefined => {
    const value = raw[key];
    if (value === undefined || value === null) return undefined;
    if (!Array.isArray(value) || !value.every((entry) => entry === null || isInt(entry))) {
      throw invalid(`${effect}: ${type} ${key} must list whole numbers or null`);
    }
    return value as (number | null)[];
  };
  const intRows = (key: string): number[][] | undefined => {
    const value = raw[key];
    if (value === undefined || value === null) return undefined;
    if (!Array.isArray(value) || !value.every((entry) => Array.isArray(entry) && entry.every(isInt))) {
      throw invalid(`${effect}: ${type} ${key} must list rows of whole numbers`);
    }
    return value as number[][];
  };
  const perTick = <T>(values: T[] | undefined, key: string): T[] => {
    const list = need(values, key);
    if (list.length !== loop) throw invalid(`${effect}: ${type} ${key} has ${list.length} entries, not ${loop}`);
    return list;
  };
  const roleSet = (): Set<number> => new Set(stringList(need(raw.roles, "roles"), `${effect}.roles`).map((symbol) => role(symbol, effect)));
  const looksChecked = (looks: (string | null)[]): (string | null)[] => {
    for (const name of looks) if (name !== null && !shapes.has(name)) throw invalid(`${effect}: unknown shape ${name}`);
    return looks;
  };
  const looks = (): (string | null)[] | undefined => {
    const value = raw.looks;
    if (value === undefined || value === null) return undefined;
    if (!Array.isArray(value) || !value.every((entry) => entry === null || typeof entry === "string")) {
      throw invalid(`${effect}: ${type} looks must list shape names or null`);
    }
    return value as (string | null)[];
  };
  const particleMode = (): RadiantParticleMode => {
    const mode = raw.mode === undefined || raw.mode === null ? "air" : raw.mode;
    if (!PARTICLE_MODES.includes(mode as RadiantParticleMode)) throw invalid(`${effect}: unknown mode ${String(mode)}`);
    return mode as RadiantParticleMode;
  };
  const anchor = (): RadiantAnchor => {
    const value = need(raw.anchor, "anchor");
    if (!isObject(value)) throw invalid(`${effect}: bad anchor`);
    const origin = value.of;
    if (origin !== "item" && origin !== "itemTip" && origin !== "pet" && origin !== "itemRole") {
      throw invalid(`${effect}: unknown anchor ${String(origin)}`);
    }
    if (!isInt(value.x) || !isInt(value.y)) throw invalid(`${effect}: anchor needs x and y`);
    const parsed = value.role === undefined || value.role === null ? undefined : role(value.role, effect);
    if (origin === "itemRole" && parsed === undefined) throw invalid(`${effect}: itemRole anchor needs a role`);
    const offset = (key: string): number => {
      const entry = value[key];
      if (entry === undefined || entry === null) return 0;
      if (!isInt(entry)) throw invalid(`${effect}: anchor ${key} must be a whole number`);
      return entry;
    };
    return { origin, x: value.x, y: value.y, dx: offset("dx"), dy: offset("dy"), role: parsed };
  };
  /* `near` is a column count for a glint and a role for a satellite; `rows` a count for a glint and art for a grid. */
  const nearNumber = isInt(raw.near) ? raw.near : undefined;
  const nearRole = typeof raw.near === "string" ? raw.near : undefined;
  const color = () => role(need(raw.color, "color"), effect);
  switch (type) {
    case "glint": {
      const rows = raw.rows;
      if (rows !== undefined && rows !== null && !isInt(rows)) throw invalid(`${effect}: glint rows must be a count`);
      return {
        type,
        roles: roleSet(),
        color: color(),
        width: int("width") ?? 1,
        slope: int("slope") ?? 1,
        slant: int("slant") ?? 1,
        rows: isInt(rows) ? rows : undefined,
        near: nearNumber,
        positions: perTick(optionalInts("positions"), "positions"),
      };
    }
    case "blink":
      return { type, roles: roleSet(), which: need(ints("which"), "which"), color: color(), ticks: new Set(need(ints("ticks"), "ticks")) };
    case "hop": {
      const spark = raw.spark === undefined || raw.spark === null ? undefined : String(raw.spark);
      if (spark !== undefined && !shapes.has(spark)) throw invalid(`${effect}: unknown shape ${spark}`);
      return {
        type,
        roles: roleSet(),
        color: color(),
        abovePercent: need(int("abovePercent"), "abovePercent"),
        groups: perTick(optionalInts("groups"), "groups"),
        spark,
      };
    }
    case "particles": {
      const path = need(intRows("path"), "path");
      const checked = looksChecked(need(looks(), "looks"));
      if (checked.length !== path.length || !path.every((step) => step.length >= 2)) {
        throw invalid(`${effect}: particles need one look per path step`);
      }
      const mirror = raw.mirror === undefined || raw.mirror === null ? "none" : raw.mirror;
      if (!MIRRORS.includes(mirror as RadiantMirror)) throw invalid(`${effect}: unknown mirror`);
      return {
        type,
        anchor: anchor(),
        path,
        starts: need(ints("starts"), "starts"),
        looks: checked,
        mode: particleMode(),
        mirror: mirror as RadiantMirror,
      };
    }
    case "fixed":
      return { type, anchor: anchor(), offset: ints("offset") ?? [0, 0], looks: looksChecked(perTick(looks(), "looks")), mode: particleMode() };
    case "swing":
      return {
        type,
        roles: roleSet(),
        fromMid: int("fromMid") ?? 0,
        toMax: int("toMax") ?? 0,
        fromRow: int("fromRow") ?? 0,
        steps: perTick(ints("steps"), "steps"),
      };
    case "grid": {
      const rows = raw.rows;
      if (!Array.isArray(rows) || !rows.every((row) => typeof row === "string")) throw invalid(`${effect}: grid needs rows`);
      for (const row of rows as string[]) {
        for (const symbol of row) {
          if (symbol !== "." && roleFromSymbol(symbol) === undefined) throw invalid(`${effect}: unknown symbol ${symbol}`);
        }
      }
      const columns = raw.columns;
      if (
        !Array.isArray(columns) ||
        !columns.every((entry) => entry === null || (Array.isArray(entry) && entry.every(isInt)))
      ) {
        throw invalid(`${effect}: grid needs columns`);
      }
      return {
        type,
        anchor: anchor(),
        rows: rows as string[],
        columns: perTick(columns as (number[] | null)[], "columns"),
        mode: particleMode(),
      };
    }
    case "trace":
      return {
        type,
        pulse: need(ints("pulse"), "pulse"),
        window: int("window") ?? 8,
        pens: perTick(optionalInts("pens"), "pens"),
        line: role(need(raw.line, "line"), effect),
        pen: role(need(raw.pen, "pen"), effect),
        fade: role(need(raw.fade, "fade"), effect),
        baseline: int("baseline") ?? -3,
        left: int("left") ?? 0,
      };
    case "surfaceTrace":
      return {
        type,
        roles: roleSet(),
        pulse: need(ints("pulse"), "pulse"),
        window: int("window") ?? 8,
        pens: perTick(optionalInts("pens"), "pens"),
        line: role(need(raw.line, "line"), effect),
        pen: role(need(raw.pen, "pen"), effect),
        rowPercent: need(int("rowPercent"), "rowPercent"),
      };
    case "satellite": {
      const body = String(need(raw.body, "body"));
      if (!shapes.has(body)) throw invalid(`${effect}: unknown shape ${body}`);
      const moon = perTick(intRows("moon"), "moon");
      if (!moon.every((step) => step.length === 3)) throw invalid(`${effect}: moon steps need 3 numbers`);
      return {
        type,
        anchor: anchor(),
        body,
        moon,
        near: role(need(nearRole, "near"), effect),
        far: role(need(raw.far, "far"), effect),
      };
    }
    default:
      throw invalid(`${effect}: unknown piece type ${type}`);
  }
}

/**
 * The measured cost of every placement (pixels changed from one tick to the
 * next, at most, over every breed and pose) and the Radiant budgets, from
 * `radiant-costs.json`. Port of RadiantCosts.
 */
export class RadiantCosts {
  constructor(
    /** The most pixels one Radiant effect may change from one tick to the next. */
    readonly perTickBudget: number,
    /** The most pixels all the Radiant effects worn together may change from one tick to the next. */
    readonly combinedBudget: number,
    /** `[item id][intensity]` to one row of per-tick costs per placement. */
    readonly table: Readonly<Record<string, Readonly<Record<string, readonly (readonly number[])[]>>>>,
  ) {}

  cost(item: PetItem, intensity: PetRadiantIntensity, placement: number): readonly number[] | undefined {
    const byIntensity = Object.hasOwn(this.table, item) ? this.table[item] : undefined;
    const rows = byIntensity && Object.hasOwn(byIntensity, intensity) ? byIntensity[intensity] : undefined;
    return placement >= 0 ? rows?.[placement] : undefined;
  }

  static decode(raw: unknown): RadiantCosts {
    if (!isObject(raw)) throw invalid("radiant-costs.json is not an object");
    if (raw.schema !== RADIANT_COSTS_SCHEMA) {
      throw invalid(`Unsupported schema "${String(raw.schema)}"; expected "${RADIANT_COSTS_SCHEMA}"`);
    }
    if (!isInt(raw.perTickBudget) || !isInt(raw.combinedBudget) || !isObject(raw.costs)) {
      throw invalid("radiant-costs.json needs budgets and costs");
    }
    const table: Record<string, Record<string, number[][]>> = {};
    for (const [item, byIntensity] of Object.entries(raw.costs)) {
      if (!isObject(byIntensity)) throw invalid(`Costs of ${item} are not an object`);
      table[item] = {};
      for (const [intensity, rows] of Object.entries(byIntensity)) {
        if (!Array.isArray(rows) || !rows.every((row) => Array.isArray(row) && row.every(isInt))) {
          throw invalid(`Costs of ${item} ${intensity} must be rows of whole numbers`);
        }
        (table[item] as Record<string, number[][]>)[intensity] = rows as number[][];
      }
    }
    return new RadiantCosts(raw.perTickBudget, raw.combinedBudget, table);
  }
}

let sharedArt: RadiantArt | undefined;
let sharedCosts: RadiantCosts | undefined;

/** The shipped Radiant art, parsed on first use; a broken file is a build mistake, so this throws. */
export function radiantArt(): RadiantArt {
  if (!sharedArt) {
    try {
      sharedArt = RadiantArt.decode(radiantFile);
    } catch (error) {
      throw new RadiantArtLoadError(`Invalid pet art radiant.json: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return sharedArt;
}

/** The shipped per-placement costs, parsed on first use. */
export function radiantCosts(): RadiantCosts {
  if (!sharedCosts) {
    try {
      sharedCosts = RadiantCosts.decode(radiantCostsFile);
    } catch (error) {
      throw new RadiantArtLoadError(`Invalid pet art radiant-costs.json: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return sharedCosts;
}

