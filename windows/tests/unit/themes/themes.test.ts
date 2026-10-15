import { describe, expect, it } from "vitest";
import { adjustedSpring, FAST_SCALE } from "../../../src/core/motion/motionPace";
import { MotionTokens } from "../../../src/core/motion/motionTokens";
import { applyAccentTreatment, MINIMUM_ACCENT_CONTRAST } from "../../../src/core/themes/accentTreatment";
import {
  adjustedForThemeMotion,
  brightestSheen,
  resolveControlMaterial,
  REQUIRED_THEME_IDS,
} from "../../../src/core/themes/appTheme";
import {
  allThemes,
  DEFAULT_THEME_ID,
  findTheme,
  resolveTheme,
  standardGlassSheen,
  themeIdForKitValue,
} from "../../../src/core/themes/themeCatalog";
import {
  accentColor,
  composited,
  contrast,
  gray,
  luminance,
  mixed,
  rgb,
  type ThemeColor,
} from "../../../src/core/themes/themeColor";

/* Ports of ThemeCatalogTests, ThemeColorTests, AccentTreatmentTests and ControlMaterialTests. */

function theme(id: string) {
  const found = findTheme(id);
  if (!found) throw new Error(`no theme ${id}`);
  return found;
}

describe("theme catalog", () => {
  it("ships every theme once in picker order", () => {
    expect(allThemes.map((t) => t.id)).toEqual(REQUIRED_THEME_IDS);
    expect(new Set(allThemes.map((t) => t.name)).size).toBe(allThemes.length);
    expect(allThemes.filter((t) => t.family === "cozy").map((t) => t.id)).toEqual(["cozy", "sakura", "forest"]);
    expect(DEFAULT_THEME_ID).toBe("midnight");
  });

  it("keeps every panel body opaque black, with at most a hint of glow", () => {
    for (const t of allThemes) {
      expect(t.palette.background, t.name).toEqual(gray(0));
      if (t.palette.glow) expect(t.palette.glow.opacity, t.name).toBeLessThanOrEqual(0.3);
    }
  });

  it("keeps text readable on every card, with a clear step between secondary and tertiary", () => {
    for (const t of allThemes) {
      const palette = t.palette;
      const body = composited(palette.glow ?? palette.background, palette.background);
      const card = composited(palette.surfaceHover, body);
      const on = (text: ThemeColor) => contrast(composited(text, card), card);
      expect(on(palette.primaryText), `${t.name} primary`).toBeGreaterThanOrEqual(7);
      expect(on(palette.secondaryText), `${t.name} secondary`).toBeGreaterThanOrEqual(6);
      expect(on(palette.tertiaryText), `${t.name} tertiary`).toBeGreaterThanOrEqual(4.5);
      expect(on(palette.secondaryText), `${t.name} hierarchy`).toBeGreaterThan(on(palette.tertiaryText) + 1);
    }
  });

  it("moves cozy themes gently and gives glass only to Liquid Glass", () => {
    for (const t of allThemes) {
      expect(t.motion === "gentle", t.name).toBe(t.family === "cozy");
      expect(t.controls === "glass", t.name).toBe(t.id === "liquidGlass");
      expect(t.surfaces === "glass", t.name).toBe(t.id === "liquidGlass");
    }
  });

  it("lights glass from above, brighter than a flat card", () => {
    const sheen = standardGlassSheen;
    const black = gray(0);
    expect(sheen.fillTop.opacity).toBeGreaterThan(sheen.fillBottom.opacity);
    expect(sheen.rimTop.opacity).toBeGreaterThan(sheen.rimBottom.opacity);
    const flatCard = composited(theme("midnight").palette.surface, black);
    expect(luminance(composited(sheen.fillTop, black))).toBeGreaterThan(luminance(flatCard) * 2);
    expect(sheen.rimTop.opacity).toBeGreaterThan(theme("midnight").palette.stroke.opacity * 4);
  });

  it("keeps text readable on the brightest glass", () => {
    const palette = theme("liquidGlass").palette;
    const body = composited(palette.glow ?? palette.background, palette.background);
    const brightest = brightestSheen(standardGlassSheen, body);
    const on = (text: ThemeColor) => contrast(composited(text, brightest), brightest);
    expect(on(palette.primaryText)).toBeGreaterThanOrEqual(7);
    expect(on(palette.secondaryText)).toBeGreaterThanOrEqual(4.5);
    expect(on(palette.tertiaryText)).toBeGreaterThanOrEqual(4.5);
  });

  it("plays every spring slower and calmer in gentle motion", () => {
    const { open, close, hover, snappy, content, press, check } = MotionTokens;
    for (const spec of [open, close, hover, snappy, content, press, check]) {
      expect(adjustedForThemeMotion("standard", spec)).toEqual(spec);
      const gentle = adjustedForThemeMotion("gentle", spec);
      expect(gentle.duration).toBeGreaterThan(spec.duration);
      expect(gentle.peak).toBeLessThanOrEqual(spec.peak);
      expect(gentle.bounce).toBeGreaterThanOrEqual(0);
    }
    /* The close still lands with no overshoot. */
    expect(adjustedForThemeMotion("gentle", close).overshoots).toBe(false);
  });

  it("composes gentle motion with the Fast pace", () => {
    const gentle = adjustedForThemeMotion("gentle", MotionTokens.open);
    expect(adjustedSpring("fast", gentle)?.duration).toBeCloseTo(gentle.duration * FAST_SCALE, 9);
  });

  it("resolves unknown ids to the default", () => {
    expect(findTheme("aurora")).toBeUndefined();
    expect(resolveTheme("aurora").id).toBe(DEFAULT_THEME_ID);
    expect(resolveTheme("forest").name).toBe("Forest");
  });

  it("accepts the old notch name in kits", () => {
    expect(themeIdForKitValue("notch")).toBe("midnight");
    expect(themeIdForKitValue("cozy")).toBe("cozy");
    expect(themeIdForKitValue("aurora")).toBeUndefined();
    expect(themeIdForKitValue("toString")).toBeUndefined();
  });
});

describe("theme color", () => {
  it("matches WCAG contrast", () => {
    expect(contrast(gray(1), gray(0))).toBeCloseTo(21, 2);
    expect(contrast(gray(0.5), gray(0.5))).toBeCloseTo(1, 3);
  });

  it("composites and mixes", () => {
    expect(composited(gray(1, 0.5), gray(0))).toEqual(gray(0.5));
    expect(mixed(rgb(1, 0, 0), rgb(0, 0, 1), 0.25)).toEqual(rgb(0.75, 0, 0.25));
  });
});

describe("accent treatment", () => {
  const teal = { red: 0.2, green: 0.6, blue: 0.5 };

  it("keeps the module accent in original", () => {
    expect(applyAccentTreatment("original", teal)).toEqual(accentColor(teal));
  });

  it("makes monochrome a light gray", () => {
    const g = applyAccentTreatment("monochrome", teal);
    expect(g.red).toBe(g.green);
    expect(g.green).toBe(g.blue);
    expect(g.red).toBeGreaterThan(0.55);
    expect(g.red).toBeLessThanOrEqual(0.95);
  });

  it("keeps the hue at full saturation in vivid", () => {
    const vivid = applyAccentTreatment("vivid", teal);
    expect(vivid.red).toBeCloseTo(0, 4);
    expect(vivid.green).toBeCloseTo(1, 4);
    expect(vivid.blue).toBeCloseTo(0.75, 4);
    expect(applyAccentTreatment("vivid", { red: 0.4, green: 0.4, blue: 0.4 })).toEqual(gray(1));
  });

  it("lifts dark vivid hues until they read on black", () => {
    const vivid = applyAccentTreatment("vivid", { red: 0.45, green: 0.35, blue: 0.95 });
    expect(contrast(vivid, gray(0))).toBeGreaterThanOrEqual(MINIMUM_ACCENT_CONTRAST);
    expect(vivid.blue).toBeGreaterThan(vivid.red);
    expect(vivid.red).toBeGreaterThan(vivid.green);
  });

  it("makes pastel lighter and warmer", () => {
    const pastel = applyAccentTreatment("pastel", teal);
    expect(luminance(pastel)).toBeGreaterThan(luminance(accentColor(teal)));
    expect(pastel.red).toBeGreaterThan(teal.red);
  });
});

describe("control material", () => {
  it("uses glass only where the system has it and transparency is allowed", () => {
    expect(resolveControlMaterial("glass", true, false)).toBe("glass");
    expect(resolveControlMaterial("glass", false, false)).toBe("material");
    expect(resolveControlMaterial("glass", true, true)).toBe("opaque");
    expect(resolveControlMaterial("glass", false, true)).toBe("opaque");
  });

  it("keeps solid themes on their opaque surface", () => {
    expect(resolveControlMaterial("solid", true, false)).toBe("opaque");
  });
});
