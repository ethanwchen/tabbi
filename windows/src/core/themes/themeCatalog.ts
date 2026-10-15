/*
 * Port of ThemeCatalog: every theme Tabbi ships, in picker order, read from
 * the Mac's themes.json so both apps draw the same colors from one source.
 */

import themesJson from "@mac/Themes/themes.json";
import type { AppTheme, GlassSheen, ThemeID } from "./appTheme";
import { decodeThemeFile, type ThemeFile } from "./themeFile";

/* The file ships inside the app, so a broken one is a build mistake and fails at import, as on the Mac. */
const file: ThemeFile = decodeThemeFile(themesJson);

/** The parsed themes.json. */
export const themeFile: ThemeFile = file;

/** Used when nothing (settings or kit) picks a theme. */
export const DEFAULT_THEME_ID: ThemeID = file.defaultTheme;

/** Every theme in picker order. */
export const allThemes: readonly AppTheme[] = file.themes;

/** The light drawn on glass cards. */
export const standardGlassSheen: GlassSheen = file.glassSheen;

/** The theme with `id`, or undefined when this build does not have it. */
export function findTheme(id: ThemeID): AppTheme | undefined {
  return allThemes.find((theme) => theme.id === id);
}

/** The theme with `id`, falling back to the default so an unknown saved id still draws something sensible. */
export function resolveTheme(id: ThemeID): AppTheme {
  const theme = findTheme(id) ?? findTheme(DEFAULT_THEME_ID);
  if (!theme) throw new Error(`themes.json has no theme "${DEFAULT_THEME_ID}"`);
  return theme;
}

/*
 * The theme a kit's `theme` field names, or undefined for an id this build
 * does not have. "notch", the name kits used before themes existed, is Midnight.
 */
export function themeIdForKitValue(value: string): ThemeID | undefined {
  const legacy = Object.hasOwn(file.legacyKitThemes, value) ? file.legacyKitThemes[value] : undefined;
  return findTheme(legacy ?? value)?.id;
}
