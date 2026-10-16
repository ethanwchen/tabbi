/*
 * The web's `TimelineView(.animation(minimumInterval:paused:))`: a clock in
 * seconds that ticks at most `frameRate` times a second while `active`, the
 * element is on screen and the page is visible, and holds otherwise, so a
 * loader stops the moment it leaves the screen. In a still render it stays
 * at zero and never ticks. The element ref tells it what "on screen" means.
 */

import { useEffect, useRef, useState, type RefObject } from "react";
import { LoaderClock } from "../../core/motion/loaderClock";
import { useKit } from "./context";

export function useLoaderClock(active: boolean, element: RefObject<Element | null>, frameRate: number = LoaderClock.frameRate): number {
  const { still } = useKit();
  const [time, setTime] = useState(0);
  const [visible, setVisible] = useState(true);
  const origin = useRef<number | undefined>(undefined);

  useEffect(() => {
    const target = element.current;
    if (!target || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) setVisible(entry.isIntersecting);
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, [element]);

  useEffect(() => {
    if (still || !active || !visible) return;
    let frame = 0;
    let last = -Infinity;
    const interval = 1000 / frameRate;
    const tick = (now: number) => {
      origin.current ??= now;
      if (now - last >= interval - 1) {
        last = now;
        setTime((now - origin.current) / 1000);
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    const onVisibility = () => {
      if (document.visibilityState === "hidden") cancelAnimationFrame(frame);
      else frame = requestAnimationFrame(tick);
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, [still, active, visible, frameRate]);

  return still ? 0 : time;
}
