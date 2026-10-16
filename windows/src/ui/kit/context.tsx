/*
 * What every kit component reads from its surroundings, the web's stand-in
 * for the Mac's environment values: the active theme (`Theme.current`), the
 * motion pace, Reduce Motion, whether this is a still render (a snapshot,
 * where nothing may move or tick: `rendersToImage`), how far a marquee is
 * scrolled in a still render (`marqueeScrolled`), and the loader reveal
 * delay. A `KitProvider` wraps a root; the defaults draw the default theme
 * at the Smooth pace, following the system's Reduce Motion setting.
 */

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { PawTrail } from "../../core/motion/pawTrail";
import type { MotionPace } from "../../core/motion/motionPace";
import type { AppTheme, ThemeID } from "../../core/themes/appTheme";
import { DEFAULT_THEME_ID, resolveTheme } from "../../core/themes/themeCatalog";
import { adaptedTransition, springs, transitionCss, type CssTransition } from "./motion";
import type { SpringToken } from "./tokens";
import { themedSpring } from "./tokens";

export interface KitEnvironment {
  readonly theme: AppTheme;
  readonly pace: MotionPace;
  readonly reduceMotion: boolean;
  /** A still render: no timers, no animation, every loader at its first frame. */
  readonly still: boolean;
  /** In a still render, how far (0 to 1) every overflowing marquee is scrolled. */
  readonly marqueeScrolled?: number;
  /** How long a PawLoader waits before it shows, in seconds. */
  readonly loaderRevealDelay: number;
  /** Styled tooltips, or the browser's `title` ones. */
  readonly nativeTooltips: boolean;
}

const systemReduceMotion = () =>
  typeof window !== "undefined" && typeof window.matchMedia === "function"
    ? window.matchMedia("(prefers-reduced-motion: reduce)").matches
    : false;

const DEFAULTS: KitEnvironment = {
  theme: resolveTheme(DEFAULT_THEME_ID),
  pace: "smooth",
  reduceMotion: false,
  still: false,
  loaderRevealDelay: PawTrail.revealDelay,
  nativeTooltips: false,
};

const KitContext = createContext<KitEnvironment>(DEFAULTS);

export interface KitProviderProps {
  readonly themeId?: ThemeID;
  readonly pace?: MotionPace;
  /** Forces Reduce Motion on or off; undefined follows the system setting. */
  readonly reduceMotion?: boolean;
  readonly still?: boolean;
  readonly marqueeScrolled?: number;
  readonly loaderRevealDelay?: number;
  readonly nativeTooltips?: boolean;
  readonly children?: ReactNode;
}

export function KitProvider({
  themeId = DEFAULT_THEME_ID,
  pace = "smooth",
  reduceMotion,
  still = false,
  marqueeScrolled,
  loaderRevealDelay,
  nativeTooltips = false,
  children,
}: KitProviderProps) {
  const [system, setSystem] = useState(systemReduceMotion);
  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return;
    const query = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setSystem(query.matches);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  const value = useMemo<KitEnvironment>(
    () => ({
      theme: resolveTheme(themeId),
      pace,
      reduceMotion: reduceMotion ?? system,
      still,
      ...(marqueeScrolled === undefined ? {} : { marqueeScrolled }),
      loaderRevealDelay: loaderRevealDelay ?? (still ? 0 : PawTrail.revealDelay),
      nativeTooltips,
    }),
    [themeId, pace, reduceMotion, system, still, marqueeScrolled, loaderRevealDelay, nativeTooltips],
  );
  return <KitContext.Provider value={value}>{children}</KitContext.Provider>;
}

export function useKit(): KitEnvironment {
  return useContext(KitContext);
}

/** The theme every token reads. */
export function useTheme(): AppTheme {
  return useContext(KitContext).theme;
}

/** True when nothing should move: Reduce Motion, the Instant pace, or a still render. */
export function useReduceMotion(): boolean {
  const { reduceMotion, still } = useContext(KitContext);
  return reduceMotion || still;
}

/** `token`'s spring as a CSS transition for this theme, pace and Reduce Motion setting. */
export function useSpring(token: SpringToken): CssTransition {
  const { theme, pace, reduceMotion, still } = useContext(KitContext);
  return useMemo(() => {
    if (still) return { duration: 0, easing: "linear" };
    const spec = themedSpring(theme, pace, token) ?? springs[token];
    return adaptedTransition(spec, reduceMotion, pace);
  }, [theme, pace, reduceMotion, still, token]);
}

/** A CSS `transition` string for `properties` along `token`. */
export function useTransition(token: SpringToken, properties: readonly string[]): string {
  const transition = useSpring(token);
  return useMemo(() => transitionCss(properties, transition), [properties, transition]);
}
