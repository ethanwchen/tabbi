import { tr } from "../localization/tr";

/**
 * Port of NotchMode: how much of Tabbi stays on screen while the panel is
 * closed. The stored raw values are the Mac's ("always", "hover", "hidden").
 */
export type NotchMode = "always" | "hover" | "hidden";

export const NOTCH_MODES: readonly NotchMode[] = ["always", "hover", "hidden"];

/** The closed pill, its wings and preview are always drawn (`alwaysVisible` on the Mac). */
export const DEFAULT_NOTCH_MODE: NotchMode = "always";

export function isNotchMode(value: unknown): value is NotchMode {
  return typeof value === "string" && (NOTCH_MODES as readonly string[]).includes(value);
}

/** The name Settings and the right-click menu show. */
export function notchModeTitle(mode: NotchMode): string {
  switch (mode) {
    case "always":
      return tr("Always Visible");
    case "hover":
      return tr("Show on Hover");
    case "hidden":
      return tr("Hidden");
  }
}
