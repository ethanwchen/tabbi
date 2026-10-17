import { describe, expect, it } from "vitest";
import { ACCENT_TREATMENTS, applyAccentTreatment } from "../../src/core/themes/accentTreatment";
import { GLASS_SHEEN_ROLES, paletteRoles, themeAccent, themeIdentityAccent, themeOnAccent } from "../../src/core/themes/appTheme";
import { allThemes, DEFAULT_THEME_ID, standardGlassSheen, themeFile } from "../../src/core/themes/themeCatalog";
import type { ThemeColor } from "../../src/core/themes/themeColor";
import { loadFixture } from "../support/fixtures";

/*
 * Replays shared/fixtures/themes/themes.json, written by ThemeGoldenTests on
 * the Mac: every resolved theme, the glass sheen and every accent treatment,
 * each color component within 1e-9 (the fixture's README).
 */

interface GoldenColor {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
  readonly opacity: number;
}

interface GoldenTheme {
  readonly id: string;
  readonly name: string;
  readonly summary: string;
  readonly family: string;
  readonly accents: string;
  readonly typeface: string;
  readonly motion: string;
  readonly controls: string;
  readonly surfaces: string;
  /* glow, accent and onAccent are absent when the theme doesn't set them. */
  readonly palette: Readonly<Record<string, GoldenColor>>;
  /* What the theme draws for RESOLVED_SAMPLE: accent, identityAccent and onAccent. */
  readonly resolved: Readonly<Record<string, GoldenColor>>;
}

/* The module accent each theme's `resolved` colors are drawn for: Study's amber, the brand color. */
const RESOLVED_SAMPLE = { red: 1.0, green: 0.62, blue: 0.26 };

interface Golden {
  readonly schema: string;
  readonly version: number;
  readonly defaultTheme: string;
  readonly legacyKitThemes: Readonly<Record<string, string>>;
  readonly glassSheen: Readonly<Record<string, GoldenColor>>;
  readonly themes: readonly GoldenTheme[];
  readonly accentSamples: readonly {
    readonly base: GoldenColor;
    readonly treated: Readonly<Record<string, GoldenColor>>;
  }[];
}

const golden = loadFixture<Golden>("themes/themes.json");

function expectColor(actual: ThemeColor | undefined, expected: GoldenColor | undefined, label: string): void {
  expect(actual, label).toBeDefined();
  expect(expected, label).toBeDefined();
  if (!actual || !expected) return;
  for (const name of ["red", "green", "blue", "opacity"] as const) {
    expect(Math.abs(actual[name] - expected[name]), `${label}.${name}: ${actual[name]} vs ${expected[name]}`).toBeLessThan(
      1e-9,
    );
  }
}

describe("themes fixture", () => {
  it("is the golden file this suite reads", () => {
    expect(golden.schema).toBe("tabbi.themes.golden");
    expect(golden.version).toBe(1);
  });

  it("has the default theme and the old kit values", () => {
    expect(DEFAULT_THEME_ID).toBe(golden.defaultTheme);
    expect(themeFile.legacyKitThemes).toEqual(golden.legacyKitThemes);
  });

  it("resolves every theme in picker order", () => {
    expect(allThemes.map((t) => t.id)).toEqual(golden.themes.map((t) => t.id));
    golden.themes.forEach((expected, index) => {
      const theme = allThemes[index];
      expect(theme).toBeDefined();
      if (!theme) return;
      const { palette, ...fields } = theme;
      const { palette: expectedPalette, resolved: expectedResolved, ...expectedFields } = expected;
      expect(fields, theme.id).toEqual(expectedFields);
      const roles = Object.fromEntries(paletteRoles(palette));
      expect(Object.keys(roles).sort(), `${theme.id} roles (glow, accent and onAccent only when set)`).toEqual(
        Object.keys(expectedPalette).sort(),
      );
      for (const [role, color] of Object.entries(expectedPalette)) {
        expectColor(roles[role], color, `${theme.id}.palette.${role}`);
      }
      const resolved: Record<string, ThemeColor> = {
        accent: themeAccent(theme, RESOLVED_SAMPLE),
        identityAccent: themeIdentityAccent(theme, RESOLVED_SAMPLE),
        onAccent: themeOnAccent(theme),
      };
      expect(Object.keys(expectedResolved).sort(), `${theme.id} resolved`).toEqual(Object.keys(resolved).sort());
      for (const [name, color] of Object.entries(expectedResolved)) {
        expectColor(resolved[name], color, `${theme.id}.resolved.${name}`);
      }
    });
  });

  it("draws the glass sheen", () => {
    expect(Object.keys(golden.glassSheen).sort()).toEqual([...GLASS_SHEEN_ROLES].sort());
    for (const role of GLASS_SHEEN_ROLES) {
      expectColor(standardGlassSheen[role], golden.glassSheen[role], `glassSheen.${role}`);
    }
  });

  it("treats every sample accent the same way", () => {
    expect(golden.accentSamples.length).toBeGreaterThan(0);
    golden.accentSamples.forEach((sample, index) => {
      expect(Object.keys(sample.treated).sort()).toEqual([...ACCENT_TREATMENTS].sort());
      for (const treatment of ACCENT_TREATMENTS) {
        expectColor(
          applyAccentTreatment(treatment, sample.base),
          sample.treated[treatment],
          `accentSamples[${index}].${treatment}`,
        );
      }
    });
  });
});
