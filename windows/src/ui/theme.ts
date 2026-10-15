/*
 * Theme colors as CSS variables, from the core's port of the Mac's themes
 * (themes.json read in place, so both apps share one source). A theme's
 * palette becomes `--background`, `--surface-hover`, ... and `--glow` when
 * the theme has one; module accents go through the theme's treatment.
 */

import { themeAccent, paletteRoles, type ThemeID } from "../core/themes/appTheme";
import { DEFAULT_THEME_ID, resolveTheme } from "../core/themes/themeCatalog";
import type { ModuleAccent } from "../core/themes/themeColor";

/* A color as themes.json writes it ({white} or {red, green, blue}, with an optional opacity), or fully resolved. */
export interface ThemeColor {
  readonly white?: number;
  readonly red?: number;
  readonly green?: number;
  readonly blue?: number;
  readonly opacity?: number;
}

const channel = (v: number) => Math.round(Math.min(1, Math.max(0, v)) * 255);

/* A theme color as CSS. */
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

/* The palette of a theme as `--background`, `--surface-hover`, ... variables; an unknown id draws the default. */
export function paletteVariables(themeId: ThemeID = DEFAULT_THEME_ID): Record<string, string> {
  const variables: Record<string, string> = {};
  for (const [role, color] of paletteRoles(resolveTheme(themeId).palette)) {
    variables[`--${kebab(role)}`] = cssColor(color);
  }
  return variables;
}

/* A module's accent as the theme shows it (muted, vivid or pastel), as CSS. */
export function accentCss(accent: ModuleAccent, themeId: ThemeID = DEFAULT_THEME_ID): string {
  return cssColor(themeAccent(resolveTheme(themeId), accent));
}

export function applyTheme(root: HTMLElement, themeId?: ThemeID): void {
  /* A flat theme has no glow, so a glow left by the previous theme must not linger. */
  root.style.removeProperty("--glow");
  for (const [name, value] of Object.entries(paletteVariables(themeId))) {
    root.style.setProperty(name, value);
  }
}
