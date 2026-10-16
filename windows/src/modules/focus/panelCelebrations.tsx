/*
 * The celebrations a timer panel plays over itself: a store asks for one
 * (a focus block finished) and the panel, which knows the theme and its
 * accent, turns it into a burst on a `CelebrationStage`. The Mac routes
 * these through one app-wide `CelebrationCenter`; here each panel keeps a
 * center of its own, so the pacer's limits hold per panel, and a burst
 * only ever plays while the panel is on screen (the stores hold one back
 * until then).
 */

import { useEffect, useMemo, useState, type ReactNode } from "react";
import type { CelebrationStyle } from "../../core/motion/celebration";
import type { ModuleAccent } from "../../core/themes/themeColor";
import { CelebrationStage, type Celebration } from "../../ui/kit/Celebration";
import { CelebrationCenter } from "../../ui/kit/celebrationCenter";
import { useKit } from "../../ui/kit/context";
import { accentCss } from "../../ui/kit/tokens";

export interface PanelCelebrationsProps {
  /** Calls `play` with the style of each burst the store asks for; returns the function that stops it. */
  readonly requests: (play: (style: CelebrationStyle) => void) => () => void;
  readonly accent: ModuleAccent;
  readonly source: string;
  /** Seconds since 1970 and the user's zone, for the pacer. */
  readonly now: () => number;
  readonly timeZone: () => string;
  readonly className?: string;
  readonly children?: ReactNode;
}

export function PanelCelebrations({ requests, accent, source, now, timeZone, className, children }: PanelCelebrationsProps) {
  const { theme, still } = useKit();
  const [current, setCurrent] = useState<Celebration | undefined>(undefined);
  const center = useMemo(() => new CelebrationCenter({ isEnabled: !still, now, timeZone: timeZone() }), [still, now, timeZone]);
  useEffect(() => {
    center.stageAppeared();
    const stop = center.subscribe(() => setCurrent(center.current));
    return () => {
      stop();
      center.stageDisappeared();
    };
  }, [center]);
  useEffect(() => requests((style) => void center.celebrate("burst", style, accentCss(theme, accent), theme, source, true)), [requests, center, theme, accent, source]);
  return (
    <CelebrationStage celebration={current} className={className}>
      {children}
    </CelebrationStage>
  );
}
