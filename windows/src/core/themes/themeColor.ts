/*
 * Port of ThemeColor: an sRGB color with opacity, in 0...1 components, so
 * themes live in data (themes.json) and can be tested without a renderer.
 */

export interface ThemeColor {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
  readonly opacity: number;
}

/** A module's accent color (port of ModuleAccent), always opaque. */
export interface ModuleAccent {
  readonly red: number;
  readonly green: number;
  readonly blue: number;
}

export function rgb(red: number, green: number, blue: number, opacity = 1): ThemeColor {
  return { red, green, blue, opacity };
}

/** A gray (or white with `opacity`) at `level` brightness. */
export function gray(level: number, opacity = 1): ThemeColor {
  return rgb(level, level, level, opacity);
}

/** The same color at another opacity. */
export function withOpacity(color: ThemeColor, opacity: number): ThemeColor {
  return rgb(color.red, color.green, color.blue, opacity);
}

/** An opaque color from a module accent. */
export function accentColor(accent: ModuleAccent): ThemeColor {
  return rgb(accent.red, accent.green, accent.blue);
}

/** Mixes `fraction` (0...1) of `other` into `color`. */
export function mixed(color: ThemeColor, other: ThemeColor, fraction: number): ThemeColor {
  const t = Math.min(Math.max(fraction, 0), 1);
  const mix = (a: number, b: number) => a + (b - a) * t;
  return rgb(
    mix(color.red, other.red),
    mix(color.green, other.green),
    mix(color.blue, other.blue),
    mix(color.opacity, other.opacity),
  );
}

/** Relative luminance (WCAG 2), ignoring opacity. */
export function luminance(color: ThemeColor): number {
  const linear = (c: number) => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
  return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue);
}

/** `color` painted at its opacity over an opaque `base`. */
export function composited(color: ThemeColor, base: ThemeColor): ThemeColor {
  return rgb(
    base.red + (color.red - base.red) * color.opacity,
    base.green + (color.green - base.green) * color.opacity,
    base.blue + (color.blue - base.blue) * color.opacity,
  );
}

/** WCAG contrast ratio between two opaque colors (1...21). */
export function contrast(a: ThemeColor, b: ThemeColor): number {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}
