import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import { ACCENT_TREATMENTS } from "../../../src/core/themes/accentTreatment";
import {
  BASE_THEME_FAMILIES,
  OPTIONAL_PALETTE_ROLES,
  PALETTE_ROLES,
  paletteRoles,
  REQUIRED_THEME_IDS,
  THEME_CONTROL_STYLES,
  THEME_FAMILIES,
  THEME_MOTIONS,
  THEME_SURFACE_STYLES,
  THEME_TYPEFACES,
  themeAccent,
  themeOnAccent,
} from "../../../src/core/themes/appTheme";
import { allThemes, standardGlassSheen, themeFile } from "../../../src/core/themes/themeCatalog";
import { gray, rgb } from "../../../src/core/themes/themeColor";
import { decodeThemeFile, ThemeFileError, type ThemeFileProblem } from "../../../src/core/themes/themeFile";
import { loadRepoJson } from "../../support/fixtures";

/* Port of ThemeFileTests: the format, the checks that stop a broken file, and the schema agreeing with the code. */

type Json = Record<string, unknown>;

const sheen = (): Json => ({
  fillTop: { white: 1, opacity: 0.1 },
  fillBottom: { white: 1 },
  glint: { white: 1 },
  rimTop: { white: 1 },
  rimBottom: { white: 1 },
});

function theme(id: string, glow?: Json, family = "classic", extra: { group?: unknown; accent?: Json } = {}): Json {
  return {
    id,
    name: id,
    summary: "A look.",
    family,
    ...(extra.group === undefined ? {} : { group: extra.group }),
    accents: "original",
    typeface: "rounded",
    motion: "standard",
    controls: "solid",
    surfaces: "flat",
    palette: {
      background: { white: 0 },
      ...(glow ? { glow } : {}),
      surface: { white: 1, opacity: 0.07 },
      surfaceHover: { white: 1, opacity: 0.12 },
      stroke: { white: 1, opacity: 0.08 },
      primaryText: { white: 1 },
      secondaryText: { white: 1, opacity: 0.62 },
      tertiaryText: { white: 1, opacity: 0.48 },
      success: { red: 0.3, green: 0.85, blue: 0.48 },
      warning: { red: 1, green: 0.74, blue: 0.28 },
      danger: { red: 1, green: 0.38, blue: 0.36 },
      ...extra.accent,
    },
  };
}

const requiredThemes = () => REQUIRED_THEME_IDS.map((id) => theme(id));

function file(options: { schema?: string; defaultTheme?: string; legacy?: Json; sheen?: Json; themes?: Json[] } = {}) {
  return {
    schema: options.schema ?? "themes.v1",
    defaultTheme: options.defaultTheme ?? "midnight",
    legacyKitThemes: options.legacy ?? { notch: "midnight" },
    glassSheen: options.sheen ?? sheen(),
    themes: options.themes ?? requiredThemes(),
  };
}

function problem(value: unknown): ThemeFileProblem | undefined {
  try {
    decodeThemeFile(value);
    return undefined;
  } catch (error) {
    if (error instanceof ThemeFileError) return error.problem;
    throw error;
  }
}

describe("themes.json loading", () => {
  it("decodes colors, glow and theme order", () => {
    const themes = requiredThemes();
    themes.splice(1, 0, theme("aurora", { red: 0.36, green: 0.38, blue: 0.42, opacity: 0.24 }, "cozy"));
    const decoded = decodeThemeFile(file({ themes }));
    expect(decoded.themes.map((t) => t.id)).toEqual(["midnight", "aurora", ...REQUIRED_THEME_IDS.slice(1)]);
    const aurora = decoded.themes[1];
    expect(aurora?.family).toBe("cozy");
    expect(aurora?.palette.glow).toEqual(rgb(0.36, 0.38, 0.42, 0.24));
    expect(decoded.themes[0]?.palette.glow).toBeUndefined();
    expect(aurora?.palette.surface).toEqual(gray(1, 0.07));
    expect(aurora?.palette.primaryText).toEqual(gray(1, 1));
    expect(decoded.glassSheen.fillTop).toEqual(gray(1, 0.1));
    expect(decoded.legacyKitThemes).toEqual({ notch: "midnight" });
  });

  it("rejects broken files with the Mac's reasons", () => {
    expect(problem(file({ schema: "themes.v2" }))).toEqual({ kind: "unsupportedSchema", schema: "themes.v2" });
    expect(problem(file({ defaultTheme: "aurora" }))).toEqual({
      kind: "unknownTheme",
      path: "defaultTheme",
      id: "aurora",
    });
    expect(problem(file({ legacy: { notch: "aurora" } }))).toEqual({
      kind: "unknownTheme",
      path: "legacyKitThemes.notch",
      id: "aurora",
    });
    expect(problem(file({ themes: [theme("midnight")] }))).toEqual({
      kind: "unknownTheme",
      path: "themes",
      id: "graphite",
    });
    expect(problem(file({ themes: [...requiredThemes(), theme("neon")] }))).toEqual({
      kind: "duplicateTheme",
      id: "neon",
    });
    const glowing = [theme("midnight", { white: 1, opacity: 1.2 }), ...REQUIRED_THEME_IDS.slice(1).map((id) => theme(id))];
    expect(problem(file({ themes: glowing }))).toEqual({
      kind: "componentOutOfRange",
      path: "themes[0].palette.glow.opacity",
      value: 1.2,
    });
    expect(problem(file({ sheen: { ...sheen(), glint: { white: -0.5 } } }))).toEqual({
      kind: "componentOutOfRange",
      path: "glassSheen.glint.red",
      value: -0.5,
    });
    /* Unknown names and missing colors are decoding errors. */
    expect(problem(file({ themes: [theme("midnight", undefined, "retro")] }))?.kind).toBe("invalid");
    expect(problem({ schema: "themes.v1" })?.kind).toBe("invalid");
  });

  /*
   * `group` refines `family` in builds that know it, and a group from a
   * newer build falls back to `family`, so the file stays readable by every
   * build; `family` itself stays a value older builds know.
   */
  it("refines the family with group and falls back to it", () => {
    const themes = [...requiredThemes(), theme("candy", undefined, "cozy", { group: "sweet" }), theme("comet", undefined, "cozy", { group: "space" })];
    const decoded = decodeThemeFile(file({ themes }));
    expect(decoded.themes.find((t) => t.id === "candy")?.family).toBe("sweet");
    expect(decoded.themes.find((t) => t.id === "comet")?.family).toBe("cozy");
    expect(problem(file({ themes: [...requiredThemes(), theme("candy", undefined, "sweet")] }))?.kind).toBe("invalid");
  });

  /* A theme accent and its on-accent color are optional palette roles; without them the theme behaves as before. */
  it("decodes the optional theme accent", () => {
    const accent = { accent: { red: 1, green: 0.7, blue: 0.82 }, onAccent: { red: 0.29, green: 0.06, blue: 0.16 } };
    const themes = [...requiredThemes(), theme("candy", undefined, "cozy", { group: "sweet", accent })];
    const decoded = decodeThemeFile(file({ themes }));
    const candy = decoded.themes.at(-1);
    if (!candy) throw new Error("no candy");
    expect(candy.palette.accent).toEqual(rgb(1, 0.7, 0.82));
    expect(themeOnAccent(candy)).toEqual(rgb(0.29, 0.06, 0.16));
    expect(themeAccent(candy, { red: 0.2, green: 0.6, blue: 0.5 })).toEqual(candy.palette.accent);
    expect(paletteRoles(candy.palette).slice(-2).map(([role]) => role)).toEqual(["accent", "onAccent"]);
    const plain = decoded.themes[0];
    if (!plain) throw new Error("no plain");
    expect(plain.palette.accent).toBeUndefined();
    expect(themeOnAccent(plain)).toEqual(plain.palette.background);
    expect(paletteRoles(plain.palette).some(([role]) => role === "accent" || role === "onAccent")).toBe(false);
    const broken = [theme("midnight", undefined, "classic", { accent: { accent: { white: 1.5 } } }), ...REQUIRED_THEME_IDS.slice(1).map((id) => theme(id))];
    expect(problem(file({ themes: broken }))).toEqual({
      kind: "componentOutOfRange",
      path: "themes[0].palette.accent.red",
      value: 1.5,
    });
  });

  /* The bundled file keeps every theme readable by builds from before theme accents and groups: `family` is always one they know. */
  it("keeps the bundled file readable by older builds", () => {
    const bundled = loadRepoJson<{ themes: Json[] }>("Sources/TabbiKitCore/Themes/themes.json");
    for (const t of bundled.themes) {
      expect(BASE_THEME_FAMILIES as readonly unknown[], String(t.id)).toContain(t.family);
      expect(ACCENT_TREATMENTS as readonly unknown[], String(t.id)).toContain(t.accents);
    }
  });

  it("explains a problem in plain words", () => {
    expect(() => decodeThemeFile(file({ schema: "themes.v2" }))).toThrow(
      'Unsupported schema "themes.v2"; expected "themes.v1"',
    );
    expect(() => decodeThemeFile(file({ defaultTheme: "aurora" }))).toThrow('defaultTheme: no theme "aurora"');
  });

  it("defines the catalog from the bundled file", () => {
    expect(allThemes.map((t) => t.id).slice(0, REQUIRED_THEME_IDS.length)).toEqual(REQUIRED_THEME_IDS);
    expect(themeFile.defaultTheme).toBe("midnight");
    expect(standardGlassSheen).toEqual(themeFile.glassSheen);
  });
});

describe("themes.v1 schema", () => {
  const schema = loadRepoJson<Json>("shared/schemas/themes.v1.schema.json");

  it("accepts the bundled themes.json and rejects a broken one", () => {
    const validate = new Ajv2020({ allErrors: true }).compile(schema);
    const bundled = loadRepoJson("Sources/TabbiKitCore/Themes/themes.json");
    expect(validate(bundled), JSON.stringify(validate.errors)).toBe(true);
    expect(validate(file())).toBe(true);
    expect(validate(file({ themes: [theme("midnight", undefined, "retro")] }))).toBe(false);
  });

  it("lists the same values and palette roles as the code", () => {
    const defs = schema.$defs as Record<string, Json>;
    const properties = (defs.theme?.properties ?? {}) as Record<string, Json>;
    const values = (key: string) => properties[key]?.enum;
    expect(values("family")).toEqual([...BASE_THEME_FAMILIES]);
    expect(values("group")).toEqual(THEME_FAMILIES.filter((f) => !(BASE_THEME_FAMILIES as readonly string[]).includes(f)));
    expect(values("accents")).toEqual([...ACCENT_TREATMENTS]);
    expect(values("typeface")).toEqual([...THEME_TYPEFACES]);
    expect(values("motion")).toEqual([...THEME_MOTIONS]);
    expect(values("controls")).toEqual([...THEME_CONTROL_STYLES]);
    expect(values("surfaces")).toEqual([...THEME_SURFACE_STYLES]);
    const palette = properties.palette ?? {};
    expect(Object.keys((palette.properties ?? {}) as Json).sort()).toEqual([...PALETTE_ROLES, ...OPTIONAL_PALETTE_ROLES].sort());
    const full = allThemes.find((t) => t.palette.glow !== undefined && t.palette.accent !== undefined);
    expect(full).toBeDefined();
    if (full) expect(paletteRoles(full.palette).map(([role]) => role).sort()).toEqual([...PALETTE_ROLES, ...OPTIONAL_PALETTE_ROLES].sort());
    expect([...((palette.required ?? []) as string[])].sort()).toEqual([...PALETTE_ROLES].sort());
  });
});
