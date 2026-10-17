import { afterEach, describe, expect, it } from "vitest";
import { resetLanguage } from "../../../src/core/localization/lookup";
import { adjustedSpring, FAST_SCALE } from "../../../src/core/motion/motionPace";
import { MotionTokens } from "../../../src/core/motion/motionTokens";
import { applyAccentTreatment, MINIMUM_ACCENT_CONTRAST } from "../../../src/core/themes/accentTreatment";
import {
  adjustedForThemeMotion,
  brightestSheen,
  resolveControlMaterial,
  REQUIRED_THEME_IDS,
  themeAccent,
  themeDisplayName,
  themeDisplaySummary,
  themeIdentityAccent,
  themeOnAccent,
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
  withOpacity,
  type ThemeColor,
} from "../../../src/core/themes/themeColor";
import { THEMES as SNAPSHOT_THEMES } from "../../snapshots/snapshot";
import { switchLanguage } from "../../support/catalogs";

/* Ports of ThemeCatalogTests, ThemeColorTests, AccentTreatmentTests and ControlMaterialTests. */

function theme(id: string) {
  const found = findTheme(id);
  if (!found) throw new Error(`no theme ${id}`);
  return found;
}

const STUDY = { red: 1, green: 0.62, blue: 0.26 };
const ANKI = { red: 0.36, green: 0.62, blue: 1.0 };

const SWEET_IDS = [
  "blueberryMilk",
  "strawberryMilk",
  "taro",
  "matchaLatte",
  "bananaMilk",
  "deepSea",
  "cherrySoda",
  "stargazer",
  "mintChoco",
  "cottonCandy",
];

describe("theme catalog", () => {
  it("ships every theme once in picker order", () => {
    expect(allThemes.map((t) => t.id)).toEqual([...REQUIRED_THEME_IDS, ...SWEET_IDS]);
    expect(new Set(allThemes.map((t) => t.name)).size).toBe(allThemes.length);
    expect(allThemes.filter((t) => t.family === "cozy").map((t) => t.id)).toEqual(["cozy", "sakura", "forest"]);
    /* Five to a row: the pastels, then each one's deep or duo partner right below it. */
    expect(allThemes.filter((t) => t.family === "sweet").map((t) => t.id)).toEqual(SWEET_IDS);
    expect(DEFAULT_THEME_ID).toBe("midnight");
  });

  it("snapshots every theme the catalog ships", () => {
    expect(SNAPSHOT_THEMES).toEqual(allThemes.map((t) => t.id));
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

  it("moves cozy and sweet themes gently and gives glass only to Liquid Glass", () => {
    for (const t of allThemes) {
      expect(t.motion === "gentle", t.name).toBe(t.family !== "classic");
      expect(t.controls === "glass", t.name).toBe(t.id === "liquidGlass");
      expect(t.surfaces === "glass", t.name).toBe(t.id === "liquidGlass");
    }
  });

  /*
   * A theme's key color is what the active module's ring, selected tab,
   * primary button and chips wear, so it must hold up on every card the
   * panel draws (flat or hovered, over the black top or the full glow):
   * WCAG 4.5:1 where it is text and 3:1 for the ring arc against its 20%
   * track; on-accent text keeps 4.5:1 on the solid fill and on the 88% fill
   * a button rests at.
   */
  it("keeps theme accents readable on every card", () => {
    const accented = allThemes.filter((t) => t.palette.accent !== undefined);
    expect(accented.length).toBeGreaterThanOrEqual(10);
    for (const t of accented) {
      const palette = t.palette;
      const accent = themeAccent(t, STUDY);
      expect(accent, t.name).toEqual(palette.accent);
      expect(accent.opacity, `${t.name} accent is opaque`).toBe(1);
      expect(palette.onAccent, `${t.name} sets onAccent with its accent`).toBeDefined();
      const black = palette.background;
      const glow = composited(palette.glow ?? black, black);
      for (const body of [black, glow]) {
        for (const surface of [palette.surface, palette.surfaceHover]) {
          const card = composited(surface, body);
          const label = `${t.name} on ${surface === palette.surface ? "surface" : "surfaceHover"}${body === black ? "" : " over the glow"}`;
          expect(contrast(accent, card), `${label}: accent as text`).toBeGreaterThanOrEqual(4.5);
          const track = composited(withOpacity(accent, 0.2), card);
          expect(contrast(accent, track), `${label}: ring arc vs track`).toBeGreaterThanOrEqual(3);
          const resting = composited(withOpacity(accent, 0.88), card);
          expect(contrast(composited(themeOnAccent(t), resting), resting), `${label}: on-accent text on a resting button`).toBeGreaterThanOrEqual(4.5);
        }
      }
      expect(contrast(themeOnAccent(t), accent), `${t.name} on-accent`).toBeGreaterThanOrEqual(4.5);
      /* Status colors keep their meaning: the accent never passes for one. */
      for (const status of [palette.success, palette.warning, palette.danger]) expect(accent, t.name).not.toEqual(status);
    }
  });

  /*
   * Themes without a key color draw exactly what they did before theme
   * accents existed: the treated module accent, and the black body as text
   * on it. Midnight, the default, is one of them.
   */
  it("keeps module accents in themes without an accent", () => {
    expect(theme("midnight").palette.accent).toBeUndefined();
    for (const t of allThemes.filter((t) => t.palette.accent === undefined)) {
      expect(themeAccent(t, STUDY), t.name).toEqual(applyAccentTreatment(t.accents, STUDY));
      expect(themeOnAccent(t), t.name).toEqual(t.palette.background);
      expect(t.palette.onAccent, t.name).toBeUndefined();
    }
  });

  /* The sweet family all own a key color, and module identity (icons listed side by side) still follows the treatment. */
  it("gives sweet themes their own accent and keeps module identity", () => {
    const sweet = allThemes.filter((t) => t.family === "sweet");
    expect(sweet.length).toBe(10);
    for (const t of sweet) {
      expect(t.palette.accent, t.name).toBeDefined();
      expect(themeAccent(t, STUDY), t.name).toEqual(themeAccent(t, ANKI));
      expect(themeIdentityAccent(t, STUDY), t.name).toEqual(applyAccentTreatment(t.accents, STUDY));
      expect(themeIdentityAccent(t, STUDY), t.name).not.toEqual(themeIdentityAccent(t, ANKI));
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

/* Port of LocalizationTests.testEveryThemeNameAndSummaryIsTranslated, through tr as the picker reads them. */
describe("theme names", () => {
  afterEach(resetLanguage);

  it("shows the name and summary as written before a language is loaded", () => {
    for (const t of allThemes) {
      expect(themeDisplayName(t)).toBe(t.name);
      expect(themeDisplaySummary(t)).toBe(t.summary);
    }
  });

  it("are in English under theme.<id>, and translated in German", () => {
    switchLanguage("en");
    for (const t of allThemes) {
      expect(themeDisplayName(t)).toBe(t.name);
      expect(themeDisplaySummary(t)).toBe(t.summary);
    }
    switchLanguage("de");
    expect(themeDisplayName(theme("strawberryMilk"))).toBe("Erdbeermilch");
    for (const t of allThemes) {
      expect(themeDisplaySummary(t), `de summary of ${t.id}`).not.toBe(t.summary);
    }
  });
});
