import { tr } from "../localization/tr";

/**
 * Port of PanelSize: how big the open panel is. Every tab lays out inside
 * the same canvas, so one choice sizes them all. The raw values are stored.
 */
export type PanelSize = "compact" | "regular" | "large";

export const PANEL_SIZES: readonly PanelSize[] = ["compact", "regular", "large"];

export const DEFAULT_PANEL_SIZE: PanelSize = "regular";

export function isPanelSize(value: unknown): value is PanelSize {
  return typeof value === "string" && (PANEL_SIZES as readonly string[]).includes(value);
}

/** The open panel's canvas, header included. Regular is the size every panel was designed for. */
export function panelCanvasSize(size: PanelSize): { width: number; height: number } {
  switch (size) {
    case "compact":
      return { width: 512, height: 224 };
    case "regular":
      return { width: 560, height: 236 };
    case "large":
      return { width: 640, height: 272 };
  }
}

/**
 * How much every panel's type, icons, controls and spacing grow at this
 * size. Panels are designed once, at Regular; Large draws them 9/8 larger
 * (which keeps the 4 pt grid on whole pixels), Compact adapts its layouts.
 */
export function panelContentScale(size: PanelSize): number {
  return size === "large" ? 9 / 8 : 1;
}

/** The name Settings shows. */
export function panelSizeTitle(size: PanelSize): string {
  switch (size) {
    case "compact":
      return tr("Compact");
    case "regular":
      return tr("Regular");
    case "large":
      return tr("Large");
  }
}
