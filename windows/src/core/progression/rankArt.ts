import { petArt } from "../pets/petArt";
import { PetCanvas } from "../pets/petCanvas";
import { PetPalette, colorFromHex, roleAt, type PaletteOverrides, type PetColor } from "../pets/petPalette";
import type { PetBitmap } from "../pets/petRenderer";
import { rankPips, type RankTier, type StudyRank } from "./studyLevel";

/*
 * Port of RankArt and RankPalette: the Study Level rank emblems in the
 * pet's sprite language. A 16 by 16 grid per named rank in the Mac's
 * `Pets/PetArt/rank.json`, stamped one pixel in on an 18 by 18 canvas and
 * colored through the rank's palette; Galaxy II and up add one small gold
 * star per numeral in the free corners, up to four.
 */

export const RANK_ART_SIZE = 18;
export const RANK_EMBLEM_SIZE = 16;
/** Top-left corners of the 3 by 3 stars, in the order they are added. */
export const RANK_PIP_ORIGINS: readonly { readonly x: number; readonly y: number }[] = [
  { x: 15, y: 0 },
  { x: 0, y: 0 },
  { x: 0, y: 15 },
  { x: 15, y: 15 },
];

function gridName(tier: RankTier): string {
  return `emblem${tier.charAt(0).toUpperCase()}${tier.slice(1)}`;
}

export function rankCanvas(rank: StudyRank): PetCanvas {
  const art = petArt("rank");
  const canvas = new PetCanvas(RANK_ART_SIZE, RANK_ART_SIZE);
  canvas.stamp(art.grid(gridName(rank.tier)), 1, 1);
  for (const origin of RANK_PIP_ORIGINS.slice(0, rankPips(rank))) canvas.stamp(art.grid("pip"), origin.x, origin.y);
  return canvas;
}

export interface RankColors {
  readonly outline: PetColor;
  readonly body: PetColor;
  readonly shade: PetColor;
  readonly core: PetColor;
  readonly light: PetColor;
  readonly hot: PetColor;
  readonly second: PetColor;
  readonly sparkle: PetColor;
}

function hex(value: string): PetColor {
  const color = colorFromHex(value);
  if (!color) throw new Error(`Bad rank color ${value}`);
  return color;
}

function colors(...values: [string, string, string, string, string, string, string, string]): RankColors {
  const [outline, body, shade, core, light, hot, second, sparkle] = values.map(hex) as [
    PetColor, PetColor, PetColor, PetColor, PetColor, PetColor, PetColor, PetColor,
  ];
  return { outline, body, shade, core, light, hot, second, sparkle };
}

const TIER_COLORS: Record<RankTier, RankColors> = {
  spark: colors("#2A1A14", "#FFD66B", "#E0A23A", "#FFF3C4", "#FFF8E1", "#FFFFFF", "#FFD66B", "#FFF3C4"),
  ember: colors("#2A1A14", "#FF8A3D", "#D2452A", "#FFC94D", "#FFB27A", "#FFF4D6", "#FF8A3D", "#FFF3C4"),
  comet: colors("#14202A", "#8FD8FF", "#4A9BD6", "#F2FBFF", "#DFF5FF", "#FFFFFF", "#5FB8F0", "#FFFFFF"),
  nova: colors("#2A1420", "#FF9BD2", "#D45C9E", "#FFE3F2", "#FFD0EA", "#FFFFFF", "#FF9BD2", "#FFFFFF"),
  nebula: colors("#1C1430", "#A88BFF", "#6E54C8", "#EDE6FF", "#D9CCFF", "#FFFFFF", "#FF9BD2", "#F4F1FF"),
  galaxy: colors("#0E1030", "#4654C8", "#2E3790", "#C8D0FF", "#DDE2FF", "#FFD66B", "#4654C8", "#FFFFFF"),
};

export function rankTierColors(tier: RankTier): RankColors {
  return TIER_COLORS[tier];
}

/** `O` outline, `C` body, `D` shade, `W` core, `L` highlight, `Y` hot point, `T` second color, `Z` sparkles. */
export function rankPalette(tier: RankTier): PetPalette {
  const c = TIER_COLORS[tier];
  const overrides: PaletteOverrides = {
    outline: c.outline,
    costumeBase: c.body,
    costumeShade: c.shade,
    belly: c.core,
    eyeLight: c.light,
    gold: c.hot,
    costumeTrim: c.second,
    effect: c.sparkle,
  };
  return new PetPalette(overrides);
}

/** The emblem's pixels as colors, row-major, undefined for transparent. */
export function rankColors(rank: StudyRank): (PetColor | undefined)[] {
  const palette = rankPalette(rank.tier);
  const canvas = rankCanvas(rank);
  const out: (PetColor | undefined)[] = new Array(canvas.pixels.length);
  for (let index = 0; index < canvas.pixels.length; index++) {
    const pixel = canvas.pixels[index] ?? 0;
    out[index] = pixel === 0 ? undefined : palette.color(roleAt(pixel - 1));
  }
  return out;
}

const bitmaps = new Map<string, PetBitmap>();

/** The emblem at `scale` device pixels per sprite pixel, cached by tier, stars and scale. */
export function rankBitmap(rank: StudyRank, scaleIn: number): PetBitmap {
  const scale = Math.max(1, Math.trunc(scaleIn));
  const key = `${rank.tier}|${rankPips(rank)}|${scale}`;
  const hit = bitmaps.get(key);
  if (hit) return hit;
  const pixels = rankColors(rank);
  const width = RANK_ART_SIZE * scale;
  const data = new Uint8ClampedArray(width * width * 4);
  for (let sy = 0; sy < RANK_ART_SIZE; sy++) {
    for (let sx = 0; sx < RANK_ART_SIZE; sx++) {
      const color = pixels[sy * RANK_ART_SIZE + sx];
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
