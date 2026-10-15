import { maxX, maxY, rect, type Rect } from "./rect";

/** Sizes the header is built from. The defaults match the notch's design. */
export interface NotchHeaderMetrics {
  /** Distance from the canvas edge to the first and last control. */
  readonly outerInset: number;
  /** Clear room kept between any control and the camera cutout. */
  readonly cutoutMargin: number;
  /** Gap between the two sides on a display without a notch (every Windows display). */
  readonly notchlessGap: number;
  readonly controlHeight: number;
  readonly tabWidth: number;
  /** The smallest hit target a tab shrinks to before tabs overflow. */
  readonly minTabWidth: number;
  readonly tabSpacing: number;
  readonly moreWidth: number;
  readonly gearSize: number;
  readonly shortcutWidth: number;
  readonly shortcutSpacing: number;
  /** Gap between the title, the gear and the shortcuts. */
  readonly trailingSpacing: number;
  /** How far a slightly long title may shrink to fit; past that it is dropped. */
  readonly minTitleScale: number;
  /** Gap above the overflow list, below the "more" button and the cutout. */
  readonly moreListGap: number;
}

export const DEFAULT_HEADER_METRICS: NotchHeaderMetrics = {
  outerInset: 32,
  cutoutMargin: 8,
  notchlessGap: 24,
  controlHeight: 24,
  tabWidth: 28,
  minTabWidth: 24,
  tabSpacing: 2,
  moreWidth: 24,
  gearSize: 22,
  shortcutWidth: 28,
  shortcutSpacing: 2,
  trailingSpacing: 8,
  minTitleScale: 0.88,
  moreListGap: 4,
};

export interface NotchHeaderInput {
  /** Width of the open panel. */
  readonly canvasWidth: number;
  /** Size of the hardware notch, or undefined on a display without one (always, on Windows). */
  readonly notchSize?: { readonly width: number; readonly height: number };
  /** Height of the header row the controls center in. */
  readonly headerHeight: number;
  /** Tabs in the row before any overflow. */
  readonly tabCount: number;
  /** Header shortcuts at the far right (the pet's paw). */
  readonly shortcutCount: number;
  /** The title's natural width, as the UI measures it. */
  readonly titleWidth: number;
  readonly metrics?: NotchHeaderMetrics;
}

/** Rounds half away from zero, as Swift's `rounded()` does. */
function round(value: number): number {
  return Math.sign(value) * Math.round(Math.abs(value));
}

/**
 * Port of NotchHeaderLayout: where every part of the open panel's header
 * goes. The header is one row: the tabs on the left of the center, and the
 * tab's title, the Settings gear and the header shortcuts on the right. Each
 * side gets the room between the outer inset and a gap at the center (the
 * camera cutout and its margin on a notched Mac; a fixed gap on Windows).
 *
 * When the tabs don't fit at full size they first tighten (narrower
 * buttons, then no gaps, never below `minTabWidth`), and only then the last
 * ones move behind a "more" button. On the right the title first shrinks a
 * little and is dropped when it still doesn't fit, so it never shows
 * clipped. Frames are in the panel's coordinates, x from its left edge and
 * y from its top edge.
 */
export class NotchHeaderLayout {
  /** The camera cutout, or undefined on a display without a notch. */
  readonly cutout?: Rect;
  /** The room the tabs (and the "more" button) may use. */
  readonly leadingZone: Rect;
  /** The room the title, gear and shortcuts may use. */
  readonly trailingZone: Rect;
  /** Width of each tab button, between `minTabWidth` and `tabWidth`. */
  readonly tabWidth: number;
  /** Gap between neighboring tabs (and before the "more" button). */
  readonly tabSpacing: number;
  /** One frame per tab that shows in the row, in order; the rest overflow. */
  readonly tabFrames: readonly Rect[];
  /** The "more" button, or undefined when every tab fits. */
  readonly moreFrame?: Rect;
  /** Top edge of the overflow list, or undefined when every tab fits. */
  readonly moreListTop?: number;
  /** The tab title, undefined when it was dropped to make room. */
  readonly titleFrame?: Rect;
  /** The type scale that fits the title whole: 1 at full size, never below `minTitleScale`. */
  readonly titleScale: number;
  readonly gearFrame: Rect;
  /** One frame per header shortcut, the last at the far right. */
  readonly shortcutFrames: readonly Rect[];

  constructor(input: NotchHeaderInput) {
    const metrics = input.metrics ?? DEFAULT_HEADER_METRICS;
    const { canvasWidth, notchSize, headerHeight } = input;
    const center = canvasWidth / 2;
    const halfGap = notchSize ? notchSize.width / 2 + metrics.cutoutMargin : metrics.notchlessGap / 2;
    if (notchSize) this.cutout = rect(center - notchSize.width / 2, 0, notchSize.width, notchSize.height);
    const zoneWidth = Math.max(center - halfGap - metrics.outerInset, 0);
    this.leadingZone = rect(metrics.outerInset, 0, zoneWidth, headerHeight);
    this.trailingZone = rect(center + halfGap, 0, zoneWidth, headerHeight);

    const row = (x: number, width: number, height = metrics.controlHeight): Rect =>
      rect(x, round((headerHeight - height) / 2), width, height);

    /* Tabs: full size, then narrower, then without gaps, then overflow. */
    const tabs = Math.max(input.tabCount, 0);
    const fit = fitTabs(tabs, zoneWidth, metrics);
    this.tabWidth = fit.width;
    this.tabSpacing = fit.spacing;
    let x = this.leadingZone.x;
    const tabFrames: Rect[] = [];
    for (let i = 0; i < fit.visible; i++) {
      tabFrames.push(row(x, fit.width));
      x += fit.width + fit.spacing;
    }
    this.tabFrames = tabFrames;
    if (fit.visible < tabs) {
      const more = row(x, metrics.moreWidth);
      this.moreFrame = more;
      this.moreListTop = Math.max(maxY(more), notchSize?.height ?? 0) + metrics.moreListGap;
    }

    /* Trailing side, laid out from the far right: shortcuts, gear, title. */
    let right = maxX(this.trailingZone);
    const shortcutFrames: Rect[] = [];
    for (let i = 0; i < Math.max(input.shortcutCount, 0); i++) {
      right -= metrics.shortcutWidth;
      shortcutFrames.unshift(row(right, metrics.shortcutWidth));
      right -= metrics.shortcutSpacing;
    }
    if (shortcutFrames.length > 0) right += metrics.shortcutSpacing - metrics.trailingSpacing;
    right -= metrics.gearSize;
    this.gearFrame = row(right, metrics.gearSize, metrics.gearSize);
    this.shortcutFrames = shortcutFrames;
    /*
     * The title shows whole, shrunk a little if needed, or not at all: the
     * selected tab already names the page, so a clipped title only adds noise.
     */
    const titleWidth = input.titleWidth;
    const titleRoom = right - metrics.trailingSpacing - this.trailingZone.x;
    const shownTitle = Math.min(Math.ceil(titleWidth), titleRoom);
    /* A point of slack, since type doesn't shrink exactly in proportion. */
    const scale = titleWidth > shownTitle ? (shownTitle - 1) / titleWidth : 1;
    if (titleWidth > 0 && scale >= metrics.minTitleScale) {
      this.titleFrame = row(right - metrics.trailingSpacing - shownTitle, shownTitle);
      this.titleScale = scale;
    } else {
      this.titleScale = 1;
    }
  }

  /** How many tabs show in the row; tabs from this index on overflow. */
  get visibleTabCount(): number {
    return this.tabFrames.length;
  }

  get hasOverflow(): boolean {
    return this.moreFrame !== undefined;
  }

  /** The tabs behind the "more" button, in their usual order. */
  overflowTabs<Tab>(tabs: readonly Tab[]): Tab[] {
    return tabs.slice(this.visibleTabCount);
  }

  /** The open tab when it sits behind the "more" button, which then wears the selection. */
  overflowSelection<Tab>(tabs: readonly Tab[], selected: Tab | undefined): Tab | undefined {
    return selected !== undefined && this.overflowTabs(tabs).includes(selected) ? selected : undefined;
  }

  /** Every control's frame, for checking that none meets the center gap. */
  get controlFrames(): Rect[] {
    const optional = [this.moreFrame, this.titleFrame, this.gearFrame].filter(
      (frame): frame is Rect => frame !== undefined,
    );
    return [...this.tabFrames, ...optional, ...this.shortcutFrames];
  }
}

function fitTabs(
  count: number,
  room: number,
  metrics: NotchHeaderMetrics,
): { width: number; spacing: number; visible: number } {
  if (count <= 0) return { width: metrics.tabWidth, spacing: metrics.tabSpacing, visible: 0 };
  for (const spacing of [metrics.tabSpacing, 0]) {
    const width = Math.min(metrics.tabWidth, Math.floor((room - (count - 1) * spacing) / count));
    if (width >= metrics.minTabWidth) return { width, spacing, visible: count };
  }
  /* Overflow: smallest tabs without gaps, and the "more" button last. */
  const visible = Math.floor((room - metrics.moreWidth) / metrics.minTabWidth);
  return { width: metrics.minTabWidth, spacing: 0, visible: Math.min(Math.max(visible, 0), count - 1) };
}
