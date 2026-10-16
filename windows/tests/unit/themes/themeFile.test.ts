import Ajv2020 from "ajv/dist/2020";
import { describe, expect, it } from "vitest";
import { ACCENT_TREATMENTS } from "../../../src/core/themes/accentTreatment";
import {
  PALETTE_ROLES,
  REQUIRED_THEME_IDS,
  THEME_CONTROL_STYLES,
  THEME_FAMILIES,
  THEME_MOTIONS,
  THEME_SURFACE_STYLES,
  THEME_TYPEFACES,
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

function theme(id: string, glow?: Json, family = "classic"): Json {
  return {
    id,
    name: id,
    summary: "A look.",
    family,
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

  it("explains a problem in plain words", () => {
    expect(() => decodeThemeFile(file({ schema: "themes.v2" }))).toThrow(
      'Unsupported schema "themes.v2"; expected "themes.v1"',
    );
    expect(() => decodeThemeFile(file({ defaultTheme: "aurora" }))).toThrow('defaultTheme: no theme "aurora"');
  });

  it("defines the catalog from the bundled file", () => {
    expect(allThemes.map((t) => t.id)).toEqual(REQUIRED_THEME_IDS);
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
    expect(values("family")).toEqual([...THEME_FAMILIES]);
    expect(values("accents")).toEqual([...ACCENT_TREATMENTS]);
    expect(values("typeface")).toEqual([...THEME_TYPEFACES]);
    expect(values("motion")).toEqual([...THEME_MOTIONS]);
    expect(values("controls")).toEqual([...THEME_CONTROL_STYLES]);
    expect(values("surfaces")).toEqual([...THEME_SURFACE_STYLES]);
    const palette = properties.palette ?? {};
    expect(Object.keys((palette.properties ?? {}) as Json).sort()).toEqual([...PALETTE_ROLES, "glow"].sort());
    expect([...((palette.required ?? []) as string[])].sort()).toEqual([...PALETTE_ROLES].sort());
  });
});
