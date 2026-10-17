/*
 * The design tokens as CSS variables, the Windows side of the Mac's
 * `Theme` (Sources/TabbiKit/Design/Theme.swift). Colors come from the core's
 * port of themes.json, so both apps draw from one source; type, spacing and
 * radii are fixed values that kit.css reads. `applyKitTheme` writes a
 * theme's variables onto a root element (the document, or one gallery
 * cell), and `accentVariables` gives a module its `--accent` pair.
 */

import {
  adjustedForThemeMotion,
  themeAccent,
  themeIdentityAccent,
  themeOnAccent,
  type AppTheme,
  type ThemeID,
} from "../../core/themes/appTheme";
import { MotionTokens } from "../../core/motion/motionTokens";
import { adjustedSpring, pacedDuration, type MotionPace } from "../../core/motion/motionPace";
import type { SpringSpec } from "../../core/motion/springSpec";
import { DEFAULT_THEME_ID, resolveTheme, standardGlassSheen } from "../../core/themes/themeCatalog";
import { withOpacity, type ModuleAccent, type ThemeColor } from "../../core/themes/themeColor";
import { springTransition } from "./motion";

/** A theme color as a CSS `rgb()` value. */
export function cssColor(color: ThemeColor): string {
  const channel = (v: number) => Math.round(Math.min(1, Math.max(0, v)) * 255);
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)} / ${color.opacity})`;
}

/** The same color at `opacity`, as CSS. */
export function cssColorAt(color: ThemeColor, opacity: number): string {
  return cssColor(withOpacity(color, opacity));
}

/** Theme.Spacing: the 4 px grid. */
export const Spacing = { xxs: 2, xs: 4, s: 8, m: 12, l: 16, xl: 24 } as const;

/** Theme.Radius, used with the squircle-like corners kit.css draws. */
export const Radius = { s: 6, m: 10, l: 14 } as const;

/** Theme.Layout. */
export const Layout = {
  expandedWidth: 560,
  expandedHeight: 236,
  contentInset: 20,
  compactWingWidth: 34,
  openTopRadius: 12,
  openBottomRadius: 26,
} as const;

/** Theme.Typography as CSS font shorthands (family comes from the `--font` variable). */
export const Typography = {
  title: { size: 13, weight: 600 },
  body: { size: 12, weight: 400 },
  bodyEmphasis: { size: 12, weight: 500 },
  caption: { size: 10.5, weight: 500 },
  metric: { size: 22, weight: 600 },
  metricSmall: { size: 13, weight: 600 },
} as const;

/*
 * The Mac draws SF Pro Rounded (or SF Pro for the standard typeface);
 * neither ships on Windows, so the rounded themes and the standard ones both
 * set in Segoe UI Variable, with the system CJK and Arabic fonts behind it.
 * Text uses the optical size for body copy; Display is for the 22 px metric.
 */
export const FONT_TEXT =
  '"Segoe UI Variable Text", "Segoe UI Variable", "Segoe UI", "Yu Gothic UI", "Microsoft YaHei UI", "Microsoft JhengHei UI", "Malgun Gothic", system-ui, sans-serif';
export const FONT_DISPLAY =
  '"Segoe UI Variable Display", "Segoe UI Variable", "Segoe UI", "Yu Gothic UI", "Microsoft YaHei UI", "Microsoft JhengHei UI", "Malgun Gothic", system-ui, sans-serif';

const kebab = (key: string) => key.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);

/** The motion tokens a theme and pace play, by name. */
export const SPRING_TOKENS = ["open", "close", "hover", "snappy", "content", "press", "check"] as const;
export type SpringToken = (typeof SPRING_TOKENS)[number];

/** `token` as `theme` and `pace` play it, or undefined at the Instant pace. */
export function themedSpring(theme: AppTheme, pace: MotionPace, token: SpringToken): SpringSpec | undefined {
  return adjustedSpring(pace, adjustedForThemeMotion(theme.motion, MotionTokens[token]));
}

/**
 * Every variable for `theme`: the palette (`--background`, `--surface-hover`,
 * ...), `--glow` when the theme has one, `--on-accent`, the glass sheen, the typeface, and a
 * `--spring-<token>` transition (duration plus a `linear()` easing sampled
 * from the spring) for each motion token at `pace`.
 */
export function themeVariables(theme: AppTheme, pace: MotionPace = "smooth"): Record<string, string> {
  const variables: Record<string, string> = {};
  const palette = theme.palette;
  variables["--background"] = cssColor(palette.background);
  variables["--glow"] = palette.glow ? cssColor(palette.glow) : "transparent";
  for (const role of [
    "surface",
    "surfaceHover",
    "stroke",
    "primaryText",
    "secondaryText",
    "tertiaryText",
    "success",
    "warning",
    "danger",
  ] as const) {
    variables[`--${kebab(role)}`] = cssColor(palette[role]);
  }
  /* Text and symbols on an accent fill (Theme.Palette.onAccent): the theme's onAccent, or the black body. */
  variables["--on-accent"] = cssColor(themeOnAccent(theme));
  /* The liked-song heart (Theme.Palette.favorite), pink-red in every player, even in a theme with a key color. */
  variables["--favorite"] = cssColor(themeIdentityAccent(theme, { red: 0.98, green: 0.26, blue: 0.4 }));
  const sheen = standardGlassSheen;
  variables["--sheen-fill-top"] = cssColor(sheen.fillTop);
  variables["--sheen-fill-bottom"] = cssColor(sheen.fillBottom);
  variables["--sheen-glint"] = cssColor(sheen.glint);
  variables["--sheen-rim-top"] = cssColor(sheen.rimTop);
  variables["--sheen-rim-bottom"] = cssColor(sheen.rimBottom);
  /* One family for both typefaces on Windows; `data-typeface` still tells the two apart for anyone who bundles a rounded OFL font later. */
  variables["--font"] = FONT_TEXT;
  variables["--font-display"] = FONT_DISPLAY;
  for (const token of SPRING_TOKENS) {
    const spec = themedSpring(theme, pace, token);
    const transition = spec ? springTransition(spec) : { duration: 0, easing: "linear" };
    variables[`--spring-${token}`] = `${transition.duration}ms ${transition.easing}`;
    variables[`--spring-${token}-duration`] = `${transition.duration}ms`;
  }
  variables["--content-delay"] = `${Math.round(pacedDuration(pace, MotionTokens.contentDelay) * 1000)}ms`;
  variables["--content-fade-in"] = `${Math.round(pacedDuration(pace, MotionTokens.contentFadeIn) * 1000)}ms`;
  variables["--content-fade-out"] = `${Math.round(pacedDuration(pace, MotionTokens.contentFadeOut) * 1000)}ms`;
  variables["--reduced-crossfade"] = `${Math.round(MotionTokens.reducedCrossfade * 1000)}ms`;
  return variables;
}

/*
 * The `--accent` pair a module's subtree reads: the theme's key color, or the
 * module accent as `theme` treats it, a soft 16% tint, and `--on-accent`,
 * the text color on that fill, so the two always travel together.
 */
export function accentVariables(theme: AppTheme, accent: ModuleAccent): Record<string, string> {
  const color = themeAccent(theme, accent);
  return {
    "--accent": cssColor(color),
    "--accent-soft": cssColorAt(color, 0.16),
    "--accent-faint": cssColorAt(color, 0.12),
    "--on-accent": cssColor(themeOnAccent(theme)),
  };
}

/** A module's accent as `theme` shows it (the theme's key color when it has one), as CSS. */
export function accentCss(theme: AppTheme, accent: ModuleAccent, opacity = 1): string {
  return cssColorAt(themeAccent(theme, accent), opacity);
}

/*
 * A module's own accent as `theme` treats it, even in a theme with a key
 * color, as CSS: for places that list several modules side by side or show
 * another module's item (the Mac's `identityColor`).
 */
export function identityAccentCss(theme: AppTheme, accent: ModuleAccent, opacity = 1): string {
  return cssColorAt(themeIdentityAccent(theme, accent), opacity);
}

/*
 * The `--accent` pair for a module's own identity color (identityAccentCss),
 * for a subtree listing modules or another module's item. Text on that fill
 * is the black body, as before themes had accents.
 */
export function identityAccentVariables(theme: AppTheme, accent: ModuleAccent): Record<string, string> {
  const color = themeIdentityAccent(theme, accent);
  return {
    "--accent": cssColor(color),
    "--accent-soft": cssColorAt(color, 0.16),
    "--accent-faint": cssColorAt(color, 0.12),
    "--on-accent": cssColor(theme.palette.background),
  };
}

/**
 * Writes `theme`'s variables and `data-theme`, `data-controls`, `data-surfaces`
 * and `data-typeface` onto `root`, so kit.css can style glass controls and
 * frosted cards, and clears what a previous theme left.
 */
export function applyKitTheme(root: HTMLElement, themeId: ThemeID = DEFAULT_THEME_ID, pace: MotionPace = "smooth"): AppTheme {
  const theme = resolveTheme(themeId);
  for (const [name, value] of Object.entries(themeVariables(theme, pace))) {
    root.style.setProperty(name, value);
  }
  root.dataset.theme = theme.id;
  root.dataset.controls = theme.controls;
  root.dataset.surfaces = theme.surfaces;
  root.dataset.typeface = theme.typeface;
  root.dataset.motion = theme.motion;
  return theme;
}
