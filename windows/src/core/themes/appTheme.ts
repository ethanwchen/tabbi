/*
 * Port of AppTheme and the values a theme is made of: the palette, the type
 * family, the motion, controls and surfaces, and the glass sheen. The closed
 * island is pure black in every theme.
 */

import { tr } from "../localization/tr";
import { SpringSpec } from "../motion/springSpec";
import { applyAccentTreatment, type AccentTreatment } from "./accentTreatment";
import { composited, withOpacity, type ModuleAccent, type ThemeColor } from "./themeColor";

/** Identifies a theme. Open, so an id from a newer build or a kit survives a round trip. */
export type ThemeID = string;

/** The ids the code names, which themes.json must define (ThemeID's static members). */
export const REQUIRED_THEME_IDS: readonly ThemeID[] = [
  "midnight",
  "graphite",
  "liquidGlass",
  "neon",
  "monochrome",
  "cozy",
  "sakura",
  "forest",
];

/*
 * Which group a theme is listed under in the picker (port of ThemeFamily).
 * themes.json writes a theme's group as `family`, which every build reads
 * and which stays classic or cozy, plus an optional `group` that builds
 * knowing newer groups (sweet) prefer, so a file with a new group still
 * decodes in a build that predates it.
 */
export const THEME_FAMILIES = ["classic", "cozy", "sweet"] as const;
export type ThemeFamily = (typeof THEME_FAMILIES)[number];

/** The values `family` may take, which every build since themes reads (ThemeFamily.baseFamilies). */
export const BASE_THEME_FAMILIES = ["classic", "cozy"] as const satisfies readonly ThemeFamily[];

/** The type family a theme sets in (port of ThemeTypeface): rounded is the Tabbi default. */
export const THEME_TYPEFACES = ["rounded", "standard"] as const;
export type ThemeTypeface = (typeof THEME_TYPEFACES)[number];

/** How lively a theme's animations are (port of ThemeMotion). */
export const THEME_MOTIONS = ["standard", "gentle"] as const;
export type ThemeMotion = (typeof THEME_MOTIONS)[number];

/** What small floating controls sit on (port of ThemeControlStyle). */
export const THEME_CONTROL_STYLES = ["solid", "glass"] as const;
export type ThemeControlStyle = (typeof THEME_CONTROL_STYLES)[number];

/** What content surfaces (cards) are drawn as (port of ThemeSurfaceStyle). */
export const THEME_SURFACE_STYLES = ["flat", "glass"] as const;
export type ThemeSurfaceStyle = (typeof THEME_SURFACE_STYLES)[number];

/*
 * Port of ThemeMotion.adjusted: `spec` as a theme plays it: unchanged for standard; for gentle, 30% longer
 * with 0.08 less bounce (never below none), so a cozy theme keeps every
 * motion token's character but calmer.
 */
export function adjustedForThemeMotion(motion: ThemeMotion, spec: SpringSpec): SpringSpec {
  switch (motion) {
    case "standard":
      return spec;
    case "gentle":
      return new SpringSpec(spec.duration * 1.3, Math.max(spec.bounce - 0.08, 0));
  }
}

/** The material a control is actually drawn with (port of ControlMaterial). */
export type ControlMaterial = "glass" | "material" | "opaque";

/*
 * Resolves a theme's control style for this system: glass only where the
 * system can draw it and transparency is allowed, a standard material where
 * it cannot, and the opaque surface under reduced transparency.
 */
export function resolveControlMaterial(
  style: ThemeControlStyle,
  glassAvailable: boolean,
  reduceTransparency: boolean,
): ControlMaterial {
  if (style !== "glass" || reduceTransparency) return "opaque";
  return glassAvailable ? "glass" : "material";
}

/*
 * Port of ThemePalette. The body is always opaque and its top edge black, so
 * the panel stays continuous with the top of the screen; a theme adds a soft
 * glow toward the bottom instead of repainting the panel.
 */
export interface ThemePalette {
  readonly background: ThemeColor;
  /** A soft color rising from the bottom edge; absent for a flat body. */
  readonly glow?: ThemeColor;
  readonly surface: ThemeColor;
  readonly surfaceHover: ThemeColor;
  readonly stroke: ThemeColor;
  readonly primaryText: ThemeColor;
  readonly secondaryText: ThemeColor;
  readonly tertiaryText: ThemeColor;
  readonly success: ThemeColor;
  readonly warning: ThemeColor;
  readonly danger: ThemeColor;
  /*
   * The theme's own key color, absent when every module keeps its own accent
   * (as the theme's `accents` treats it). When set, the active module's ring,
   * selected tab, primary button and chips all wear it (see themeAccent).
   */
  readonly accent?: ThemeColor;
  /** Text and symbols drawn on an `accent` fill; absent for the panel background. */
  readonly onAccent?: ThemeColor;
}

/*
 * The palette's required roles, in declaration order (glow is optional and
 * follows background; accent and onAccent are optional and come last).
 */
export const PALETTE_ROLES = [
  "background",
  "surface",
  "surfaceHover",
  "stroke",
  "primaryText",
  "secondaryText",
  "tertiaryText",
  "success",
  "warning",
  "danger",
] as const;

/** The palette's optional roles. */
export const OPTIONAL_PALETTE_ROLES = ["glow", "accent", "onAccent"] as const;

export type PaletteRole = (typeof PALETTE_ROLES)[number] | (typeof OPTIONAL_PALETTE_ROLES)[number];

/** Every color by its themes.json key, in declaration order; glow, accent and onAccent only when set. */
export function paletteRoles(palette: ThemePalette): [PaletteRole, ThemeColor][] {
  const roles: [PaletteRole, ThemeColor][] = [["background", palette.background]];
  if (palette.glow) roles.push(["glow", palette.glow]);
  for (const role of PALETTE_ROLES.slice(1)) roles.push([role, palette[role]]);
  if (palette.accent) roles.push(["accent", palette.accent]);
  if (palette.onAccent) roles.push(["onAccent", palette.onAccent]);
  return roles;
}

/*
 * Port of GlassSheen: the drawn light of a glass surface, a fill brighter at
 * the top, a glint near the top-leading corner and a rim lit from above. It
 * is plain paint, so it looks the same in the app and in snapshots.
 */
export interface GlassSheen {
  readonly fillTop: ThemeColor;
  readonly fillBottom: ThemeColor;
  readonly glint: ThemeColor;
  readonly rimTop: ThemeColor;
  readonly rimBottom: ThemeColor;
}

export const GLASS_SHEEN_ROLES = ["fillTop", "fillBottom", "glint", "rimTop", "rimBottom"] as const;

/** The brightest the fill gets (top edge plus glint) over `base`, for checking text contrast. */
export function brightestSheen(sheen: GlassSheen, base: ThemeColor): ThemeColor {
  return composited(sheen.glint, composited(sheen.fillTop, base));
}

/** A complete look for the open panel (port of AppTheme). */
export interface AppTheme {
  readonly id: ThemeID;
  readonly name: string;
  /** One line for the picker. */
  readonly summary: string;
  readonly family: ThemeFamily;
  readonly palette: ThemePalette;
  readonly accents: AccentTreatment;
  readonly typeface: ThemeTypeface;
  readonly motion: ThemeMotion;
  readonly controls: ThemeControlStyle;
  readonly surfaces: ThemeSurfaceStyle;
}

/**
 * The brightest color `theme` can put behind a pet, opaque: the glow at full
 * strength under a hovered flat card, or under the top of a glass card's sheen
 * (the corner glint is left out). Port of AppTheme.brightestPetBackdrop.
 */
export function brightestPetBackdrop(theme: AppTheme, sheen: GlassSheen): ThemeColor {
  const palette = theme.palette;
  let body = withOpacity(palette.background, 1);
  if (palette.glow) body = composited(palette.glow, body);
  return theme.surfaces === "glass" ? composited(sheen.fillTop, body) : composited(palette.surfaceHover, body);
}

/*
 * The accent a module with `base` shows in `theme`: the theme's own key
 * color when it has one (palette.accent), so the ring, the selected tab, the
 * primary button and the chips all match it, or else `base` as the theme's
 * `accents` treats it.
 */
export function themeAccent(theme: AppTheme, base: ModuleAccent): ThemeColor {
  return theme.palette.accent ?? themeIdentityAccent(theme, base);
}

/*
 * `base` as the theme's `accents` treats it, even when the theme has a key
 * color: for what has to tell modules apart, such as module icons listed
 * side by side or another module's item in Today's list, and for colors
 * with a meaning of their own (the favorite heart).
 */
export function themeIdentityAccent(theme: AppTheme, base: ModuleAccent): ThemeColor {
  return applyAccentTreatment(theme.accents, base);
}

/** Text and symbols on a themeAccent fill: the palette's onAccent, or the panel background. */
export function themeOnAccent(theme: AppTheme): ThemeColor {
  return theme.palette.onAccent ?? theme.palette.background;
}

/*
 * The theme's name in the user's language. themes.json holds the English,
 * so the translation is looked up under `theme.<id>` (a name such as
 * Midnight also names a fur color, so the English text cannot be the key);
 * a theme the catalog lacks shows its name as written.
 */
export function themeDisplayName(theme: AppTheme): string {
  const key = `theme.${theme.id}`;
  const name = tr(key);
  return name === key ? theme.name : name;
}

/** The theme's summary in the user's language, looked up by its English text. */
export function themeDisplaySummary(theme: AppTheme): string {
  return tr(theme.summary);
}
