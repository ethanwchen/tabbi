/*
 * A number that follows its target along a spring, for the few drawings
 * that SwiftUI animates through `Animatable` (the check glyph's progress,
 * the progress ring's arc) and CSS transitions cannot: each frame samples
 * the core's SpringSpec curve from where the value was when the target
 * changed, retargeting mid-flight like SwiftUI does. Under Reduce Motion
 * the value eases over the short crossfade; in a still render it jumps.
 */

import { useEffect, useRef, useState } from "react";
import { MotionTokens } from "../../core/motion/motionTokens";
import type { SpringSpec } from "../../core/motion/springSpec";
import { useKit } from "./context";
import { themedSpring, type SpringToken } from "./tokens";

export interface SpringValueOptions {
  /** Jumps straight to the target (a tick too small to see, a restart). */
  readonly immediate?: boolean;
}

export function useSpringValue(target: number, token: SpringToken, { immediate = false }: SpringValueOptions = {}): number {
  const { theme, pace, reduceMotion, still } = useKit();
  const [value, setValue] = useState(target);
  const current = useRef(target);
  const frame = useRef(0);

  useEffect(() => {
    cancelAnimationFrame(frame.current);
    const from = current.current;
    const spec: SpringSpec | undefined = themedSpring(theme, pace, token);
    const settle = (v: number) => {
      current.current = v;
      setValue(v);
    };
    if (immediate || still || !spec || from === target) {
      settle(target);
      return;
    }
    const start = performance.now();
    const duration = reduceMotion ? MotionTokens.reducedCrossfade : spec.settlingTime(0.002);
    const tick = (now: number) => {
      const t = (now - start) / 1000;
      if (t >= duration) {
        settle(target);
        return;
      }
      const fraction = reduceMotion ? easeInOut(t / duration) : spec.value(t);
      settle(from + (target - from) * fraction);
      frame.current = requestAnimationFrame(tick);
    };
    frame.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame.current);
  }, [target, token, theme, pace, reduceMotion, still, immediate]);

  return value;
}

function easeInOut(t: number): number {
  const v = Math.min(1, Math.max(0, t));
  return v < 0.5 ? 2 * v * v : 1 - Math.pow(-2 * v + 2, 2) / 2;
}
