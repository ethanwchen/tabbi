import { describe, expect, it } from "vitest";
import { MotionTokens } from "../../../src/core/motion/motionTokens";
import { SYMBOL_ICONS } from "../../../src/core/symbols/symbols";
import { allThemes, resolveTheme } from "../../../src/core/themes/themeCatalog";
import { edgeFadeMask } from "../../../src/ui/kit/EdgeFade";
import { ICON_IDS, resolveIconId } from "../../../src/ui/kit/Icon";
import { adaptedTransition, springTransition, staggerDelay } from "../../../src/ui/kit/motion";
import { accentVariables, themeVariables } from "../../../src/ui/kit/tokens";
import { TrackSliderGeometry } from "../../../src/ui/kit/TrackSlider";

describe("kit tokens", () => {
  it("writes every palette color, the glow, the sheen and a spring per motion token for each theme", () => {
    for (const theme of allThemes) {
      const vars = themeVariables(theme);
      for (const name of ["--background", "--glow", "--surface", "--surface-hover", "--stroke", "--primary-text", "--secondary-text", "--tertiary-text", "--success", "--warning", "--danger", "--sheen-rim-top", "--font"]) {
        expect(vars[name], `${theme.id} ${name}`).toBeDefined();
      }
      expect(vars["--spring-snappy"]).toMatch(/^\d+ms linear\(/);
      if (theme.palette.glow) expect(vars["--glow"]).toMatch(/^rgb/);
      else expect(vars["--glow"]).toBe("transparent");
    }
  });

  it("treats a module accent as the theme does", () => {
    const midnight = accentVariables(resolveTheme("midnight"), { red: 1, green: 0.62, blue: 0.26 });
    expect(midnight["--accent"]).toBe("rgb(255 158 66 / 1)");
    expect(midnight["--accent-soft"]).toBe("rgb(255 158 66 / 0.16)");
    const mono = accentVariables(resolveTheme("monochrome"), { red: 1, green: 0.62, blue: 0.26 });
    expect(mono["--accent"]).toMatch(/^rgb\((\d+) \1 \1 \/ 1\)$/);
  });
});

describe("kit motion", () => {
  it("turns a spring into a linear() easing that ends on its target and keeps the overshoot", () => {
    const open = springTransition(MotionTokens.open);
    expect(open.duration).toBeGreaterThan(300);
    expect(open.easing.endsWith("1)")).toBe(true);
    const stops = open.easing.slice("linear(".length, -1).split(", ").map(Number);
    expect(Math.max(...stops)).toBeGreaterThan(1);
    const close = springTransition(MotionTokens.close);
    const closeStops = close.easing.slice("linear(".length, -1).split(", ").map(Number);
    expect(Math.max(...closeStops)).toBeLessThanOrEqual(1);
  });

  it("falls back to the crossfade under Reduce Motion and to nothing at Instant", () => {
    expect(adaptedTransition(MotionTokens.snappy, true)).toEqual({ duration: 180, easing: "ease-in-out" });
    expect(adaptedTransition(MotionTokens.snappy, false, "instant").duration).toBe(0);
    expect(staggerDelay(3, false)).toBe(90);
    expect(staggerDelay(9, false)).toBe(150);
    expect(staggerDelay(3, true)).toBe(0);
  });
});

describe("kit icons", () => {
  it("draws every id the symbol table names, and the placeholder for an unknown one", () => {
    const ids = new Set(ICON_IDS);
    for (const id of Object.values(SYMBOL_ICONS)) expect(ids.has(id), id).toBe(true);
    expect(resolveIconId("timer")).toBe("timer");
    expect(resolveIconId("pawprint.fill")).toBe("paw-filled");
    expect(resolveIconId("no.such.symbol")).toBe("placeholder");
  });
});

describe("TrackSliderGeometry", () => {
  it("keeps the knob on the track at both ends with its center under the pointer", () => {
    const g = new TrackSliderGeometry(100, 10);
    expect(g.knobOffset(0)).toBe(0);
    expect(g.knobOffset(1)).toBe(90);
    expect(g.fillWidth(0.5)).toBe(50);
    expect(g.fraction(5)).toBe(0);
    expect(g.fraction(95)).toBe(1);
    expect(g.fraction(50)).toBe(0.5);
    expect(g.fraction(-20)).toBe(0);
    expect(new TrackSliderGeometry(8, 10).fraction(4)).toBe(0);
  });
});

describe("EdgeFade", () => {
  it("fades the cut edge, with inline edges following the reading direction", () => {
    expect(edgeFadeMask("bottom", 16)).toBe("linear-gradient(to bottom, black calc(100% - 16px), transparent)");
    expect(edgeFadeMask("end", 16, "ltr")).toContain("to right");
    expect(edgeFadeMask("end", 16, "rtl")).toContain("to left");
  });
});
