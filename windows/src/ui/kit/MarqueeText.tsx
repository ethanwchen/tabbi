/*
 * The Mac's `MarqueeText` and `Marquee`: one line of text that shows whole
 * when it fits and, when it does not, scrolls gently to reveal the rest: it
 * rests at the start, eases across until the end is in view, rests there,
 * then fades back to the start (the core's MarqueeMotion). Never an
 * ellipsis. A line cut off at an edge fades out there over 12 px, the
 * pointer resting on it pauses the scroll, its tooltip and accessible name
 * carry the full text, right-to-left text scrolls the other way, and under
 * Reduce Motion it stays at rest, clipped with the fade and the tooltip. A
 * line that fits runs no timer, and one that overflows only while on screen.
 */

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { MarqueeMotion } from "../../core/motion/marqueeMotion";
import { useKit } from "./context";
import { Tooltip } from "./Tooltip";

export interface MarqueeProps {
  /** The whole line as plain text, for the tooltip and the accessible name. */
  readonly text: string;
  /** A tooltip to show at all times, in place of the full text (which shows only while the line overflows). */
  readonly help?: string;
  readonly className?: string;
  readonly style?: CSSProperties;
  readonly children?: ReactNode;
}

/** The mask that fades each cut edge, `leading` and `trailing` as fractions of the width. */
export function marqueeMask(leading: number, trailing: number, direction: "ltr" | "rtl"): string {
  const toEnd = direction === "rtl" ? "to left" : "to right";
  const l = Math.max(0, Math.min(leading, 1)) * 100;
  const t = (1 - Math.max(0, Math.min(trailing, 1))) * 100;
  return `linear-gradient(${toEnd}, transparent 0%, black ${l}%, black ${t}%, transparent 100%)`;
}

export function Marquee({ text, help, className, style, children }: MarqueeProps) {
  const { reduceMotion, still, marqueeScrolled } = useKit();
  const container = useRef<HTMLSpanElement>(null);
  const line = useRef<HTMLSpanElement>(null);
  const [overflow, setOverflow] = useState(0);
  const [direction, setDirection] = useState<"ltr" | "rtl">("ltr");
  const [visible, setVisible] = useState(true);
  const [paused, setPaused] = useState(false);
  const startedAt = useRef(0);
  const pausedAt = useRef<number | undefined>(undefined);

  const measure = useCallback(() => {
    const outer = container.current;
    const inner = line.current;
    if (!outer || !inner) return;
    const next = MarqueeMotion.overflow(inner.scrollWidth, outer.clientWidth);
    setOverflow((previous) => (Math.abs(previous - next) < 0.5 ? previous : next));
    setDirection(getComputedStyle(outer).direction === "rtl" ? "rtl" : "ltr");
  }, []);

  useLayoutEffect(measure, [measure, text, children]);

  useEffect(() => {
    const outer = container.current;
    if (!outer || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(outer);
    if (line.current) observer.observe(line.current);
    return () => observer.disconnect();
  }, [measure]);

  useEffect(() => {
    const outer = container.current;
    if (!outer || typeof IntersectionObserver === "undefined") return;
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) setVisible(entry.isIntersecting);
    });
    observer.observe(outer);
    return () => observer.disconnect();
  }, []);

  const scrolls = MarqueeMotion.scrolls(overflow, reduceMotion || still, visible && document.visibilityState !== "hidden");

  /* Draws one pose straight into the DOM, so a 60 fps scroll never re-renders React. */
  const draw = useCallback(
    (offset: number, opacity: number) => {
      const outer = container.current;
      const inner = line.current;
      if (!outer || !inner) return;
      const width = Math.max(outer.clientWidth, 1);
      const fade = MarqueeMotion.edgeFade;
      const leading = Math.min(offset, fade) / width;
      const trailing = Math.min(Math.max(overflow - offset, 0), fade) / width;
      const shift = direction === "rtl" ? offset : -offset;
      inner.style.transform = shift === 0 ? "" : `translateX(${shift.toFixed(2)}px)`;
      inner.style.opacity = opacity === 1 ? "" : opacity.toFixed(3);
      const mask = overflow > 0 ? marqueeMask(leading, trailing, direction) : "";
      outer.style.maskImage = mask;
      outer.style.webkitMaskImage = mask;
    },
    [overflow, direction],
  );

  /* A new line, or one that starts to overflow, starts from its beginning. */
  useEffect(() => {
    startedAt.current = performance.now();
    if (pausedAt.current !== undefined) pausedAt.current = 0;
  }, [text, scrolls]);

  useEffect(() => {
    if (!scrolls) {
      const pose = still && overflow > 0 ? MarqueeMotion.poseScrolled(marqueeScrolled ?? 0, overflow) : MarqueeMotion.rest;
      draw(pose.offset, pose.opacity);
      return;
    }
    if (paused) {
      const elapsed = pausedAt.current ?? 0;
      const pose = MarqueeMotion.pose(elapsed, overflow);
      draw(pose.offset, pose.opacity);
      return;
    }
    let frame = 0;
    const tick = (now: number) => {
      const pose = MarqueeMotion.pose((now - startedAt.current) / 1000, overflow);
      draw(pose.offset, pose.opacity);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [scrolls, paused, overflow, draw, still, marqueeScrolled]);

  const onEnter = () => {
    if (!scrolls) return;
    pausedAt.current = (performance.now() - startedAt.current) / 1000;
    setPaused(true);
  };
  const onLeave = () => {
    if (pausedAt.current !== undefined) {
      startedAt.current = performance.now() - pausedAt.current * 1000;
      pausedAt.current = undefined;
    }
    setPaused(false);
  };

  const tooltip = help ?? (overflow > 0 ? text : "");
  return (
    <Tooltip text={tooltip}>
      <span
        ref={container}
        className={["kit-marquee", className].filter(Boolean).join(" ")}
        data-overflows={overflow > 0 || undefined}
        style={style}
        aria-label={text}
        onPointerEnter={onEnter}
        onPointerLeave={onLeave}
      >
        <span ref={line} className="kit-marquee-line" aria-hidden="true">
          {children ?? text}
        </span>
      </span>
    </Tooltip>
  );
}

export interface MarqueeTextProps {
  readonly text: string;
  readonly help?: string;
  readonly className?: string;
  readonly style?: CSSProperties;
}

export function MarqueeText({ text, help, className, style }: MarqueeTextProps) {
  return <Marquee text={text} help={help} className={className} style={style} />;
}
