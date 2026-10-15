import { describe, expect, it } from "vitest";
import { DEFAULT_HEADER_METRICS, NotchHeaderLayout } from "../../../src/core/modules/notchHeaderLayout";
import { insetBy, intersects, maxX, maxY, rect } from "../../../src/core/modules/rect";
import { PANEL_SIZES, panelCanvasSize, type PanelSize } from "../../../src/core/settings/panelSize";

const canvas = 560;
const header = 32;
type Notch = { width: number; height: number } | undefined;
/* Real notch widths (narrow, 14"/16" MacBook Pro, wide) and a notchless display, the Windows case. */
const notches: Notch[] = [{ width: 160, height: 32 }, { width: 185, height: 32 }, { width: 210, height: 38 }, undefined];
const metrics = DEFAULT_HEADER_METRICS;
const pro = { width: 185, height: 32 };

function layout(tabs: number, notch: Notch, shortcuts = 1, title = 90): NotchHeaderLayout {
  return new NotchHeaderLayout({
    canvasWidth: canvas,
    notchSize: notch,
    headerHeight: Math.max(notch?.height ?? 0, header),
    tabCount: tabs,
    shortcutCount: shortcuts,
    titleWidth: title,
  });
}

function sized(size: PanelSize, tabs: number): NotchHeaderLayout {
  return new NotchHeaderLayout({
    canvasWidth: panelCanvasSize(size).width,
    notchSize: pro,
    headerHeight: 32,
    tabCount: tabs,
    shortcutCount: 1,
    titleWidth: 76,
  });
}

describe("NotchHeaderLayout", () => {
  it("keeps every control clear of the center at any tab count", () => {
    for (const notch of notches) {
      for (let tabs = 1; tabs <= 12; tabs++) {
        for (const shortcuts of [0, 1]) {
          const result = layout(tabs, notch, shortcuts);
          const label = `${tabs} tabs, ${shortcuts} shortcuts, notch ${notch?.width ?? "none"}`;
          /* The cutout plus its safe margin, or the bare center on a notchless display. */
          const keepOut = result.cutout ? insetBy(result.cutout, -metrics.cutoutMargin, 0) : rect(canvas / 2, 0, 0, 32);
          for (const frame of result.controlFrames) {
            expect(intersects(frame, keepOut), label).toBe(false);
            expect(frame.x, label).toBeGreaterThanOrEqual(metrics.outerInset);
            expect(maxX(frame), label).toBeLessThanOrEqual(canvas - metrics.outerInset);
          }
          for (const tab of [...result.tabFrames, ...(result.moreFrame ? [result.moreFrame] : [])]) {
            expect(tab.width, label).toBeGreaterThanOrEqual(metrics.minTabWidth);
            expect(tab.height, label).toBeGreaterThanOrEqual(24);
            expect(maxX(tab), label).toBeLessThanOrEqual(maxX(result.leadingZone));
          }
          expect(result.hasOverflow, label).toBe(result.visibleTabCount < tabs);
          expect(result.visibleTabCount, label).toBeGreaterThan(0);
          expect(result.shortcutFrames.length, label).toBe(shortcuts);
        }
      }
    }
  });

  it("never overlaps two controls", () => {
    for (const notch of notches) {
      for (let tabs = 1; tabs <= 12; tabs++) {
        const frames = layout(tabs, notch).controlFrames;
        frames.forEach((frame, index) => {
          for (const other of frames.slice(index + 1)) expect(intersects(frame, other), `${tabs} tabs`).toBe(false);
        });
      }
    }
  });

  it("keeps few tabs at full size", () => {
    const result = layout(4, pro);
    expect(result.tabWidth).toBe(28);
    expect(result.tabSpacing).toBe(2);
    expect(result.hasOverflow).toBe(false);
  });

  it("tightens tabs before they overflow", () => {
    const five = layout(5, pro);
    expect(five.hasOverflow).toBe(false);
    expect(five.tabWidth).toBeLessThan(28);
    const six = layout(6, pro);
    expect(six.hasOverflow).toBe(false);
    expect(six.tabWidth).toBe(24);
    expect(six.tabSpacing).toBe(0);
  });

  it("moves tabs that don't fit behind more", () => {
    const result = layout(10, pro);
    expect(result.hasOverflow).toBe(true);
    expect(result.visibleTabCount).toBe(5);
    const last = result.tabFrames[result.tabFrames.length - 1];
    expect(result.moreFrame?.x).toBe(last ? maxX(last) : NaN);
  });

  it("opens the overflow list below the notch and the more button", () => {
    for (const notch of notches) {
      const result = layout(10, notch);
      const more = result.moreFrame;
      const top = result.moreListTop;
      expect(more).toBeDefined();
      expect(top).toBeDefined();
      if (!more || top === undefined) continue;
      expect(top).toBeGreaterThan(maxY(more));
      expect(top).toBeGreaterThan(result.cutout ? maxY(result.cutout) : 0);
    }
    expect(layout(3, pro).moreListTop).toBeUndefined();
  });

  it("keeps hidden tabs in order and marks more while one is open", () => {
    const result = layout(8, pro);
    const tabs = ["now", "system", "usage", "today", "ask", "focus", "anki", "party"];
    expect(result.overflowTabs(tabs)).toEqual(tabs.slice(result.visibleTabCount));
    expect(result.overflowTabs(tabs).length + result.visibleTabCount).toBe(tabs.length);
    expect(result.overflowSelection(tabs, "party")).toBe("party");
    expect(result.overflowSelection(tabs, "now")).toBeUndefined();
    expect(result.overflowSelection(tabs, undefined)).toBeUndefined();
    const roomy = layout(3, undefined);
    expect(roomy.overflowTabs(["a", "b", "c"])).toEqual([]);
    expect(roomy.overflowSelection(["a", "b", "c"], "c")).toBeUndefined();
  });

  it("follows the panel width when tabs overflow", () => {
    for (const size of PANEL_SIZES) {
      expect(sized(size, 5).hasOverflow, size).toBe(false);
      expect(sized(size, 5).tabWidth).toBeGreaterThanOrEqual(metrics.minTabWidth);
    }
    const compact = sized("compact", 8);
    expect(compact.hasOverflow).toBe(true);
    expect(compact.visibleTabCount).toBe(4);
    expect(compact.shortcutFrames.length).toBe(1);
    const paw = compact.shortcutFrames[0];
    expect(paw && maxX(compact.gearFrame) < paw.x).toBe(true);
    for (const size of PANEL_SIZES) {
      for (let tabs = 1; tabs <= 12; tabs++) {
        const shown = sized(size, tabs);
        expect(shown.visibleTabCount).toBeGreaterThan(0);
        expect(shown.hasOverflow).toBe(shown.visibleTabCount < tabs);
        expect(sized("large", tabs).visibleTabCount).toBeGreaterThanOrEqual(shown.visibleTabCount);
      }
    }
  });

  it("fits more tabs on a notchless display", () => {
    const notched = layout(7, pro);
    const notchless = layout(7, undefined);
    expect(notched.hasOverflow).toBe(true);
    expect(notchless.hasOverflow).toBe(false);
    expect(notchless.cutout).toBeUndefined();
  });

  it("puts the shortcut at the far right after the gear", () => {
    const result = layout(4, pro);
    const paw = result.shortcutFrames[result.shortcutFrames.length - 1];
    expect(paw).toBeDefined();
    if (!paw) return;
    expect(maxX(paw)).toBe(canvas - metrics.outerInset);
    expect(maxX(result.gearFrame)).toBeLessThan(paw.x);
    expect(result.titleFrame && maxX(result.titleFrame) < result.gearFrame.x).toBe(true);
  });

  it("shows a title whole or not at all", () => {
    const notch = { width: 210, height: 32 };
    const short = layout(4, notch, 1, 30);
    expect(short.titleFrame?.width).toBe(30);
    expect(short.titleScale).toBe(1);
    const long = layout(4, notch, 1, 120);
    expect(long.titleFrame).toBeUndefined();
    expect(long.titleScale).toBe(1);
    const crowded = layout(4, notch, 3, 120);
    expect(crowded.titleFrame).toBeUndefined();
    expect(crowded.shortcutFrames.length).toBe(3);
  });

  it("drops titles that would clip on the compact canvas", () => {
    const compact = new NotchHeaderLayout({
      canvasWidth: panelCanvasSize("compact").width,
      notchSize: pro,
      headerHeight: 32,
      tabCount: 4,
      shortcutCount: 1,
      titleWidth: 76,
    });
    expect(compact.titleFrame).toBeUndefined();
    expect(layout(4, pro, 1, 76).titleFrame).toBeDefined();
  });

  it("shrinks a slightly long title instead of truncating it", () => {
    const result = layout(4, pro, 1, 87.4);
    expect(result.titleFrame).toBeDefined();
    expect(result.titleScale).toBeLessThan(1);
    expect(result.titleScale).toBeGreaterThanOrEqual(metrics.minTitleScale);
    expect(result.titleFrame?.width ?? 0).toBeGreaterThanOrEqual(87.4 * result.titleScale - 0.5);
    expect(layout(4, pro, 1, 40).titleScale).toBe(1);
  });

  /* The Windows island has no camera housing: these pin the notchless path it uses. */
  it("lays out the notchless header on the regular canvas exactly", () => {
    const result = layout(5, undefined, 1, 60);
    expect(result.cutout).toBeUndefined();
    expect(result.leadingZone).toEqual(rect(32, 0, 236, 32));
    expect(result.trailingZone).toEqual(rect(292, 0, 236, 32));
    expect(result.tabWidth).toBe(28);
    expect(result.tabSpacing).toBe(2);
    expect(result.tabFrames.map((frame) => frame.x)).toEqual([32, 62, 92, 122, 152]);
    expect(result.tabFrames[0]).toEqual(rect(32, 4, 28, 24));
    expect(result.shortcutFrames).toEqual([rect(500, 4, 28, 24)]);
    expect(result.gearFrame).toEqual(rect(470, 5, 22, 22));
    expect(result.titleFrame).toEqual(rect(402, 4, 60, 24));
    expect(result.titleScale).toBe(1);
    expect(result.moreFrame).toBeUndefined();
  });

  it("overflows the notchless header only past nine tabs on the regular canvas", () => {
    expect(layout(7, undefined).hasOverflow).toBe(false);
    expect(layout(9, undefined).hasOverflow).toBe(false);
    const ten = layout(10, undefined);
    expect(ten.hasOverflow).toBe(true);
    expect(ten.visibleTabCount).toBe(8);
    expect(ten.moreListTop).toBe(32);
    expect(layout(0, undefined).visibleTabCount).toBe(0);
  });
});
