/*
 * Theme colors as CSS variables, read straight from the Mac's themes.json so
 * both apps share one source. Phase 1 applies the default theme's palette;
 * the full theme port (glows, accent treatments, the themes fixture) comes
 * with Settings > Look.
 */

import themes from "../../../Sources/TabbiKitCore/Themes/themes.json";

export interface ThemeColor {
  readonly white?: number;
  readonly red?: number;
  readonly green?: number;
  readonly blue?: number;
  readonly opacity?: number;
}

const channel = (v: number) => Math.round(Math.min(1, Math.max(0, v)) * 255);

/* A themes.json color ({white} or {red, green, blue}, with an optional opacity) as CSS. */
export function cssColor(color: ThemeColor): string {
  const alpha = color.opacity ?? 1;
  if (color.white !== undefined) {
    const w = channel(color.white);
    return `rgb(${w} ${w} ${w} / ${alpha})`;
  }
  if (color.red !== undefined && color.green !== undefined && color.blue !== undefined) {
    return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)} / ${alpha})`;
  }
  throw new Error(`Unknown theme color ${JSON.stringify(color)}`);
}

const kebab = (key: string) => key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

/* The palette of a theme as `--background`, `--surface-hover`, ... variables. */
export function paletteVariables(themeId: string = themes.defaultTheme): Record<string, string> {
  const theme = themes.themes.find((t) => t.id === themeId) ?? themes.themes[0];
  if (!theme) throw new Error("themes.json has no themes");
  const variables: Record<string, string> = {};
  for (const [key, value] of Object.entries(theme.palette as Record<string, ThemeColor>)) {
    variables[`--${kebab(key)}`] = cssColor(value);
  }
  return variables;
}

export function applyTheme(root: HTMLElement, themeId?: string): void {
  for (const [name, value] of Object.entries(paletteVariables(themeId))) {
    root.style.setProperty(name, value);
  }
}
