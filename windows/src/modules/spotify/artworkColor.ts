/*
 * The color the panel's glow takes behind a cover: the Mac's
 * `SpotifyArtworkLoader.averageColor` (the cover's mean color, nudged
 * brighter so a dark cover still gives a visible, soft halo on the black
 * panel), `SpotifyGeneratedCoverView.glowColor` for a generated cover and
 * `DemoAlbumCover.glowColor` for the demo track. Hues, saturation and
 * brightness are HSB as SwiftUI's `Color(hue:saturation:brightness:)` takes
 * them, written out as CSS `hsl()`.
 */

import type { GeneratedCover } from "../../core/nowPlaying/nowPlayingFormat";

/** The warm sunset tone behind the demo cover (#F08A5D). */
export const DEMO_GLOW = "rgb(240 138 93)";

/** HSB (each 0 to 1) as a CSS color. */
export function hsbCss(hue: number, saturation: number, brightness: number): string {
  const s = Math.min(Math.max(saturation, 0), 1);
  const b = Math.min(Math.max(brightness, 0), 1);
  const lightness = b * (1 - s / 2);
  const chroma = lightness === 0 || lightness === 1 ? 0 : (b - lightness) / Math.min(lightness, 1 - lightness);
  const h = ((hue % 1) + 1) % 1;
  return `hsl(${Math.round(h * 360)} ${Math.round(chroma * 100)}% ${Math.round(lightness * 100)}%)`;
}

/** The glow behind a generated cover: its start hue, saturated and bright. */
export function generatedGlow(cover: GeneratedCover): string {
  return hsbCss(cover.startHue, 0.7, 0.85);
}

/** The two stops of a generated cover's gradient, top-leading to bottom-trailing. */
export function generatedGradient(cover: GeneratedCover): [string, string] {
  return [hsbCss(cover.startHue, 0.72, 0.86), hsbCss(cover.endHue, 0.8, 0.42)];
}

/** RGB (0 to 255) as HSB, each 0 to 1. */
export function rgbToHsb(red: number, green: number, blue: number): { hue: number; saturation: number; brightness: number } {
  const r = red / 255;
  const g = green / 255;
  const b = blue / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const delta = max - min;
  let hue = 0;
  if (delta > 0) {
    if (max === r) hue = ((g - b) / delta) % 6;
    else if (max === g) hue = (b - r) / delta + 2;
    else hue = (r - g) / delta + 4;
    hue = ((hue / 6) % 1 + 1) % 1;
  }
  return { hue, saturation: max === 0 ? 0 : delta / max, brightness: max };
}

/** A cover's mean color as its glow: more saturated, and never darker than 60% brightness. */
export function glowFromAverage(red: number, green: number, blue: number): string {
  const { hue, saturation, brightness } = rgbToHsb(red, green, blue);
  return hsbCss(hue, Math.min(saturation * 1.2, 1), Math.max(brightness, 0.6));
}
