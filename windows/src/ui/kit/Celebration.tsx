/*
 * The Mac's celebrations (Sources/TabbiKit/Components/Celebration/): a
 * `Celebration` value is one burst to play, in a style and palette (the
 * module accent leads, with warm companions from the theme). `CelebrationStage`
 * overlays a panel and plays each new celebration once: a particle burst
 * drawn on a canvas from the core's pure `CelebrationBurst` (the same moment
 * always draws the same picture), capped at 60 fps and gone when the last
 * particle is, or under Reduce Motion a soft glow of the accent that
 * brightens and fades in place. Nothing here blocks input. The
 * `CelebrationCenter` (celebrationCenter.ts) is where real events ask for one.
 */

import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { CelebrationBurst, type CelebrationStyle, type CelebrationTier } from "../../core/motion/celebration";
import type { AppTheme } from "../../core/themes/appTheme";
import { cssColor } from "./tokens";
import { useKit } from "./context";
import { unitPath2D } from "./celebrationShapes";

export interface Celebration {
  readonly id: string;
  readonly tier: CelebrationTier;
  readonly style: CelebrationStyle;
  /** The colors particles take, the accent first. */
  readonly colors: readonly string[];
  /** Where the burst starts, as a unit point in the stage (0.5, 0.6 by default). */
  readonly originX: number;
  readonly originY: number;
  /** When the event happened, in milliseconds on `performance.now()`'s clock. */
  readonly startedAt: number;
  /** The seed for the burst's particles. */
  readonly seed: number;
}

let nextSeed = 1;

/** The palette for `style`: the accent leads; hearts stay warm; paw prints stay close to the accent. */
export function celebrationPalette(theme: AppTheme, accent: string, style: CelebrationStyle): string[] {
  const pink = "rgb(255 140 179)";
  const sky = "rgb(115 194 255)";
  const { success, warning, danger } = theme.palette;
  switch (style) {
    case "confetti":
    case "sparkles":
      return [accent, cssColor(success), cssColor(warning), pink, sky, "white"];
    case "hearts":
      return [accent, pink, cssColor(danger), "rgb(255 140 179 / 0.8)"];
    case "pawPrints":
      return [accent, `color-mix(in srgb, ${accent} 75%, transparent)`, "rgb(255 255 255 / 0.9)"];
  }
}

export interface CelebrationInput {
  readonly tier: CelebrationTier;
  readonly style: CelebrationStyle;
  readonly accent: string;
  readonly theme: AppTheme;
  readonly originX?: number;
  readonly originY?: number;
  readonly startedAt?: number;
  readonly seed?: number;
}

export function makeCelebration({ tier, style, accent, theme, originX = 0.5, originY = 0.6, startedAt, seed }: CelebrationInput): Celebration {
  const s = seed ?? nextSeed++;
  return {
    id: `${s}-${startedAt ?? performance.now()}`,
    tier,
    style,
    colors: celebrationPalette(theme, accent, style),
    originX,
    originY,
    startedAt: startedAt ?? performance.now(),
    seed: s,
  };
}

/** The burst's particles, seeded so a redraw never reshuffles them. */
export function burstOf(celebration: Celebration): CelebrationBurst {
  return new CelebrationBurst(celebration.tier, celebration.style, celebration.seed, celebration.colors.length);
}

/** Draws one frame of `burst` onto `context` (CSS pixel coordinates), `elapsed` seconds in. */
export function drawCelebrationFrame(
  context: CanvasRenderingContext2D,
  burst: CelebrationBurst,
  colors: readonly string[],
  origin: { x: number; y: number },
  elapsed: number,
): void {
  const path = unitPath2D(burst.style);
  for (const particle of burst.particles) {
    const state = CelebrationBurst.state(particle, elapsed);
    if (!state) continue;
    const side = particle.size * state.scale;
    context.save();
    context.translate(origin.x + state.x, origin.y + state.y);
    context.rotate((state.rotation * Math.PI) / 180);
    context.scale(side, side);
    context.globalAlpha = state.opacity;
    context.fillStyle = colors[particle.colorIndex % colors.length] ?? "white";
    context.fill(path);
    context.restore();
  }
}

export const CELEBRATION_FRAME_RATE = 60;
/** How long the Reduce Motion glow lasts, in seconds. */
export const CELEBRATION_GLOW_DURATION = 0.9;

/** The glow's level (0 to 1) `elapsed` seconds in: up in the first third, back down over the rest. */
export function glowLevel(elapsed: number): number {
  const progress = Math.min(1, Math.max(0, elapsed / CELEBRATION_GLOW_DURATION));
  return progress < 1 / 3 ? progress * 3 : (1 - progress) * 1.5;
}

export interface CelebrationBurstViewProps {
  readonly celebration: Celebration;
  /** Draws this moment instead of playing, for frame strips. */
  readonly elapsed?: number;
  readonly onFinished?: () => void;
}

export function CelebrationBurstView({ celebration, elapsed, onFinished }: CelebrationBurstViewProps) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const burst = useMemo(() => burstOf(celebration), [celebration]);
  const { still } = useKit();
  const finished = useRef(onFinished);
  useEffect(() => {
    finished.current = onFinished;
  }, [onFinished]);

  useEffect(() => {
    const element = canvas.current;
    if (!element) return;
    const context = element.getContext("2d");
    if (!context) return;
    const draw = (at: number) => {
      const ratio = window.devicePixelRatio || 1;
      const width = element.clientWidth;
      const height = element.clientHeight;
      const w = Math.round(width * ratio);
      const h = Math.round(height * ratio);
      if (element.width !== w || element.height !== h) {
        element.width = w;
        element.height = h;
      }
      context.setTransform(ratio, 0, 0, ratio, 0, 0);
      context.clearRect(0, 0, width, height);
      drawCelebrationFrame(context, burst, celebration.colors, { x: width * celebration.originX, y: height * celebration.originY }, at);
    };
    if (elapsed !== undefined || still) {
      draw(elapsed ?? 0);
      return;
    }
    let frame = 0;
    let last = -Infinity;
    const tick = (now: number) => {
      const at = (now - celebration.startedAt) / 1000;
      if (burst.isFinished(at)) {
        draw(at);
        finished.current?.();
        return;
      }
      if (now - last >= 1000 / CELEBRATION_FRAME_RATE - 1) {
        last = now;
        draw(at);
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [burst, celebration, elapsed, still]);

  return <canvas ref={canvas} className="kit-celebration-canvas" aria-hidden="true" />;
}

export interface CelebrationGlowProps {
  readonly celebration: Celebration;
  readonly elapsed?: number;
  readonly onFinished?: () => void;
}

/** The Reduce Motion stand-in for a burst. */
export function CelebrationGlow({ celebration, elapsed, onFinished }: CelebrationGlowProps) {
  const [now, setNow] = useState(() => (elapsed === undefined ? (performance.now() - celebration.startedAt) / 1000 : elapsed));
  const { still } = useKit();
  const finished = useRef(onFinished);
  useEffect(() => {
    finished.current = onFinished;
  }, [onFinished]);
  useEffect(() => {
    if (elapsed !== undefined || still) return;
    let frame = 0;
    const tick = (time: number) => {
      const at = (time - celebration.startedAt) / 1000;
      setNow(at);
      if (at >= CELEBRATION_GLOW_DURATION) {
        finished.current?.();
        return;
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [celebration, elapsed, still]);
  const color = celebration.colors[0] ?? "white";
  const level = glowLevel(elapsed ?? now);
  return (
    <div
      className="kit-celebration-glow"
      aria-hidden="true"
      style={{
        opacity: level,
        background: `radial-gradient(circle 140px at ${celebration.originX * 100}% ${celebration.originY * 100}%, ${glowColor(color, 0.32)}, transparent)`,
      }}
    />
  );
}

function glowColor(color: string, opacity: number): string {
  return `color-mix(in srgb, ${color} ${Math.round(opacity * 100)}%, transparent)`;
}

export interface CelebrationStageProps {
  /** The latest celebration; a new id plays once. A stage that appears mid-burst picks it up where it is. */
  readonly celebration?: Celebration;
  readonly children?: ReactNode;
  readonly className?: string;
}

/** Makes its children a stage: the celebration plays over them, ignoring hits, and leaves when it is done. */
export function CelebrationStage({ celebration, children, className }: CelebrationStageProps) {
  const { reduceMotion } = useKit();
  /* The id of the celebration that has finished playing, so it leaves the hierarchy and never replays. */
  const [doneId, setDoneId] = useState<string | undefined>(undefined);
  const playing = celebration && celebration.id !== doneId ? celebration : undefined;
  const done = () => setDoneId(celebration?.id);
  return (
    <div className={["kit-celebration-stage", className].filter(Boolean).join(" ")}>
      {children}
      {playing && (reduceMotion ? <CelebrationGlow celebration={playing} onFinished={done} /> : <CelebrationBurstView celebration={playing} onFinished={done} />)}
    </div>
  );
}
