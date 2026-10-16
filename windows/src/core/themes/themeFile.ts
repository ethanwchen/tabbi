/*
 * Port of ThemeFile: reads themes.json (the themes in picker order, the
 * default, kit values from before themes existed, and the glass sheen) and
 * checks what the Swift loader checks: the schema version, unique ids, every
 * id the file or the code refers to, and color components in 0...1.
 */

import { ACCENT_TREATMENTS } from "./accentTreatment";
import {
  GLASS_SHEEN_ROLES,
  PALETTE_ROLES,
  REQUIRED_THEME_IDS,
  THEME_CONTROL_STYLES,
  THEME_FAMILIES,
  THEME_MOTIONS,
  THEME_SURFACE_STYLES,
  THEME_TYPEFACES,
  paletteRoles,
  type AppTheme,
  type GlassSheen,
  type ThemeID,
  type ThemePalette,
} from "./appTheme";
import { gray, rgb, type ThemeColor } from "./themeColor";

export const THEME_FILE_SCHEMA = "themes.v1";

export interface ThemeFile {
  readonly schema: string;
  readonly defaultTheme: ThemeID;
  readonly legacyKitThemes: Readonly<Record<string, ThemeID>>;
  readonly glassSheen: GlassSheen;
  readonly themes: readonly AppTheme[];
}

/** Why a themes file cannot load: ThemeFile.LoadError, plus the decoding errors Swift's decoder throws. */
export type ThemeFileProblem =
  | { readonly kind: "unsupportedSchema"; readonly schema: string }
  | { readonly kind: "duplicateTheme"; readonly id: ThemeID }
  | { readonly kind: "unknownTheme"; readonly path: string; readonly id: ThemeID }
  | { readonly kind: "componentOutOfRange"; readonly path: string; readonly value: number }
  | { readonly kind: "invalid"; readonly path: string; readonly expected: string };

export function describeThemeFileProblem(problem: ThemeFileProblem): string {
  switch (problem.kind) {
    case "unsupportedSchema":
      return `Unsupported schema "${problem.schema}"; expected "${THEME_FILE_SCHEMA}"`;
    case "duplicateTheme":
      return `Theme "${problem.id}" is defined twice`;
    case "unknownTheme":
      return `${problem.path}: no theme "${problem.id}"`;
    case "componentOutOfRange":
      return `${problem.path}: ${problem.value} is outside 0...1`;
    case "invalid":
      return `${problem.path || "file"}: expected ${problem.expected}`;
  }
}

export class ThemeFileError extends Error {
  readonly problem: ThemeFileProblem;

  constructor(problem: ThemeFileProblem) {
    super(describeThemeFileProblem(problem));
    this.name = "ThemeFileError";
    this.problem = problem;
  }
}

type JsonObject = Readonly<Record<string, unknown>>;

function invalid(path: string, expected: string): never {
  throw new ThemeFileError({ kind: "invalid", path, expected });
}

function object(value: unknown, path: string): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) invalid(path, "an object");
  return value as JsonObject;
}

function string(value: unknown, path: string): string {
  if (typeof value !== "string") invalid(path, "a string");
  return value;
}

function number(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) invalid(path, "a number");
  return value;
}

function oneOf<T extends string>(values: readonly T[], value: unknown, path: string): T {
  const text = string(value, path);
  const match = values.find((v) => v === text);
  if (match === undefined) invalid(path, `one of ${values.join(", ")}`);
  return match;
}

/** themes.json's color form: {"white": w} for a gray, or red, green and blue; opacity defaults to 1. */
export function decodeThemeColor(value: unknown, path: string): ThemeColor {
  const json = object(value, path);
  const opacity = json.opacity === undefined ? 1 : number(json.opacity, `${path}.opacity`);
  if (json.white !== undefined) return gray(number(json.white, `${path}.white`), opacity);
  return rgb(
    number(json.red, `${path}.red`),
    number(json.green, `${path}.green`),
    number(json.blue, `${path}.blue`),
    opacity,
  );
}

function decodePalette(value: unknown, path: string): ThemePalette {
  const json = object(value, path);
  const color = (role: string) => decodeThemeColor(json[role], `${path}.${role}`);
  const roles = Object.fromEntries(PALETTE_ROLES.map((role) => [role, color(role)])) as Record<
    (typeof PALETTE_ROLES)[number],
    ThemeColor
  >;
  return json.glow === undefined ? roles : { ...roles, glow: color("glow") };
}

function decodeTheme(value: unknown, path: string): AppTheme {
  const json = object(value, path);
  return {
    id: string(json.id, `${path}.id`),
    name: string(json.name, `${path}.name`),
    summary: string(json.summary, `${path}.summary`),
    family: oneOf(THEME_FAMILIES, json.family, `${path}.family`),
    palette: decodePalette(json.palette, `${path}.palette`),
    accents: oneOf(ACCENT_TREATMENTS, json.accents, `${path}.accents`),
    typeface: oneOf(THEME_TYPEFACES, json.typeface, `${path}.typeface`),
    motion: oneOf(THEME_MOTIONS, json.motion, `${path}.motion`),
    controls: oneOf(THEME_CONTROL_STYLES, json.controls, `${path}.controls`),
    surfaces: oneOf(THEME_SURFACE_STYLES, json.surfaces, `${path}.surfaces`),
  };
}

function decodeSheen(value: unknown, path: string): GlassSheen {
  const json = object(value, path);
  const color = (role: string) => decodeThemeColor(json[role], `${path}.${role}`);
  return {
    fillTop: color("fillTop"),
    fillBottom: color("fillBottom"),
    glint: color("glint"),
    rimTop: color("rimTop"),
    rimBottom: color("rimBottom"),
  };
}

const byKey = ([a]: [string, unknown], [b]: [string, unknown]) => (a < b ? -1 : a > b ? 1 : 0);

/** Parses and checks a themes file, throwing a ThemeFileError with the Swift loader's reason. */
export function decodeThemeFile(value: unknown): ThemeFile {
  const json = object(value, "");
  const schema = string(json.schema, "schema");
  const defaultTheme = string(json.defaultTheme, "defaultTheme");
  const legacyJson = object(json.legacyKitThemes, "legacyKitThemes");
  const legacyKitThemes: Record<string, ThemeID> = {};
  for (const [key, id] of Object.entries(legacyJson)) legacyKitThemes[key] = string(id, `legacyKitThemes.${key}`);
  const glassSheen = decodeSheen(json.glassSheen, "glassSheen");
  const themesJson: unknown = json.themes;
  if (!Array.isArray(themesJson)) invalid("themes", "an array");
  const themes = (themesJson as unknown[]).map((theme, index) => decodeTheme(theme, `themes[${index}]`));

  if (schema !== THEME_FILE_SCHEMA) throw new ThemeFileError({ kind: "unsupportedSchema", schema });
  const ids = new Set<ThemeID>();
  for (const theme of themes) {
    if (ids.has(theme.id)) throw new ThemeFileError({ kind: "duplicateTheme", id: theme.id });
    ids.add(theme.id);
  }
  const checkID = (id: ThemeID, path: string) => {
    if (!ids.has(id)) throw new ThemeFileError({ kind: "unknownTheme", path, id });
  };
  checkID(defaultTheme, "defaultTheme");
  for (const [key, id] of Object.entries(legacyKitThemes).sort(byKey)) checkID(id, `legacyKitThemes.${key}`);
  for (const id of REQUIRED_THEME_IDS) checkID(id, "themes");
  const checkColor = (color: ThemeColor, path: string) => {
    for (const name of ["red", "green", "blue", "opacity"] as const) {
      const component = color[name];
      if (!(component >= 0 && component <= 1)) {
        throw new ThemeFileError({ kind: "componentOutOfRange", path: `${path}.${name}`, value: component });
      }
    }
  };
  for (const role of GLASS_SHEEN_ROLES) checkColor(glassSheen[role], `glassSheen.${role}`);
  themes.forEach((theme, index) => {
    for (const [role, color] of paletteRoles(theme.palette)) checkColor(color, `themes[${index}].palette.${role}`);
  });
  return { schema, defaultTheme, legacyKitThemes, glassSheen, themes };
}
