import type { Rect } from "../modules/rect";
import { resolveDisplay, type DisplayPreference, type DisplayScreen } from "./displayPreference";
import type { NotchMode } from "./notchMode";

/*
 * Port of NotchVisibility's platform-free rules: whether the closed panel is
 * drawn, where hovering reaches for it, and which screen it uses. Detecting
 * a fullscreen app is the host's job on Windows (SHQueryUserNotificationState),
 * so the Mac's window-list heuristic is not ported.
 */

export interface VisibilityInput {
  readonly mode: NotchMode;
  readonly hideInFullscreen: boolean;
  readonly fullscreenAppActive: boolean;
  /** The user asked for the panel with the global shortcut, which shows it in every mode and over fullscreen apps. */
  readonly revealed: boolean;
  /** The pointer is in the hover zone, or on the panel while it is drawn. */
  readonly pointerNear: boolean;
  /** The panel is open (or pinned open), so it stays drawn in any mode until it closes. */
  readonly isOpen: boolean;
}

/** Whether the panel is shown. */
export function isNotchShown(input: VisibilityInput): boolean {
  if (input.revealed) return true;
  if (input.hideInFullscreen && input.fullscreenAppActive) return false;
  switch (input.mode) {
    case "always":
      return true;
    case "hover":
      return input.pointerNear || input.isOpen;
    case "hidden":
      return input.isOpen;
  }
}

/** Room around the closed shape that still counts as reaching for it. */
export const HOVER_ZONE_MARGIN = { width: 24, height: 8 } as const;

/**
 * The top-center area that brings a hover-mode panel out, in top-left
 * screen coordinates: the closed shape (which touches the top of its screen)
 * wider by the margin on each side and taller below. Undefined for an empty shape.
 */
export function hoverZone(closedShape: Rect): Rect | undefined {
  if (closedShape.width <= 0 || closedShape.height <= 0) return undefined;
  return {
    x: closedShape.x - HOVER_ZONE_MARGIN.width,
    y: closedShape.y,
    width: closedShape.width + HOVER_ZONE_MARGIN.width * 2,
    height: closedShape.height + HOVER_ZONE_MARGIN.height,
  };
}

function contains(r: Rect, x: number, y: number): boolean {
  return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height;
}

/**
 * Whether the pointer keeps a hover-mode panel out: in the hover zone, or
 * (once drawn) anywhere on its shape with a 4 point allowance, so moving onto
 * a wing or a preview does not make it vanish.
 */
export function isPointerNear(
  point: { readonly x: number; readonly y: number },
  zone: Rect | undefined,
  drawnShape: Rect | undefined,
): boolean {
  if (zone && contains(zone, point.x, point.y)) return true;
  if (!drawnShape) return false;
  return contains(
    { x: drawnShape.x - 4, y: drawnShape.y - 4, width: drawnShape.width + 8, height: drawnShape.height + 8 },
    point.x,
    point.y,
  );
}

/**
 * The screen the panel should appear on, or undefined when it should not
 * appear: with `showOnExternalDisplays` off only built-in screens qualify.
 */
export function notchScreen(
  preference: DisplayPreference,
  showOnExternalDisplays: boolean,
  screens: readonly DisplayScreen[],
): DisplayScreen | undefined {
  return resolveDisplay(preference, showOnExternalDisplays ? screens : screens.filter((screen) => screen.isBuiltIn));
}
