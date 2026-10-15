import themes from "@mac/Themes/themes.json";

/*
 * A narrow view of the Mac's ThemeCatalog, read from the same themes.json:
 * only the theme ids, the default, and the kit names kits used before themes
 * existed. Colors and treatments belong to the theme port.
 */

/** A theme id from themes.json, such as "midnight". Kept as saved even when this build lacks it. */
export type ThemeID = string;

const themeIDs: readonly ThemeID[] = themes.themes.map((theme) => theme.id);
const legacyKitThemes: Readonly<Record<string, ThemeID>> = themes.legacyKitThemes;

/** Used when nothing (settings or kit) picks a theme. */
export const DEFAULT_THEME_ID: ThemeID = themes.defaultTheme;

/** Whether this build has the theme `id`. */
export function hasTheme(id: ThemeID): boolean {
  return themeIDs.includes(id);
}

/**
 * The theme a kit's `theme` field names, or undefined for an id this build
 * doesn't have. "notch", the name kits used before themes existed, is Midnight.
 */
export function themeIDForKitValue(value: string): ThemeID | undefined {
  const id = legacyKitThemes[value] ?? value;
  return hasTheme(id) ? id : undefined;
}
