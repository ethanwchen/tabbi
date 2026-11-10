import { petArt } from "../pets/petArt";
import { PetCanvas } from "../pets/petCanvas";
import { PetPalette, colorFromHex, roleAt, type PaletteOverrides, type PetColor } from "../pets/petPalette";
import type { PetBitmap } from "../pets/petRenderer";
import type { ProgressTier, ProgressTrack } from "./progressTrack";

/*
 * Port of BadgeArt and BadgePalette: the Goals badges drawn in the pet's
 * sprite language. A 28 by 28 frame per state and a 9 by 9 glyph per track
 * (`Pets/PetArt/badge.json`, the Mac's file, never a copy), the glyph
 * stamped on the frame's inner disc and colored through a per-state
 * palette, so one glyph serves every tier the way one costume serves every
 * breed.
 *
 * The frames carry their outline as drawn and approved, and the colors are
 * a plain role lookup: the pet's lit rim for dark coats is not applied, so
 * the quiet "not yet" coin keeps its dim outline.
 */

/** The grid's side, in sprite pixels. */
export const BADGE_SIZE = 28;
/** CSS pixels per sprite pixel on the compact and regular panels (42 px). */
export const BADGE_REGULAR_PIXEL_SIZE = 1.5;
/** CSS pixels per sprite pixel on the large panel (56 px). */
export const BADGE_LARGE_PIXEL_SIZE = 2;
/** Seconds between the Starlight sparkle's two frames. */
export const BADGE_TWINKLE_SECONDS = 1.5;

/** A badge's state: a tier reached, or none yet. Port of BadgeArt.State. */
export const BADGE_STATES = ["notYet", "bronze", "silver", "gold", "starlight"] as const;
export type BadgeState = (typeof BADGE_STATES)[number];

export function badgeState(tier: ProgressTier | undefined): BadgeState {
  return tier ?? "notYet";
}

function capitalized(name: string): string {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

/** The frame's grid name in `badge.json`. */
export function badgeFrameName(state: BadgeState, twinkle = false): string {
  return state === "starlight" && twinkle ? "frameStarlightTwinkle" : `frame${capitalized(state)}`;
}

/** The glyph's grid name in `badge.json`. */
export function badgeGlyphName(track: ProgressTrack): string {
  return `glyph${capitalized(track)}`;
}

/** Where the glyph's top-left corner lands: the inner disc's origin. The silver medal sits two pixels higher for its ribbon tails. */
export function badgeGlyphOrigin(state: BadgeState): { readonly x: number; readonly y: number } {
  return state === "silver" ? { x: 10, y: 8 } : { x: 10, y: 10 };
}

/** The composed badge: the state's frame with the track's glyph on it. `twinkle` picks Starlight's second sparkle frame. */
export function badgeCanvas(track: ProgressTrack, state: BadgeState, twinkle = false): PetCanvas {
  const art = petArt("badge");
  const canvas = new PetCanvas(BADGE_SIZE, BADGE_SIZE);
  canvas.stamp(art.grid(badgeFrameName(state, twinkle)), 0, 0);
  const origin = badgeGlyphOrigin(state);
  canvas.stamp(art.grid(badgeGlyphName(track)), origin.x, origin.y);
  return canvas;
}

/** The colors a state fills the frame and glyph slots with. Port of BadgePalette.Colors. */
export interface BadgeColors {
  readonly rim: PetColor;
  readonly shade: PetColor;
  readonly inner: PetColor;
  readonly glyph: PetColor;
  readonly light: PetColor;
  readonly outline: PetColor;
}

function hex(value: string): PetColor {
  const color = colorFromHex(value);
  if (!color) throw new Error(`Bad badge color ${value}`);
  return color;
}

export const BADGE_LEAF = hex("#6CC46A");
export const BADGE_LEAF_SHADE = hex("#4C9A4B");
export const BADGE_SPARKLE = hex("#F4F1FF");

const STATE_COLORS: Record<BadgeState, BadgeColors> = {
  notYet: { rim: hex("#2B2B30"), shade: hex("#232327"), inner: hex("#18181B"), glyph: hex("#4A4A50"), light: hex("#35353A"), outline: hex("#0D0D0F") },
  bronze: { rim: hex("#D9945C"), shade: hex("#A8683A"), inner: hex("#8E5530"), glyph: hex("#FFF1DC"), light: hex("#F2C49A"), outline: hex("#2A1A14") },
  silver: { rim: hex("#C7D1DE"), shade: hex("#8E9BAB"), inner: hex("#6F7C8C"), glyph: hex("#FFFFFF"), light: hex("#F6F8FB"), outline: hex("#2A1A14") },
  gold: { rim: hex("#F2C14E"), shade: hex("#C98A2A"), inner: hex("#A86E1E"), glyph: hex("#FFF7D6"), light: hex("#FFE9A6"), outline: hex("#2A1A14") },
  starlight: { rim: hex("#BDA8FF"), shade: hex("#7C63C8"), inner: hex("#5B47A6"), glyph: hex("#FFFFFF"), light: hex("#F4F1FF"), outline: hex("#2A1A14") },
};

export function badgeStateColors(state: BadgeState): BadgeColors {
  return STATE_COLORS[state];
}

/**
 * A pet palette with the state's colors in the badge slots: `C` the rim,
 * `D` its lower right shade, `U` the inner disc, `W` the glyph, `L` the two
 * pixel highlight, `O` the outline, `F` and `S` the laurel leaves, `Z` the
 * sparkles.
 */
export function badgePalette(state: BadgeState): PetPalette {
  const colors = STATE_COLORS[state];
  const overrides: PaletteOverrides = {
    costumeBase: colors.rim,
    costumeShade: colors.shade,
    coat: colors.inner,
    belly: colors.glyph,
    eyeLight: colors.light,
    outline: colors.outline,
    leaf: BADGE_LEAF,
    furShade: BADGE_LEAF_SHADE,
    effect: BADGE_SPARKLE,
  };
  return new PetPalette(overrides);
}

/** The badge's pixels as colors, row-major, undefined for transparent: a plain role lookup, no rim rule. */
export function badgeColors(track: ProgressTrack, state: BadgeState, twinkle = false): (PetColor | undefined)[] {
  const palette = badgePalette(state);
  const canvas = badgeCanvas(track, state, twinkle);
  const out: (PetColor | undefined)[] = new Array(canvas.pixels.length);
  for (let index = 0; index < canvas.pixels.length; index++) {
    const pixel = canvas.pixels[index] ?? 0;
    out[index] = pixel === 0 ? undefined : palette.color(roleAt(pixel - 1));
  }
  return out;
}

/**
 * Whole device pixels per sprite pixel for a panel: 1.5 CSS px (or 2 on the
 * large panel) times the device pixel ratio; on a 1x display, 1 px per
 * sprite pixel rather than a fractional scale, so the art stays crisp.
 */
export function badgeScale(pixelSize: number, devicePixelRatio: number): number {
  const exact = pixelSize * devicePixelRatio;
  if (Number.isInteger(exact)) return Math.max(1, exact);
  return Math.max(1, Math.round(devicePixelRatio));
}

const bitmaps = new Map<string, PetBitmap>();

/** The badge rendered at `scale`, straight RGBA with each sprite pixel an exact block, cached per track, state, frame and scale. */
export function badgeBitmap(track: ProgressTrack, state: BadgeState, twinkle: boolean, scaleIn: number): PetBitmap {
  const scale = Math.max(1, Math.trunc(scaleIn));
  const key = `${track}|${state}|${twinkle ? 1 : 0}|${scale}`;
  const hit = bitmaps.get(key);
  if (hit) return hit;
  const colors = badgeColors(track, state, twinkle);
  const width = BADGE_SIZE * scale;
  const data = new Uint8ClampedArray(width * width * 4);
  for (let sy = 0; sy < BADGE_SIZE; sy++) {
    for (let sx = 0; sx < BADGE_SIZE; sx++) {
      const color = colors[sy * BADGE_SIZE + sx];
      if (!color) continue;
      for (let dy = 0; dy < scale; dy++) {
        let offset = ((sy * scale + dy) * width + sx * scale) * 4;
        for (let dx = 0; dx < scale; dx++) {
          data[offset] = color.red;
          data[offset + 1] = color.green;
          data[offset + 2] = color.blue;
          data[offset + 3] = color.alpha;
          offset += 4;
        }
      }
    }
  }
  const bitmap: PetBitmap = { width, height: width, data };
  bitmaps.set(key, bitmap);
  return bitmap;
}
