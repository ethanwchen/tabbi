/*
 * Port of AccentTreatment: how a theme treats each module's accent color, so
 * one theme can mute or warm every module without the modules knowing.
 */

import { accentColor, contrast, gray, mixed, rgb, type ModuleAccent, type ThemeColor } from "./themeColor";

export const ACCENT_TREATMENTS = ["original", "monochrome", "vivid", "pastel"] as const;

export type AccentTreatment = (typeof ACCENT_TREATMENTS)[number];

/** The contrast against black a vivid accent keeps, so it still reads as text. */
export const MINIMUM_ACCENT_CONTRAST = 4.5;

const CREAM = rgb(1.0, 0.94, 0.86);

/** The accent `base` becomes under `treatment`. */
export function applyAccentTreatment(treatment: AccentTreatment, base: ModuleAccent): ThemeColor {
  const color = accentColor(base);
  switch (treatment) {
    case "original":
      return color;
    case "monochrome": {
      /* Perceived lightness, kept in a band that reads on black. */
      const level = 0.299 * color.red + 0.587 * color.green + 0.114 * color.blue;
      return gray(0.55 + level * 0.4);
    }
    case "vivid": {
      const high = Math.max(color.red, color.green, color.blue);
      const low = Math.min(color.red, color.green, color.blue);
      if (!(high > low)) return gray(1);
      /* Stretch the channels to the full 0...1 range: same hue, full saturation and brightness. */
      const stretch = (c: number) => (c - low) / (high - low);
      const saturated = rgb(stretch(color.red), stretch(color.green), stretch(color.blue));
      /* Pure blues and violets are too dark to read on black, so lift them toward white just enough. */
      const black = gray(0);
      const white = gray(1);
      let lift = 0;
      while (contrast(mixed(saturated, white, lift), black) < MINIMUM_ACCENT_CONTRAST && lift < 1) {
        lift += 0.05;
      }
      return mixed(saturated, white, lift);
    }
    case "pastel":
      return mixed(color, CREAM, 0.35);
  }
}
