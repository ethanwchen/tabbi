import breedsFile from "@mac/Pets/PetArt/breeds.json";

/*
 * Port of PetColor, PetPaletteRole, PetFurTone and PetPalette: what a sprite
 * pixel means (a role) and the colors a breed or a user recolor gives it.
 * The base colors come from `breeds.json` through `petArt.ts`.
 */

/** An 8-bit sRGB color. Port of PetColor. */
export interface PetColor {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
  readonly alpha: number;
}

export function petColor(red: number, green: number, blue: number, alpha = 255): PetColor {
  return { red, green, blue, alpha };
}

/** Parses `#RRGGBB` or `#RRGGBBAA` (the `#` is optional), or returns undefined. */
export function colorFromHex(hex: string): PetColor | undefined {
  const digits = hex.startsWith("#") ? hex.slice(1) : hex;
  if ((digits.length !== 6 && digits.length !== 8) || !/^[0-9a-fA-F]+$/.test(digits)) return undefined;
  const value = parseInt(digits, 16);
  if (digits.length === 6) return petColor((value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff);
  return petColor((value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff);
}

function hex2(value: number): string {
  return value.toString(16).toUpperCase().padStart(2, "0");
}

/** Uppercase `#RRGGBB`, plus `AA` when not fully opaque. */
export function colorHex(color: PetColor): string {
  const rgb = `#${hex2(color.red)}${hex2(color.green)}${hex2(color.blue)}`;
  return color.alpha === 255 ? rgb : `${rgb}${hex2(color.alpha)}`;
}

export function colorsEqual(a: PetColor, b: PetColor): boolean {
  return a.red === b.red && a.green === b.green && a.blue === b.blue && a.alpha === b.alpha;
}

function linear(value: number): number {
  const c = value / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

/** Relative luminance (0...1, WCAG formula), to tell whether dark fur needs a light rim. */
export function luminance(color: PetColor): number {
  return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue);
}

/** Swift's `truncatingRemainder(dividingBy:)`, which JavaScript's `%` matches for doubles. */
function remainder(value: number, divisor: number): number {
  return value % divisor;
}

/** Hue, saturation and lightness, each 0...1. */
export function hsl(color: PetColor): { hue: number; saturation: number; lightness: number } {
  const r = color.red / 255;
  const g = color.green / 255;
  const b = color.blue / 255;
  const maxC = Math.max(r, g, b);
  const minC = Math.min(r, g, b);
  const lightness = (maxC + minC) / 2;
  const delta = maxC - minC;
  if (!(delta > 0)) return { hue: 0, saturation: 0, lightness };
  const saturation = delta / (1 - Math.abs(2 * lightness - 1));
  let hue: number;
  if (maxC === r) hue = remainder((g - b) / delta, 6);
  else if (maxC === g) hue = (b - r) / delta + 2;
  else hue = (r - g) / delta + 4;
  hue /= 6;
  if (hue < 0) hue += 1;
  return { hue, saturation: Math.min(saturation, 1), lightness };
}

/** Swift's `.rounded()`: half away from zero. */
function roundHalfAway(value: number): number {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

export function colorFromHSL(hue: number, saturation: number, lightness: number, alpha = 255): PetColor {
  const l = Math.min(Math.max(lightness, 0), 1);
  const s = Math.min(Math.max(saturation, 0), 1);
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const h6 = hue * 6;
  const x = chroma * (1 - Math.abs(remainder(h6, 2) - 1));
  let rgb: [number, number, number];
  switch (Math.trunc(h6) % 6) {
    case 0:
      rgb = [chroma, x, 0];
      break;
    case 1:
      rgb = [x, chroma, 0];
      break;
    case 2:
      rgb = [0, chroma, x];
      break;
    case 3:
      rgb = [0, x, chroma];
      break;
    case 4:
      rgb = [x, 0, chroma];
      break;
    default:
      rgb = [chroma, 0, x];
  }
  const m = l - chroma / 2;
  const byte = (v: number) => roundHalfAway(Math.min(Math.max((v + m) * 255, 0), 255));
  return petColor(byte(rgb[0]), byte(rgb[1]), byte(rgb[2]), alpha);
}

/** Lightness, chroma and hue in OKLCH, where fur tones are derived. */
export function oklch(color: PetColor): { lightness: number; chroma: number; hue: number } {
  const r = linear(color.red);
  const g = linear(color.green);
  const b = linear(color.blue);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const lightness = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const a = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  let hue = Math.atan2(bb, a);
  if (hue < 0) hue += 2 * Math.PI;
  return { lightness, chroma: Math.sqrt(a * a + bb * bb), hue };
}

/**
 * The OKLCH color, or the closest one sRGB can show: chroma is lowered
 * (lightness and hue kept) until every channel fits.
 */
export function colorFromOKLCH(lightnessIn: number, chroma: number, hue: number, alpha = 255): PetColor {
  const lightness = Math.min(Math.max(lightnessIn, 0), 1);
  const rgb = (c: number): [number, number, number] => {
    const a = c * Math.cos(hue);
    const b = c * Math.sin(hue);
    const l = Math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3);
    const m = Math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3);
    const s = Math.pow(lightness - 0.0894841775 * a - 1.291485548 * b, 3);
    return [
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
    ];
  };
  const fits = (c: [number, number, number]) => c.every((v) => v >= -0.0001 && v <= 1.0001);
  let fitted = Math.max(chroma, 0);
  if (!fits(rgb(fitted))) {
    let low = 0;
    let high = fitted;
    for (let i = 0; i < 24; i++) {
      const mid = (low + high) / 2;
      if (fits(rgb(mid))) low = mid;
      else high = mid;
    }
    fitted = low;
  }
  const byte = (lin: number) => {
    const c = Math.min(Math.max(lin, 0), 1);
    const encoded = c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
    return roundHalfAway(encoded * 255);
  };
  const [r, g, b] = rgb(fitted);
  return petColor(byte(r), byte(g), byte(b), alpha);
}

/**
 * What a sprite pixel means, in the Mac's declaration order (the order is
 * the canvas encoding, so never reorder it). Port of PetPaletteRole.
 */
export const PET_PALETTE_ROLES = [
  "outline",
  "furBase",
  "furShade",
  "furAccent",
  "furSpot",
  "belly",
  "eye",
  "pupil",
  "eyeLight",
  "nose",
  "mouth",
  "blush",
  "costumeBase",
  "costumeShade",
  "costumeTrim",
  "coat",
  "coatShade",
  "accessoryBase",
  "accessoryShade",
  "ink",
  "gold",
  "metal",
  "effect",
  "effectFaint",
  "heart",
  "leaf",
  "leather",
  "crimson",
  "pumpkin",
] as const;

export type PetPaletteRole = (typeof PET_PALETTE_ROLES)[number];

/** The grid character of each role, in `PET_PALETTE_ROLES` order. */
const ROLE_SYMBOLS = "OBSAKWEiLNRPCDTUVGJQYMZzHFIXo";

export function roleSymbol(role: PetPaletteRole): string {
  return ROLE_SYMBOLS.charAt(roleIndex(role));
}

const ROLE_INDEX = new Map<PetPaletteRole, number>(PET_PALETTE_ROLES.map((role, index) => [role, index]));

/** The role's position in `PET_PALETTE_ROLES`. */
export function roleIndex(role: PetPaletteRole): number {
  return ROLE_INDEX.get(role) ?? 0;
}

export function roleAt(index: number): PetPaletteRole {
  return PET_PALETTE_ROLES[index] ?? "outline";
}

export function roleFromSymbol(symbol: string): PetPaletteRole | undefined {
  const index = ROLE_SYMBOLS.indexOf(symbol);
  return index < 0 || symbol.length !== 1 ? undefined : PET_PALETTE_ROLES[index];
}

export function isPetPaletteRole(value: string): value is PetPaletteRole {
  return ROLE_INDEX.has(value as PetPaletteRole);
}

/** Roles a user may recolor from the customization UI. */
export const USER_EDITABLE_ROLES: readonly PetPaletteRole[] = [
  "furBase",
  "furShade",
  "furAccent",
  "furSpot",
  "belly",
  "costumeBase",
  "costumeShade",
  "costumeTrim",
  "accessoryBase",
  "accessoryShade",
];

/** The fur roles a fur tint may recolor. Eyes, nose and outline never are. */
export const TINTABLE_FUR_ROLES: readonly PetPaletteRole[] = ["furBase", "furShade", "furAccent", "furSpot", "belly"];

export type PaletteOverrides = Partial<Record<PetPaletteRole, PetColor>>;

/**
 * How one fur role follows a picked fur color, in OKLCH: a step toward
 * darker or lighter fur as a fraction of the room left. Port of PetFurTone.
 */
export class PetFurTone {
  /** The darkest any derived fur gets (OKLab lightness). */
  static readonly darkest = 0.27;
  /** The lightest any derived fur gets. */
  static readonly lightest = 0.97;

  readonly step: number;
  readonly chroma: number;
  readonly maxLightness: number;

  constructor(step: number, chroma = 1, maxLightness: number = PetFurTone.lightest) {
    this.step = Math.min(Math.max(step, -1), 1);
    this.chroma = Math.max(chroma, 0);
    this.maxLightness = maxLightness;
  }

  /** The pick itself (the main coat). */
  static readonly pick = new PetFurTone(0);
  /** The pick as a marking on white fur: never so light it melts into the white. */
  static readonly marking = new PetFurTone(0, 1, 0.82);

  static darker(amount: number, chroma = 0.9): PetFurTone {
    return new PetFurTone(-amount, chroma);
  }

  static lighter(amount: number, chroma = 0.7): PetFurTone {
    return new PetFurTone(amount, chroma);
  }

  color(pick: PetColor): PetColor {
    const base = oklch(pick);
    let lightness = base.lightness;
    if (this.step < 0) lightness += this.step * Math.max(base.lightness - PetFurTone.darkest, 0);
    else lightness += this.step * Math.max(PetFurTone.lightest - base.lightness, 0);
    lightness = Math.max(Math.min(lightness, this.maxLightness, PetFurTone.lightest), PetFurTone.darkest);
    return colorFromOKLCH(lightness, base.chroma * this.chroma, base.hue, pick.alpha);
  }
}

/** Fur darker than this needs a rim (about #555 gray). */
const DARK_FUR_THRESHOLD = 0.09;
/** Outlines at least this bright already read on black. */
const RIM_MINIMUM_LUMINANCE = 0.12;
const RIM_LIGHTNESS = 0.5;
const RIM_MAXIMUM_SATURATION = 0.14;

/** Fur around a mouth darker than this (on average) gets a rim-colored mouth. */
export const DARK_MOUTH_BACKGROUND = 0.08;

/**
 * A complete role to color table. Missing roles fall back to the base
 * palette, so rendering never hits a hole. Port of PetPalette.
 */
export class PetPalette {
  /** Every role's color, indexed like `PET_PALETTE_ROLES`. */
  private readonly table: readonly PetColor[];

  constructor(colors: PaletteOverrides, base?: readonly PetColor[]) {
    const fallback = base ?? baseColors();
    this.table = PET_PALETTE_ROLES.map((role, index) => colors[role] ?? fallback[index] ?? petColor(0, 0, 0));
  }

  color(role: PetPaletteRole): PetColor {
    return this.colorAt(roleIndex(role));
  }

  colorAt(index: number): PetColor {
    return this.table[index] ?? petColor(0, 0, 0);
  }

  /** The palette as a role to color record. */
  get colors(): Record<PetPaletteRole, PetColor> {
    const out = {} as Record<PetPaletteRole, PetColor>;
    PET_PALETTE_ROLES.forEach((role, index) => {
      out[role] = this.colorAt(index);
    });
    return out;
  }

  /** A copy with `overrides` replacing the matching roles. */
  applying(overrides: PaletteOverrides): PetPalette {
    return new PetPalette({ ...this.colors, ...overrides }, this.table);
  }

  /** Overrides that recolor fur from one picked color, role by role. */
  furTint(pick: PetColor, tones: Partial<Record<PetPaletteRole, PetFurTone>>): PaletteOverrides {
    const overrides: PaletteOverrides = {};
    for (const role of TINTABLE_FUR_ROLES) {
      const tone = tones[role];
      if (tone) overrides[role] = tone.color(pick);
    }
    return overrides;
  }

  /** A copy whose outline stays visible on the black notch: dark fur gets a soft light rim. */
  withVisibleRim(): PetPalette {
    if (!(luminance(this.color("furBase")) < DARK_FUR_THRESHOLD)) return this;
    if (!(luminance(this.color("outline")) < RIM_MINIMUM_LUMINANCE)) return this;
    return this.applying({ outline: this.rim });
  }

  /** The light rim (and mouth color) for dark fur: the fur's hue at a soft mid tone. */
  get rim(): PetColor {
    const fur = hsl(this.color("furBase"));
    return colorFromHSL(fur.hue, Math.min(fur.saturation, RIM_MAXIMUM_SATURATION), RIM_LIGHTNESS);
  }

  equals(other: PetPalette): boolean {
    return this.table.every((color, index) => colorsEqual(color, other.colorAt(index)));
  }

  /** A stable key for caches. */
  get key(): string {
    return this.table.map(colorHex).join(",");
  }

  /** The flat `{ "furBase": "#RRGGBB", ... }` form the Mac's Codable writes. */
  toJSON(): Record<string, string> {
    const out: Record<string, string> = {};
    PET_PALETTE_ROLES.forEach((role, index) => {
      out[role] = colorHex(this.colorAt(index));
    });
    return out;
  }

  /** Reads the flat form leniently: unknown roles and bad colors are skipped. */
  static fromJSON(raw: Record<string, unknown>): PetPalette {
    const colors: PaletteOverrides = {};
    for (const [key, value] of Object.entries(raw)) {
      if (typeof value !== "string" || !isPetPaletteRole(key)) continue;
      const color = colorFromHex(value);
      if (color) colors[key] = color;
    }
    return new PetPalette(colors);
  }
}

let baseTable: readonly PetColor[] | undefined;

/** The shared, breed-independent colors: the `basePalette` in `breeds.json`. */
function baseColors(): readonly PetColor[] {
  if (!baseTable) {
    const raw = (breedsFile as { basePalette?: Record<string, string> }).basePalette ?? {};
    baseTable = PET_PALETTE_ROLES.map((role) => {
      const hex = raw[role];
      const color = hex === undefined ? undefined : colorFromHex(hex);
      if (!color) throw new Error(`breeds.json basePalette has no valid color for ${role}`);
      return color;
    });
  }
  return baseTable;
}
