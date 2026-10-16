import { describe, expect, it } from "vitest";
import { CANVAS, HIDDEN, OPEN, PILL, PILL_HOVERED, hitRect, notchPath, openSilhouette, pillSilhouette } from "../../src/ui/shell/geometry";
import { MOTION, stepSpring, type SpringValue } from "../../src/ui/shell/spring";
import { BUNDLED_KITS } from "../../src/core/kits/bundledKits";
import { kitLayout } from "../../src/core/kits/kitApplication";
import { ModuleCatalog } from "../../src/core/modules/moduleCatalog";
import { panelCanvasSize } from "../../src/core/settings/panelSize";
import { resolveTheme } from "../../src/core/themes/themeCatalog";
import { MODULE_LIST } from "../../src/modules/moduleList";
import { themeVariables } from "../../src/ui/kit/tokens";

describe("geometry", () => {
  it("matches the Mac's sizes", () => {
    expect(OPEN).toEqual({ width: 560, height: 236, topRadius: 12, bottomRadius: 26 });
    expect(PILL).toEqual({ width: 202, height: 32, topRadius: 6, bottomRadius: 10 });
    expect(PILL_HOVERED).toMatchObject({ width: 218, height: 36 });
  });

  it("draws NotchShape's path, centered in the canvas", () => {
    expect(notchPath(OPEN)).toBe(
      "M 0 0 Q 12 0 12 12 L 12 210 Q 12 236 38 236 L 522 236 Q 548 236 548 210 L 548 12 Q 548 0 560 0 Z",
    );
    expect(notchPath(PILL)).toBe(
      "M 179 0 Q 185 0 185 6 L 185 22 Q 185 32 195 32 L 365 32 Q 375 32 375 22 L 375 6 Q 375 0 381 0 Z",
    );
  });

  it("clamps the radii on a small shape, as the Swift path does", () => {
    /* 8 px tall: the flare is at most h/2 = 4, the corner at most h - t = 4. */
    const path = notchPath({ ...PILL, height: 8 });
    expect(path).toBe("M 179 0 Q 183 0 183 4 L 183 4 Q 183 8 187 8 L 373 8 Q 377 8 377 4 L 377 4 Q 377 0 381 0 Z");
  });

  it("draws nothing at zero height", () => {
    expect(notchPath(HIDDEN)).toBe("");
  });

  it("gives the pill a hit area that covers its hovered size plus the 4 px slop", () => {
    expect(hitRect("pill")).toEqual({ x: 167, y: 0, width: 226, height: 40 });
    expect(hitRect("open")).toEqual({ x: 0, y: 0, width: CANVAS.width, height: CANVAS.height });
  });
});

describe("spring", () => {
  function run(spec: { duration: number; bounce: number }, from: number, to: number) {
    const spring: SpringValue = { value: from, velocity: 0 };
    let time = 0;
    let peak = from;
    while (!stepSpring(spring, to, spec, 1 / 60)) {
      time += 1 / 60;
      peak = Math.max(peak, spring.value);
      if (time > 5) throw new Error("never settled");
    }
    return { time, peak, value: spring.value };
  }

  it("closes with no overshoot and comes to rest exactly on the target", () => {
    const { peak, value } = run(MOTION.close, 0, 236);
    expect(peak).toBeLessThanOrEqual(236);
    expect(value).toBe(236);
  });

  it("opens with the Mac's small bounce and settles within about a second", () => {
    const { peak, time } = run(MOTION.open, 0, 236);
    expect(peak).toBeGreaterThan(236);
    expect(peak).toBeLessThan(236 * 1.03);
    expect(time).toBeLessThan(1.1);
  });

  it("reaches 95 percent of the way within the spring's duration", () => {
    const spring: SpringValue = { value: 0, velocity: 0 };
    let elapsed = 0;
    while (spring.value < 0.95 * 236) {
      stepSpring(spring, 236, MOTION.close, 1 / 120);
      elapsed += 1 / 120;
    }
    expect(elapsed).toBeLessThanOrEqual(MOTION.close.duration);
  });
});

describe("theme", () => {
  it("turns the default theme into the kit's variables", () => {
    const variables = themeVariables(resolveTheme("midnight"));
    expect(variables["--background"]).toBe("rgb(0 0 0 / 1)");
    expect(variables["--secondary-text"]).toBe("rgb(255 255 255 / 0.62)");
    expect(variables["--surface-hover"]).toBe("rgb(255 255 255 / 0.12)");
  });
});

describe("kit layout", () => {
  it("puts the Essentials modules in kit order, with the Closet as the header shortcut", () => {
    const catalog = new ModuleCatalog(MODULE_LIST.map((type) => type.descriptor));
    const essentials = BUNDLED_KITS.get("essentials");
    if (essentials === undefined) throw new Error("Essentials is bundled");
    const layout = kitLayout(essentials, catalog);
    expect(layout.tabs).toEqual(["study", "planner", "spotify", "claudeAsk"]);
    expect(layout.headerShortcuts).toEqual(["closet"]);
  });
});

describe("panel sizes and the pill's wings", () => {
  it("opens to each panel size's canvas", () => {
    expect(openSilhouette(panelCanvasSize("large"))).toEqual({ width: 640, height: 272, topRadius: 12, bottomRadius: 26 });
    expect(hitRect("open", panelCanvasSize("compact"))).toEqual({ x: 0, y: 0, width: 512, height: 224 });
  });

  it("widens the pill by a wing on each side and keeps its region around the hovered size", () => {
    expect(pillSilhouette(0, false)).toEqual(PILL);
    expect(pillSilhouette(40, false).width).toBe(PILL.width + 80);
    expect(pillSilhouette(40, true)).toMatchObject({ width: PILL.width + 96, height: 36 });
    expect(hitRect("pill", CANVAS, 40)).toEqual({ x: 127, y: 0, width: 306, height: 40 });
  });
});
