import { recapWeekTitle } from "./recapStats";
import type { RecapWeek } from "./recapWeek";

/*
 * Port of RecapShareFormat: the shapes a weekly recap exports to, a square
 * post and a 9:16 story, both 1080 pixels wide so they look sharp on a phone.
 */
export type RecapShareFormat = "square" | "story";

export const RECAP_SHARE_FORMATS: readonly RecapShareFormat[] = ["square", "story"];

/** The brand line printed on every exported image. */
export const RECAP_SHARE_BRAND = "Tabbi";
export const RECAP_SHARE_WEBSITE = "tabbinotch.com";
/** Pixels per point the image is drawn at. */
export const RECAP_SHARE_SCALE = 3;

/** Size of the exported PNG, in pixels. */
export function recapSharePixelSize(format: RecapShareFormat): { readonly width: number; readonly height: number } {
  return format === "square" ? { width: 1080, height: 1080 } : { width: 1080, height: 1920 };
}

/** Size of the layout the image is drawn from, in points. */
export function recapSharePointSize(format: RecapShareFormat): { readonly width: number; readonly height: number } {
  const pixels = recapSharePixelSize(format);
  return { width: pixels.width / RECAP_SHARE_SCALE, height: pixels.height / RECAP_SHARE_SCALE };
}

/** The menu item that exports this shape (the Mac leaves it untranslated too). */
export function recapShareTitle(format: RecapShareFormat): string {
  return format === "square" ? "Square (1:1)" : "Story (9:16)";
}

/*
 * Characters Windows forbids in a file name (plus the Mac's colon and
 * slashes), and control characters, become hyphens.
 */
const FORBIDDEN = new Set(["/", "\\", ":", "*", "?", '"', "<", ">", "|"]);

function safeCharacter(character: string): string {
  return FORBIDDEN.has(character) || character.charCodeAt(0) < 0x20 ? "-" : character;
}

/**
 * A file name for `week`'s image in this shape, safe on every file system,
 * for example "Tabbi week Oct 5 - 11 (square).png".
 */
export function recapShareFileName(format: RecapShareFormat, week: RecapWeek, locale: string, timeZone: string): string {
  const safe = Array.from(recapWeekTitle(week, locale, timeZone), safeCharacter).join("");
  return `${RECAP_SHARE_BRAND} week ${safe} (${format}).png`;
}
