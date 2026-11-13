/*
 * Port of StudyLevelViews.swift: the rank emblem drawn as crisp pixel art,
 * the "[emblem] Lv 12 Ember" label beside a name (shortened to "Lv 12",
 * then "12", never cut off), and the nameplate tint a name wears.
 */

import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { rankBitmap, RANK_ART_SIZE } from "../../core/progression/rankArt";
import {
  levelShortLabel,
  nameplateGlows,
  nameplateHex,
  rankForLevel,
  rankName,
  standingHelp,
  type Nameplate,
  type StudyRank,
  type StudyStanding,
} from "../../core/progression/studyLevel";
import { Tooltip } from "./Tooltip";

/** Whole device pixels per sprite pixel, never fewer than one. */
export function emblemScale(pixelSize: number, devicePixelRatio: number): number {
  return Math.max(1, Math.round(pixelSize * devicePixelRatio));
}

/**
 * A rank's pixel emblem: `pixelSize` CSS px per sprite pixel (1 beside the
 * pet's name, 0.5 in Party's rows, 1.5 on the Goals Level card), drawn at
 * a whole number of device pixels per sprite pixel, never smoothed.
 */
export function StudyRankEmblem({ rank, pixelSize = 1 }: { rank: StudyRank; pixelSize?: number }) {
  const element = useRef<HTMLCanvasElement>(null);
  const [ratio, setRatio] = useState(() => (typeof window === "undefined" ? 1 : window.devicePixelRatio || 1));
  const side = RANK_ART_SIZE * pixelSize;

  useLayoutEffect(() => {
    if (typeof window === "undefined") return;
    const update = () => setRatio(window.devicePixelRatio || 1);
    window.addEventListener("resize", update);
    return () => window.removeEventListener("resize", update);
  }, []);

  useLayoutEffect(() => {
    const canvas = element.current;
    if (!canvas) return;
    const panelScale = Number.parseFloat(getComputedStyle(canvas).getPropertyValue("--panel-scale")) || 1;
    const scale = emblemScale(pixelSize * panelScale, ratio);
    /* Resizing a canvas reallocates it even at the same size, so only on a change. */
    const size = RANK_ART_SIZE * scale;
    if (canvas.width !== size) canvas.width = size;
    if (canvas.height !== size) canvas.height = size;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.imageSmoothingEnabled = false;
    const bitmap = rankBitmap(rank, scale);
    const image = context.createImageData(bitmap.width, bitmap.height);
    image.data.set(bitmap.data);
    context.putImageData(image, 0, 0);
  }, [rank, pixelSize, ratio]);

  return <canvas ref={element} className="kit-rank-emblem" style={{ width: side, height: side }} aria-hidden="true" />;
}

export type StudyLevelLength = "full" | "level" | "number";
export const STUDY_LEVEL_LENGTHS: readonly StudyLevelLength[] = ["full", "level", "number"];

/** The Study Level beside a name: the emblem, then "Lv 12 Ember", "Lv 12" or "12". The tooltip always says it in full. */
export function StudyLevelLabel({ standing, length = "full", pixelSize = 1 }: { standing: StudyStanding; length?: StudyLevelLength; pixelSize?: number }) {
  const rank = rankForLevel(standing.level);
  const help = standingHelp(standing);
  return (
    <Tooltip text={help}>
      <span className="kit-study-level kit-caption" role="img" aria-label={help}>
        <StudyRankEmblem rank={rank} pixelSize={pixelSize} />
        {length === "number" ? (
          <span className="kit-secondary">{standing.level}</span>
        ) : (
          <span className="kit-secondary">{levelShortLabel(standing.level)}</span>
        )}
        {length === "full" && <span className="kit-tertiary kit-study-level-rank">{` ${rankName(rank)}`}</span>}
      </span>
    </Tooltip>
  );
}

/** The CSS a name wears for `nameplate`: plain is the theme's primary text, the rest their color, glowing from Level 40. */
export function nameplateStyle(nameplate: Nameplate): CSSProperties {
  if (nameplate === "plain") return { color: "var(--primary-text)" };
  const color = nameplateHex(nameplate);
  return nameplateGlows(nameplate) ? { color, textShadow: `0 0 3px ${color}8C` } : { color };
}

/** A nameplate's tint as CSS, plain following the theme. */
export function nameplateTint(nameplate: Nameplate): string {
  return nameplate === "plain" ? "var(--primary-text)" : nameplateHex(nameplate);
}

/**
 * The Mac's horizontal ViewThatFits over a few layouts of one row: shows
 * the first variant whose content fits the row's width, and the last one
 * whatever the width. Measured before paint, again when `fitKey` changes.
 */
export function VariantsThatFit({
  count,
  fitKey,
  className,
  render,
}: {
  count: number;
  fitKey: string;
  className?: string;
  render: (index: number) => ReactNode;
}) {
  const row = useRef<HTMLDivElement>(null);
  const [fitted, setFitted] = useState({ key: fitKey, index: 0 });
  if (fitted.key !== fitKey) setFitted({ key: fitKey, index: 0 });
  const index = fitted.index;
  useLayoutEffect(() => {
    const element = row.current;
    if (!element || index >= count - 1) return;
    if (element.scrollWidth > element.clientWidth + 1) setFitted({ key: fitKey, index: index + 1 });
  }, [index, fitKey, count]);
  return (
    <div ref={row} className={["kit-variants-fit", className].filter(Boolean).join(" ")}>
      {render(index)}
    </div>
  );
}
